# Starling 0.3.0 — apps can render on the NVIDIA GPU

The first release since 0.2.3 that changes what the desktop can do rather than
what it gets wrong. Ninety-two commits. The headline is that a laptop with two
GPUs now behaves like one: the shell keeps the display, and an app that wants
the discrete card gets it.

## Per-app PRIME render offload

An app's registry record can say where it renders:

    Gpu=discrete

One key, read by both launch paths, with the policy in the record and the
mechanism in the launcher — no app tables in the shell. `DiscreteGpu` resolves
"the render node that is not the shell's" by comparing sysfs PCI devices
against `FLUTTER_DRM_DEVICE`, falling back to `boot_vga` when that is unset (a
discrete 3D controller has no `boot_vga` file, which is what makes the fallback
work). The compositor then serves that client dma-buf feedback naming the
discrete node, so its buffers come back importable instead of being silently
dropped.

Blender ships with the key set. Anything else is one line in its `.app` record.

Two things this shook out along the way: a client whose dma-buf we cannot
import can no longer take the shell down with it, and the in-tree X server now
hands DRI3 clients the GPU the compositor is actually on rather than assuming
card0.

The screen recorder learned the same lesson — it encodes on whichever GPU has
the frames, and says which one it picked instead of only that it is ready.

## Every monitor is its own desktop

Displays have separate Spaces. Each monitor runs its own workspace, Mission
Control opens on the monitor you asked for it on, a secondary's space switch
slides like the host's, and the second monitor's desktop is a desktop rather
than a picture of one. Typing into a window on a second screen shows up without
needing a nudge.

## Workspace mode

A named workspace holds a driver app down the middle and everything it opens as
tabs on the right, with the workspace list on the left. Rename from the pencil
on the row you are pointing at; delete from the trash beside it, which stops the
apps rather than rehoming them. Tabs you can read, and a way out.

## Recording, with a camera

**Ctrl+Shift+=** and **Ctrl+Shift+-** zoom the recording — 1x, 1.5x, 2x, 3x —
and nothing on screen moves: it crops what the encoder sees, so the room sees
nothing and the take comes out zoomed. On a 4K panel the 2x step is the 1:1
crop, which makes a zoomed shot sharper than the wide one rather than softer.
While zoomed the crop follows the pointer, so a narrator cannot walk out of
their own shot. The menu-bar indicator reads `0:07  2.0×`, because the feature
is deliberately invisible on screen and that is the only feedback there is.

## X server

Three protocol fixes, all of which broke real apps: `XGrabPointer` is honoured
instead of being answered with success and ignored, pointer events are no longer
delivered twice, and two event/reply framing bugs that broke Zoom and Chromium
apps are fixed. Menus composite.

## Terminal

Scrolling inside a full-screen app used to replace it with the shell's old
output — the scrollback belongs to the primary buffer, and the wheel was walking
it. The alternate screen no longer touches scrollback; mouse reporting
(1000/1002/1003 with SGR 1006) is implemented for the wheel, so Claude Code,
`less` and `htop` scroll themselves; anything that asks for no mouse gets
xterm's alternateScroll fallback. Terminal cell metrics are measured with the
same font the rows are painted in, so a font that fails to resolve no longer
puts the cursor 24 cells adrift.

## Known issues

**`fl_drm_view.h` drift.** The engine grew an external-outputs API
(`fl_drm_view_set_output_external` and an input callback) that the shell does
not use, and the SDK's copy of the header has not been updated to match. The
fast tier has been red on this since the API landed. It cannot affect this
release: the shell never enables an external output, so the callback can never
fire. Closing it properly means wiring the input path, which is feature work and
did not belong in a release branch.

## Verified

T3 release gate on a clean Ubuntu 26.04 VM: `.deb` installed the way the docs
tell a user to, rebooted into GDM, logged in, session confirmed seat-active and
started by the display manager (not by hand), polkit authorising `app-install`
through the pkexec hop — then the functional suite twice, once with 3D
acceleration and once on llvmpipe with none.
