#!/usr/bin/env bash
# T3 — the release gate: install the .deb on a clean machine, log in through
# GDM, and run the functional checks against the session that produces.
#
#   test/vm.sh [--deb PATH] [--keep]
#
#   --deb PATH   use an existing .deb instead of building one
#   --keep       leave the VM running afterwards (for poking at a failure)
#
# Why this tier exists at all: every other tier runs against a desktop started
# by hand from an SSH shell, and that is not the thing we ship. The difference
# is not cosmetic — it has produced real, shipped-breaking bugs that no other
# tier can see:
#
#   * The portal claimed its D-Bus name on the user's real session bus instead
#     of the session's own, so every file dialog in every Chromium/Electron/GTK
#     app broke. It worked perfectly under sudo on the dev box.
#   * `pkexec app-install` is authorised by polkit's allow_active, which means
#     the seat-active session. A shell launched over SSH is not it, so the App
#     Store's Install and Remove buttons cannot work on the dev box and cannot
#     be tested there.
#
# The harness this drives is in test/vm-harness/ — the launchers, ssh/scp, the
# in-guest g1/g2/g3 steps, the QMP input helpers. Its *state* is not, and
# cannot be: the disk images run to tens of gigabytes and the SSH key is a
# secret, so those stay at $STARLING_VM (default ~/starling-vm). See
# test/vm-harness/README.md for the manual equivalent of every step below.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$REPO/test/vm-harness"
VM="${STARLING_VM:-$HOME/starling-vm}"
DEB=""
KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --deb)  DEB="$2"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

fail() { echo; echo "FAIL — $*"; exit 1; }
step() { echo; echo "══ $* ═══════════════════════════════════════════"; }

# Everything worth reading after a functional failure lives in the guest, and
# `fail` kills the VM on the way out — so pull it BEFORE failing, not after.
#
# This is not hypothetical tidiness. A functional run once lost the shell
# between the seat-active check and the first test; all that survived was
# "Connection refused" against a dead broker socket, because the guest was
# destroyed with the journal, the session log and any core still in it. The
# next run passed on the same artifact and the cause was never found.
#
# `--keep` is not the answer either: the last step has the desktop power
# ITSELF off, so on a full run there is no guest left to keep.
dump_guest() {
    echo
    echo "── guest diagnostics ($1) ──────────────────────────────────────"
    # Bounded: ssh-vm.sh sets ConnectTimeout, which covers a guest that is
    # gone, but not one that accepts the connection and then wedges — and a
    # diagnostic that hangs the gate is worse than no diagnostic.
    timeout 60 "$HARNESS/ssh-vm.sh" \
           'echo "--- shell alive? ---"; pgrep -ax DesktopShellApp || echo "NOT RUNNING"
            echo "--- session log (tail) ---"
            sudo tail -60 /tmp/starling-session-*.log 2>/dev/null
            echo "--- session unit journal ---"
            sudo journalctl -b --no-pager -n 80 \
                 -u gdm _COMM=DesktopShellApp 2>/dev/null | tail -80
            # Ubuntu, not systemd: core_pattern pipes to apport and
            # systemd-coredump is not installed, so coredumpctl does not exist
            # and a crash lands in /var/crash/*.crash. Looking only for
            # coredumpctl would report "none" over an unread stack trace.
            echo "--- apport crash reports ---"
            sudo ls -la /var/crash/ 2>/dev/null | tail -6
            for c in /var/crash/*.crash; do
                [ -e "$c" ] || continue
                echo "--- $c ---"
                sudo grep -aE "^(ExecutablePath|Signal|ProcCmdline):" "$c" 2>/dev/null
                sudo sed -n "/^Stacktrace:/,/^[A-Z]/p" "$c" 2>/dev/null | head -25
            done
            echo "--- coredumpctl (if this guest has it) ---"
            command -v coredumpctl >/dev/null \
                && sudo coredumpctl list --no-pager 2>/dev/null | tail -5 \
                || echo "(absent — apport is the handler here)"' 2>&1 | sed 's/^/  /'
    echo "── end guest diagnostics ───────────────────────────────────────"
}

for f in launch-vm-2604.sh launch-vm-2604-nogl.sh ssh-vm.sh scp-vm.sh \
         g1-install.sh g2-setup-login.sh g3-check.sh qmp-abs-click.py; do
    [ -e "$HARNESS/$f" ] || fail "$HARNESS/$f is missing — harness incomplete"
done
# What the harness scripts expect to find in the state directory. A fresh
# checkout has every script above and none of this: the images are built, not
# cloned, and the key is machine-local.
[ -d "$VM" ] || fail "no VM state directory at $VM (set STARLING_VM)"
for f in disk2604.qcow2 seed2604.iso id_starling; do
    [ -e "$VM/$f" ] || fail "$VM/$f is missing — see test/vm-harness/README.md"
done

ssh_vm() { "$HARNESS/ssh-vm.sh" "$@"; }

# The harness forwards a fixed port, so a second VM on it makes this gate test
# the wrong machine. Refuse rather than guess.
if ss -ltn 2>/dev/null | grep -q '127.0.0.1:2222'; then
    if ! pgrep -af "qemu-system.*disk2604\.qcow2" >/dev/null; then
        echo "port 2222 is taken by something that is not the desktop VM:" >&2
        pgrep -af "qemu-system" | sed 's/^/  /' >&2
        fail "stop it first (the minimal VM uses the same forward)"
    fi
fi

# ── 1. the artifact under test ───────────────────────────────────────────────
step "build the .deb"
if [ -n "$DEB" ]; then
    [ -f "$DEB" ] || fail "no such .deb: $DEB"
    echo "using $DEB"
else
    OUT=$(mktemp -d)
    "$REPO/build/package-desktop.sh" "$OUT" >/dev/null 2>&1 \
        || fail "package-desktop.sh failed"
    DEB=$(ls -1 "$OUT"/*.deb | head -1)
    echo "built $(basename "$DEB")"
fi

# ── 2. a clean machine ───────────────────────────────────────────────────────
step "revert to the clean snapshot and boot"
pkill -f "qemu-system.*disk2604\.qcow2" 2>/dev/null && sleep 3
(cd "$VM" && qemu-img snapshot -a desktop-ready disk2604.qcow2) \
    || fail "could not revert to the desktop-ready snapshot"
(setsid bash "$HARNESS/launch-vm-2604.sh" >/dev/null 2>&1 &)

echo -n "waiting for ssh"
for _ in $(seq 1 60); do
    ssh_vm true 2>/dev/null && break
    echo -n "."
    sleep 5
done
echo
ssh_vm true 2>/dev/null || fail "the VM never came up on ssh"
ssh_vm '. /etc/os-release; echo "guest: $PRETTY_NAME"'

cleanup() {
    if [ "$KEEP" = 1 ]; then
        echo "leaving the VM running (--keep); ssh with $HARNESS/ssh-vm.sh"
    else
        pkill -f "qemu-system.*disk2604\.qcow2" 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

# Ubuntu's unattended-upgrade timers must not run during a gate. They fire on
# their own schedule, they hold the dpkg lock the store's install path needs,
# and — the way this actually bit — `systemctl poweroff` queues behind them:
# apt-daily-upgrade.service ran for 2m43s (1.5G peak) at exactly the moment the
# no-3D pass asked the guest to shut down, so the VM was still busy when the
# 120s window expired and the whole gate failed on a machine where nothing was
# wrong. Masking is what a test VM should have done from the start; adding a
# vendor apt repo (VS Code) just made the daily job expensive enough to notice.
step "mask the guest's unattended-upgrade timers"
ssh_vm 'sudo systemctl mask --now apt-daily.timer apt-daily-upgrade.timer \
        unattended-upgrades.service >/dev/null 2>&1;
        sudo systemctl stop apt-daily.service apt-daily-upgrade.service >/dev/null 2>&1;
        systemctl is-enabled apt-daily-upgrade.timer 2>&1 | tail -1'

# ── 3. install exactly as the docs tell a user to ────────────────────────────
step "install the .deb (g1)"
"$HARNESS/scp-vm.sh" "$DEB" '~/' >/dev/null || fail "scp of the .deb failed"
for g in g1-install.sh g2-setup-login.sh g3-check.sh; do
    "$HARNESS/scp-vm.sh" "$HARNESS/$g" '~/' >/dev/null || fail "scp of $g failed"
done
ssh_vm "bash ~/g1-install.sh $(basename "$DEB")" 2>&1 | tail -20
ssh_vm 'dpkg -s starling >/dev/null 2>&1' \
    || fail "starling is not installed after apt install"

# ── 4. a real login, through the display manager ─────────────────────────────
step "set up the GDM login and reboot into it (g2)"
ssh_vm 'bash ~/g2-setup-login.sh' 2>&1 | tail -8
# Shorten the screensaver's idle timeout before the session starts. The two
# screensaver checks need one they can actually wait out, and the shipped
# default is ten minutes — without this they SKIP, and the gate reports a
# clean run over a hole, exactly as it would without wl-clipboard above.
#
# Through the config file, not the environment: the session is started by GDM,
# so this is the same constraint the fixture catalog has further down, and the
# same answer. It also means the persistence path is what gets exercised,
# which is the one a user actually takes.
ssh_vm 'mkdir -p ~/.config/starling && echo 15 > ~/.config/starling/screensaver'
ssh_vm 'sudo systemctl reboot' >/dev/null 2>&1
sleep 20
echo -n "waiting for the graphical boot"
for _ in $(seq 1 60); do
    ssh_vm true 2>/dev/null && break
    echo -n "."
    sleep 5
done
echo
ssh_vm true 2>/dev/null || fail "the VM did not come back after reboot"

step "confirm the session came up through the DM (g3)"
ssh_vm 'bash ~/g3-check.sh' 2>&1 | head -30
ssh_vm 'pgrep -x DesktopShellApp >/dev/null' \
    || fail "the Starling shell is not running after a GDM login"

# The whole point of this tier: a session that polkit considers active on a
# seat. If this is not true, the App Store's buttons cannot work and every
# result below is about the wrong kind of session.
step "the session is seat-active (what the dev box can never be)"
SEAT=$(ssh_vm 'loginctl show-seat seat0 -p ActiveSession --value' 2>/dev/null)
[ -n "$SEAT" ] || fail "no active session on seat0"
echo "seat0 active session: $SEAT"

# ── 5. the privilege hop no other tier can reach ─────────────────────────────
step "polkit authorises app-install for the session (pkexec hop)"
# pkcheck asks polkit the exact question the App Store's pkexec asks, on behalf
# of a process inside the graphical session — without performing the install
# and without needing an agent. --allow-user-interaction is deliberately NOT
# passed: allow_active must authorise with no prompt, or the buttons stall.
if ssh_vm 'sudo pkcheck --action-id org.starling.app-install \
              --process $(pgrep -x DesktopShellApp | head -1) 2>&1'; then
    echo "  authorised — Install/Remove will work in this session"
else
    fail "polkit refused org.starling.app-install for the session's own shell;
      the App Store's Install and Remove buttons are dead in a real login"
fi

# ── 6. reuse the functional tier against the packaged desktop ────────────────
step "functional checks, against the installed .deb"
# STARLING_TEST_INSTALL=1 turns on the checks that install and remove a REAL
# app through app-install — the store's own recipe, writing the record through
# the production path. The app the identity checks need is produced by that
# install rather than set up behind the tests' back; installing is one of the
# behaviours under test, not a precondition. This is the tier to do it in: a
# clean snapshot, and a machine whose software we are free to change.
"$HARNESS/scp-vm.sh" "$REPO/test/functional.py" '~/' >/dev/null
# The screencast check shells out to its portal client, resolved beside
# functional.py — forget this file and the check fails as "portal handshake
# failed" with a python traceback about a missing script.
"$HARNESS/scp-vm.sh" "$REPO/test/screencast_client.py" '~/' >/dev/null
# Same trap for the clipboard check's stand-in for Chrome: resolved beside
# functional.py, and without it the check reports SKIP rather than failing —
# which reads as "covered" in the tally when it is not.
"$HARNESS/scp-vm.sh" "$REPO/test/clipboard_gtk_client.py" '~/' >/dev/null
"$HARNESS/scp-vm.sh" "$REPO/build/shell-drive.py" '~/' >/dev/null
# The screensaver inhibit check compiles this in the guest. Resolved beside
# functional.py, like the two clients above — there is no repo in the VM.
"$HARNESS/scp-vm.sh" "$REPO/test/fixtures/idle-inhibit-client.c" '~/' >/dev/null
# The clipboard checks need wl-clipboard (a data-control peer to copy from and
# paste to) and GTK 3 python bindings (a wl_data_device client, which is the
# only kind that can catch the offer-on-interaction regression). Neither is in
# the base image, and both checks SKIP silently without them — so install here,
# the same way g3-check.sh pulls mesa-utils, rather than let the gate report a
# clean run over a hole.
# The screensaver inhibit check builds its zwp_idle_inhibit_manager_v1 client
# in the guest — wayland-scanner for the bindings, the protocol XML, and a
# compiler — rather than shipping a binary that would rot against libwayland.
# Without them it SKIPs, which is the hole this whole block exists to close.
ssh_vm 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        wl-clipboard python3-gi gir1.2-gtk-3.0 \
        libwayland-bin libwayland-dev wayland-protocols gcc' >/dev/null 2>&1 \
    || echo "  note: test deps unavailable — clipboard/screensaver checks will skip"
ssh_vm 'mkdir -p ~/fixtures'
for f in "$REPO"/test/fixtures/*.app; do
    "$HARNESS/scp-vm.sh" "$f" '~/fixtures/' >/dev/null
done
# The session is started by GDM, so the fixture catalog cannot be injected
# through the environment. Drop the records into the installed catalog
# instead — the running shell picks them up over inotify, which exercises the
# live-update path in the packaged layout rather than around it.
ssh_vm 'sudo cp ~/fixtures/*.app /usr/share/starling/catalog.d/'
# Keep the whole run, show the tail. `tail -24` on its own is what made a
# real failure undiagnosable: the checks scroll past, so "3 passed" was all
# that survived to say WHERE it died — and the order of the suite was the
# only way to work out which check that was.
FUNC_LOG=$(mktemp)
ssh_vm 'sudo XDG_RUNTIME_DIR=/run/user/1000 STARLING_TEST_INSTALL=1 \
        python3 ~/functional.py' >"$FUNC_LOG" 2>&1
# No pipeline any more, so this is $? and NOT ${PIPESTATUS[0]} — the old form
# read tail's status, which is why the capture had to be commented at all.
functional=$?
tail -24 "$FUNC_LOG"
if [ "$functional" -ne 0 ]; then
    echo
    echo "── full functional output ───────────────────────────────────────"
    cat "$FUNC_LOG"
    dump_guest "3D pass"
    fail "functional checks failed against the .deb"
fi
rm -f "$FUNC_LOG"

# ── 7. the same desktop, with 3D acceleration switched OFF ───────────────────
# Everything above runs on virgl, and a GPU hides a whole class of bug: the
# shell holds the primary DRM node through libseat and can allocate on it,
# while a child app has only what it can open for itself. v0.2 shipped with
# every app allocating on a render node, which rejects the dumb-buffer ioctl
# software Mesa falls back to — so on a machine with no GPU the desktop came
# up and NOT ONE app could start. The gate could not see it, because no tier
# ran without a GPU.
#
# That is not an exotic configuration: GNOME Boxes, VirtualBox and VMware all
# default to 3D acceleration OFF, which is what most people evaluating the
# .deb are running. So the same installed desktop is rebooted onto plain
# virtio-vga (llvmpipe) and put through the same checks. STARLING_TEST_INSTALL
# stays off — the store's install path was proved above and does not depend on
# the GPU; what this pass is for is whether apps still render.
step "reboot the same desktop with NO 3D acceleration (virtio-vga, llvmpipe)"
ssh_vm 'sudo systemctl poweroff' >/dev/null 2>&1
for _ in $(seq 1 60); do
    pgrep -f "qemu-system.*disk2604\.qcow2" >/dev/null || break
    sleep 3
done
if pgrep -f "qemu-system.*disk2604\.qcow2" >/dev/null; then
    # Say WHAT is holding it. A bare "did not power off" sent the last
    # investigation to the guest's journal to discover an apt timer; the
    # queue is one ssh away, and the guest usually still answers.
    echo "  jobs still queued in the guest:"
    ssh_vm 'systemctl list-jobs --no-pager 2>&1 | head -12' 2>&1 | sed 's/^/    /'
    fail "the VM did not power off for the no-3D pass (180s)"
fi
# The tablet (an absolute pointing device) is for the power-menu check at the
# end of this tier: QEMU can only click a given pixel through `input-send-event`
# on an absolute device — relative PS/2 deltas never move Starling's pointer at
# all (verified against the shell's own [Input] log: every injected click landed
# on the untouched screen centre). The in-guest functional checks drive their
# own uinput device and are indifferent to the extra tablet.
(STARLING_VM_TABLET=1 setsid bash "$HARNESS/launch-vm-2604-nogl.sh" >/dev/null 2>&1 &)

echo -n "waiting for the graphical boot"
for _ in $(seq 1 60); do
    ssh_vm true 2>/dev/null && break
    echo -n "."
    sleep 5
done
echo
ssh_vm true 2>/dev/null || fail "the VM never came back without 3D acceleration"

# Prove the guest really has no 3D before trusting the pass — if virgl were
# somehow still on, this tier would be a second run of the tier above.
ssh_vm 'sudo dmesg | grep -q "features:.*-virgl"' \
    || fail "the guest still reports virgl; this pass is not testing software GL"
ssh_vm 'pgrep -x DesktopShellApp >/dev/null' \
    || fail "the shell is not running after a login with no 3D acceleration"

step "functional checks with no GPU"
NOGL_LOG=$(mktemp)
ssh_vm 'sudo XDG_RUNTIME_DIR=/run/user/1000 python3 ~/functional.py' \
    >"$NOGL_LOG" 2>&1
nogl=$?
tail -24 "$NOGL_LOG"
ssh_vm 'sudo rm -f /usr/share/starling/catalog.d/starling*.app'
if [ "$nogl" -ne 0 ]; then
    echo
    echo "── full functional output ───────────────────────────────────────"
    cat "$NOGL_LOG"
    dump_guest "no-GPU pass"
    fail "the desktop fails on a machine with no GPU
      (the session came up, so look for apps that start and die: the child
      renderer's device choice is logged to /tmp/starling-session-*.log)"
fi
rm -f "$NOGL_LOG"

step "power menu: Shut Down from the UI actually powers the machine off"
# The teardown IS the test: instead of pkilling QEMU, shut the desktop down
# the way a user would — power icon (top right), Shut Down…, confirm — and
# require the guest to reach ACPI poweroff. This covers what no other tier
# can: the status-bar popup opens and hit-tests, the confirm step works, and
# logind authorises `systemctl poweroff` for the seat-active session
# (allow_active — the same class of privilege path as the pkexec check above,
# and equally invisible from an SSH-launched dev shell). Until 0.2.2 the menu
# had no coverage at all; it shipped as the only way to shut the desktop down
# from the UI, sight unseen.
#
# Coordinates are physical pixels at the harness's fixed 1280x800, measured
# 2026-08-03 (icon 1252,17; "Shut Down…" row 1123,165; confirm button
# 1197,121). All three confirm prompts are single-line by an invariant
# documented on PowerAction.prompt, so every confirm panel shares this
# geometry — a prompt that wraps moves the buttons and breaks it. A layout
# change that moves them makes the clicks land elsewhere, the guest stays up,
# and this step fails loudly — the coordinates cannot rot in silence.
#
# Physical pixels means these are only valid at the scale the session chose:
# the previous set was measured while the shell assumed 2.0 on every panel,
# and deriving it from the display (1.0 here) moved every one of them. So
# check the scale first and say so, rather than clicking blind and reporting
# the shutdown as broken.
expected_scale=1.0
got_scale=$(ssh_vm 'grep -ho "scale [0-9.]* for" /tmp/starling-session-*.log \
                    | head -1 | cut -d" " -f2' 2>/dev/null | tr -d '\r')
[ "$got_scale" = "$expected_scale" ] || fail "the session is running at scale
      ${got_scale:-unknown}, but the power-menu coordinates below were measured
      at $expected_scale — re-measure them against a live desktop (gshot.py)
      before trusting this step"

click() { python3 "$HARNESS/qmp-abs-click.py" "$1" "$2" 1280 800 >/dev/null; }
click 1252 17;  sleep 2   # power icon -> menu
click 1123 165; sleep 2   # Shut Down… -> confirm panel
click 1197 121            # confirm Shut Down
echo -n "waiting for the guest to power itself off"
# 120s, not 60: this pass runs on llvmpipe, and a software-GL session takes
# its time tearing down — one run shut down correctly but crossed the line
# after 60s, failing the gate with every click having landed.
for _ in $(seq 1 40); do
    pgrep -f "qemu-system.*disk2604\.qcow2" >/dev/null || break
    echo -n "."
    sleep 3
done
echo
pgrep -f "qemu-system.*disk2604\.qcow2" >/dev/null \
    && fail "the guest is still up 120s after Shut Down was confirmed — the
      power menu did not shut the machine down (misplaced clicks fail the
      same way; screenshot the guest with gshot.py to tell which)"
echo "  ok    the desktop shut itself down through its own power menu"

step "result"
echo "PASS — the packaged desktop installs, logs in through GDM, is"
echo "       seat-active, authorises its own privileged helper, passes"
echo "       the functional checks both on a GPU and with none, and shuts"
echo "       itself down through its own power menu."
