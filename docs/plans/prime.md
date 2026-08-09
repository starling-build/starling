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
