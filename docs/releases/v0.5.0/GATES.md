# 0.5.0 release validation

Run on 2026-09-19 from `release-0.5.0` in both repositories.
The tested package contains runtime source commit `7d2e402`; the later
`65c5648` and `e91582f` commits correct test setup, capture timing and log buffering without changing the
packaged runtime. This is release preparation, not a published release.

## Artifact

- Package: `starling_0.5.0_amd64.deb`
- Target: Ubuntu 26.04 LTS, amd64
- Build stamp: `7d2e402 2026-09-19 22:12:15`
- SHA-256: `b56e3d722c38cceccffd900fbdbc889cbdd50f20c7276e38c02502cb1786528d`
- Package includes `libstarling_room.so` and the city world assets.

## Checks

| Gate | Result |
| --- | --- |
| Release engine build | Passed; host_release was up to date |
| Static and standard unit/protocol tests | Passed, including rerun after the RDP fix |
| SDK tests | Passed: 4,307 XCTest tests and 822 Swift Testing tests |
| Release SDK, shell, all apps and renderer | Passed |
| Debian packaging | Passed |
| Independent display lenses | Passed: 48 checks |
| Independent GPU scenes | Passed: cameras, render targets, mixed sizes and teardown |
| Live two-display navigation | Passed on both connected displays |
| Website in Chrome | Passed: desktop/mobile layout, preview toggle, playback, captions, no-JavaScript player |
| WSL/RDP display mode | Passed: all 15 checks |
| Clean VM, accelerated rendering | Passed: 34 checks passed, six skipped |
| Same package, software rendering | Passed: 28 checks passed, 12 skipped |
| Power-menu shutdown | Passed: the guest powered itself off through the UI |

## Failures found and corrected

The animated city continued rendering in WSL without an RDP viewer. Idle CPU
was about 9.7% before a connection and 9.6% after disconnect. The scene clock
now stops without a viewer and restarts on connection. The expanded WSL gate
explicitly enables 3D, verifies visible motion and reconnects. Both idle
measurements were 0.00% after the fix; motion was visible on both connections.

The recording-zoom test's launch click was consumed by the VM's screensaver.
The preceding recording test analyzes frames long enough to exceed the gate's
15-second idle timeout. Reproduction confirmed the first click woke the desktop
and the second launched Terminal. The test now wakes explicitly and waits for
the saver to clear. The isolated regression passed from an idle desktop:
screen difference 0.02, recorded edge-density ratio 0.70. Its original recording
assertions were retained.

The first software-rendered city frame took 15.3 seconds in the four-vCPU
llvmpipe VM, while the capture helper gave up after six seconds. The shell
remained alive and subsequently saved the requested frame. The helper now waits
up to 30 seconds using a monotonic deadline. The isolated no-GPU 3D regression
then passed: entering changed the image, and leaving restored the 2D pixels
exactly. This does not establish interactive city performance on software GL;
its cold start is substantially slower than hardware rendering.

## VM coverage limits

The accelerated tier reports six skips: no managed wired device, no simulated
Wi-Fi lab, missing hostile DMA-buffer fixtures, no discrete GPU, no GStreamer,
and the pixel-glyph fixture not copied into the VM. The unit glyph-coverage gate
ran separately. The software tier additionally omits real app installations and
the identity/removal checks that depend on the removed GIMP installation; the
accelerated tier already exercised those on this exact package.

The accelerated pass is preserved in `verified-vm.log`. After correcting the
capture helper, the software tier and power-menu steps were resumed from the
same `test/vm.sh` on the same installed package, rather than reinstalling the
already-validated artifact. `resume-software.sh` preserves those exact steps,
checks the installed shell against the packaged binary's SHA-256, verifies that
virgl is disabled, and restores the test fixtures before running the complete
software functional suite. Its final exit status was zero. Shutdown completed
within the harness's 120-second bound, after the guest's session-stop timeout.

## Local evidence

Logs and packages are retained on the build machine under
`/home/starling/tmp/release-0.5.0-gates/`:

- `build.log`, `idle-fix-unit.log`, `final-build.log`, `final-package.log`
- `navigation.log`, `independent-scenes.log`, `website.log`
- `final-wsl.log`, `zoom-repro.log`, `zoom-fixed.log`, `verified-vm.log`
- `software-3d-fixed.log`, `software-vm.log`, `resume-software.sh`
- `final-pkg/starling_0.5.0_amd64.deb`

Earlier logs preserve the failures and the superseded package for comparison.
