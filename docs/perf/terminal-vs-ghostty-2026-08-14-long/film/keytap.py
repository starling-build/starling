#!/usr/bin/env python3
# Minimal uinput keyboard: taps a named combo into the running compositor.
# Usage: sudo keytap.py super+left | super+right | alt+tab
import fcntl, struct, sys, time
KEYS = {"super": 125, "alt": 56, "left": 105, "right": 106, "tab": 15}
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405c5503, 0x5501, 0x5502
f = open("/dev/uinput", "wb", buffering=0)
fcntl.ioctl(f, UI_SET_EVBIT, 1)                     # EV_KEY
for code in KEYS.values(): fcntl.ioctl(f, UI_SET_KEYBIT, code)
fcntl.ioctl(f, UI_DEV_SETUP, struct.pack("HHHH80sI", 3, 1, 1, 1, b"keytap", 0))
fcntl.ioctl(f, UI_DEV_CREATE)
time.sleep(1.0)                                     # let GNOME bind the device
def emit(t, c, v): f.write(struct.pack("llHHi", 0, 0, t, c, v))
def syn(): emit(0, 0, 0)
combo = [KEYS[k] for k in sys.argv[1].split("+")]
for c in combo: emit(1, c, 1); syn(); time.sleep(0.05)
time.sleep(0.15)
for c in reversed(combo): emit(1, c, 0); syn(); time.sleep(0.05)
time.sleep(0.3)
fcntl.ioctl(f, UI_DEV_DESTROY)
