#!/bin/sh
# app-install.sh — install third-party apps onto the HOST via apt/dpkg only.
#
# v0 Ubuntu launch model (user direction): apps run HOST-DIRECT and install
# through apt — NO SNAP, ever. Browsers: Chrome only — firefox and chromium
# are deliberately absent (Ubuntu's archive versions of both are snap shims,
# and the product ships one browser).
#
# Recipe kinds:
#   archive      plain `apt-get install` from the Ubuntu archive
#   vendor-deb   download the vendor's .deb, `apt-get install ./x.deb`
#                (Google's deb registers its own apt repo -> auto-updates;
#                Slack/Discord/Zoom debs don't — rerun to update)
#   vendor-repo  add the vendor's apt repo (keyring + .list), then install
#   tarball      no deb exists anywhere (Telegram) — official tarball to /opt
#
# ON SUCCESS THIS WRITES THE APP REGISTRY RECORD, and that is the point:
# nothing else on the system knows an install happened. The record lands in
# $RECORDS/<id>.app and carries what only exists once the app is on disk — the
# .desktop entry apt dropped, the window class it declares (StartupWMClass,
# which is the app_id its windows report, and therefore how the dock ties a
# window back to an app), its icon, its version. The shell watches that
# directory, so an install lights up the launcher and dock immediately.
# Removal deletes the record. See registry/catalog.d/README.md.
#
# Usage (root):
#   sudo app-install <name>     # e.g. chrome, vscode, spotify, gimp, …
#   app-install --list
set -eu

SELF="$(readlink -f "$0")"
BINDIR="$(dirname "$SELF")"

# The shipped catalog: one record per app the desktop knows about. Staged tree
# puts it beside bin/, the package at /usr/share/starling.
CATALOG=""
for _c in "${STARLING_CATALOG_DIR:-}" "$BINDIR/../share/catalog.d" \
          "$BINDIR/../share/starling/catalog.d" /usr/share/starling/catalog.d; do
    if [ -n "$_c" ] && [ -d "$_c" ]; then CATALOG="$_c"; break; fi
done
RECORDS="${STARLING_APP_RECORDS:-/var/lib/starling/installed.d}"

# Recipes with no catalog record. They install, but nothing in the desktop
# offers, launches or displays them — no store tile, no launcher icon, no dock
# identity. Give one a record in registry/catalog.d (and a launch recipe in
# app-run.sh) to surface it.
UNLISTED="mpv vlc libreoffice obs"

# Read one key out of a freedesktop-style key file. Only the FIRST group is
# read: a `.desktop` entry's `[Desktop Action …]` groups carry their own Icon
# and Exec keys and must not win over `[Desktop Entry]`.
kf_get() { # file key
    [ -f "$1" ] || return 0
    awk -v k="$2" '
        /^\[/  { g++; if (g > 1) exit; next }
        index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
    ' "$1"
    return 0
}

# Poke the records directory so the shell's watch fires even when nothing else
# in it changed. Needed because removing an app that never had a record (it
# was installed by apt before the registry existed, or by hand) is a no-op
# `rm` — no inotify event, so the launcher and dock would keep showing an app
# that is no longer on disk until the next login.
bump_records_stamp() {
    mkdir -p "$RECORDS" 2>/dev/null || return 0
    date +%s > "$RECORDS/.changed" 2>/dev/null || true
}

# Is the app running right now? Matches every live process's exe symlink
# against the catalog's Bins, both fully resolved — /proc/<pid>/exe is already
# resolved, so a symlinked launcher like /usr/bin/code only matches if the
# candidate is resolved too.
#
# Deliberately not a `pgrep -f` on the name: that matches its own command line
# (the same trap that makes `pkill -f` unsafe here — see CLAUDE.md) and any
# unrelated process with the name in an argument.
#
# Exit status is three-way and the caller must treat "cannot tell" as unsafe:
#   0  running
#   1  not running
#   2  cannot tell — no catalog record, or it declares no Bins
# Failing open here once already deleted a package it should have refused to
# touch: run from a tree with no catalog, $CATALOG is empty, every lookup
# comes back blank, and "no bins" read as "not running".
app_is_running() { # id
    { [ -n "$CATALOG" ] && [ -f "$CATALOG/$1.app" ]; } || return 2
    _bins="$(kf_get "$CATALOG/$1.app" Bins | tr ';' ' ')"
    [ -n "$_bins" ] || return 2
    # Both the declared path and what it canonicalizes to: /usr/bin/gimp is a
    # symlink to gimp-3.2, and which one the kernel reports depends on which
    # the launcher exec'd.
    _resolved=""
    for _b in $_bins; do
        _resolved="$_resolved $_b"
        _r="$(readlink -f "$_b" 2>/dev/null || true)"
        [ -n "$_r" ] && _resolved="$_resolved $_r"
    done
    [ -n "$_resolved" ] || return 2
    for _e in /proc/[0-9]*/exe; do
        # Plain readlink, not -f: a process whose binary was replaced or
        # deleted has its exe reported as "/path/to/bin (deleted)", and -f
        # cannot canonicalize a path that no longer exists. That process is
        # still the app, and is exactly the case this check exists to catch —
        # dropping it is how a running app gets uninstalled anyway.
        _x="$(readlink "$_e" 2>/dev/null || true)"
        [ -n "$_x" ] || continue
        _x="${_x% (deleted)}"
        for _r in $_resolved; do
            [ "$_x" = "$_r" ] && return 0
        done
    done
    return 1
}

catalog_installable() {
    [ -n "$CATALOG" ] || return 0
    for _f in "$CATALOG"/*.app; do
        [ -f "$_f" ] || continue
        _i="$(kf_get "$_f" Install)"
        [ -n "$_i" ] && printf '%s ' "$_i"
    done
}

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
    echo "apps: $(catalog_installable)"
    echo "unlisted (installable, but not in the app catalog): $UNLISTED"
    exit 0
fi
REMOVE=""
RECORD_ONLY=""
RUNNING_ONLY=""
FORCE=""
while [ $# -gt 0 ]; do
    case "${1:-}" in
        --remove) REMOVE=1; shift ;;
        # Re-resolve and rewrite one app's registry record without installing
        # anything: for an app installed by hand, or to repair a record after
        # the app moved. Needs no root when STARLING_APP_RECORDS points
        # somewhere writable, which is also how it is tested.
        --record) RECORD_ONLY=1; shift ;;
        # Report whether an app is running, and exit. The removal guard's
        # own answer, observable without entering the removal path — so it
        # can be tested without risking the thing it protects.
        --running) RUNNING_ONLY=1; shift ;;
        # Remove even though the app is running. Escape hatch for a wedged
        # process; the default refusal is there for a reason.
        --force)  FORCE=1; shift ;;
        *) break ;;
    esac
done
NAME="${1:-}"
[ -n "$NAME" ] || { echo "app-install: missing app name" >&2; exit 2; }

if [ -n "$RUNNING_ONLY" ]; then
    _live=0
    app_is_running "$NAME" || _live=$?
    case "$_live" in
        0) echo "$NAME: running"; exit 0 ;;
        1) echo "$NAME: not running"; exit 1 ;;
        *) echo "$NAME: cannot tell (no catalog record in '${CATALOG:-<none found>}')"
           exit 2 ;;
    esac
fi

[ -n "$RECORD_ONLY" ] || [ "$(id -u)" -eq 0 ] \
    || { echo "app-install: need root (apt)" >&2; exit 1; }

# apt/dpkg poke the controlling terminal when one exists; from a background
# process group (the App Store's pkexec under a tty-attached session) that
# raises SIGTTOU, whose default disposition STOPS the whole install mid-
# flight. With SIGTTOU/SIGTTIN ignored, POSIX lets the tty operations
# proceed. Real display-manager sessions have no controlling tty at all —
# this covers dev shells and tty-attached test sessions.
trap '' TTOU TTIN
exec </dev/null

export DEBIAN_FRONTEND=noninteractive

if [ -n "$REMOVE" ]; then
    # Refuse to uninstall a running app. apt would delete its binaries and
    # data out from under live processes, leaving something half-removed and
    # still on screen. The App Store disables Remove for running apps, but
    # this is the check that makes it a guarantee: it runs at the moment of
    # removal and covers the CLI too.
    if [ -z "$FORCE" ]; then
        _live=0
        app_is_running "$NAME" || _live=$?
        if [ "$_live" -eq 0 ]; then
            echo "app-install: $NAME is running — quit it first (--force overrides)" >&2
            exit 3
        elif [ "$_live" -eq 2 ]; then
            echo "app-install: cannot tell whether $NAME is running — no catalog" \
                 "record in '${CATALOG:-<none found>}'. Refusing; use --force." >&2
            exit 3
        fi
    fi
    case "$NAME" in
        chrome)       apt-get remove -y -q google-chrome-stable ;;
        claude)       apt-get remove -y -q claude-desktop ;;
        vscode)       apt-get remove -y -q code ;;
        spotify)      apt-get remove -y -q spotify-client ;;
        slack)        apt-get remove -y -q slack-desktop ;;
        discord)      apt-get remove -y -q discord ;;
        zoom)         apt-get remove -y -q zoom ;;
        teams)        apt-get remove -y -q teams-for-linux ;;
        telegram)     rm -rf /opt/telegram ;;
        intellij)     rm -rf /opt/idea ;;
        blender)      apt-get remove -y -q blender ;;
        gimp)         apt-get remove -y -q gimp ;;
        mpv)          apt-get remove -y -q mpv ;;
        vlc)          apt-get remove -y -q vlc ;;
        libreoffice)  apt-get remove -y -q libreoffice ;;
        obs)          apt-get remove -y -q obs-studio ;;
        *) echo "app-install: unknown app '$NAME'" >&2; exit 2 ;;
    esac
    # The app is gone, so its registry record is a lie. Deleting it is what
    # takes the app out of the launcher and the dock.
    rm -f "$RECORDS/$NAME.app"
    bump_records_stamp
    echo "app-install: $NAME removed"
    exit 0
fi
KEYRINGS=/etc/apt/keyrings
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fetch() { # url dest
    wget -q -O "$2" "$1" 2>/dev/null || curl -fsSL -o "$2" "$1"
}

# The installed package name, captured for the registry record's Version.
# Taken from the recipe rather than declared per app, so a recipe change can't
# leave a stale name behind. Tarball installs (Telegram, IntelliJ) have no
# package and simply record no version.
PKG=""

inst() {
    case "${1:-}" in
        /*|./*) : ;;                  # a local .deb — vendor_deb named it
        *) [ -n "$PKG" ] || PKG="$1" ;;
    esac
    apt-get install -y -q "$@"
}

# vendor_repo <id> <key-url> <repo-line-after-signed-by>
vendor_repo() {
    # apt decides how to read a keyring from its extension, so the file has to
    # match what the vendor actually publishes: .asc for ASCII-armored, .gpg
    # for binary. Microsoft armors theirs; Spotify ships binary. Saving binary
    # bytes as .asc gets the whole keyring skipped — "unsupported filetype" —
    # and every install from that repo then fails as unsigned. Normalise to
    # binary .gpg instead of trusting the URL's extension.
    mkdir -p "$KEYRINGS"
    fetch "$2" "$TMP/$1.key"
    if head -c 30 "$TMP/$1.key" | grep -q "BEGIN PGP"; then
        gpg --dearmor < "$TMP/$1.key" > "$KEYRINGS/$1.gpg"
    else
        cp "$TMP/$1.key" "$KEYRINGS/$1.gpg"
    fi
    chmod 0644 "$KEYRINGS/$1.gpg"
    rm -f "$KEYRINGS/$1.asc"          # leftover from the broken layout
    echo "deb [arch=amd64 signed-by=$KEYRINGS/$1.gpg] $3" \
        > "/etc/apt/sources.list.d/$1.list"
    apt-get update -q
}

vendor_deb() { # url  (basename kept so apt's ./ install works)
    fetch "$1" "$TMP/app.deb"
    PKG="$(dpkg-deb -f "$TMP/app.deb" Package 2>/dev/null || true)"
    inst "$TMP/app.deb"
}

# ── App registry record ──────────────────────────────────────────────────────
# Resolve, on THIS host, the facts about the app that exist only after the
# install, and record them. Same freedesktop lookup every other desktop does;
# doing it once here means the shell never guesses. In particular WmClass:
# `StartupWMClass` is the value the app's windows carry in
# `xdg_toplevel.set_app_id`, so recording it is what lets the dock tie a
# running window back to an app. The alternative the shell used to use —
# matching window titles — cannot work for an app whose title is
# "<document> – <thing>" (IntelliJ's project window is "untitled – Main.java",
# with no "IntelliJ" anywhere in it).

xdg_data_dirs() {
    printf '%s\n' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' '\n'
    echo /var/lib/snapd/desktop
    echo /var/lib/flatpak/exports/share
}

find_desktop_file() { # entry-basename…
    for _e in "$@"; do
        for _d in $(xdg_data_dirs); do
            if [ -f "$_d/applications/$_e.desktop" ]; then
                echo "$_d/applications/$_e.desktop"
                return 0
            fi
        done
    done
    return 0
}

# An `Icon=` value: an absolute path, or a theme name to look up. Raster only —
# the engine's image codecs do not decode SVG. Best size first; the dock tile
# is 256px at 2x, and a too-large icon still beats a too-small one.
find_icon() { # icon-name-or-path
    [ -n "${1:-}" ] || return 0
    case "$1" in
        /*)
            case "$1" in
                *.png|*.jpg|*.jpeg) [ -f "$1" ] && echo "$1" ;;
            esac
            return 0
            ;;
    esac
    for _d in $(xdg_data_dirs); do
        for _s in 256 192 128 512 96 64 48 32; do
            for _sub in apps devices; do
                if [ -f "$_d/icons/hicolor/${_s}x${_s}/$_sub/$1.png" ]; then
                    echo "$_d/icons/hicolor/${_s}x${_s}/$_sub/$1.png"
                    return 0
                fi
            done
        done
    done
    # Legacy location, and where Chrome's .deb actually puts its icon.
    for _d in $(xdg_data_dirs); do
        for _x in png jpg; do
            if [ -f "$_d/pixmaps/$1.$_x" ]; then
                echo "$_d/pixmaps/$1.$_x"
                return 0
            fi
        done
    done
    return 0
}

write_record() { # id   ($PKG, when the recipe set one, supplies the version)
    _id="$1"
    _cat="$CATALOG/$_id.app"
    _entries="$(kf_get "$_cat" DesktopEntry | tr ';' ' ')"
    _df=""
    # shellcheck disable=SC2086  # deliberate word splitting: a candidate list
    [ -n "$_entries" ] && _df="$(find_desktop_file $_entries)"
    _wm=""
    _icon=""
    if [ -n "$_df" ]; then
        _wm="$(kf_get "$_df" StartupWMClass)"
        # No override means the client reports its own desktop id.
        [ -n "$_wm" ] || _wm="$(basename "$_df" .desktop)"
        _icon="$(find_icon "$(kf_get "$_df" Icon)")"
    fi
    # Apps that register no entry at all (tarball installs — IntelliJ,
    # Telegram) fall back to what the catalog declares for them.
    [ -n "$_wm" ]   || _wm="$(kf_get "$_cat" WmClass | cut -d';' -f1)"
    [ -n "$_icon" ] || _icon="$(find_icon "$(kf_get "$_cat" Icon)")"
    # A record's existence is what tells the desktop the app is installed, so
    # do not write one for an app that isn't. Guards `--record` against
    # inventing a launcher tile that launches nothing; on the install path
    # everything below is true by construction.
    _present=""
    for _b in $(kf_get "$_cat" Bins | tr ';' ' '); do
        [ -x "$_b" ] && { _present=1; break; }
    done
    if [ -z "$_present" ] && [ -z "$_df" ]; then
        echo "app-install: $_id is not installed — no record written" >&2
        return 1
    fi

    _ver=""
    [ -n "${PKG:-}" ] && _ver="$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null || true)"

    # World-readable: the shell reads these as the session user, while this
    # runs as root under pkexec.
    mkdir -p "$RECORDS"
    chmod 0755 "$RECORDS" 2>/dev/null || true
    _tmp="$RECORDS/.$_id.$$"
    {
        echo "[Starling App]"
        echo "Id=$_id"
        [ -n "$_df" ]   && echo "DesktopFile=$_df"
        [ -n "$_wm" ]   && echo "WmClass=$_wm"
        [ -n "$_icon" ] && echo "Icon=$_icon"
        [ -n "$_ver" ]  && echo "Version=$_ver"
        echo "InstalledAt=$(date +%s)"
    } > "$_tmp"
    chmod 0644 "$_tmp"
    # Rename into place rather than write in place: a reader must never see
    # half a record, and the shell watches this directory for the rename.
    mv -f "$_tmp" "$RECORDS/$_id.app"
    echo "app-install: recorded $RECORDS/$_id.app (wm_class=${_wm:-?} icon=${_icon:-none})"
}

if [ -n "$RECORD_ONLY" ]; then
    write_record "$NAME"
    exit 0
fi

case "$NAME" in
    chrome)
        # Google's deb registers google-chrome.sources -> future `apt
        # upgrade` updates it like any repo package.
        vendor_deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
        ;;
    claude)
        # Anthropic's own repo. The key is published one level ABOVE the
        # suite (…/claude-desktop/key.asc, not …/apt/stable/), which is the
        # one thing about this recipe that is easy to get wrong.
        vendor_repo claude-desktop \
            "https://downloads.claude.ai/claude-desktop/key.asc" \
            "https://downloads.claude.ai/claude-desktop/apt/stable stable main"
        inst claude-desktop
        ;;
    vscode)
        vendor_repo vscode \
            "https://packages.microsoft.com/keys/microsoft.asc" \
            "https://packages.microsoft.com/repos/code stable main"
        inst code
        ;;
    spotify)
        vendor_repo spotify \
            "https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg" \
            "http://repository.spotify.com stable non-free"
        inst spotify-client
        ;;
    slack)
        # No stable "latest" URL — version pinned, bump on update.
        vendor_deb "https://downloads.slack-edge.com/desktop-releases/linux/x64/4.39.95/slack-desktop-4.39.95-amd64.deb"
        ;;
    discord)
        vendor_deb "https://discord.com/api/download?platform=linux&format=deb"
        ;;
    zoom)
        vendor_deb "https://zoom.us/client/latest/zoom_amd64.deb"
        ;;
    teams)
        # teams-for-linux — community Electron client (Microsoft ended the
        # native Linux Teams; their official path is the PWA).
        vendor_repo teams-for-linux \
            "https://repo.teamsforlinux.de/teams-for-linux.asc" \
            "https://repo.teamsforlinux.de/debian/ stable main"
        inst teams-for-linux
        ;;
    telegram)
        # Removed from the Ubuntu archive as of 26.04 and Telegram publishes
        # no deb — official tarball to /opt/telegram (app-run's path).
        fetch "https://telegram.org/dl/desktop/linux" "$TMP/tg.tar.xz"
        rm -rf /opt/telegram
        tar -xJf "$TMP/tg.tar.xz" -C /opt
        mv /opt/Telegram /opt/telegram
        ;;
    intellij)
        # No JetBrains apt repo and nothing in the archive, so this is the
        # telegram model: official tarball to /opt/idea (app-run's path).
        # The release index gives the current version and its checksum —
        # verify it, this is a ~1 GB download.
        #
        # IIC is the Community channel. Do not read that as "the Community
        # tarball": since 2025.3 JetBrains ships ONE distribution, and the
        # edition is a licence decision at runtime, not a different download.
        # ideaIC-2024.3.tar.gz still resolves; ideaIC-2025.3.tar.gz is a 404,
        # and the file below reports productCode IU while running the free
        # feature set until a licence is applied (Ultimate-only plugins log
        # "requires plugin with id=com.intellij.modules.ultimate" at startup
        # and stay disabled). IIC is used because it tracks the free tier —
        # IIU points at a newer release on the paid channel.
        fetch "https://data.services.jetbrains.com/products/releases?code=IIC&latest=true&type=release" \
              "$TMP/idea.json"
        url=$(tr ',' '\n' < "$TMP/idea.json" \
              | grep -o 'https://download\.jetbrains\.com/idea/idea-[0-9.]*\.tar\.gz' \
              | head -1)
        [ -n "$url" ] || {
            echo "app-install: could not resolve the IntelliJ download URL" >&2
            exit 1
        }
        fetch "$url" "$TMP/idea.tar.gz"
        fetch "$url.sha256" "$TMP/idea.sha256"
        # Compare digests directly — the .sha256 names the versioned upstream
        # file, not the local one, so `sha256sum -c` would fail on the name.
        want=$(cut -d' ' -f1 < "$TMP/idea.sha256")
        have=$(sha256sum "$TMP/idea.tar.gz" | cut -d' ' -f1)
        [ "$want" = "$have" ] || {
            echo "app-install: IntelliJ checksum mismatch (want $want, got $have)" >&2
            exit 1
        }
        rm -rf /opt/idea
        mkdir -p /opt/idea
        tar -xzf "$TMP/idea.tar.gz" -C /opt/idea --strip-components=1
        ;;
    blender)      inst blender ;;
    gimp)         inst gimp ;;
    mpv)          inst mpv ;;
    vlc)          inst vlc ;;
    libreoffice)  inst libreoffice ;;
    obs)          inst obs-studio ;;
    firefox|chromium)
        echo "app-install: not offered — Starling ships one browser (chrome)," >&2
        echo "and Ubuntu's archive '$NAME' is a snap shim anyway." >&2
        exit 2
        ;;
    *)
        echo "app-install: unknown app '$NAME'" >&2
        echo "apps: $LIST" >&2
        exit 2
        ;;
esac

# Tell the desktop. Never fatal: the app IS installed at this point, and a
# failure here costs an icon, not the install.
write_record "$NAME" \
    || echo "app-install: warning: could not write the registry record" >&2
bump_records_stamp

echo "app-install: $NAME installed"
