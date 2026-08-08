#!/usr/bin/env bash
# Run the Starling desktop from this source tree on the real GPU.
#
#   build/run-desktop.sh [-- <shell args>]
#   build/run-desktop.sh --no-stage        reuse the existing .stage/ as-is
#
# Stages the build outputs into one self-contained tree (build/stage.sh) and
# runs the desktop out of it — the same arrangement the .deb installs, so the
# dev loop exercises the shipping configuration. Uses the distro's Mesa and the
# engine from the sibling starling-engine checkout (via the repo-root `engine`
# symlink). Nothing from the starling-os repo is required.
#
# Prereqs:
#   ./bootstrap.sh                                  (engine symlink)
#   engine built:  ninja -C engine/src/out/host_release \
#                        libflutter_engine.so libflutter_linux_drm.so
#   shell built:   cd shell && swift build -c release
#   apps built:    cd apps/<App> && swift build -c release   (optional)
#
# The GPU must be free: no display manager or compositor holding it. Drop to
# a TTY or `sudo systemctl isolate multi-user.target`, then check with
#   sudo fuser -v /dev/dri/card*      (nothing)
#   pgrep -x Xorg gnome-shell kwin_wayland sway
#
# Seat access is automatic: libseat (seatd or logind — no sudo) when a seat
# manager is reachable, else a root device open via sudo. Force with
# STARLING_SEAT_MODE=libseat|direct.
#
# Teardown: Ctrl-C here. If backgrounded or over SSH it holds the GPU until
# killed: sudo pkill -x DesktopShellApp   (pkill -f matches its own line).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_DIR="${STARLING_STAGE:-$REPO/.stage}"

DO_STAGE=1
ARGS=()
for a in "$@"; do
    case "$a" in
        --no-stage) DO_STAGE=0 ;;
        *) ARGS+=("$a") ;;
    esac
done

# --- stage --------------------------------------------------------------------
if [ "$DO_STAGE" = 1 ]; then
    "$REPO/build/stage.sh" "$STAGE_DIR"
else
    [ -x "$STAGE_DIR/lib/DesktopShellApp" ] || {
        echo "error: --no-stage but no staged tree at $STAGE_DIR" >&2; exit 1
    }
fi
LIB=$STAGE_DIR/lib
SHARE=$STAGE_DIR/share

# --- DRM device: first card with a connected connector -----------------------
if [ -z "${FLUTTER_DRM_DEVICE:-}" ]; then
    for st in /sys/class/drm/card*-*/status; do
        [ -e "$st" ] || continue
        if [ "$(cat "$st")" = connected ]; then
            c=$(basename "$(dirname "$st")")
            FLUTTER_DRM_DEVICE=/dev/dri/${c%%-*}
            break
        fi
    done
fi
FLUTTER_DRM_DEVICE="${FLUTTER_DRM_DEVICE:-/dev/dri/card0}"

# --- seat: libseat when a seat manager is reachable, else root ---------------
# libseat means no sudo in the launch path — the shipping model. seatd needs
# this user to reach its socket (e.g. in the `video` group); logind needs an
# active session on this seat.
if [ -n "${STARLING_SEAT_MODE:-}" ]; then
    SEAT=$STARLING_SEAT_MODE
elif [ -S /run/seatd.sock ] && [ -r /run/seatd.sock ]; then
    SEAT=libseat
elif [ -n "${XDG_SESSION_ID:-}" ] && command -v loginctl >/dev/null 2>&1; then
    SEAT=libseat
else
    SEAT=direct
fi
echo "drm:    $FLUTTER_DRM_DEVICE"
echo "seat:   $SEAT"

# --- runtime dir + session bus ------------------------------------------------
# The Starling session's own bus (mirrors /run/user/<uid>/bus). The shell's
# portal claims org.freedesktop.portal.Desktop here; runtime apps find it via
# $XDG_RUNTIME_DIR/bus.
#
# XDG_DATA_HOME points the bus's servicedir at a private dir, NOT
# ~/.local/share, which also serves the user's real desktop session. That dir
# is searched BEFORE /usr/share/dbus-1/services, so a stub .service file there
# masks a system one — which is how both entries below work.
#
# org.freedesktop.secrets is masked to fail fast: there is no keyring in this
# session, and the stock gnome-keyring service file only "discovers" the host
# daemon without ever claiming the name, so every Chromium/Electron app stalls
# 120 s (service_start_timeout). Exec=/usr/bin/false fails in milliseconds and
# the apps fall back to their basic password store.
#
# org.freedesktop.portal.Desktop is masked because our OWN portal serves it.
# Left activatable, the stock /usr/libexec/xdg-desktop-portal starts on this
# bus and TAKES THE NAME — our portal asks for it with ALLOW_REPLACEMENT, and
# xdg-desktop-portal asks with REPLACE_EXISTING, so it wins. It then serves
# only the interfaces that need no backend (Trash, MemoryMonitor, GameMode,
# ProxyResolver, NetworkMonitor, PowerProfileMonitor, Realtime): FileChooser
# needs an org.freedesktop.impl.portal.desktop.* backend and none declares
# Starling, so it vanishes from the bus. Clients then log
# "No such interface org.freedesktop.portal.FileChooser" and fall back to
# their own file dialog — which is what made VS Code's Open dialog come up
# empty. Masking it keeps our portal the owner for the life of the session.
# Owned by the invoking user and 0700 in both modes: /tmp is world-writable,
# and whoever owns this dir owns every session socket inside it. Root can
# still reach in, which is all the root-shell dev path needs. The uid suffix
# matches the packaged session (build/package-desktop.sh): a fixed shared
# name meant whoever claimed it first locked every other user out.
XDG=/tmp/xdg-starling-$(id -u)
if [ "$SEAT" = direct ]; then
    # Root shell: the portal thread drops euid to this user before connecting,
    # so the dir must be owned by them, not by root.
    sudo mkdir -p "$XDG"
    sudo chown "$(id -u):$(id -g)" "$XDG"
    sudo chmod 700 "$XDG"
else
    mkdir -p "$XDG"
    chmod 700 "$XDG"
fi
if [ -L "$XDG" ] || [ ! -d "$XDG" ] || [ ! -O "$XDG" ]; then
    echo "run-desktop: $XDG is not a directory owned by $(id -un) — refusing" >&2
    exit 1
fi
mkdir -p "$XDG/data/dbus-1/services"
for n in org.freedesktop.secrets org.freedesktop.portal.Desktop \
         org.freedesktop.Notifications; do
    printf '[D-BUS Service]\nName=%s\nExec=/usr/bin/false\n' "$n" \
        > "$XDG/data/dbus-1/services/$n.service"
done
# Ours or nothing — never adopt a bus socket we did not create (see the
# packaged launcher in build/package-desktop.sh for why).
if [ -e "$XDG/bus" ] && { [ ! -S "$XDG/bus" ] || [ ! -O "$XDG/bus" ]; }; then
    rm -f "$XDG/bus"
fi
if [ ! -S "$XDG/bus" ]; then
    # Log inside $XDG, never a fixed /tmp name: a root-owned leftover of a
    # shared log path made this redirect fail, and the backgrounded daemon
    # died before exec — silently, leaving the whole session busless (no
    # portal, no notifications) while everything else worked.
    setsid env XDG_DATA_HOME="$XDG/data" \
        dbus-daemon --session --address="unix:path=$XDG/bus" --nofork \
        >"$XDG/bus.log" 2>&1 &
    for _ in $(seq 1 10); do [ -S "$XDG/bus" ] && break; sleep 0.2; done
    [ -S "$XDG/bus" ] || echo "run-desktop: WARNING — session bus did not start ($XDG/bus.log)" >&2
fi
echo "bus:    $XDG/bus"

ENV_ARGS=(
    LD_LIBRARY_PATH="$LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    FLUTTER_DRM_DEVICE="$FLUTTER_DRM_DEVICE"
    FLUTTER_DRM_SEAT="$SEAT"
    FLUTTER_ENGINE_OUT="$SHARE"
    STARLING_DATA_DIR="$SHARE"
    FLUTTER_APPS_DIR="$LIB/apps"
    XDG_RUNTIME_DIR="$XDG"
    # libpipewire resolves its daemon socket under XDG_RUNTIME_DIR, which
    # the line above points at the private session dir — hand the shell the
    # real one explicitly or ScreenCast (and any other PipeWire client in
    # this process) finds no daemon. Guarded below: forwarded only when the
    # socket actually exists (never as an empty string — the env-knob rule).
    STARLING_CHILD_HOST_GL=1
    STARLING_APP_RUN="$STAGE_DIR/bin/app-run"
    STARLING_WECHAT_RUN="$STAGE_DIR/bin/wechat-run"
    # STARLING_APP_INSTALL is deliberately NOT forwarded, unlike the two
    # above. The App Store installs through `pkexec app-install`, and the
    # polkit policy authorises one exact path — /usr/bin/app-install. Point
    # the store at the staged copy instead and pkexec stops matching the
    # policy, falls back to asking for an admin password, and fails outright
    # in a session with no polkit agent. So the store always runs the
    # installed tool; to exercise a change to app-install.sh in the dev loop,
    # sync it (and the catalog it reads) to where the package puts them:
    #   sudo install -m755 .stage/bin/app-install /usr/bin/app-install
    #   sudo install -m644 registry/catalog.d/*.app /usr/share/starling/catalog.d/
)

# See the note beside XDG_RUNTIME_DIR above.
PW_RUN="/run/user/$(id -u)"
if [ -S "$PW_RUN/${PIPEWIRE_REMOTE:-pipewire-0}" ]; then
    ENV_ARGS+=(PIPEWIRE_RUNTIME_DIR="$PW_RUN")
fi

# LCD subpixel text (RGB-stripe panels) + Core-Graphics-style stem darkening.
# Default on; export either as "" (empty) to disable — the engine treats an
# empty value as off. On BGR/OLED/rotated panels disable FLUTTER_TEXT_LCD.
export FLUTTER_TEXT_LCD="${FLUTTER_TEXT_LCD-1}"
export FLUTTER_TEXT_EMBOLDEN="${FLUTTER_TEXT_EMBOLDEN-1}"

# Optional knobs, forwarded ONLY when set to a non-empty value. Passing them
# empty is not harmless: the engine reads several with a bare getenv(), and an
# empty string is non-NULL in C — FLUTTER_DRM_CONNECTOR="" makes the connector
# filter compare every output against "" and reject all of them ("[DRM] No
# connected connector found" on a perfectly good display).
for v in FLUTTER_DRM_DPI FLUTTER_DRM_CONNECTOR FLUTTER_DRM_MODE FLUTTER_VT \
         FLUTTER_DRM_COMPOSITOR FLUTTER_DRM_SECONDARY_TEST \
         FLUTTER_TEXT_LCD FLUTTER_TEXT_EMBOLDEN FLUTTER_TEXT_HINTING \
         FLUTTER_TEXT_CONTRAST \
         STARLING_DEBUG_CAPTURE STARLING_DMABUF_TILED STARLING_SIM_OUTPUTS \
         STARLING_DEV_SHELL STARLING_ANDROID_APP STARLING_APP_DRM_DEVICE \
         STARLING_SWAPCHAIN_DEBUG STARLING_NO_NVENC \
         STARLING_SCREENSAVER_TEST STARLING_SCREENSAVER_IDLE \
         STARLING_AERIAL STARLING_AERIAL_RES; do
    [ -n "${!v:-}" ] && ENV_ARGS+=("$v=${!v}")
done

# Drop terminal-multiplexer markers, as build/session/starling-session does:
# started from inside tmux, they reach every app the desktop launches and are
# believed. Only the seatd branch needs it — sudo's env_reset does the same
# job for free on the direct one, which is exactly why this leak is invisible
# on the dev path and shows up only on the shipping-shaped one.
NO_MUX=(-u TMUX -u TMUX_PANE -u TERM_PROGRAM -u TERM_PROGRAM_VERSION -u STY -u WINDOW)

cd "$LIB"
if [ "$SEAT" = direct ]; then
    exec sudo env "${ENV_ARGS[@]}" ./DesktopShellApp --drm "${ARGS[@]+"${ARGS[@]}"}"
else
    exec env "${NO_MUX[@]}" "${ENV_ARGS[@]}" ./DesktopShellApp --drm "${ARGS[@]+"${ARGS[@]}"}"
fi
