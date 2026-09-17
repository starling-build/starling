# Fuchsia and modern GPUs: how hard would support be?

Research note, 2026-09-16. Sources are the Fuchsia tree at HEAD
(284cde1, 2026-09-15), Fuchsia's Mesa fork, the F30/F31 release notes, and
the Linux and Mesa trees at the same date for line counts. Commit dates on
fuchsia.googlesource.com need a sign-in, so driver recency comes from the
release notes and the checked-out sources, not from `git log`.

## Bottom line

Fuchsia can run a modern *integrated* GPU only with a new kernel-side
driver written from scratch: roughly one to two engineer-years per vendor
for Intel-class hardware, far more for AMD. A modern *discrete* GPU is off
the table without redesigning Magma itself, because Magma assumes unified
memory by design. Nothing in the public tree or the last two releases
suggests Google is attempting either.

For Starling the contrast is that a Linux base inherits every DRM driver
for free; Fuchsia's GPU list is a hand-written subset that has not gained
an x86 generation since 2020.

## What Fuchsia has today (F31, July 2026)

Fuchsia's GPU stack is Magma, a Vulkan-only analogue of Linux DRM. Each GPU
needs two pieces: a Magma System Driver (MSD), which plays the kernel-driver
role but runs as a userspace driver component, and a Vulkan ICD. OpenGL
exists only through ANGLE on top of Vulkan.

### Hardware coverage in the public tree

| Piece | Hardware covered |
|---|---|
| `msd-intel-gen` | Skylake and Kaby Lake, plus exactly one Tiger Lake device id (`0x9A49`, the NUC11) |
| `intel-display` | Skylake, Kaby Lake, Tiger Lake only; no Alder Lake or later (`pci-ids.h` has `is_skl`, `is_kbl`, `is_tgl` and nothing else) |
| `msd-arm-mali`, `msd-arm-mali-csf` | Amlogic-class Mali, plus a newer driver for CSF-generation Mali |
| `msd-vsi-vip` | Verisilicon NPU, not a GPU |
| `msd-virtio-gpu` + `gfxstream-vulkan` ICD | VM guests; rendering forwarded to the host |
| `framebuffer-amd-display` | Bootloader (UEFI GOP) framebuffer only, 38 lines of code, validated on Strix Halo (Ryzen AI Max+ 395); added in F31 |
| `framebuffer-intel-display`, `framebuffer-bochs-display` | Same firmware-framebuffer approach |
| Deleted (driver epitaphs) | Qualcomm Adreno MSD, MediaTek MT8167 MSD, and the AMD Kaveri and NVIDIA scanout-only drivers |

Officially supported x64 boards: NUC7i5DNHE (Kaby Lake) and NUC11TNHi5
(Tiger Lake). Board driver directories: astro, nelson, sherlock (all
Amlogic), vim3, x86, and emulators.

### ICDs

- **Intel**: `libvulkan_intel_gen`, built from a Mesa fork frozen around
  22.3.7. The anv Magma glue (`anv_magma*`) exists only on `sandbox/*`
  branches of the fork at that version. The current fork (`main`, Mesa
  25.3.4, last commit 2026-07-31) carries Magma backends for just two
  things: turnip (Qualcomm) and lavapipe. F31 removed an "unused"
  `vulkan_loader_for_intel` package.
- **Mali**: ARM's prebuilt proprietary ICD ("ARM Mali ICDs were rolled to
  SDK 30" in F31).
- **lavapipe**: CPU fallback, with a TODO to restrict it to eng builds.
- **gfxstream**: VM guests.

### Where Google's graphics work actually goes

Judging by the Mesa fork commits and the F30/F31 notes:

- **Adreno through Starnix.** A Starnix `kgsl` module (copyright 2025,
  ~1.7k lines of Rust) translates Qualcomm's KGSL ioctls onto Magma, using
  a vendor query `MAGMA_QCOM_ADRENO_QUERY_KGSL_PARAMS`; F31 expanded it to
  "contexts, buffers, semaphores, and command execution". The Mesa fork has
  `tu_knl_magma.cc` so turnip runs on Magma directly. The Adreno MSD itself
  is **not** in the public tree.
- **Mali CSF** (`msd-arm-mali-csf`, 3.7k lines), i.e. current ARM GPUs of
  the kind in Tensor and recent Amlogic parts.
- **Microfuchsia**: Fuchsia as a VM guest under Android's virtualization
  framework (pKVM/crosvm); the GPU is whatever the host exposes over
  virtio-gpu. The Starnix `gpu` module builds a rutabaga/gfxstream device
  and currently logs "virtio-gpu unsupported".

### Project context

The January 2023 layoffs cut 16% of the ~400-person team; the workstation
product and the Chromium port were dropped. Fuchsia ships on Nest Hubs and
keeps a quarterly cadence (F30 on 2026-04-07, F31 on 2026-07-22).

## How hard a modern GPU would be

### Tier 1: a modern integrated GPU

Meteor/Lunar/Panther Lake, or an AMD APU such as Strix Halo. These fit
Magma's memory model, so the cost is the driver itself.

The userspace half is cheap. Mesa's Vulkan drivers already abstract the
kernel interface (anv has `i915/` and `xe/` backend directories; turnip has
`tu_knl_drm_msm`, `tu_knl_kgsl`, `tu_knl_drm_virtio`, `tu_knl_magma`), and
turnip's Magma backend is four files.

The kernel-side half is the whole job. Non-test source lines, counted on
2026-09-15:

| Driver | Lines |
|---|---|
| Fuchsia `msd-intel-gen`, all of it | 9,009 |
| Fuchsia `intel-display` | 31,489 |
| Fuchsia `msd-arm-mali` | 9,212 |
| Fuchsia `amlogic-display` | 23,174 |
| Linux `xe` (Tiger Lake and newer), `.c` only | 115,757 |
| Linux `i915`, `.c` only | 364,911 |
| Linux `amdgpu`, `.c` only | 1,059,642 |
| Linux `amdgpu`, `.c` plus generated headers | 6,510,346 |
| Linux `nouveau`, `.c` only | 173,628 |
| Linux `msm` (Adreno), `.c` only | 87,002 |
| Linux `panthor` (Mali CSF), `.c` only | 15,956 |
| Mesa anv / radv / nvk / turnip / panvk | 107,777 / 116,186 / 36,337 / 67,535 / 41,000 |
| Mesa lavapipe / venus | 21,799 / 25,859 |

What a new Intel MSD needs that the current one lacks: GuC and HuC firmware
loading (mandatory for submission on Xe-era parts; the current driver has
no GuC code at all and drives only the render and video command
streamers), GuC-based scheduling, modern power management, and a display
driver that knows post-Tiger-Lake DDI, Type-C and DSC details.

Genode is the closest precedent for a microkernel OS doing this. Its 25.11
release added accelerated Alder Lake by porting Mesa's Intel driver, and
it still cannot reach full GPU clocks without disabling RC6, which costs
unacceptable power. Firmware and power management are the long tail, not
command submission.

AMD is worse. An APU's init path runs through PSP, SMU and MES firmware,
and the display block (DC/DCN) has its own firmware (DMCUB), all of it a
million lines of hand-written C with no small reference implementation.
The realistic route is porting amdgpu wholesale inside a Linux-emulation
shim, the way Genode's `lx_emul` does, not writing a Magma driver.
Google's own answer for Strix Halo in F31 was the bootloader framebuffer
plus software rendering.

### Tier 2: a discrete GPU

RTX, Radeon, or Arc. The porting guide says "at the moment Magma only
supports UMA devices" and "if you're ambitious you could attempt to port
to a GPU with discrete memory"; RFC-0198 says desktop GPUs with dedicated
memory "may require API changes".

Concretely: Magma buffers are Zircon VMOs in system memory, pinned through
the IOMMU via a BTI and mapped into per-connection GPU address spaces.
There is no device-local heap, no VRAM allocator, no BAR-backed memory
type, and no migration or eviction. Adding those touches Magma, sysmem,
the Vulkan ICD glue and every existing driver. NVIDIA's only viable path
is the GSP firmware interface, which Linux's Rust `nova` driver is still
bringing up (core merged in 6.15, Ampere GSP init in 6.19).

This is multi-year platform work, and the tree shows movement the other
way: the NVIDIA and AMD scanout drivers were deleted rather than grown.

### Effort anchors

- Asahi: nothing to a conformant Vulkan 1.3 driver for Apple's GPU in
  about two years; the Vulkan half took one month because Honeykrisp
  forked NVK.
- NVK: announcement (Oct 2022) to Vulkan 1.3 conformance in about two
  years; now 1.4-conformant from Kepler through consumer Blackwell.
- Genode: Alder Lake acceleration in 25.11, clocks/RC6 deferred to 26.02.

Those were full-time specialists on UMA hardware with reusable Mesa
userspace, which is also the best case for Fuchsia.

### What works today without a driver

Run Fuchsia as a VM guest and forward Vulkan to the host through
virtio-gpu and gfxstream (microfuchsia's model), or fall back to lavapipe
on the CPU.

## Sources

- Magma design: https://fuchsia.dev/fuchsia-src/development/graphics/magma/concepts/design
- Magma porting guide: https://fuchsia.dev/fuchsia-src/development/graphics/magma/concepts/porting
- RFC-0198 Magma API: https://fuchsia.dev/fuchsia-src/contribute/governance/rfcs/0198_magma_api_design
- Magma overview: https://fuchsia.dev/fuchsia-src/development/graphics/magma
- Fuchsia hardware drivers: https://fuchsia.dev/fuchsia-src/reference/hardware/drivers
- Deprecated drivers: https://fuchsia.dev/fuchsia-src/reference/hardware/driver-epitaphs
- Supported system configurations: https://fuchsia.dev/fuchsia-src/reference/hardware/support-system-config
- F30 release notes: https://fuchsia.dev/whats-new/release-notes/f30
- F31 release notes: https://fuchsia.dev/whats-new/release-notes/f31
- Fuchsia GPU drivers: https://fuchsia.googlesource.com/fuchsia/+/HEAD/src/graphics/drivers/
- Fuchsia display drivers: https://fuchsia.googlesource.com/fuchsia/+/HEAD/src/graphics/display/drivers/
- Fuchsia Mesa fork: https://fuchsia.googlesource.com/third_party/mesa/+log/HEAD/
- DMA/IOMMU concepts: https://fuchsia.dev/fuchsia-src/concepts/drivers/hardware
- 2023 layoffs: https://www.androidpolice.com/google-2023-layoffs-fuchsia-os-and-area-120/
- Microfuchsia: https://www.androidauthority.com/microfuchsia-on-android-3457788/
- Fuchsia on Wikipedia: https://en.wikipedia.org/wiki/Fuchsia_(operating_system)
- AMDGPU size: https://www.phoronix.com/news/AMDGPU-4-Million
- Genode 25.11: https://genode.org/documentation/release-notes/25.11
- Asahi Vulkan 1.3 in one month: https://asahilinux.org/2024/06/vk13-on-the-m1-in-1-month/
- NVK conformance: https://www.collabora.com/news-and-blog/news-and-events/nvk-is-now-ready-for-prime-time.html
- gfxstream README: https://android.googlesource.com/platform/hardware/google/gfxstream/+/refs/heads/main/README.md
