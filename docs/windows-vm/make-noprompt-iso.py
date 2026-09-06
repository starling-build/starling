#!/usr/bin/env python3
# make-noprompt-iso.py — turn a Windows install ISO into one that boots
# straight into setup with no "Press any key to boot from CD or DVD" prompt.
#
#   make-noprompt-iso.py SOURCE.iso OUTPUT.iso
#
# Why this exists, in full, is docs/WINDOWS-VM.md §4: driving OVMF's boot
# menu and Windows' boot prompt with `virsh send-key` fails four different
# host-dependent ways, so the App Store recipe does not press keys at all.
# Microsoft ships the answer on the media — alongside
# efi/microsoft/boot/efisys.bin there is efisys_noprompt.bin, the same
# 1,474,560 bytes, whose bootloader skips the prompt. This swaps one for the
# other by overwriting the El Torito EFI boot image extent IN A COPY of the
# ISO. `xorriso ... replay` cannot do it (the boot images are hidden extents,
# not files in the filesystem), so the extent is patched directly.
#
# Every step that could produce a subtly-broken ISO is a HARD GATE: a
# mis-patched installer that silently fails to boot is far worse than a loud
# error here. Needs root, because it mounts the media as UDF to read the
# boot images and to re-verify install.wim afterwards.

import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile

SECTOR = 2048
EFISYS_LEN = 1474560  # 2.88 MB "floppy" image; efisys.bin and _noprompt both


def die(msg: str) -> "NoReturn":  # type: ignore[valid-type]
    print(f"make-noprompt-iso: {msg}", file=sys.stderr)
    sys.exit(1)


def find_efi_boot_extent(iso: str) -> int:
    """Byte offset of the EFI (platform 0xEF) El Torito boot image."""
    with open(iso, "rb") as f:
        # The Boot Record Volume Descriptor sits at sector 17; its bytes
        # 71..75 hold the LBA of the El Torito boot catalog.
        f.seek(17 * SECTOR)
        brvd = f.read(SECTOR)
        if brvd[1:6] != b"CD001" or b"EL TORITO" not in brvd[7:39]:
            die("no El Torito boot record — not a bootable Windows ISO?")
        catalog_lba = struct.unpack("<I", brvd[71:75])[0]
        f.seek(catalog_lba * SECTOR)
        catalog = f.read(SECTOR)

    # Walk the 32-byte catalog entries for a section header whose platform id
    # (byte 1) is 0xEF (EFI); the following entry is that section's boot entry
    # and carries the image's load LBA. On Microsoft media the layout is
    # [validation][BIOS default][0x91 0xEF header][EFI entry], but scanning is
    # robust to a different arrangement.
    for off in range(0, SECTOR - 64, 32):
        header = catalog[off:off + 32]
        if header[0] in (0x90, 0x91) and header[1] == 0xEF:
            entry = catalog[off + 32:off + 64]
            if entry[0] != 0x88:
                die("EFI section entry is not marked bootable (0x88)")
            lba = struct.unpack("<I", entry[8:12])[0]
            if lba == 0:
                die("EFI boot image LBA is zero")
            return lba * SECTOR
    die("no EFI (0xEF) boot section in the El Torito catalog")


def sha(path_or_bytes) -> str:
    h = hashlib.sha256()
    if isinstance(path_or_bytes, bytes):
        h.update(path_or_bytes)
    else:
        with open(path_or_bytes, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def read_extent(iso: str, offset: int, length: int) -> bytes:
    with open(iso, "rb") as f:
        f.seek(offset)
        return f.read(length)


def mount_udf(iso: str):
    """Mount an ISO as UDF read-only; returns the mountpoint. Root only."""
    mnt = tempfile.mkdtemp(prefix="noprompt-udf-")
    r = subprocess.run(["mount", "-t", "udf", "-o", "loop,ro", iso, mnt],
                        capture_output=True, text=True)
    if r.returncode != 0:
        os.rmdir(mnt)
        die(f"could not mount {iso} as UDF: {r.stderr.strip()}")
    return mnt


def umount(mnt: str) -> None:
    subprocess.run(["umount", mnt], capture_output=True)
    try:
        os.rmdir(mnt)
    except OSError:
        pass


def wim_size(mnt: str) -> int:
    for name in ("install.wim", "install.esd"):
        p = os.path.join(mnt, "sources", name)
        if os.path.exists(p):
            return os.path.getsize(p)
    die("no sources/install.wim (or .esd) — not a Windows install ISO")


def main() -> None:
    if len(sys.argv) != 3:
        die("usage: make-noprompt-iso.py SOURCE.iso OUTPUT.iso")
    src, out = sys.argv[1], sys.argv[2]
    if not os.path.exists(src):
        die(f"source ISO not found: {src}")
    if os.geteuid() != 0:
        die("must run as root (it mounts the media as UDF)")

    offset = find_efi_boot_extent(src)
    print(f"make-noprompt-iso: EFI boot image at byte {offset}")

    # Read both boot images off the source, and record install.wim's size so
    # the patch can be proven not to have damaged the filesystem.
    mnt = mount_udf(src)
    try:
        boot_dir = os.path.join(mnt, "efi", "microsoft", "boot")
        efisys = os.path.join(boot_dir, "efisys.bin")
        noprompt = os.path.join(boot_dir, "efisys_noprompt.bin")
        if not os.path.exists(noprompt):
            die("this ISO has no efisys_noprompt.bin — cannot make it "
                "keystroke-free (a repacked or non-Microsoft ISO?)")
        want_prompt = sha(efisys) if os.path.exists(efisys) else None
        noprompt_bytes = open(noprompt, "rb").read()
        if len(noprompt_bytes) != EFISYS_LEN:
            die(f"efisys_noprompt.bin is {len(noprompt_bytes)} bytes, "
                f"expected {EFISYS_LEN}")
        want_noprompt = sha(noprompt_bytes)
        src_wim = wim_size(mnt)
    finally:
        umount(mnt)

    # The extent we are about to overwrite must currently be the PROMPTING
    # boot image (proves the catalog pointed us at the right bytes). If it is
    # already the no-prompt image, the source ISO is already keystroke-free —
    # copy it through unchanged rather than "patching" a no-op.
    have = sha(read_extent(src, offset, EFISYS_LEN))
    if have == want_noprompt:
        print("make-noprompt-iso: source is already no-prompt; copying through")
    elif want_prompt is not None and have != want_prompt:
        die("the EFI boot extent matches neither efisys.bin nor "
            "efisys_noprompt.bin — refusing to patch an ISO I don't understand")

    # Copy, then overwrite the extent in the copy.
    print(f"make-noprompt-iso: copying {src} -> {out}")
    shutil.copyfile(src, out)
    if have != want_noprompt:
        with open(out, "r+b") as f:
            f.seek(offset)
            f.write(noprompt_bytes)
        after = sha(read_extent(out, offset, EFISYS_LEN))
        if after != want_noprompt:
            die("post-write verify failed: extent is not efisys_noprompt.bin")
        print("make-noprompt-iso: EFI boot image replaced and verified")

    # Re-verify install.wim through the UDF view setup actually reads.
    mnt = mount_udf(out)
    try:
        out_wim = wim_size(mnt)
    finally:
        umount(mnt)
    if out_wim != src_wim:
        die(f"install image changed size after patch ({src_wim} -> {out_wim}) "
            "— the UDF filesystem was damaged")
    if out_wim < 3 * 1024 * 1024 * 1024:
        die(f"install image is only {out_wim} bytes — implausibly small")
    print(f"make-noprompt-iso: install image intact ({out_wim} bytes). Done.")


if __name__ == "__main__":
    main()
