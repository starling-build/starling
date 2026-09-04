# A Windows VM you can drive from Linux

How to stand up a Windows guest under libvirt that a Linux host can build on,
run GUI applications on, screenshot, and type into — with no VNC client, no
RDP session, and (until you want one) no SSH server. This is the recipe behind
the `win11` box the terminal's Windows work uses. Budget half an hour: about
ten minutes of preparation and twelve of unattended install.

Every step here was run start to finish on Ubuntu 26.04 with libvirt/qemu
before it was written down, and the traps at the bottom are the ones that
actually bit during that run — not a list of things that might go wrong.
Templates live beside this file in `docs/windows-vm/`.

## What you get

- an unattended install — one command, then wait; no clicking through setup
- the **QEMU guest agent**, which is the important part: it runs commands in
  the guest as SYSTEM over a virtio serial channel, so the host can drive the
  box with **no network, no credentials and no SSH**
- `virsh screenshot` for seeing the desktop, `virsh send-key` for typing
- an auto-logged-in interactive session, which GUI applications need

## Host prerequisites

```bash
sudo apt install qemu-system-x86 libvirt-daemon-system virtinst swtpm \
                 swtpm-tools genisoimage ovmf wimtools
sudo usermod -aG libvirt "$USER"      # log out and back in
sudo systemctl enable --now libvirtd
sudo virsh net-start default && sudo virsh net-autostart default
```

**`qemu-kvm` is not installable on 26.04** — it is a virtual package, and apt
refuses with "has no installation candidate" rather than picking a provider.
The real one is `qemu-system-x86`. `wimtools` supplies `wiminfo` for step 1,
and libvirt's `default` network is *inactive* on a fresh install, so a guest
created against it fails to start until the two lines above have run.

`swtpm` and the `.ms.fd` OVMF firmware matter: Windows 11 wants TPM 2.0 and
Secure Boot, and giving it real ones is less trouble than bypassing them.

**Take the virt-install command in step 4 as a unit.** It was arrived at by
experiment and the parts interlock. A run on a Ryzen 7735HS that dropped
Secure Boot and SMM (to chase what looked like an SMM hang), changed the CPU
topology to one socket, and disabled the `hv-avic` enlightenment produced a
guest that booted the Windows kernel and then silently reset, about every
twelve seconds, forever — no bugcheck, no message, nothing written to disk.
Restoring the command below fixed it immediately. Those four changes were made
together and reverted together, so which one was fatal is *not* known; what is
known is that the recipe as written works and improvised variants of it may
not.

You need two ISOs in `/var/lib/libvirt/images/`:

- a Windows ISO (`Win11_25H2_English_x64.iso` here — any recent one works)
- `virtio-win.iso`, from the Fedora virtio-win project, for the guest agent
  and paravirtual drivers

## 1. Pick the edition

A retail Windows ISO carries a dozen editions and the answer file has to name
one, by index:

```bash
sudo mount -o loop,ro /var/lib/libvirt/images/Win11_25H2_English_x64.iso /mnt/w11
wiminfo /mnt/w11/sources/install.wim | grep -E '^(Index|Name)'
```

On the 25H2 ISO, index 6 is Windows 11 Pro. Put that number in
`<IMAGE/INDEX>`, and put a **matching** product key in `<ProductKey>` — see the
first trap below.

## 2. Write the answer file

Start from `docs/windows-vm/autounattend.xml`. It is commented; the parts that
matter:

- `<ProductKey>` — the generic Windows 11 Pro KMS *setup* key. It does not
  activate anything; it tells setup which edition to install.
- `<RunSynchronous>` LabConfig bypasses — belt and braces. The VM below has a
  real TPM and Secure Boot, but setup also checks the CPU model and these stop
  it refusing on a host CPU it does not recognise.
- `<DiskConfiguration>` — wipes disk 0 and lays out EFI/MSR/primary. It will
  destroy whatever is on the first disk, which is what you want for a VM and
  emphatically not what you want if you ever boot this ISO on real hardware.
- `<AutoLogon>` with `<LogonCount>999</LogonCount>` — so the box always comes
  back to a live desktop after a reboot. GUI applications need an interactive
  session and there is no one there to log in.
- `<FirstLogonCommands>` — installs the virtio guest tools and **the QEMU guest
  agent**, then writes `C:\firstlogon-done.txt` as a marker the host can poll.

Anything else you want on the box from the first boot — a payload to test, a
config file — can ride along on the same ISO; there is a `copy` command in the
template showing the pattern. The guest needs no network to get it.

**Check the answer file parses before you build the ISO.** An XML comment
cannot contain `--`, and a template whose prose says "the passwords below --
they are placeholders" is not XML. Setup does not complain about that: it
ignores the file and runs the install INTERACTIVELY, so the first thing you see
is the language page rather than `Installing Windows`, with nothing anywhere
saying why. This template shipped that way and cost a Windows 10 install to
find.

```bash
python3 -c "import xml.dom.minidom as m; m.parse('autounattend.xml')"
```

## 3. Build the answer ISO

```bash
mkdir -p iso/guest-agent
cp autounattend.xml iso/
# from virtio-win.iso, or download the two MSIs directly
cp /mnt/virtio/virtio-win-gt-x64.msi        iso/
cp /mnt/virtio/guest-agent/qemu-ga-x86_64.msi iso/guest-agent/
genisoimage -o fresh-answer.iso -J -r -V ANSWER iso
sudo cp fresh-answer.iso /var/lib/libvirt/images/
```

Windows setup scans the root of every removable drive for `autounattend.xml`,
so a second CD-ROM is all it takes — no need to rebuild the Windows ISO.

## 4. Create the VM

```bash
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11-fresh.qcow2 40G

sudo virt-install --name win11-fresh --memory 6144 --vcpus 4 \
  --cpu host-passthrough --machine q35 --features smm.state=on \
  --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --disk path=/var/lib/libvirt/images/win11-fresh.qcow2,bus=sata \
  --disk path=/var/lib/libvirt/images/Win11_25H2_English_x64.iso,device=cdrom,bus=sata \
  --disk path=/var/lib/libvirt/images/fresh-answer.iso,device=cdrom,bus=sata \
  --disk path=/var/lib/libvirt/images/virtio-win.iso,device=cdrom,bus=sata \
  --network network=default,model=e1000e \
  --graphics vnc,listen=127.0.0.1 --video qxl \
  --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
  --os-variant win11 --noautoconsole
```

Three lines are load-bearing and easy to leave out:

- `--channel ... org.qemu.guest_agent.0` — no channel, no guest agent, and the
  whole no-SSH story collapses.
- `--tpm` + the secure-boot firmware features — Windows 11 setup refuses
  without them.
- `--graphics vnc` and `--video qxl` — you never open a VNC client, but
  `virsh screenshot` needs a graphics device to capture.

**Then get it to boot the DVD, and look while you do it.** The disk is blank,
so OVMF falls through to a menu instead of booting the ISO. **Do not blind-press
your way through that menu** — its contents vary between boots of the very same
VM. On one boot it offered `HARDDISK / EFI Firmware Setup / DVD-ROM ...`; on the
next, the firmware-setup row was gone and `DVD-ROM` sat one line higher, so the
same key sequence dropped me into the firmware setup instead of the installer.
Screenshot, then move:

```bash
sleep 6
virsh screenshot win11-fresh /tmp/menu.ppm      # LOOK at it, then navigate
virsh send-key win11-fresh --codeset linux KEY_DOWN
virsh send-key win11-fresh --codeset linux KEY_ENTER
```

You want the **first** `UEFI QEMU DVD-ROM` entry — with the disks ordered as
above that is the Windows ISO; the other two are the answer and virtio ISOs.
If you land in the firmware setup instead, `Boot Manager` is two rows below
`Select Language` and gets you to the same list.

Then answer Windows' own *Press any key to boot from CD or DVD*, which lasts
about five seconds:

```bash
for i in $(seq 1 16); do
    virsh send-key win11-fresh --codeset linux KEY_SPACE; sleep 1
done
```

From here it is unattended. `Installing Windows 11 — n% complete` on the next
screenshot means the answer file was read; a **Product key** page means it was
not.

### If those keypresses do nothing: build a no-prompt ISO

On some hosts `send-key` drives OVMF's boot manager perfectly and **never
reaches Windows' bootloader**, so that prompt times out however hard you hit
it. On one Ryzen box four approaches all failed — 16 presses at 1 s, 90 at
0.3 s, 150 from a cold boot, and adding a USB keyboard to the domain
(`<input type='keyboard' bus='usb'/>`, on the theory that bootmgr ignored the
PS/2 one). Every time, the screen fell back to `BdsDxe: No bootable option or
device was found`.

Do not keep fighting it. Microsoft ships the answer on the ISO: alongside
`efi/microsoft/boot/efisys.bin` there is **`efisys_noprompt.bin`**, the same
1,474,560 bytes, whose bootloader skips the prompt entirely. Swap it in and the
install needs no keystrokes at all.

`xorriso -boot_image any replay` **cannot** do this — it fails with `Cannot
enable EL Torito boot image #1 because it is not a data file in the ISO
filesystem`, because the boot images are hidden extents rather than files. So
patch the extent directly. Find it in the El Torito catalog:

```python
import struct
f = open("Win11_25H2_English_x64.iso", "rb")
f.seek(17 * 2048)                      # Boot Record Volume Descriptor
cat = struct.unpack("<I", f.read(2048)[71:75])[0]
f.seek(cat * 2048)                     # boot catalog: 32-byte entries
e = f.read(2048)[96:128]               # the EFI (platform 0xEF) section entry
print("image LBA", struct.unpack("<I", e[8:12])[0])
```

On the 25H2 ISO that is catalog LBA 22 and image **LBA 536 = byte 1,097,728**.
Verify before writing — the extent must hash equal to `efisys.bin` — then copy
the ISO and overwrite those bytes with `efisys_noprompt.bin`:

```bash
cp Win11_25H2_English_x64.iso win11-noprompt.iso
python3 - <<'PY'
data = open("/mnt/w11/efi/microsoft/boot/efisys_noprompt.bin","rb").read()
with open("win11-noprompt.iso","r+b") as f:
    f.seek(536*2048); f.write(data)
PY
```

Then confirm you did not damage the media: mount the patched ISO **as UDF**
(`mount -t udf`) and compare `sources/install.wim` against the original. UDF is
the filesystem Windows setup actually reads, because `install.wim` is 6.8 GB
and ISO9660's view of it is not what setup uses — that size is also why the
usual "extract to a FAT32 USB image" trick is unavailable, FAT32 capping files
at 4 GB.

Boot now goes straight through: `failed to load Boot0002 "UEFI QEMU HARDDISK" :
Not Found`, then the DVD, then setup. No menu navigation, no keypresses, and
the same recipe works unattended on every host.

## 5. Wait for it

The guest agent answering a ping is the signal that setup finished, first
logon ran, and the agent installed — one poll covers all three:

```bash
until virsh qemu-agent-command win11-fresh '{"execute":"guest-ping"}' >/dev/null 2>&1
do sleep 60; echo "installing..."; done
```

Measured on an 8-core mini PC with the guest on 4 vCPU / 6 GB: **about 12
minutes** from the boot key presses to the agent answering. Sanity-check the
result with the marker the answer file writes, which proves the whole
oobeSystem pass ran and not merely that Windows booted:

```bash
winrun.py -d win11-fresh 'Get-Content C:\firstlogon-done.txt; $env:COMPUTERNAME'
```

## Driving it

Three channels, in order of how much they need from the guest.

**Guest agent — needs nothing.** `docs/windows-vm/winrun.py` runs PowerShell
through the agent and returns exit code, stdout and stderr. It runs as SYSTEM
in session 0, so it can do anything, but a GUI it starts is never composited.

```bash
winrun.py -d win11-fresh 'Get-CimInstance Win32_OperatingSystem | Select Caption'
```

**Console — for what only a human could do.** `virsh screenshot` for pixels,
`virsh send-key` for keys. There is no `send-text`, so
`docs/windows-vm/type-keys.py` maps a string to keycodes and makes chords out
of the shifted characters:

```bash
type-keys.py win11-fresh 'Administrator' TAB 'hunter2' ENTER
```

**SSH — optional, best for bulk file transfer.** Install OpenSSH Server in the
guest and add a key; then `scp` beats every other route for anything large.
Note that an admin's ssh session gets an *elevated* token, which
`schtasks /create` needs.

## Getting files in

- **on the answer ISO** — best for a payload you want present at first boot,
  and it needs no network at all
- **over HTTP from the host** — the host is `192.168.122.1` on libvirt's
  default network, so `python3 -m http.server 8899 --bind 192.168.122.1` on one
  side and `Invoke-WebRequest` on the other moves 50 MB in seconds
- **another CD-ROM, attached live** — `virsh attach-disk ... --type cdrom`,
  but see the PCI-slot trap below

## Running a GUI application

**An SSH or guest-agent command lands in session 0, which has no desktop.** A
window created there is never composited and never appears in a screenshot.
The application has to run in the interactive session, and the way to put it
there is a scheduled task marked interactive-only:

```powershell
schtasks /create /tn RunApp /ru Administrator /it /rl HIGHEST `
         /sc once /st 00:00 /tr "C:\path\to\app.exe" /f
schtasks /run /tn RunApp
```

`/it` needs no password because the task only runs when that user is logged
on — which the answer file's `<AutoLogon>` guarantees. `/rl HIGHEST` is
needed by anything that wants an elevated token (`powercfg`, for one).

## Telling progress from a hang

A Windows install shows a spinner whether it is working or wedged, so judge it
by I/O, not by the screen. `virsh domblkstat` is the honest instrument, because
it counts what the *guest* asked for:

```bash
virsh domblkstat win11-fresh sda      # the disk: writes mean real progress
virsh domblkstat win11-fresh sdb      # the Windows ISO: reads
```

Three readings and what they mean:

- **disk `wr_bytes` climbing** — installing. Nothing else needs checking.
- **ISO `rd_bytes` climbing past the size of the ISO** — a boot loop. Windows
  starts, resets, firmware re-reads, repeat; the reads accumulate past 100%
  while `wr_bytes` stays at 0. A ~12-second cycle of firmware screen → black →
  firmware screen in successive screenshots is the same thing seen from
  outside.
- **both flat, CPU high** — genuinely stuck. `virsh qemu-monitor-command
  <dom> --hmp 'info registers'` says where: `SMM=1` is the firmware's
  System Management Mode, an `RIP` of `0xfffff801…` is the Windows kernel, and
  a low `RIP` around the 2 GB mark is OVMF.

Two ways to mislead yourself here, both of which did:

- **`/proc/<pid>/io` `read_bytes` is not guest I/O.** The ISO sits in the
  host's page cache, so a guest reading it furiously shows almost no host
  block reads. It looks exactly like a hang. Use `domblkstat`.
- **`pgrep -f qemu…` matches your own shell.** The `bash -c` line containing
  the pattern is itself a match, so CPU sampled from that pid reads as zero
  and a busy VM looks dead. Select the real one:
  `ps -eo pid,cmd | awk '/qemu-system-x86_64.*guest=<name>/{print $1; exit}'`.

## Passing a GPU through

This is what the `win11-gpu` box exists for. Check the card is alone in its
IOMMU group first — if it shares one, everything in that group must move too:

```bash
ls /sys/bus/pci/devices/0000:01:00.0/iommu_group/devices/
```

Bind it to `vfio-pci` at boot, ahead of the vendor driver:

```
# /etc/modprobe.d/vfio-starling.conf
options vfio-pci ids=10de:25ac
softdep nvidia         pre: vfio-pci
softdep nvidia_drm     pre: vfio-pci
softdep nvidia_modeset pre: vfio-pci
softdep nvidia_uvm     pre: vfio-pci
```

`softdep` rather than a blacklist keeps the vendor driver installed and
upgradable; it simply finds nothing to bind. Then add the hostdev with
`managed='yes'` and reboot.

**`/etc/initramfs-tools/modules` does nothing on Ubuntu 26.04.** The initramfs
is generated by **dracut** — `dpkg -S $(readlink -f $(command -v
update-initramfs))` says `dracut: /usr/sbin/update-initramfs` — so the
initramfs-tools file is inert and vfio silently never ships. This matters
because the nvidia modules *are* in the initramfs, so without forcing vfio in
beside them the vendor driver claims the card in early boot and the softdep
above never gets a chance. The file that works:

```
# /etc/dracut.conf.d/90-vfio.conf
force_drivers+=" vfio vfio_pci vfio_iommu_type1 "
```

Verify before rebooting, because the failure is silent:

```bash
lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'vfio.*\.ko'   # expect 4
```

Two things to know before committing to this. A **muxless laptop dGPU** — PCI
class `0302` "3D controller", no display outputs, no HDMI-audio function — has
no monitor to drive, so the guest boots on its emulated display and sees the
card as a second, headless render device: good for CUDA, NVENC and compute,
not for plugging a screen into the VM. And the host loses the card entirely
while this is in place, which on this desktop means no PRIME render offload
for apps and no NVENC recording.

## Traps that cost real time

- **A missing `<ProductKey>` stops an unattended install dead.** With a
  multi-edition retail ISO, setup cannot infer which edition to lay down and
  puts up the Product key page — so the install sits there looking like the
  answer file was never read at all. A single-edition eval ISO (Server, for
  instance) does not need the key, which is exactly why an answer file cribbed
  from one fails on the other.
- **The UEFI boot menu is not stable between boots**, so a recorded key
  sequence for it is a trap rather than a recipe — see step 4. Screenshot
  before every key press in firmware; it costs one round trip and saves a
  reinstall.
- **`send-key` may reach the firmware and not the Windows bootloader.** The
  boot menu responds, the *Press any key to boot from CD* prompt does not, on
  any timing and with either keyboard bus. Build the no-prompt ISO instead of
  hunting for a magic interval — see step 4.
- **`virsh snapshot-create-as` does not capture the UEFI varstore.** The
  `<nvram>` file lives outside the disk image, so a domain restored from a
  snapshot keeps whatever boot entries it has now. Copy
  `/var/lib/libvirt/qemu/nvram/<name>_VARS.fd` alongside the snapshot.
- **A task's own console host is Windows Terminal.** On Windows 11, console
  applications are hosted in `WindowsTerminal.exe` by default, so a script
  launched from a scheduled task is *inside* one. A blanket
  `Get-Process WindowsTerminal | Stop-Process` therefore kills the script's own
  host, and it dies silently. Snapshot the pids that existed before you
  started and never kill those. Over SSH there is no such host, so the same
  code runs fine there and the bug reads as a task problem.
- **`virsh attach-disk` fails with "No more available PCI slots".** A q35
  guest with several SATA CD-ROMs runs out; free one, or move the payload to
  HTTP.
- **After a failed login the focus is on the password field**, and the username
  field keeps what was typed before. Type into it blind and you will "fail" a
  correct password. `KEY_LEFTSHIFT KEY_TAB` back to the username field,
  `KEY_LEFTCTRL KEY_A` to select what is there, then type — and screenshot the
  form to confirm before pressing Enter.
- **A brand-new profile hits the OOBE privacy dialog on first logon**, which
  covers the whole screen. An application launched underneath it *is* running;
  a few `KEY_ENTER` sends clear the dialog.
- **PowerShell's progress bars flood guest-exec output.** `Invoke-WebRequest`
  will bury a useful result under hundreds of kilobytes of CLIXML progress
  records. Set `$ProgressPreference = 'SilentlyContinue'` first.
- **Quoting a PowerShell block through ssh and cmd will defeat you.** Put the
  script in a `.ps1` file, copy it over, and run it with `-File`. The failure
  is a parser error that names the wrong line.
- **PowerShell variables are case-insensitive**, so `$REPS` and `$reps` are one
  variable. A table assigned to one and a loop counter assigned to the other
  silently destroys the table on the first iteration.

## Tearing it down

```bash
virsh destroy win11-fresh
virsh undefine win11-fresh --nvram        # --nvram or the varstore is orphaned
sudo rm -f /var/lib/libvirt/images/win11-fresh.qcow2
```
