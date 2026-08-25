# Tests

```
test/run.sh                  static checks + unit tests   ~0.4s, no GPU
test/run.sh --build          + every package and the .deb  ~4min
test/run.sh --sdk            + sdk/ tests (see "Known gaps")
sudo test/run.sh --functional   + live-desktop checks       ~15s, needs a GPU
sudo test/functional.sh      the live-desktop checks on their own
test/vm.sh                   T3 release gate: .deb on a clean VM, GDM login
sudo test/net-sim.sh up      simulated network, for the network checks
```

Run the default tier on every change. It needs no compositor, no GPU, no
network, and no build.

**It also runs on the Mac**, where the terminal and the SDK are developed, and
it has to come back PASS there or it stops being read. Two steps skip on a
platform that cannot host them — `record` wants VA-API headers, the clipboard
bridge wants Wayland ones — and each says so on the line where it skips. The
glyph gate does *not* skip: it follows the `#if os(macOS)` in
`TerminalView.register()` and checks the families the terminal names through
CoreText, which is why ❌ resolves there without a Noto file in sight. A step
that cannot run says SKIPPED; a step that runs says what it found.

## Simulated network

`test/net-sim.sh up` builds a network lab, wireless and wired, so the network
UI can be driven end to end without touching the machine's real connection.
`down` removes every trace. Needs `hostapd` and `dnsmasq-base`; without them
it exits 3 and the network checks skip rather than fail.

- **Wireless** — `mac80211_hwsim` gives three virtual radios. Two run hostapd
  (**Starling-Lab**, WPA2, password `starling123`; **Starling-Guest**, open);
  the third is left to NetworkManager as the client. Scans, associations,
  leases and wrong-password failures are all real.
- **Wired** — a veth pair, one end managed by NetworkManager as an ordinary
  ethernet device (`starling-lan`), the other playing the switch with its own
  DHCP. This exists so connect/disconnect can be exercised on *something other
  than the developer's real NIC*: disconnecting that one takes their network
  with it, and the UI offers no way to tell the two apart.

The functional tier's wifi check joins the **open** network, so it asserts the
network path rather than the shell's text input; the wired check is read-only
and compares the shell against `nmcli`.

Two caveats when testing by hand:

- `up` installs a polkit rule for the invoking user, because a shell launched
  over SSH is not seat-active and polkit would otherwise deny every connect. A
  real session needs no such rule — **remove it before concluding anything
  about the shipping path**, or the dev box will tell you a privileged
  operation works when it only worked for you.
- Ubuntu's server/cloud base lets NetworkManager manage only WiFi, leaving the
  wire to netplan, so wired devices appear as `unmanaged` and the desktop
  correctly shows none. The .deb ships
  `/usr/lib/NetworkManager/conf.d/90-starling-managed-devices.conf` to fix
  that; on a dev tree run from source, there is no such file, and the wired
  check skips on a machine whose ethernet NM does not manage.

## Why these checks

Almost every expensive bug in this project has had the same shape: **two
places that must agree, silently disagreeing.** Nothing crashes and nothing
logs; the symptom surfaces much later as "that one app is broken".

- `wayland_server_on_shm_surface_commit` was declared, defined and called in C
  — and never registered in Swift, so every software client composited as
  nothing while its buffers were dutifully released.
- `wayland_server_on_app_id_changed`, same shape: every window's identity
  thrown away, so the dock guessed from window titles and no third-party app
  got an icon.
- An app id present in seven tables and missing from two, so IntelliJ launched
  fine but had no dock presence and no icon.

So the checks are all comparisons between two sources that must match, and
they are cheap enough that there is no excuse to skip them.

### `lint.py` — static, no build

- **Catalog**: every `registry/catalog.d/*.app` parses; `Id` matches its
  filename; `Kind` and `Glyph` are values something actually implements (the
  glyph vocabulary is *read out of* `DesktopShell.iconType(named:)` and the
  store's `iconKind`, so adding a glyph does not make the lint wrong);
  `Color` is RRGGBB; `Order`/`Dock` do not collide; `Bins` are absolute;
  `Install=` names a real recipe in `app-install.sh`; `Exec=` names a real one
  in `app-run.sh`; first-party `Exec` is a real package under `apps/` and has
  a `Window=`; `RenameWindows` has something that can identify its windows.
- **The reverse direction**: an `app-install` recipe with no catalog record
  and not in its `UNLISTED` list. That is how mpv/vlc/libreoffice/obs became
  installable but invisible to the whole desktop.
- **Wayland callbacks**: every `wayland_server_on_*` declared in
  `wayland_server.h` is registered somewhere in the Swift shell. Deliberate
  exceptions live in `KNOWN_UNREGISTERED` and each one needs a written reason
  — a bare name is not enough, because the entire point is that an
  unregistered callback is invisible.
- **Syntax**: every build script parses, each with the shell it declares
  (`run-desktop.sh` and `wechat-run.sh` are bash and use arrays, which
  `sh -n` rejects for syntax it does not have).

### `registry/Tests` — unit, `swift test`

The parsing and matching that app identity rests on: key-file group scoping
(a `.desktop` file's `[Desktop Action …]` groups must not override
`[Desktop Entry]`), `;`-lists, app_id matching, installed-ness, the default
dock, `Window=` parsing, and the `" (deleted)"` exe suffix. Every case here is
one that occurs on a real machine.

### `functional.py` — a live desktop, asserted through the broker

`sudo test/functional.sh` stands up a desktop with a fixture catalog, runs the
checks, and tears it down. Everything is asserted against broker JSON —
`list_apps` (what the launcher would show), `dock_rects` (the dock as laid out
right now) — and never against pixels. A screenshot suite over a compositor
rots faster than it catches anything: every theme tweak and animation
invalidates it, the baseline gets re-blessed, and it ends up testing nothing.
Screenshots stay artifacts for humans.

**One check reads pixels**, and what that rule is against is a stored
*baseline* — of which it has none. See `glyph-pixels.py` below.

Nine checks: the shell agrees with `catalog.d` on disk; the dock's pinned slots
are the installed `Dock=` apps in order; **a real app installs through
`app-install` and appears in the launcher**; a third-party window is attributed
via app_id; **a window is not attributed to an app that merely shares its
binary**; a dock click launches a first-party app (which also exercises the
live dock geometry end to end); a record appearing and disappearing moves the
launcher with no relogin; `app-install` refuses to remove a running app; and
**that real app removes again and leaves the launcher**.

The install and remove of a real app are gated on `STARLING_TEST_INSTALL=1`
(they download a package) and `test/vm.sh` turns them on. They matter for a
reason beyond coverage: the app the identity checks need is *produced* by the
install check rather than set up behind the tests' back. An earlier version
ran `apt-get install gimp` and then `app-install --record gimp` — fabricating
the end state with the repair tool, exercising none of the real path, and
quietly making "can this desktop install an app?" a preconditon instead of a
question. `app-install <id>` is exactly the subprocess the store's Install
button runs; the store adds `pkexec`, and that hop is proved separately by the
`pkcheck` step in `test/vm.sh`.

That fourth check is what keeps the third honest. "GIMP's window was
attributed to gimp" would also pass if the shell credited any window to any
running app — so `test/fixtures/starlingnotgimp.app` shares GIMP's binary and
declares a window class matching nothing. While GIMP runs, the shell must
report the decoy as process=true, window=false.

The install/remove loop uses `test/fixtures/starlingselftest.app`: no vendor,
no download, nothing on the machine worth breaking. Testing that loop against a
real app means uninstalling real software to prove a button works — which is
how the author of these files uninstalled the user's GIMP.

Fixtures are overlaid onto a *copy* of the real catalog via
`STARLING_CATALOG_DIR`; the shipped catalog is never modified. They are
deliberately outside `lint.py`'s scope: they are test doubles, not apps, and
`starlingselftest` has an `Exec` that launches nothing on purpose.

### `glyph-pixels.py` — the terminal's pixels, in the functional tier

Everything else in this tree checks the **grid**. The grid has been right in
every rendering failure this terminal has shipped, and there have been four:

| what happened | how it looked | what saw it |
| --- | --- | --- |
| no glyph in any loaded face | box drawing, then braille, painted nothing | a person, months apart |
| a run downstream of a backwards font fallback | `日本語 ✓✗→` lost its tail | a person, `cat`ing the corpus |
| a cell background painted by the text engine | short of its cell, or absent | this gate, first run |
| a row placed by the shaper | wide glyphs walked off their columns | a person, screenshotting |

The benchmark scored all four as *improvements*, because not painting is
cheaper than painting. `test/bench/glyph-gate.py` closed the first (a font
question, answered from the fonts on disk, in the default tier). This closes
the rest, where the only evidence is what reached the screen.

It works without a baseline: the terminal prints a block whose background it
sets itself, including a **ruler** — a row of cells with alternating background
colours, which the row painter fills by the grid rect. So the cell grid is
measured from the same frame as the glyphs, and every assertion relates two
things inside that one screenshot: does this cell contain ink, does the row's
background cover its cells, and does the row's last glyph sit on the column the
ruler puts it in. Change the theme, the font or the window and it re-derives
itself.

    sudo test/glyph-pixels.py            drive a live desktop end to end
    sudo test/glyph-pixels.py --keep     ... and leave the terminal up
         test/glyph-pixels.py --shot P   analyse a screenshot taken earlier
         test/glyph-pixels.py --pattern  print the pattern, to run by hand

Verified failing, twice. With `DejaVuSans.ttf` moved out of the staged
resources it reports `braille: 19/20 glyphs painted NOTHING`; against the
renderer as it stood before this work it reports seventeen findings — a blank
ruler, eleven rows showing the terminal through their backgrounds, a glyph that
never painted, and rows off their columns.

### `vm.sh` — the release gate

`test/vm.sh` builds the .deb, reverts the VM to its clean `desktop-ready`
snapshot, installs the package the way the docs tell a user to, sets up a GDM
login, reboots into it, and then runs the functional tier **against that
session**. The harness it drives — the launchers, `ssh-vm.sh`/`scp-vm.sh`, the
in-guest `g1`/`g2`/`g3` steps and the QMP input helpers — is in
`test/vm-harness/`. Only the VM **state** is outside the repo, at
`$STARLING_VM` (default `~/starling-vm`): the disk images run to tens of
gigabytes and the guest SSH key is a secret. `test/vm-harness/README.md`
documents both, including how to build a state directory from scratch.

It is the only tier that runs against the thing we actually ship, and the only
one that can see privilege-path bugs. Two have already cost real time: the
portal claiming its D-Bus name on the wrong bus (breaking every file dialog,
while working perfectly under sudo on the dev box), and `pkexec app-install`,
which polkit authorises only for the seat-active session. Every dev shell here
is SSH-launched and therefore not it, so the App Store's Install and Remove
buttons *cannot* work on the dev box — the gate proves they do in a real
login, using `pkcheck` against the session's own shell process.

It then reboots the same installed desktop onto **plain `virtio-vga` — no 3D
acceleration** — and runs the functional checks a second time. A GPU hides a
class of bug this pass exists to catch: the shell holds the primary DRM node
through libseat and can allocate on it, while a child app has only what it can
open for itself. v0.2 shipped with every app allocating on a render node,
which rejects the dumb-buffer ioctl software Mesa falls back to, so on a
machine with no GPU the desktop came up and **not one app could start** — and
no tier could see it, because every tier had a GPU. GNOME Boxes, VirtualBox
and VMware all default to 3D acceleration off, so that is the configuration
most people evaluating the .deb are in. The pass asserts the guest really
reports `-virgl` first, or it would silently be a second run of the tier
above.

Note it needs port 2222 free: the harness forwards a fixed port, and the
minimal dependency-testing VM uses the same one. The script refuses rather
than testing the wrong machine.

## Not built yet

- **Performance** — few robust metrics with generous thresholds and a trend
  CSV: shell time-to-first-frame, per-app launch-to-settled (`await_settled`
  gives a defensible signal), frame pacing, and RSS after N launch/close
  cycles as a leak canary. Not micro-benchmarks: in a virgl VM absolute
  numbers are meaningless and only regressions matter.

## Known gaps this suite has already surfaced

- **`wayland_server_on_toplevel_resize_request`** is declared and fired from
  `xdg_toplevel.set_max_size` *and* `set_min_size`, and registered nowhere.
  Client size constraints are therefore ignored. It cannot simply be wired up:
  both call sites pass the same callback with no discriminator, so a minimum
  would arrive indistinguishable from a maximum. The C side needs to split it
  in two first.
- **`sdk/` tests do not build on Ubuntu 26.04.** The `-include math.h`
  workaround this project needs for the ubuntu24.04-built 6.2.4 toolchain
  (docs/BUILDING.md) collides with `<cmath>` while the compiler builds
  swift-testing's own `_Testing_Foundation` module — before it reaches any of
  our code. Hence `--sdk` rather than a permanent red: a suite that always
  fails for a known reason is one people stop reading.

## The Windows shell gate

`test/win/run-gate.sh` — eight checks against the Windows shell running on the
physical box: its processes, the strip it reserves, the wallpaper, minimize
and restore, and a packaged app that only launches because explorer is kept
alive. Exits 0 when they all pass and brings back a screenshot when they do
not. `test/win/README.md` says what each check is protecting and why it runs
as a scheduled task rather than over ssh.

Z-order is separate and slower: `test/bench/win-latency/zorder-stress.ps1`,
24 launch/close cycles with three shell restarts.
