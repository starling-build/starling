# The QEMU the guest windows run on

Starling ships its own QEMU. `build-qemu.sh` produces it, from **Ubuntu's**
source with two patches on top, installed **side by side** at
`/usr/lib/starling/qemu` — the distro's package is untouched and keeps serving
every other VM on the machine. A guest domain opts in by naming it:

    <emulator>/usr/lib/starling/qemu/bin/qemu-system-x86_64</emulator>

Side by side rather than a replacement, because this build is configured for
one job — `x86_64-softmmu` and the D-Bus display path, with SDL, GTK, VNC,
SPICE and the tools all off. As a general-purpose QEMU it would be a
downgrade, and nothing about the desktop needs it to be one.

## The two patches, and what each one costs without it

Both are against `ui/`, both are small, and both were found by running the
desktop against a real Windows guest (`docs/plans/guest-display.md`).

**`listener-no-scanout-without-texture.patch`** — *rebooting the guest kills
the VM.* On reset the console hands `dbus_gl_gfx_switch()` a fresh
`DisplaySurface` whose GL texture has not been created yet, and it passes
`ds->texture` (0) into `dbus_scanout_texture()`, which asserts. The whole VM
dies, not just the window. The fix is a three-word guard. Without it, a
Windows Update restart takes the machine down while someone is using it.

**`clipboard-forward-serial-less-guest-grabs.patch`** — *copying in Windows
never reaches the desktop.* The Windows vd_agent never announces
`VD_AGENT_CAP_CLIPBOARD_GRAB_SERIAL`, so QEMU builds its grab info with
`has_serial = false` and `dbus_clipboard_update_info()` returns before
forwarding the guest's Grab. Host-to-guest works; guest-to-host cannot, on any
Windows guest. Both directions work with it.

## What is NOT here, and why

`docs/windows-vm/triton/patches/` holds five patches; three of them are not
ours. `0001` (make the render-node context current for texture ops), `0002`
and `0004` are all about the **virgl** path — Triton, 3D, a research
direction. M1 runs a 2D guest (`viogpudo`, no virgl), which is why every one
of its milestones was reached on *unpatched* Ubuntu QEMU except the two
failures above. Carrying patches we do not need would be carrying divergence
we cannot justify.

Upstreaming the scanout guard is still worth doing on its own merits — it is a
defensive check on a path reachable with no texture to draw, and any
`dbus-display` user with `gl=on` can hit it. Nothing here waits on that.

## Building it

    build/qemu/build-qemu.sh           # build and install
    build/qemu/build-qemu.sh --check   # is it already installed, and what version

It needs `apt-get build-dep qemu` (which it runs), a source tree under
`/var/tmp/starling-qemu`, and about ten minutes on sixteen cores.
`STARLING_QEMU_PREFIX` and `STARLING_QEMU_WORK` override the two paths.

The patches apply with `--fuzz=3` on purpose: they are small hunks in files
Ubuntu also patches, and demanding exact offsets would fail on a point release
for no reason. A genuine reject is still fatal.

## Matching the machine type

This is a point release of the distro's QEMU, so its machine types are the
distro's. A domain built against a *different* QEMU (the Triton tree is
10.0.12) names an older `pc-q35-…` and will not start here — set the machine
type to one this build offers, or keep that domain on the emulator it was
built for.
