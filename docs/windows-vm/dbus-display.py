#!/usr/bin/env python3
"""Watch and drive a libvirt guest through QEMU's D-Bus display, from the host.

    dbus-display.py -d DOMAIN info
    dbus-display.py -d DOMAIN watch [--seconds N] [--reply-delay MS] [--v1] [--dump out.png]
    dbus-display.py -d DOMAIN key leftmeta+r enter ...      # evdev names, '+' chords
    dbus-display.py -d DOMAIN type 'text'
    dbus-display.py -d DOMAIN mouse X Y [--click|--right|--double|--move]
    dbus-display.py -d DOMAIN resize W H
    dbus-display.py -d DOMAIN clipboard get | set 'text'

The M0 spike for docs/plans/windows-home-vm.md: the domain runs
`<graphics type='dbus' p2p='yes'><gl .../>` + virtio-vga-gl, and this script
is the display client the compositor will one day be -- it registers a
listener and reports what QEMU actually sends (ScanoutDMABUF or a pixel
copy, damage rects, rate), and pokes the console's Keyboard/Mouse/Clipboard
interfaces the same way. Nothing here is product code; it exists to write
the results section of that doc.

Wire facts (QEMU 10.2, ui/dbus*.c), because each cost a wrong guess:
- The connection comes from libvirt: `openGraphicsFD` does the socketpair
  and the QMP `add_client` for us. QEMU is the *authentication server* on
  that socket and on the listener socket, so both ends here are CLIENT.
- A listener is a second p2p connection, handed to `RegisterListener` as an
  fd. QEMU reads our `Interfaces` property (via GetAll, synchronously, from
  its main loop) to decide between ScanoutDMABUF and ScanoutDMABUF2 -- so
  the object must be exported, and our main loop running, before it asks.
- The reply to `UpdateDMABUF` is the frame ack: QEMU blocks the console's
  GL until it arrives (`graphic_hw_gl_block`). `--reply-delay` sleeps before
  replying to see what that does to the guest.
- Clipboard: QEMU calls *back* into `/org/qemu/Display1/Clipboard` on the
  main connection, and its `Register` handler creates that proxy (another
  sync GetAll) before replying, so `Register` must be called async.
- Keys are "qnum": XT set 1, extended keys 0x80|code. Mouse coordinates are
  console pixels; buttons 0/1/2 are left/middle/right.
"""
import argparse
import fcntl
import mmap
import os
import socket
import struct
import subprocess
import sys
import time

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

import libvirt  # noqa: E402

DEFAULT_DOMAIN = "win11-dbus"
ROOT = "/org/qemu/Display1"
CONSOLE = ROOT + "/Console_0"
CLIPBOARD = ROOT + "/Clipboard"
LISTENER = ROOT + "/Listener"
IFACE_CONSOLE = "org.qemu.Display1.Console"
IFACE_KBD = "org.qemu.Display1.Keyboard"
IFACE_MOUSE = "org.qemu.Display1.Mouse"
IFACE_CLIP = "org.qemu.Display1.Clipboard"
IFACE_LISTENER = "org.qemu.Display1.Listener"
IFACE_DMABUF2 = "org.qemu.Display1.Listener.Unix.ScanoutDMABUF2"
MIME_TEXT = "text/plain;charset=utf-8"

# evdev key name (lower case, KEY_ prefix dropped) -> qnum. Generated from
# keycodemapdb: `keymap-gen code-map --lang=python3 keymaps.csv linux qnum`.
QNUM = {
    'esc': 0x01, '1': 0x02, '2': 0x03, '3': 0x04, '4': 0x05, '5': 0x06,
    '6': 0x07, '7': 0x08, '8': 0x09, '9': 0x0a, '0': 0x0b, 'minus': 0x0c,
    'equal': 0x0d, 'backspace': 0x0e, 'tab': 0x0f, 'q': 0x10, 'w': 0x11,
    'e': 0x12, 'r': 0x13, 't': 0x14, 'y': 0x15, 'u': 0x16, 'i': 0x17,
    'o': 0x18, 'p': 0x19, 'leftbrace': 0x1a, 'rightbrace': 0x1b,
    'enter': 0x1c, 'leftctrl': 0x1d, 'a': 0x1e, 's': 0x1f, 'd': 0x20,
    'f': 0x21, 'g': 0x22, 'h': 0x23, 'j': 0x24, 'k': 0x25, 'l': 0x26,
    'semicolon': 0x27, 'apostrophe': 0x28, 'grave': 0x29,
    'leftshift': 0x2a, 'backslash': 0x2b, 'z': 0x2c, 'x': 0x2d, 'c': 0x2e,
    'v': 0x2f, 'b': 0x30, 'n': 0x31, 'm': 0x32, 'comma': 0x33, 'dot': 0x34,
    'slash': 0x35, 'rightshift': 0x36, 'kpasterisk': 0x37, 'leftalt': 0x38,
    'space': 0x39, 'capslock': 0x3a, 'f1': 0x3b, 'f2': 0x3c, 'f3': 0x3d,
    'f4': 0x3e, 'f5': 0x3f, 'f6': 0x40, 'f7': 0x41, 'f8': 0x42, 'f9': 0x43,
    'f10': 0x44, 'numlock': 0x45, 'scrolllock': 0x46, 'kp7': 0x47,
    'kp8': 0x48, 'kp9': 0x49, 'kpminus': 0x4a, 'kp4': 0x4b, 'kp5': 0x4c,
    'kp6': 0x4d, 'kpplus': 0x4e, 'kp1': 0x4f, 'kp2': 0x50, 'kp3': 0x51,
    'kp0': 0x52, 'kpdot': 0x53, 'sysrq': 0x54, '102nd': 0x56, 'f11': 0x57,
    'f12': 0x58, 'kpenter': 0x9c, 'rightctrl': 0x9d, 'kpslash': 0xb5,
    'rightalt': 0xb8, 'home': 0xc7, 'up': 0xc8, 'pageup': 0xc9,
    'left': 0xcb, 'right': 0xcd, 'end': 0xcf, 'down': 0xd0,
    'pagedown': 0xd1, 'insert': 0xd2, 'delete': 0xd3, 'pause': 0xc6,
    'leftmeta': 0xdb, 'rightmeta': 0xdc, 'compose': 0xdd, 'menu': 0x9e,
    'print': 0xb9, 'mute': 0xa0, 'volumedown': 0xae, 'volumeup': 0xb0,
}
QNUM.update({'ctrl': QNUM['leftctrl'], 'alt': QNUM['leftalt'],
             'shift': QNUM['leftshift'], 'meta': QNUM['leftmeta'],
             'win': QNUM['leftmeta'], 'super': QNUM['leftmeta']})

# US layout, for `type`: char -> (key name, shifted)
CHARS = {}
for _c in "abcdefghijklmnopqrstuvwxyz":
    CHARS[_c] = (_c, False)
    CHARS[_c.upper()] = (_c, True)
for _c in "1234567890":
    CHARS[_c] = (_c, False)
for _c, _k in zip("!@#$%^&*()", "1234567890"):
    CHARS[_c] = (_k, True)
CHARS.update({
    ' ': ('space', False), '\n': ('enter', False), '\t': ('tab', False),
    '-': ('minus', False), '_': ('minus', True), '=': ('equal', False),
    '+': ('equal', True), '[': ('leftbrace', False), '{': ('leftbrace', True),
    ']': ('rightbrace', False), '}': ('rightbrace', True),
    ';': ('semicolon', False), ':': ('semicolon', True),
    "'": ('apostrophe', False), '"': ('apostrophe', True),
    '`': ('grave', False), '~': ('grave', True), '\\': ('backslash', False),
    '|': ('backslash', True), ',': ('comma', False), '<': ('comma', True),
    '.': ('dot', False), '>': ('dot', True), '/': ('slash', False),
    '?': ('slash', True),
})

BUTTON = {"left": 0, "middle": 1, "right": 2}

# drm_fourcc.h, the handful a scanout can be
FOURCC = {}
for _name in ("XR24", "AR24", "XB24", "AB24", "RG16", "XR30", "AR30", "XB30", "AB30", "BG24", "RG24"):
    FOURCC[struct.unpack("<I", _name.encode())[0]] = _name


def fourcc_name(v):
    return FOURCC.get(v, struct.pack("<I", v).decode("ascii", "replace"))


def modifier_name(m):
    # DRM_FORMAT_MOD_LINEAR = 0, DRM_FORMAT_MOD_INVALID = (1<<56)-1; vendor is the top byte.
    if m == 0:
        return "LINEAR"
    if m == (1 << 56) - 1:
        return "INVALID"
    vendor = {0x01: "INTEL", 0x02: "AMD", 0x03: "NVIDIA", 0x04: "SAMSUNG",
              0x05: "QCOM", 0x06: "VIVANTE", 0x07: "BROADCOM", 0x08: "ARM",
              0x09: "ALLWINNER", 0x0a: "AMLOGIC"}.get(m >> 56, "vendor%02x" % (m >> 56))
    return "%s:0x%014x" % (vendor, m & ((1 << 56) - 1))


def log(msg):
    sys.stdout.write("%9.3f %s\n" % (time.monotonic() - T0, msg))
    sys.stdout.flush()


T0 = time.monotonic()


# --- connections ------------------------------------------------------------

def connect(domain):
    """The main p2p connection: libvirt makes the socketpair and add_client."""
    virt = libvirt.open("qemu:///system")
    dom = virt.lookupByName(domain)
    fd = dom.openGraphicsFD(0, 0)
    sock = Gio.Socket.new_from_fd(fd)
    stream = sock.connection_factory_create_connection()
    return Gio.DBusConnection.new_sync(
        stream, None, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT, None, None)


def call(bus, path, iface, method, params=None, reply=None, timeout=25000):
    r = bus.call_sync(None, path, iface, method, params, reply,
                      Gio.DBusCallFlags.NONE, timeout, None)
    return r.unpack() if r is not None else None


def prop(bus, path, iface, name):
    r = bus.call_sync(None, path, "org.freedesktop.DBus.Properties", "Get",
                      GLib.Variant("(ss)", (iface, name)), GLib.VariantType("(v)"),
                      Gio.DBusCallFlags.NONE, 5000, None)
    return r.unpack()[0]


def props(bus, path, iface):
    r = bus.call_sync(None, path, "org.freedesktop.DBus.Properties", "GetAll",
                      GLib.Variant("(s)", (iface,)), GLib.VariantType("(a{sv})"),
                      Gio.DBusCallFlags.NONE, 5000, None)
    return r.unpack()[0]


# --- the listener -----------------------------------------------------------

LISTENER_XML = """
<node>
  <interface name="org.qemu.Display1.Listener">
    <method name="Scanout">
      <arg type="u" name="width" direction="in"/>
      <arg type="u" name="height" direction="in"/>
      <arg type="u" name="stride" direction="in"/>
      <arg type="u" name="pixman_format" direction="in"/>
      <arg type="ay" name="data" direction="in"/>
    </method>
    <method name="Update">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
      <arg type="u" name="stride" direction="in"/>
      <arg type="u" name="pixman_format" direction="in"/>
      <arg type="ay" name="data" direction="in"/>
    </method>
    <method name="ScanoutDMABUF">
      <arg type="h" name="dmabuf" direction="in"/>
      <arg type="u" name="width" direction="in"/>
      <arg type="u" name="height" direction="in"/>
      <arg type="u" name="stride" direction="in"/>
      <arg type="u" name="fourcc" direction="in"/>
      <arg type="t" name="modifier" direction="in"/>
      <arg type="b" name="y0_top" direction="in"/>
    </method>
    <method name="UpdateDMABUF">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
    </method>
    <method name="Disable"/>
    <method name="MouseSet">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
      <arg type="i" name="on" direction="in"/>
    </method>
    <method name="CursorDefine">
      <arg type="i" name="width" direction="in"/>
      <arg type="i" name="height" direction="in"/>
      <arg type="i" name="hot_x" direction="in"/>
      <arg type="i" name="hot_y" direction="in"/>
      <arg type="ay" name="data" direction="in"/>
    </method>
    <property name="Interfaces" type="as" access="read"/>
  </interface>
  <interface name="org.qemu.Display1.Listener.Unix.ScanoutDMABUF2">
    <method name="ScanoutDMABUF2">
      <arg type="ah" name="dmabuf" direction="in"/>
      <arg type="u" name="x" direction="in"/>
      <arg type="u" name="y" direction="in"/>
      <arg type="u" name="width" direction="in"/>
      <arg type="u" name="height" direction="in"/>
      <arg type="au" name="offset" direction="in"/>
      <arg type="au" name="stride" direction="in"/>
      <arg type="u" name="num_planes" direction="in"/>
      <arg type="u" name="fourcc" direction="in"/>
      <arg type="u" name="backing_width" direction="in"/>
      <arg type="u" name="backing_height" direction="in"/>
      <arg type="t" name="modifier" direction="in"/>
      <arg type="b" name="y0_top" direction="in"/>
    </method>
  </interface>
</node>
"""

CLIPBOARD_XML = """
<node>
  <interface name="org.qemu.Display1.Clipboard">
    <method name="Register"/>
    <method name="Unregister"/>
    <method name="Grab">
      <arg type="u" name="selection"/>
      <arg type="u" name="serial"/>
      <arg type="as" name="mimes"/>
    </method>
    <method name="Release">
      <arg type="u" name="selection"/>
    </method>
    <method name="Request">
      <arg type="u" name="selection"/>
      <arg type="as" name="mimes"/>
      <arg type="s" name="reply_mime" direction="out"/>
      <arg type="ay" name="data" direction="out"/>
    </method>
    <property name="Interfaces" type="as" access="read"/>
  </interface>
</node>
"""


def dmabuf_info(fd):
    """What the kernel will tell us about a dma-buf fd without importing it."""
    try:
        link = os.readlink("/proc/self/fd/%d" % fd)
    except OSError as e:
        link = "?(%s)" % e
    try:
        size = os.fstat(fd).st_size
    except OSError:
        size = -1
    return link, size


DMA_BUF_IOCTL_SYNC = 0x40086200  # _IOW('b', 0, __u64)
DMA_BUF_SYNC_READ, DMA_BUF_SYNC_START, DMA_BUF_SYNC_END = 1, 0, 4


def dump_dmabuf(fd, width, height, stride, fourcc, modifier, y0_top, out):
    """CPU-read a LINEAR dma-buf and write it as PNG. Tiled buffers are not
    readable this way (the bytes are in the GPU's swizzle), so this refuses
    rather than writing a scrambled image and calling it a result. A LINEAR
    buffer can still refuse: Triton's blob scanout is an amdgpu BO the render
    server drew into, and its mmap returns EPERM (no CPU access) -- `shot`
    is the path that always works."""
    if modifier != 0:
        log("dump: modifier is %s, not LINEAR -- no CPU dump (import path only)"
            % modifier_name(modifier))
        return False
    from PIL import Image
    size = os.fstat(fd).st_size
    fcntl.ioctl(fd, DMA_BUF_IOCTL_SYNC, struct.pack("Q", DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ))
    try:
        m = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ)
        try:
            raw = bytes(m[:stride * height])
        finally:
            m.close()
    finally:
        fcntl.ioctl(fd, DMA_BUF_IOCTL_SYNC, struct.pack("Q", DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ))
    name = fourcc_name(fourcc)
    mode = {"XR24": "BGRX", "AR24": "BGRA", "XB24": "RGBX", "AB24": "RGBA"}.get(name)
    if mode is None:
        log("dump: fourcc %s not handled" % name)
        return False
    img = Image.frombuffer("RGBA" if mode.endswith("A") else "RGB", (width, height), raw, "raw", mode, stride, 1)
    if y0_top:
        # QEMU's y0_top means the OPPOSITE of what the name suggests to a
        # framebuffer person: false is the ordinary top-down layout (row 0 =
        # top; blob scanouts and QEMU's own placeholder surface), true marks
        # a GL-rendered texture whose row 0 is the bottom, which QEMU's own
        # displays blit flipped (qemu_gl_run_texture_blit(.., flip=y0_top)).
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    img.save(out)
    log("dump: wrote %s (%dx%d %s stride %d)" % (out, width, height, name, stride))
    return True


def find_helper():
    """dmabuf-shot (dmabuf-shot.c beside this file), built with
    gcc -O2 -o dmabuf-shot dmabuf-shot.c $(pkg-config --cflags --libs egl gbm glesv2)"""
    here = os.path.dirname(os.path.abspath(__file__))
    for c in (os.environ.get("DMABUF_SHOT"), os.path.join(here, "dmabuf-shot"), "/tmp/dmabuf-shot"):
        if c and os.access(c, os.X_OK):
            return c
    return None


def shoot(s, out):
    """Read the scanout back through EGL on the render node -- the import M1
    will do, so this works for tiled buffers too -- and save it as PNG. Runs
    the helper synchronously; called from inside the UpdateDMABUF handler it
    reads a frame QEMU is not drawing into (the ack has not gone out)."""
    helper = find_helper()
    if not helper:
        log("shot: no dmabuf-shot helper (build dmabuf-shot.c, or DMABUF_SHOT=path)")
        return False
    fd = s["fds"][0]
    modifier = s["modifier"]
    if modifier == (1 << 56) - 1:  # DRM_FORMAT_MOD_INVALID
        modifier = -1
    ppm = out + ".ppm"
    args = [helper, str(fd), str(s["width"]), str(s["height"]), str(s["strides"][0]),
            str(s["offsets"][0]), str(s["fourcc"]), str(modifier), "1" if s["y0_top"] else "0", ppm]  # see dump_dmabuf on y0_top
    t0 = time.monotonic()
    r = subprocess.run(args, pass_fds=[fd], capture_output=True, text=True)
    if r.returncode != 0:
        log("shot: helper failed: %s" % (r.stderr.strip() or r.returncode))
        return False
    from PIL import Image
    img = Image.open(ppm)
    img.load()
    os.unlink(ppm)
    img.save(out)
    log("shot: wrote %s (%dx%d %s %s, %.0f ms)" % (out, s["width"], s["height"], fourcc_name(s["fourcc"]),
                                                  modifier_name(s["modifier"]), (time.monotonic() - t0) * 1000))
    return True


class Listener:
    """Exports /org/qemu/Display1/Listener on its own p2p connection and
    counts what arrives. `on_scanout` is called with the parsed scanout so a
    subcommand can react (resize waits for the new size, watch dumps)."""

    def __init__(self, bus, v2=True, reply_delay=0.0, on_scanout=None, on_event=None):
        self.v2 = v2
        self.reply_delay = reply_delay
        self.on_scanout = on_scanout
        self.on_event = on_event
        self.counts = {}
        self.updates = []      # (t, x, y, w, h) of the first rects
        self.update_area = 0
        self.scanout = None    # dict of the current scanout
        self.fd = None

        ours, theirs = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        fdl = Gio.UnixFDList.new()
        idx = fdl.append(theirs.fileno())
        bus.call_with_unix_fd_list_sync(
            None, CONSOLE, IFACE_CONSOLE, "RegisterListener",
            GLib.Variant("(h)", (idx,)), None, Gio.DBusCallFlags.NONE, 25000, fdl, None)
        theirs.close()
        sock = Gio.Socket.new_from_fd(os.dup(ours.fileno()))
        ours.close()
        stream = sock.connection_factory_create_connection()
        self.conn = Gio.DBusConnection.new_sync(
            stream, None,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.DELAY_MESSAGE_PROCESSING, None, None)
        info = Gio.DBusNodeInfo.new_for_xml(LISTENER_XML)
        for iface in info.interfaces:
            if iface.name == IFACE_DMABUF2 and not v2:
                continue
            self.conn.register_object(LISTENER, iface, self._method, self._get_prop, None)
        self.conn.connect("closed", lambda c, remote, err: log("listener: connection closed (%s)" % err))
        self.conn.start_message_processing()

    def _get_prop(self, conn, sender, path, iface, name):
        if name == "Interfaces":
            return GLib.Variant("as", [IFACE_DMABUF2] if self.v2 else [])
        return None

    def _count(self, name):
        self.counts[name] = self.counts.get(name, 0) + 1
        return self.counts[name]

    def _method(self, conn, sender, path, iface, method, params, invocation):
        n = self._count(method)
        p = params.unpack()
        msg = invocation.get_message()
        fdl = msg.get_unix_fd_list()
        try:
            if method == "ScanoutDMABUF":
                h, w, hgt, stride, fourcc, modifier, y0_top = p
                fd = fdl.get(h)
                self._set_scanout(dict(kind="ScanoutDMABUF", fds=[fd], width=w, height=hgt,
                                       x=0, y=0, backing_width=w, backing_height=hgt,
                                       strides=[stride], offsets=[0], planes=1,
                                       fourcc=fourcc, modifier=modifier, y0_top=y0_top))
            elif method == "ScanoutDMABUF2":
                hs, x, y, w, hgt, offsets, strides, planes, fourcc, bw, bh, modifier, y0_top = p
                fds = [fdl.get(h) for h in hs]
                self._set_scanout(dict(kind="ScanoutDMABUF2", fds=fds, width=w, height=hgt,
                                       x=x, y=y, backing_width=bw, backing_height=bh,
                                       strides=list(strides), offsets=list(offsets), planes=planes,
                                       fourcc=fourcc, modifier=modifier, y0_top=y0_top))
            elif method == "UpdateDMABUF":
                x, y, w, hgt = p
                self.update_area += w * hgt
                if len(self.updates) < 40:
                    self.updates.append((time.monotonic() - T0, x, y, w, hgt))
                    log("UpdateDMABUF #%d %d,%d %dx%d" % (n, x, y, w, hgt))
                if self.reply_delay:
                    time.sleep(self.reply_delay)
            elif method == "Scanout":
                w, hgt, stride, fmt, data = p
                log("Scanout (PIXEL COPY) %dx%d stride %d pixman 0x%x, %d bytes" % (w, hgt, stride, fmt, len(data)))
                self.scanout = dict(kind="Scanout", width=w, height=hgt, fds=[])
                if self.on_scanout:
                    self.on_scanout(self.scanout)
            elif method == "Update":
                x, y, w, hgt, stride, fmt, data = p
                if n <= 20:
                    log("Update (PIXEL COPY) #%d %d,%d %dx%d, %d bytes" % (n, x, y, w, hgt, len(data)))
            elif method == "CursorDefine":
                w, hgt, hx, hy, data = p
                if n <= 10:
                    log("CursorDefine #%d %dx%d hot %d,%d %d bytes" % (n, w, hgt, hx, hy, len(data)))
            elif method == "MouseSet":
                x, y, on = p
                if n <= 10:
                    log("MouseSet #%d %d,%d on=%d" % (n, x, y, on))
            elif method == "Disable":
                log("Disable")
            else:
                log("%s %r" % (method, p))
            if self.on_event:
                self.on_event(method, p)
        except Exception as e:  # never leave QEMU waiting on a traceback
            log("listener: %s handler failed: %r" % (method, e))
        invocation.return_value(None)

    def _set_scanout(self, s):
        if self.scanout and self.scanout.get("fds"):
            for fd in self.scanout["fds"]:
                os.close(fd)
        self.scanout = s
        infos = [dmabuf_info(fd) for fd in s["fds"]]
        log("%s %dx%d at %d,%d backing %dx%d planes=%d strides=%s offsets=%s fourcc=%s modifier=%s y0_top=%s fds=%s"
            % (s["kind"], s["width"], s["height"], s["x"], s["y"], s["backing_width"], s["backing_height"],
               s["planes"], s["strides"], s["offsets"], fourcc_name(s["fourcc"]),
               modifier_name(s["modifier"]), s["y0_top"],
               ", ".join("%s size=%d" % i for i in infos)))
        if self.on_scanout:
            self.on_scanout(s)

    def summary(self, seconds):
        log("summary over %.1fs: %s" % (seconds, ", ".join("%s=%d" % kv for kv in sorted(self.counts.items()))))
        u = self.counts.get("UpdateDMABUF", 0)
        if u and seconds:
            log("UpdateDMABUF rate %.1f/s, mean damaged area %d px" % (u / seconds, self.update_area // u))


# --- subcommands ------------------------------------------------------------

def cmd_info(bus, a):
    vm = props(bus, ROOT + "/VM", "org.qemu.Display1.VM")
    print("VM:", vm)
    for i in vm.get("ConsoleIDs", [0]):
        c = props(bus, ROOT + "/Console_%d" % i, IFACE_CONSOLE)
        print("Console_%d:" % i, c)
    print("Mouse.IsAbsolute:", prop(bus, CONSOLE, IFACE_MOUSE, "IsAbsolute"))
    print("Keyboard.Modifiers:", prop(bus, CONSOLE, IFACE_KBD, "Modifiers"))
    try:
        print("Clipboard.Interfaces:", prop(bus, CLIPBOARD, IFACE_CLIP, "Interfaces"))
    except GLib.Error as e:
        print("Clipboard: not exported (%s)" % e.message)


def cmd_watch(bus, a):
    loop = GLib.MainLoop()
    dumped = [False]

    def on_scanout(s):
        if a.dump and not dumped[0] and s.get("fds"):
            dumped[0] = dump_dmabuf(s["fds"][0], s["width"], s["height"], s["strides"][0],
                                    s["fourcc"], s["modifier"], s["y0_top"], a.dump)

    lst = Listener(bus, v2=not a.v1, reply_delay=a.reply_delay / 1000.0, on_scanout=on_scanout)
    log("listener registered (advertising %s)" % ("ScanoutDMABUF2" if not a.v1 else "v1 only"))
    start = time.monotonic()
    GLib.timeout_add_seconds(a.seconds, loop.quit)
    if a.dump:
        # a later frame than the first is more representative (the first
        # scanout can precede the guest's first paint)
        def later_dump():
            s = lst.scanout
            if s and s.get("fds"):
                dumped[0] = False
                on_scanout(s)
            return False
        GLib.timeout_add(max(1, a.seconds - 1) * 1000, later_dump)
    loop.run()
    lst.summary(time.monotonic() - start)


def cmd_shot(bus, a):
    loop = GLib.MainLoop()
    done = [None]

    def finish(ok):
        done[0] = ok
        GLib.idle_add(loop.quit)  # after the ack has gone out

    def on_event(method, p):
        s = lst.scanout
        if done[0] is None and method == "UpdateDMABUF" and s and s.get("fds"):
            finish(shoot(s, a.out))

    def fallback():
        if done[0] is None:
            s = lst.scanout
            if s and s.get("fds"):
                log("shot: no UpdateDMABUF in %ds, reading the scanout as it stands" % a.wait)
                finish(shoot(s, a.out))
            else:
                log("shot: no dma-buf scanout in %ds" % a.wait)
                finish(False)
        return False

    lst = Listener(bus, on_event=on_event)
    GLib.timeout_add_seconds(a.wait, fallback)
    loop.run()
    sys.exit(0 if done[0] else 1)


def press_release(bus, names, hold=0.03):
    codes = []
    for n in names:
        if n not in QNUM:
            sys.exit("unknown key %r (evdev name, lower case, no KEY_)" % n)
        codes.append(QNUM[n])
    for c in codes:
        call(bus, CONSOLE, IFACE_KBD, "Press", GLib.Variant("(u)", (c,)))
    time.sleep(hold)
    for c in reversed(codes):
        call(bus, CONSOLE, IFACE_KBD, "Release", GLib.Variant("(u)", (c,)))


def cmd_key(bus, a):
    for chord in a.keys:
        press_release(bus, [k.lower() for k in chord.split("+")])
        time.sleep(a.delay / 1000.0)


def cmd_type(bus, a):
    for ch in a.text:
        if ch not in CHARS:
            sys.exit("cannot type %r on the US layout table" % ch)
        key, shifted = CHARS[ch]
        press_release(bus, (["leftshift"] if shifted else []) + [key])
        time.sleep(a.delay / 1000.0)


def cmd_mouse(bus, a):
    if not prop(bus, CONSOLE, IFACE_MOUSE, "IsAbsolute"):
        sys.exit("Mouse.IsAbsolute is false: no tablet device in the domain")
    call(bus, CONSOLE, IFACE_MOUSE, "SetAbsPosition", GLib.Variant("(uu)", (a.x, a.y)))
    if a.move:
        return
    button = BUTTON["right" if a.right else "left"]
    if a.drag:
        # press, sweep to the target in steps (Windows wants motion between
        # press and release to call it a drag), release; --seconds paces the
        # sweep so a GPU counter can be read while the window is moving
        x2, y2 = a.drag
        call(bus, CONSOLE, IFACE_MOUSE, "Press", GLib.Variant("(u)", (button,)))
        steps = max(2, int(a.seconds * 60))
        t0 = time.monotonic()
        for i in range(1, steps + 1):
            time.sleep(a.seconds / steps)
            x = a.x + (x2 - a.x) * i // steps
            y = a.y + (y2 - a.y) * i // steps
            try:
                call(bus, CONSOLE, IFACE_MOUSE, "SetAbsPosition", GLib.Variant("(uu)", (x, y)))
            except GLib.Error as e:
                # seen on the Triton domain: the p2p connection closes under
                # the drag with no other client attached -- say where
                sys.exit("drag: %s at step %d/%d, %.2fs in" % (e.message, i, steps, time.monotonic() - t0))
        time.sleep(0.05)
        call(bus, CONSOLE, IFACE_MOUSE, "Release", GLib.Variant("(u)", (button,)))
        return
    for _ in range(2 if a.double else 1):
        time.sleep(0.05)
        call(bus, CONSOLE, IFACE_MOUSE, "Press", GLib.Variant("(u)", (button,)))
        time.sleep(0.05)
        call(bus, CONSOLE, IFACE_MOUSE, "Release", GLib.Variant("(u)", (button,)))


def cmd_resize(bus, a):
    loop = GLib.MainLoop()
    before = props(bus, CONSOLE, IFACE_CONSOLE)
    log("console before: %dx%d" % (before["Width"], before["Height"]))
    got = []

    def on_scanout(s):
        if (s["width"], s["height"]) == (a.width, a.height):
            got.append(s)
            loop.quit()

    lst = Listener(bus, on_scanout=on_scanout)

    # Once a listener is registered, every call to QEMU must be async from
    # inside the loop: QEMU's main thread is doing a sync GetAll on our
    # listener object right now, and a sync call from here deadlocks both
    # sides for the 25 s D-Bus timeout (after which QEMU has given up on
    # ScanoutDMABUF2 and downgraded us to v1).
    def sent(src, res):
        try:
            bus.call_finish(res)
            log("SetUIInfo(%d, %d) accepted, waiting up to %ds for a scanout of that size"
                % (a.width, a.height, a.timeout))
        except GLib.Error as e:
            log("SetUIInfo failed: %s" % e.message)
            loop.quit()

    def send():
        # width_mm/height_mm 0 = "don't care"; xoff/yoff 0
        bus.call(None, CONSOLE, IFACE_CONSOLE, "SetUIInfo",
                 GLib.Variant("(qqiiuu)", (0, 0, 0, 0, a.width, a.height)),
                 None, Gio.DBusCallFlags.NONE, 10000, None, sent)
        return False

    GLib.timeout_add(500, send)  # after QEMU has finished registering us
    GLib.timeout_add_seconds(a.timeout, loop.quit)
    loop.run()
    after = props(bus, CONSOLE, IFACE_CONSOLE)
    log("console after: %dx%d  (%s)" % (after["Width"], after["Height"],
                                         "resized" if got else "NO scanout at the requested size"))
    lst.summary(a.timeout)


def cmd_uiinfo(bus, a):
    """SetUIInfo alone, on a connection with no listener: pair it with a
    `watch` in another process to see the guest's reaction on one timeline."""
    before = props(bus, CONSOLE, IFACE_CONSOLE)
    call(bus, CONSOLE, IFACE_CONSOLE, "SetUIInfo",
         GLib.Variant("(qqiiuu)", (0, 0, 0, 0, a.width, a.height)))
    log("SetUIInfo(%d, %d) accepted; console was %dx%d"
        % (a.width, a.height, before["Width"], before["Height"]))


class ClipboardPeer:
    """Our side of org.qemu.Display1.Clipboard: QEMU calls Grab/Release when
    the guest copies, Request when the guest pastes what we grabbed."""

    def __init__(self, bus, text=None, on_grab=None):
        self.bus = bus
        self.text = text
        self.on_grab = on_grab
        self.grabs = []
        self.requests = 0
        info = Gio.DBusNodeInfo.new_for_xml(CLIPBOARD_XML)
        bus.register_object(CLIPBOARD, info.interfaces[0], self._method, self._get_prop, None)

    def _get_prop(self, conn, sender, path, iface, name):
        return GLib.Variant("as", []) if name == "Interfaces" else None

    def _method(self, conn, sender, path, iface, method, params, invocation):
        p = params.unpack()
        if method == "Grab":
            log("guest Grab selection=%d serial=%d mimes=%s" % p)
            self.grabs.append(p)
            invocation.return_value(None)
            if self.on_grab:
                self.on_grab(p)
        elif method == "Release":
            log("guest Release selection=%d" % p)
            invocation.return_value(None)
        elif method == "Request":
            self.requests += 1
            log("guest Request selection=%d mimes=%s" % p)
            data = (self.text or "").encode()
            invocation.return_value(GLib.Variant("(say)", (MIME_TEXT, data)))
        elif method == "Register":
            log("QEMU re-registered the clipboard session (serial reset)")
            invocation.return_value(None)
        else:
            log("clipboard %s %r" % (method, p))
            invocation.return_value(None)


def cmd_clipboard(bus, a):
    loop = GLib.MainLoop()
    state = {"result": None}

    def request():
        bus.call(None, CLIPBOARD, IFACE_CLIP, "Request",
                 GLib.Variant("(uas)", (0, [MIME_TEXT])), GLib.VariantType("(say)"),
                 Gio.DBusCallFlags.NONE, 10000, None, requested)

    def requested(src, res):
        try:
            mime, data = bus.call_finish(res).unpack()
            state["result"] = bytes(data).decode("utf-8", "replace")
            log("guest clipboard (%s): %r" % (mime, state["result"]))
            loop.quit()
        except GLib.Error as e:
            log("Request failed: %s -- waiting for the guest to Grab" % e.message)

    # a guest copy after we registered shows up as a Grab; fetch it then
    peer = ClipboardPeer(bus, text=a.text, on_grab=(lambda p: request()) if a.op == "get" else None)

    def grabbed(src, res):
        try:
            bus.call_finish(res)
            log("Grab ok: host owns the clipboard; paste in the guest within %ds" % a.timeout)
        except GLib.Error as e:
            log("Grab failed: %s" % e.message)

    def registered(src, res):
        try:
            bus.call_finish(res)
            log("Register ok")
        except GLib.Error as e:
            log("Register failed: %s" % e.message)
            loop.quit()
            return
        if a.op == "set":
            bus.call(None, CLIPBOARD, IFACE_CLIP, "Grab",
                     GLib.Variant("(uuas)", (0, 1, [MIME_TEXT])), None,
                     Gio.DBusCallFlags.NONE, 5000, None, grabbed)
        else:
            request()

    # async on purpose: QEMU's Register handler does a sync GetAll on our
    # object before it replies, which needs our loop running
    bus.call(None, CLIPBOARD, IFACE_CLIP, "Register", None, None,
             Gio.DBusCallFlags.NONE, 10000, None, registered)
    GLib.timeout_add_seconds(a.timeout, loop.quit)
    loop.run()
    if a.op == "set":
        log("guest requested our text %d time(s)" % peer.requests)
    elif state["result"] is None:
        log("no clipboard text obtained")
        sys.exit(1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-d", "--domain", default=DEFAULT_DOMAIN)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info").set_defaults(fn=cmd_info)

    w = sub.add_parser("watch")
    w.add_argument("--seconds", type=int, default=10)
    w.add_argument("--reply-delay", type=float, default=0, help="ms to sleep before acking each UpdateDMABUF")
    w.add_argument("--v1", action="store_true", help="do not advertise ScanoutDMABUF2")
    w.add_argument("--dump", help="write the scanout to this PNG if it is CPU-readable (LINEAR)")
    w.set_defaults(fn=cmd_watch)

    sh = sub.add_parser("shot", help="screenshot: import the scanout dma-buf through EGL (dmabuf-shot.c)")
    sh.add_argument("out", help="PNG path")
    sh.add_argument("--wait", type=int, default=5, help="seconds to wait for an UpdateDMABUF before reading anyway")
    sh.set_defaults(fn=cmd_shot)

    k = sub.add_parser("key")
    k.add_argument("keys", nargs="+", help="evdev names, lower case; chords with '+', e.g. leftmeta+r")
    k.add_argument("--delay", type=float, default=60, help="ms between chords")
    k.set_defaults(fn=cmd_key)

    t = sub.add_parser("type")
    t.add_argument("text")
    t.add_argument("--delay", type=float, default=30, help="ms between characters")
    t.set_defaults(fn=cmd_type)

    m = sub.add_parser("mouse")
    m.add_argument("x", type=int)
    m.add_argument("y", type=int)
    g = m.add_mutually_exclusive_group()
    g.add_argument("--click", action="store_true", help="left click (default)")
    g.add_argument("--right", action="store_true")
    g.add_argument("--double", action="store_true")
    g.add_argument("--move", action="store_true", help="move only")
    m.add_argument("--drag", type=int, nargs=2, metavar=("X2", "Y2"), help="press at x,y, sweep to X2,Y2, release")
    m.add_argument("--seconds", type=float, default=1.0, help="how long a --drag sweep takes")
    m.set_defaults(fn=cmd_mouse)

    r = sub.add_parser("resize")
    r.add_argument("width", type=int)
    r.add_argument("height", type=int)
    r.add_argument("--timeout", type=int, default=15)
    r.set_defaults(fn=cmd_resize)

    u = sub.add_parser("uiinfo", help="SetUIInfo without registering a listener")
    u.add_argument("width", type=int)
    u.add_argument("height", type=int)
    u.set_defaults(fn=cmd_uiinfo)

    c = sub.add_parser("clipboard")
    c.add_argument("op", choices=["get", "set"])
    c.add_argument("text", nargs="?")
    c.add_argument("--timeout", type=int, default=20)
    c.set_defaults(fn=cmd_clipboard)

    a = p.parse_args()
    if a.cmd == "clipboard" and a.op == "set" and a.text is None:
        p.error("clipboard set needs text")
    bus = connect(a.domain)
    a.fn(bus, a)


if __name__ == "__main__":
    main()
