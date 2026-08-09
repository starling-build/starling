# PRIME render offload

Goal: what other desktops ship — ONE shell/compositor on the display GPU
(the AMD 680M here), individual apps rendering on the discrete GPU (the
RTX 3050), their buffers imported for compositing. This supersedes the
per-screen-shell track (docs/plans/nv-view.md, PAUSED 2026-08-08 — that
architecture is a much bigger change and stays parked on branch
`workspace-mode-per-output`).

## Base (verified 2026-08-08)

- Branch `prime-render-offload` (this repo), cut from main plus one
  cherry-pick: 7c47ded "Apps can render on the NVIDIA GPU" —
  GpuDmaBufRenderer's swapchain mode, the whole app-side mechanism.
- Engine: branch `prime-render-offload` at 47d9da38403 (pre-external-view;
  the Stage A work stays with the parked branch). PRIME needs no engine
  changes — keep it that way.
- Verified live: `STARLING_APP_DRM_DEVICE=/dev/dri/renderD128` makes every
  first-party app render on the NVIDIA GPU (swapchain mode logs confirm)
  and composite normally on the AMD desktop. Relevant probed facts from
  nv-view.md: NVIDIA renders into linear via gbm_surface swapchain
  (fact 1); AMD imports NVIDIA linear buffers as GL textures (fact 2).

## Work plan

1. **Per-app GPU preference, not a session switch.** Today the env is
   global — every app or none. Add an opt-in key to the app's registry
   record (`registry/catalog.d/<id>.app`, the ONE description of an app),
   e.g. `Gpu=discrete`; the launch paths read it per spawn. No tables in
   the shell.
2. **Discrete-node discovery.** Resolve "the render node that is not the
   shell's" via the sysfs card↔render pairing (the pattern
   find_render_node_devid uses) instead of hardcoding renderD128. No
   discrete GPU → the key is a no-op, apps render on the shell's GPU.
3. **First-party path:** the process-app spawn sets
   `STARLING_APP_DRM_DEVICE=<discrete node>` for marked apps. Swapchain
   mode auto-detects from there (7c47ded).
4. **Third-party path:** `build/app-run.sh` injects the standard offload
   envs for marked apps: `DRI_PRIME=1` (mesa) and
   `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia`
   (NVIDIA GL). Their Wayland buffers negotiate through the existing
   dmabuf feedback (main_device stays the AMD node; the LINEAR-only table
   plus runtime demotion already steer explicit-modifier clients to
   layouts AMD imports).
5. **Compositor: no changes expected.** Import of NV linear buffers is
   proven; recording doctrine unchanged (AMD screen → VA-API).
6. **Measure** (the nv-view open question, still open): frame times, GPU
   utilization both sides, and app CPU for a busy app on/off the discrete
   GPU. Power: the 3050 wakes only while a marked app runs — a better
   battery story than a permanent NV screen.

## Chrome (and Chromium apps): why Wayland offload is blocked (2026-08-08)

Investigated to the bottom; three distinct failure modes, all reproduced:

1. **Env-side device selection cannot reach Chromium.** Ozone/wayland takes
   its render node from dmabuf-feedback `main_device` and hands ANGLE a
   device directly (surfaceless); Mesa's window-surface path — where
   DRI_PRIME and the client-side PRIME blit live — never runs. Chrome with
   the full working env (zink + DRI_PRIME) stays on the AMD device
   (chrome://gpu: zink RADV), sandbox on or off.
2. **Serving Chromium a discrete `main_device` (compositor-side steering,
   tried and reverted) founders on allocation.** Chromium then allocates
   its shared buffers itself via gbm on the NVIDIA node — and NVIDIA's gbm
   refuses LINEAR render targets (nv-view fact 1), so the explicit-LINEAR
   attempt fails and the implicit fallback yields NVIDIA-tiled
   (0x300000000606014), which the AMD compositor cannot import. Chromium
   has no cross-device blit; render device must equal allocation device.
   (This run also exposed a shell robustness bug: the failed import
   cascaded into an amdgpu CS rejection and a shell abort — filed.)
3. **ANGLE-on-Vulkan pinned to the NVIDIA ICD** initializes but dies in
   shared-image SkSurface creation — same device split, one layer down.
   A GLX detour is also closed: any GL env override makes Chromium's GPU
   probe touch GLX against the in-tree X server, which dies on an xcb
   assert (hence the discrete env empties DISPLAY).

What DOES work: **Mesa-EGL window-surface clients** (weston-simple-egl
verified live; Blender is the same stack). With `MESA_LOADER_DRIVER_
OVERRIDE=zink DRI_PRIME=1` the context lands on the NVIDIA Vulkan device
and Mesa's kopper blits to compositor-compatible LINEAR internally — the
compositor needs no changes and receives modifier=0x0.

Chrome avenues if it becomes a requirement: (a) run it under rootful
Xwayland (the WeChat machinery) with DRI3 PRIME, at the cost of
single-window integration; (b) revisit when Chromium/ANGLE learn split
render/allocation devices; (c) accept AMD rendering for browsers — the
workload benefiting from the dGPU (WebGL/video) is also the workload the
Xwayland box hurts least.

## Measured (2026-08-08, dev box: RTX 3050 6GB + Radeon 680M)

glmark2-es2-wayland through the live compositor, discrete via the verified
env (`MESA_LOADER_DRIVER_OVERRIDE=zink DRI_PRIME=1`). GPU busy% sampled
from `nvidia-smi` and `/sys/class/drm/card2/device/gpu_busy_percent`.

| workload | AMD (integrated) | NVIDIA (offload) | verdict |
|---|---|---|---|
| off-screen `build` (pure GPU) | score 7500 | score 8220 | dGPU ~10% faster |
| on-screen `terrain` (heavy) | 110 fps / 9.1ms | **127 fps / 7.9ms** | offload WINS |
| on-screen `build` (light) | **1585 fps** | 323 fps | offload LOSES 5× |

The `terrain` run is the case offload is for. Rendering it integrated pins
the AMD GPU at **100%** (0% NVIDIA); offloaded, NVIDIA sits at **79%** and
AMD drops to **13%** — that 13% is the mandatory presentation blit
(importing the NVIDIA linear buffer and compositing it; nv-view fact 3).
So a heavy app both runs ~15% faster AND vacates the GPU that drives the
desktop, for a cheap ~13% iGPU presentation cost.

The `build` run is the counter-case, and the whole argument for per-app
opt-in over a global switch: a light workload at 1500+ fps is dominated by
per-frame overhead, and the cross-GPU copy (NVIDIA render → dma-buf → AMD
present) dwarfs the tiny render, so offload is a 5× LOSS. Only apps heavy
enough to saturate the iGPU and amortize the copy should carry
`Gpu=discrete` — which is exactly why blender (heavy 3D) has it and nothing
else does.

Power: the 3050 idles at ~6.3W / 0 MiB once a workload ends (it does not
return to D3cold while the desktop holds it awake only if an offloaded app
is running — a marked app that has exited leaves it free to sleep). On a
laptop, `Gpu=discrete` is a per-app battery cost paid only while that app
runs, not a permanent one — strictly better than the parked per-screen
shell, which kept the dGPU awake for the whole session.

## Traps to carry over

- Test third-party behaviour unprivileged (`LIBSEAT_BACKEND=seatd
  /usr/libexec/starling-session` over SSH, or the VM) — root dev mode both
  invents and hides third-party bugs (CLAUDE.md).
- The dev box's only NVIDIA GPU is on the dev box, not the VM — GPU-path
  verification stays here, packaging/user-path verification in the VM.
- shell-drive's broker socket resolution prefers the invoking user's
  runtime dir: a dead `/tmp/xdg-starling-1000/starling-agent.sock` from an
  old unprivileged run makes `dock` actions die with ECONNREFUSED while
  the root-owned live socket sits one directory over. Delete the stale
  file.
