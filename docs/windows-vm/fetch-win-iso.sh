#!/bin/sh
# fetch-win-iso.sh — get a Windows 11 install ISO, printing its path.
#
#   fetch-win-iso.sh --out /var/lib/libvirt/images/starling-windows.iso
#
# Status goes to STDERR (the App Store streams it into the tile). The final
# line of STDOUT is the resolved ISO path; nothing else is written there.
#
# PRIMARY: auto-download from Microsoft. There is no stable direct URL for a
# consumer Windows ISO — Microsoft mints a time-limited (~24 h) link behind a
# session-gated, anti-bot API. This resolves it the way quickemu's mido/Fido
# do. `productEditionId` changes with each Windows release, so it is PINNED
# here and bumped on new releases (a documented one-liner, like the pinned
# vendor debs in build/app-install.sh). The magic profile/org constants are
# Microsoft's public ones mido/Fido track.
#
# FALLBACK (NOT optional): Microsoft blocks known datacenter/CI IP ranges and
# rate-limits this endpoint — a resolved-but-rejected request comes back as
# `Sentinel marked this request as rejected`. When the resolver fails, this
# looks for an ISO the user dropped in ~/Downloads or the images dir, so the
# button is never a dead end on a blocked network.
set -eu

OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        *) echo "fetch-win-iso: unknown arg $1" >&2; exit 2 ;;
    esac
done
[ -n "$OUT" ] || { echo "fetch-win-iso: --out is required" >&2; exit 2; }

log() { echo "$@" >&2; }

# Pinned per Windows release. 3321 = "Windows 11 (multi-edition ISO for x64)".
PRODUCT_EDITION_ID="${STARLING_WIN_PRODUCT_EDITION:-3321}"
ORG_ID=y6jn8c31
PROFILE=606624d44113
LANG_NAME="${STARLING_WIN_LANG:-English (United States)}"
IMAGES_DIR="${STARLING_WIN_IMAGES_DIR:-/var/lib/libvirt/images}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

# Is this a usable Windows install ISO? Mounts as UDF (what setup reads) and
# has a plausibly-sized install image. Integrity is deliberately structural,
# not a fixed SHA: Microsoft's per-release hash is not something we can pin
# across releases.
iso_is_valid() { # path
    [ -f "$1" ] || return 1
    _m="$(mktemp -d)"
    _ok=1
    if mount -t udf -o loop,ro "$1" "$_m" 2>/dev/null; then
        for _w in "$_m/sources/install.wim" "$_m/sources/install.esd"; do
            if [ -f "$_w" ]; then
                _sz=$(stat -c%s "$_w" 2>/dev/null || echo 0)
                [ "$_sz" -gt 3221225472 ] && _ok=0   # > 3 GB
            fi
        done
        umount "$_m" 2>/dev/null || true
    fi
    rmdir "$_m" 2>/dev/null || true
    return $_ok
}

# Already have it at the target?
if iso_is_valid "$OUT"; then
    log "Windows ISO already present, reusing it."
    echo "$OUT"; exit 0
fi

# ── Primary: resolve and download from Microsoft ────────────────────────────
resolve_ms() {
    command -v curl >/dev/null || return 1
    SID="$(cat /proc/sys/kernel/random/uuid)"
    # 1. Register the session against the anti-bot service.
    curl -fsS -A "$UA" --max-time 30 -o /dev/null \
        "https://vlscppe.microsoft.com/fp/tags?org_id=$ORG_ID&session_id=$SID" \
        2>/dev/null || return 1
    # 2. SKU for the edition + language.
    _skujson="$(curl -fsS -A "$UA" --max-time 30 \
        -H 'Referer: https://www.microsoft.com/en-us/software-download/windows11' \
        "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$PROFILE&ProductEditionId=$PRODUCT_EDITION_ID&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$SID" \
        2>/dev/null)" || return 1
    SKU="$(printf '%s' "$_skujson" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
want = sys.argv[1].lower()
for s in d.get("Skus", []):
    if s.get("LocalizedLanguage", "").lower() == want or s.get("Language", "").lower() == want:
        print(s.get("Id", "")); break
' "$LANG_NAME" 2>/dev/null)" || return 1
    [ -n "$SKU" ] || return 1
    # 3. The download link for that SKU.
    _linkjson="$(curl -fsS -A "$UA" --max-time 30 \
        -H 'Referer: https://www.microsoft.com/en-us/software-download/windows11' \
        "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$PROFILE&productEditionId=undefined&SKU=$SKU&friendlyFileName=undefined&Locale=en-US&sessionID=$SID" \
        2>/dev/null)" || return 1
    URL="$(printf '%s' "$_linkjson" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if d.get("Errors"):
    sys.exit(1)
best = ""
for o in d.get("ProductDownloadOptions", []):
    u = o.get("Uri", "")
    if u.endswith(".iso") or "x64" in u.lower():
        best = u
        if str(o.get("DownloadType")) in ("2", "x64"):
            break
print(best)
' 2>/dev/null)" || return 1
    [ -n "$URL" ] || return 1
    echo "$URL"
}

log "Resolving a Windows 11 download from Microsoft…"
if URL="$(resolve_ms)" && [ -n "$URL" ]; then
    log "Downloading Windows (this is ~6 GB)…"
    mkdir -p "$(dirname "$OUT")"
    # -C - resumes a partial file; the URL is time-limited, so re-resolve if a
    # resume is refused. curl's own progress goes to the terminal; the store
    # tile shows the coarse status line above.
    if curl -fL -C - -A "$UA" -o "$OUT.part" "$URL" && mv "$OUT.part" "$OUT" \
       && iso_is_valid "$OUT"; then
        log "Download complete."
        echo "$OUT"; exit 0
    fi
    log "Download failed or the ISO did not verify; trying a local ISO."
else
    log "Microsoft's download endpoint is unavailable from this network"
    log "(it blocks datacenter IPs and rate-limits). Looking for a local ISO."
fi

# ── Fallback: a user-provided ISO ───────────────────────────────────────────
# $STARLING_WIN_ISO wins; then Win11*.iso, then any *.iso, in the images dir
# and the invoking user's Downloads.
search_dirs() {
    echo "$IMAGES_DIR"
    for _h in "${SUDO_HOME:-}" "/home/${SUDO_USER:-}" "$HOME"; do
        [ -n "$_h" ] && [ -d "$_h/Downloads" ] && echo "$_h/Downloads"
    done
}

if [ -n "${STARLING_WIN_ISO:-}" ] && iso_is_valid "$STARLING_WIN_ISO"; then
    log "Using STARLING_WIN_ISO=$STARLING_WIN_ISO"
    echo "$STARLING_WIN_ISO"; exit 0
fi

for _pat in 'Win11*.iso' 'Windows11*.iso' '*.iso'; do
    for _d in $(search_dirs); do
        for _f in "$_d"/$_pat; do
            [ -f "$_f" ] || continue
            log "Found $_f — checking it…"
            if iso_is_valid "$_f"; then
                log "Using local ISO $_f"
                echo "$_f"; exit 0
            fi
        done
    done
done

log "No Windows ISO. Download one from Microsoft and drop it in"
log "$IMAGES_DIR or your Downloads folder, then press Install again."
exit 1
