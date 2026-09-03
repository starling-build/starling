# build/session — the system-integration payload

Four files that a Starling install needs outside its own tree. They used to be
heredocs inside `build/package-desktop.sh`, which meant a packager for another
distribution had to transcribe them and then keep the copies in step by hand.
They are real files so that every packager installs the same bytes.

| file | installs as | mode |
| --- | --- | --- |
| `starling-session` | `/usr/libexec/starling-session` + a `/usr/bin/starling-session` symlink to it | 755 |
| `starling.desktop` | `/usr/share/wayland-sessions/starling.desktop` | 644 |
| `org.starling.app-install.policy` | `/usr/share/polkit-1/actions/org.starling.app-install.policy` | 644 |
| `90-starling-managed-devices.conf` | `/usr/lib/NetworkManager/conf.d/90-starling-managed-devices.conf` | 644 |

Install them verbatim. Nothing here is templated — no build-time substitution
happens, and `package-desktop.sh` copies them unchanged.

**The one path you may move is the session script itself.** `starling.desktop`
names `/usr/bin/starling-session`, so that is the only location fixed by the
shipped files; `/usr/libexec` is where the Debian package happens to put the
real script. `/usr/libexec` is not universal — Arch merged it into `/usr/lib`
and the AUR refuses to install there — so put the script wherever your
distribution wants it and make `/usr/bin/starling-session` point at it. Nothing
else needs editing, and in particular you should not have to patch
`starling.desktop`. If you find yourself patching any file in this directory,
that is a bug in the file; please report it.

## What each one is for

**`starling-session`** is what the display manager execs, and it is the piece
worth reading before adapting anything. It is unprivileged: DRM master and
input arrive from logind through libseat. It picks the first DRM card with a
connected connector, then builds the session a private `XDG_RUNTIME_DIR` at
`/tmp/xdg-starling-<uid>` holding its own D-Bus daemon. The per-uid name and
the ownership checks around it are load-bearing rather than defensive
decoration: a shared name locked the second user out of the desktop entirely,
and adopting a pre-planted directory or bus socket would hand another user
every socket the session puts inside. The stub `.service` files it drops mask
system services that would otherwise claim names the shell serves itself —
most importantly `org.freedesktop.portal.Desktop`, because the stock portal has
no Starling backend and taking that name breaks the file dialog in every
Chromium, Electron, and GTK app.

**`starling.desktop`** is the session entry the display manager lists.

**`org.starling.app-install.policy`** lets the active session's user run
`/usr/bin/app-install` through `pkexec` without a password prompt; the App
Store's Install button depends on it. It authorises that one path, so it is
only meaningful alongside the `app-install` this package ships.

**`90-starling-managed-devices.conf`** makes NetworkManager manage wired
devices. Ubuntu's server base hands ethernet to netplan, which leaves the
desktop's network UI showing no wired connection on a machine with a cable in
it. The number keeps it out of a fight with `ubuntu-desktop` over the same
path, and `/etc/NetworkManager/conf.d` still overrides it. On a distribution
whose NetworkManager already manages everything, this file is unnecessary.

## If you are packaging Starling elsewhere

`build/stage.sh` assembles the tree that becomes `/usr/lib/starling` and
`/usr/share/starling` — it is the single definition of that layout, so consume
it rather than reproducing it. This directory is the rest: the four files
above, installed at the paths in the table. `build/package-desktop.sh` is the
worked example (it builds the Debian package), and `docs/BUILDING.md` covers
the build itself, including the `$STARLING_ENGINE_OUT`, `$STARLING_GN`, and
`$STARLING_SWIFT_INCLUDE` overrides that exist for non-Ubuntu builds.

The App Store's install path is Debian-only: `build/app-install.sh` drives
`apt` and `dpkg` directly. There is no pacman or dnf backend yet, so on other
distributions the store can browse but not install.
