# Windows, installable from the App Store

Draft for approval, 2026-09-05. Decisions taken up front (from the user):
the ISO is **auto-downloaded from Microsoft**, and this plan is written
**before** any of the recipe is built.

The goal: the `Windows` tile in the App Store has an **Install** button, and
pressing it provisions a real Windows 11 VM end to end — download the official
ISO, run an unattended install, and leave a domain the desktop already knows
how to open as a window (`Kind=vm`, `docs/plans/guest-display.md`) and, later,
as seamless app windows (`docs/plans/guest-seamless.md`). No terminal, no
`virsh`, no answer-file editing. `docs/WINDOWS-VM.md` becomes the description
of what the button does, not a checklist a human runs.

## It plugs into the store model that already exists

The App Store installs anything whose catalog record carries an `Install=`
recipe: the tile calls `pkexec app-install <id>`, `build/app-install.sh` runs
the recipe, streams its stdout into the tile's status line, and on success
writes the installed record so the launcher and dock light up
(`HostStore.swift`, `app-install.sh`). Nothing about that machinery is
apt-specific — it runs a shell recipe and watches it. So "install Windows"
is, structurally, **one more recipe** in `app-install.sh`, plus the record
change that surfaces it, plus the helper scripts the recipe calls.

What is genuinely new is that the recipe is long-running (a ~6 GB download and
a 20–40 minute unattended install, versus apt's seconds), opaque in the
middle (Windows setup reports nothing the host can read cleanly), and
provisions libvirt state rather than dropping files. The plan is mostly about
handling those three things well.

## Phase 1 — the record, and what "installed" means

`registry/catalog.d/windows.app` today is launcher-only (`Kind=vm`, no
`Install=`), so the store never shows it. Change:

- Add `Install=windows` → the store lists it and the Install button appears.
- Keep `Kind=vm` and `Domain=windows` — the launch arm is unchanged; a VM the
  store provisioned opens exactly as one created by hand.
- Change `Bins=` from `/usr/bin/virsh` (which only ever meant "libvirt is
  present") to **`/var/lib/starling/vm/windows.installed`** — a marker the
  recipe writes only after the guest has booted once and its agent answered.
  This reuses the store's existing file-exists install check (`isInstalled(bins:)`)
  with no new code: "installed" now means *the VM is provisioned and has
  booted*, which is what both the store tile and the launcher want to show.
- Store copy: `Size=~6 GB download`, and a `Description` that states the
  download size and that the user needs their own Windows license to activate
  (the setup key the answer file carries is a KMS *setup* key — it selects the
  edition, it does not activate).

`app-install --remove windows`: `virsh destroy` + `virsh undefine --nvram
--remove-all-storage windows`, then delete the marker. The cached ISO is kept
(it is expensive and reusable); a later `--purge` flag can drop it.

## Phase 2 — get the ISO (auto-download from Microsoft)

There is no stable direct URL for a Windows ISO the way there is for Chrome's
deb; Microsoft mints a **time-limited** link (~24 h) behind a session-gated
API. This is the flow `quickemu`'s `mido`/`Fido` use, and the recipe vendors a
small resolver (`docs/windows-vm/fetch-win-iso.sh`) that does the same:

1. Mint a random `sessionId` (GUID).
2. `POST https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=<sessionId>`
   — registers the session against Microsoft's anti-bot; without it the SKU
   calls return "download unavailable".
3. `GET …/software-download-connector/api/getskuinformationbyproductedition
   ?profile=606624d44113&productEditionId=<PID>&Locale=en-US&sessionID=<sessionId>`
   → the SKU id for the edition+language.
4. `GET …/software-download-connector/api/GetProductDownloadLinksBySku?…&SKU=<sku>…`
   → the `software-download.microsoft.com` URL.
5. `curl -C -` it to the cache (resumable), into
   `/var/lib/libvirt/images/`.

`productEditionId` changes with each Windows release, so it is **pinned in the
resolver and bumped on Windows releases** (a documented one-liner, like the
version-pinned vendor debs already in `app-install.sh`). The magic constants
(`org_id=y6jn8c31`, `profile=606624d44113`) are Microsoft's public ones that
mido/Fido track.

**This endpoint fails from some networks** — Microsoft blocks known datacenter
ranges and occasionally rate-limits — so even though auto-download is the
chosen path, the recipe **falls back** to a user-provided ISO: if the resolver
fails, it looks for a `Win11*.iso` (or `*.iso` with a valid `sources/install.wim`)
in `~/Downloads` and the images dir, and the store's status line tells the user
to drop one there and retry. The fallback is cheap and turns a hard failure
into a one-step manual path.

Caching: keyed on the resolved filename; a present, size-plausible, mountable
ISO is reused. Integrity — Microsoft's per-release ISO hash is not something
we can pin across releases, so the check is "mounts as UDF and has a
`sources/install.wim` of the expected order of magnitude", not a fixed SHA.

## Phase 3 — make it install with zero keystrokes

Two inputs get built from the ISO and the in-tree templates, both cached:

- **The answer ISO.** `docs/windows-vm/autounattend.xml` already exists and is
  complete: LabConfig bypasses, disk wipe/layout, `AutoLogon` with
  `LogonCount=999`, and `FirstLogonCommands` that install the virtio guest
  tools and the QEMU guest agent and write `C:\firstlogon-done.txt`. The
  recipe stages it plus `virtio-win-gt-x64.msi` and `qemu-ga-x86_64.msi`
  (pulled from `virtio-win.iso`, itself a stable fetch from the Fedora
  virtio-win project) and builds `answer.iso` with `genisoimage -V ANSWER`.
- **The no-prompt Windows ISO.** The single most important robustness step.
  Driving OVMF's boot menu with `send-key` is unreliable — `docs/WINDOWS-VM.md`
  documents four host-dependent failure modes — so the recipe does not press
  keys at all. It patches the El Torito EFI boot image in a *copy* of the
  Windows ISO, swapping `efisys.bin` for `efisys_noprompt.bin` (both on the
  media), so setup boots straight through. `docs/WINDOWS-VM.md §4` has the
  exact extent-patch procedure (find the boot-catalog LBA, verify the extent
  hashes equal to `efisys.bin`, overwrite with the no-prompt image, re-verify
  the UDF `install.wim`); the recipe is that procedure as a script
  (`docs/windows-vm/make-noprompt-iso.py`), with the verify steps kept as hard
  gates — a mis-patched ISO must fail loudly, not silently produce an
  unbootable install.

## Phase 4 — create the domain, boot, and wait

The domain is generated from **`docs/windows-vm/win11-dbus.xml`**, not the
plain-VNC `virt-install` in `docs/WINDOWS-VM.md §4`: that template is the
**seamless-capable** shape the desktop actually wants — EFI+secure-boot,
emulated TPM 2.0, the dbus p2p graphics the shell imports as a dma-buf, the
`org.qemu.guest_agent.0` channel, the `qemu-vdagent` clipboard channel, and
the `org.starling.agent.0` virtio-serial channel the seamless helper will use.
The recipe templatizes the name (`windows`), the qcow2 path, and the nvram
path, attaches the three install CD-ROMs (patched Windows ISO, answer ISO,
virtio ISO) for the first boot, `virsh define`s it, and starts it.

Provisioning the qcow2 (`qemu-img create -f qcow2 … 64G`) and the per-domain
nvram (copied from `OVMF_VARS_4M.ms.fd`) are the two bits of libvirt state the
template references.

**Done signal:** the guest agent answering a ping — one poll that proves setup
finished, first logon ran, and the agent installed (`docs/WINDOWS-VM.md §5`).
On success the recipe detaches the install CD-ROMs (so later boots don't offer
them), writes `/var/lib/starling/vm/windows.installed`, and returns. The store
tile flips to Installed and the launcher gains the real Windows entry.

## Phase 5 — prerequisites and host checks (run first, fail clearly)

Before any of the above, the recipe ensures the host can actually run a VM,
apt-installing what's missing (this part *is* an ordinary archive install):
`qemu-system-x86`, `libvirt-daemon-system`, `ovmf`, `swtpm`, `genisoimage`,
`libguestfs-tools` (for `wiminfo`). Then it checks, and fails with a one-line
reason the store shows, when: `/dev/kvm` is absent (no virtualization), the
`default` libvirt network is not active, there is less than ~70 GB free on the
images filesystem, or the invoking user is not in `libvirt`/`kvm`. app-install
already runs as root under pkexec, so it can create the state; group
membership is only needed for the *launch* later, and the recipe adds the
login user to `libvirt`/`kvm` if missing (the packaged session already assumes
`kvm`, see `docs/WINDOWS-VM.md`).

## Phase 6 — progress the user can read, and a confirm

- **Confirm before the download.** A 6 GB fetch and a Windows install with a
  licensing caveat should not start on a stray click. The store shows a
  one-time dialog: *"Install Windows? This downloads ~6 GB from Microsoft and
  provisions a virtual machine (20–40 min). You need your own Windows license
  to activate."* — Continue / Cancel. (Small `AppStoreApp` addition, gated on
  `Kind=vm`; every other install is unchanged.)
- **Honest phases, no fake percentages.** The recipe emits coarse, truthful
  status lines the tile already streams: `Checking prerequisites…`,
  `Downloading Windows (2.1 / 6.0 GB)…` (curl's own progress, throttled to a
  line/sec), `Preparing the installer…`, `Installing Windows — this takes
  20–40 minutes and needs no input…`, `Waiting for first boot…`. The opaque
  Windows-setup phase gets an elapsed-time heartbeat, not a percentage the
  host cannot actually measure (`virsh screenshot` OCR of "n% complete" is too
  fragile to drive a bar).
- **Resumable and idempotent.** Re-running after an interruption reuses the
  cached ISOs, and detects a half-provisioned domain: a defined `windows`
  domain with no `.installed` marker means "resume the wait" (or, if it never
  booted, undefine and recreate) rather than "already installed".

## Files this touches

- `registry/catalog.d/windows.app` — `Install=windows`, `Bins=<marker>`, copy.
- `build/app-install.sh` — the `windows)` recipe and `--remove windows`.
- `docs/windows-vm/fetch-win-iso.sh` (new), `make-noprompt-iso.py` (new),
  `make-answer-iso.sh` (new), and a `windows-domain.xml.in` template distilled
  from `win11-dbus.xml`.
- `build/stage.sh` / `build/package-desktop.sh` — ship the new scripts and
  templates (and `autounattend.xml`) into the package so `app-install` finds
  them at runtime, the same way it finds the catalog.
- `apps/AppStoreApp` — the one-time confirm for `Kind=vm` installs.
- `docs/WINDOWS-VM.md` — a short "the App Store does this for you" note at the
  top; the manual steps stay as the reference the recipe implements.
- `test/` — a fast check that the record surfaces in the store catalog and the
  recipe's dry-run (`--check`, below) reports prerequisites without touching
  libvirt; the full install is too heavy and network-dependent for the tier.

## Traps already known (from `docs/WINDOWS-VM.md` and the guest work)

- **Boot by patching the ISO, never by `send-key`.** The keystroke path fails
  four different host-dependent ways; the no-prompt extent patch is the only
  reliable one. `xorriso … replay` cannot do the swap (the boot images are
  hidden extents, not files) — patch the extent directly and re-verify.
- **`install.wim` is 6.8 GB, read over UDF.** Verify the patched ISO by
  mounting `-t udf` and comparing `sources/install.wim`; the ISO9660 view is
  not what setup reads, and FAT32's 4 GB cap rules out the usual USB trick.
- **The domain must be the dbus/seamless shape from the start**, not the
  plain-VNC one in `§4` — otherwise a store-installed VM opens but can never go
  seamless, and re-provisioning to add the channels means reinstalling Windows.
- **The link is time-limited (~24 h).** Resolve it at download time, not
  ahead; a cached *ISO* is fine, a cached *URL* is not.
- **Datacenter/CI IPs are blocked by the ISO endpoint.** The user-provided
  fallback is not optional even though auto-download is the default path — it
  is what keeps the button from being a dead end on a blocked network.
- **Root vs launch privilege.** app-install provisions as root (pkexec) but the
  VM is *launched* by the session user; get the `libvirt`/`kvm` group
  membership right at install time or the first launch fails with a confusing
  permission error (the class of bug `CLAUDE.md` documents for the whole app
  runtime).

## Open questions to settle at approval

- **Disk size:** 64 GB (comfortable for Windows + a few apps) vs 40 GB
  (`§4`'s value, tighter). Recommend 64 GB; it is sparse in qcow2, so the cost
  is only what Windows actually writes.
- **RAM/vCPU:** the template's 8 GB / 8 vCPU is tuned for this 32 GB dev box.
  For a shipped default, scale to the host (e.g. min(8 GB, host/4)) so it does
  not claim a third of a 16 GB laptop. Recommend host-relative sizing.
- **Edition:** Windows 11 Pro (the answer file's current target) vs Home.
  Recommend Pro — the answer file already selects it and Pro's Hyper-V/RDP are
  useful later.
- **The seamless helper (`starling-bridge`).** Out of scope here — this plan
  provisions the VM and its agent; installing the bridge that turns it into
  seamless app windows is the follow-on (`docs/plans/guest-seamless.md`,
  Phase 2's real helper). The domain is *ready* for it (the channel is
  present); the install just isn't wired yet.
