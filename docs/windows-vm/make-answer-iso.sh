#!/bin/sh
# make-answer-iso.sh — build the ANSWER CD-ROM that makes the Windows install
# unattended: the autounattend.xml setup reads at the root of every removable
# drive, plus the virtio guest tools and QEMU guest agent the answer file's
# FirstLogonCommands install (so the host can drive the box with no SSH).
#
#   make-answer-iso.sh AUTOUNATTEND.xml VIRTIO.iso OUTPUT.iso [PASSWORD]
#
# The autounattend template carries placeholder passwords (it lives in a
# public repo); this substitutes a real one before packing. The desktop opens
# the console with autologon, so this password is rarely typed by hand — it is
# documented in docs/WINDOWS-VM.md.
set -eu

AUTOUNATTEND="${1:?usage: make-answer-iso.sh AUTOUNATTEND.xml VIRTIO.iso OUTPUT.iso [PASSWORD]}"
VIRTIO="${2:?missing virtio-win.iso}"
OUT="${3:?missing output path}"
PASSWORD="${4:-Starling!2026}"

[ -f "$AUTOUNATTEND" ] || { echo "make-answer-iso: no autounattend at $AUTOUNATTEND" >&2; exit 1; }
[ -f "$VIRTIO" ]       || { echo "make-answer-iso: no virtio ISO at $VIRTIO" >&2; exit 1; }
command -v genisoimage >/dev/null || { echo "make-answer-iso: genisoimage not installed" >&2; exit 1; }

STAGE="$(mktemp -d)"
VMNT=""
cleanup() {
    [ -n "$VMNT" ] && umount "$VMNT" 2>/dev/null || true
    [ -n "$VMNT" ] && rmdir "$VMNT" 2>/dev/null || true
    rm -rf "$STAGE"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE/guest-agent"

# The answer file, with the placeholder password swapped for the real one.
# CHANGEME-Passw0rd! appears twice (AdministratorPassword and AutoLogon).
sed "s|CHANGEME-Passw0rd!|${PASSWORD}|g" "$AUTOUNATTEND" > "$STAGE/autounattend.xml"

# The two MSIs the FirstLogonCommands install, lifted from the virtio ISO.
VMNT="$(mktemp -d)"
mount -t udf -o loop,ro "$VIRTIO" "$VMNT" 2>/dev/null \
    || mount -o loop,ro "$VIRTIO" "$VMNT"
cp "$VMNT/virtio-win-gt-x64.msi"        "$STAGE/virtio-win-gt-x64.msi"
cp "$VMNT/guest-agent/qemu-ga-x86_64.msi" "$STAGE/guest-agent/qemu-ga-x86_64.msi"
umount "$VMNT"; rmdir "$VMNT"; VMNT=""

# -J (Joliet) -r (Rock Ridge) so long names survive; -V ANSWER is the volume
# label the docs reference. Windows setup scans removable media roots for
# autounattend.xml, so a labelled CD is all it takes.
genisoimage -quiet -o "$OUT" -J -r -V ANSWER "$STAGE"
echo "make-answer-iso: wrote $OUT"
