# The 3D desktop — a room you stand in, with your windows in it

Turning 3D on puts you inside a modelled room, with every app window
hanging in it as a pane of glass at a real place. You walk with the
keyboard, step up to a window and it is pixel-exact again, and turning
3D off puts the flat desktop back exactly as it was.

Branch: `desktop-3d`.

## Where it stands (2026-09-18 evening, checkpoint)

**The city ships, and it works the way the user asked for it to.**
Branch `desktop-3d`, pushed, this repo only (the engine is untouched
since the last checkpoint). One window on screen at a time, Alt+Tab
between them, a click on a brick to open, a clock on the square, a
switch in Settings, the world and its renderer in the package, and it
runs on the host GPU from inside WSL. Read this section, then "Phase
7" onward for how it got here, and "Traps paid for" before touching
anything. Phases 11 to 40 are two days of the user playing and asking;
each one names what they said.

- **The renderer is Filament** (`STARLING_ROOM=filament`), built from
  source the one way that shares the engine's EGL context
  (`build/build-filament.sh`, ~20 min once), wrapped in a C shim the
  shell dlopens (`build/build-room.sh`, `shell/Sources/StarlingRoom/`).
  It draws into the wallpaper's texture slot from its own thread and
  waits for the GPU. Real shadows, ambient occlusion, sky reflections,
  tone mapping, MSAA; 8–13 ms a frame at 2560x1600. Primitives the
  shim offers: panes (a client texture in a slab, with a world's block
  tile as the frame — `sr_room_set_pane_style`), labels (billboards, or
  fixed-yaw signs), orbs, and blocks (lit cubes with a shell-drawn face
  — `sr_room_set_block`, with a roll for tipping).
- **A world is a directory** (`STARLING_ROOM_DIR`): a cmgen sky, an
  optional glTF, and `world.json`. Three kinds: `room` (the living
  room, windows on the walls), `orrery` (rejected on looks), and
  `voxel` — **the Minecraft-style city**, 96 blocks across, eight
  building styles, doors and shopfronts under awnings and signs, roof
  tanks, crosswalks, thin lamp posts, generated in ten seconds by
  `build/tools/voxel-world.py`, walked on foot; entered by a 6 m dolly
  over a second, left by Escape (Alt+Escape with a window focused) or
  the door block on the pool's rim. The city is the direction; the
  room still works and is untouched.
- **Windows in the city** are panes with the world's block frame and a
  block title bar (planks, redstone/gold/emerald buttons) drawn IN the
  scene, so a brick in front of a window covers it; nothing floats over
  a window (the nameplates went — the bar names it). A window gets its
  place when it arrives and keeps it: the arc round the square for
  windows brought in from the flat desktop (out of sight, where the
  ring fetches them from), or right in front of the viewer at reading
  size for one opened here. A window is named after the app that owns
  it (registry, not the Wayland id), so Chrome's pane says Chrome. A
  window clicked from across the square is walked up to (a 380 ms
  glide, the click kept from the app). Fullscreen works there (emerald
  block; the top-edge reveal shows the bar alone, no status bar). **A
  window redraws when its app draws** — it did not, once, and typing
  read as slow (Phase 38); and the window that had the keyboard keeps
  it on entry (Phase 39).
- **One window on screen.** The city shows the window that has the
  focus (else the last one it showed, else the front-most), in front
  of you at 1:1; every other window is out of sight. A new window, or
  one that gains the focus, flies to the front and the previous one
  goes; closing the front one hands the screen to the next. The rest
  come back only on the ring (below), and glide out of sight again
  after it. Step aside (Alt+A/D) to see the bricks past the window.
- **Alt+Tab swings the open windows round you.** Hold Alt and press
  Tab: every open window glides onto a ring round where you stand, at
  eye height, facing in, the one you had before straight ahead and a
  little nearer; each Tab turns the ring one place (Shift+Tab back);
  let go of Alt and the chosen window flies up to the front at 1:1
  with the keyboard while the rest go back where they stood; Escape
  puts everything back. Windows have pose tweens now
  (`_desktop3DTween`), so the ring turns rather than cuts.
- **The dock is a small building of bricks in the pool**, each app a
  lit block with its colour and glyph — its real icon where it has one
  (Chrome, the App Store); a running app drops a brick onto the pile.
  Hover lights one and names it;
  a click opens its app, whose window pops up in front of you (or
  brings its open window to you), and whatever was already in front
  steps back behind it; press and drag carries it —
  anywhere in the city, at the distance it was picked up, the wheel
  pushing and pulling, riding over other bricks — and let go, it
  falls onto whatever is under it. **The bricks have weight:** pull one
  out and what it held up tips off and falls; they never overlap (a
  pairwise resolver every step, the pool's rim a box too), they settle
  onto a quarter-brick grid, and a pile that will not settle in twenty
  seconds stops and says so. Positions live in memory only.
- **A clock tower stands on the far side of the square**, in the gap
  the windows keep clear: three blocks square, twelve high, sandstone
  on a stone footing, a door toward the square, a cornice, a roof and
  a mast (`voxel-world.py`; regenerate the world to get it). The shell
  draws its face — a dial with blocky marks and two hands — on all four
  sides, and redraws it on the minute while the city is up (one wake a
  minute, none once 3D is off).
- **It ships.** The city is checked in (`shell/Resources/Worlds/city`,
  staged as `share/starling/worlds/city`), `build-all.sh` builds the
  Filament shim when Filament is built on the box and says so when it
  is not, the package declares the shim's `libc++` runtime, and the
  shell picks Filament and the city on its own whenever both are beside
  it (`STARLING_ROOM=gl` forces the GL room, `STARLING_ROOM_DIR`
  another world). Settings → Appearance has a **3D Desktop** switch,
  live in both directions like Tiling Windows, and the choice persists
  across logins as it always did (`~/.config/starling/desktop-3d`).
- **It runs in WSL, on the host GPU.** The RDP display mode asks Mesa
  for its D3D12 driver when `/dev/dxg` is there (Phase 40): the city
  at 7–12 ms a frame on the box's Radeon 780M, against ~165 ms on
  llvmpipe, seen through FreeRDP and through Windows' own Remote
  Desktop client alike. `libc++1`/`libc++abi1` must be installed or
  the renderer silently does not load (the .deb declares them; a bare
  `dpkg -i --force-all` does not bring them).
- **Driving it**: `~/tmp/filament/play.sh` starts the dev shell with the
  city and turns 3D on (`play-default.sh` with no overrides —
  what a login gets); `shell-drive` for input — one invocation per
  gesture (`down`, moves, `up`; `click` on a brick opens its app; Alt
  held across `key tab`s for the ring); `~/tmp/filament/lat/` for
  keystroke-to-screen latency (a keyboard-only driver and the debugfs
  fb-id oracle — check the idle-flip baseline first); the `[3D] bricks
  settled:` log line for positions, checked pairwise for overlap by a
  script, never by eye; `[Input] UP` against the shot's line before
  reading a screenshot of a drag; `kill -USR1 <shell>` for a screenshot
  that moves no pointer. WSL: `~/tmp/filament/wsl/` (run scripts as
  FILES from `C:/dist`; hold the launching ssh open or the distro dies;
  mstsc as a viewer only — never `SendKeys` on that live desktop).

**Next**, in the order I would take it: the city idles at ~13% CPU in
WSL where the flat desktop idles at 0 (a dozen engine threads at 1%
each — find the pump); the WSL gate should fail on unmet dependencies
instead of forcing the install; day and night following the clock;
bricks and windows through buildings (nothing in the city is solid to
them) and persisting brick positions; reaching the dock with a window
in front without stepping aside; looking up and down; the room's walls
read as concrete.

## How it is built

Nothing about the room is computed at runtime. Three tools bake it and
the shell reads the result:

```
  build/tools/room-fetch.py    CC0 furniture from Poly Haven (~20 MB)
  build/tools/room_gltf.py     as much glTF as those exports use
  build/tools/room_hdri.py     Radiance .hdr, spherical harmonics, the sun
  build/tools/room-import.py   bakes everything into three files
        |
        v
  shell/Resources/Room/room.mesh          geometry + the sky's light
                      room-diffuse.png    2k atlas, base colour
                      room-arm.png        2k atlas, occlusion/rough/metal
                      room-sky.png        the sky, square-rooted to 8-bit
```

`room.mesh` is `STARROOM`, a version, three counts, then the sky's light
(nine SH triples, the sun's direction and colour, the sky texture's
range), then an interleaved vertex array —
`pos(3) nrm(3) uv(2) ao(1) sun(1) mat(1)` — and 32-bit indices.

**Why the split matters.** The room can be rearranged, re-lit or
replaced without rebuilding the shell, and iterating on how it looks
costs 25 seconds instead of a build, a restart and a screenshot. The
shell has nothing to get wrong: it reads a file, uploads it, draws it.

Ambient occlusion is 64 cosine-weighted rays per vertex against a voxel
grid of the real triangles; daylight is one ray per vertex traced back
to the window openings. Both are per VERTEX, so the subdivision of a
surface is the resolution of every shadow that falls on it.

## The road here, and what it ruled out

The direction changed twice, and both dead ends are worth not repeating.

1. **The wallpaper wrapped around you.** A cylinder centred on the eye
   is depth-flat by construction — every point is the same distance
   away — so it is indistinguishable from the flat picture through a
   desktop lens, and no tuning changes that.
2. **The wallpaper reconstructed as a 3D scene**, using a monocular
   depth map to put every pixel back at its real distance. This works,
   and is in the history at `523bc18` if it is ever wanted: from the
   spot the photograph was taken from it IS the photograph, and a step
   sideways is real parallax. It was dropped because the modelled room
   looked better, and because a single photo has nothing behind
   anything — wander more than about two metres and its holes open up.
3. **Hand-modelled furniture.** A sofa built from eight axis-aligned
   boxes reads as polystyrene however well it is lit, because a
   silhouette is the first thing anyone sees. This was not a lighting
   problem and not a materials problem, and no amount of either fixed
   it. Real assets did, immediately.

## Prior art, and why every one of them was an effect

| What | Year | Why it did not stick |
|---|---|---|
| Sun Project Looking Glass | 2003 | Windows as 3D objects (flip to write on the back). Every window was perspective-sampled, so text was blurry everywhere. Java3D over X was too slow to live in. |
| Compiz cube / Flip 3D / KWin cube | 2006–08 | 3D only *while switching*. The working state was flat, so the geometry meant nothing and remembered nothing. |
| BumpTop | 2007 | A physics desk for icons, not app windows. |
| Fuchsia Scenic (Mozart) | 2016 | A real 3D scene graph with lighting and shadows under every window. Flattened to 2D within a few years: the cost bought nothing a flat UI needed. |
| visionOS, SimulaVR, Stardust XR | 2019– | Windows as live glass panes in an environment. This is the target feel, and it exists only through a headset: the environment *is* the display. |

Three lessons carry:

1. **Perspective-sampled text is unusable.** The window in front of the user
   must be drawn at 1:1 device pixels, square to the camera. The scene is for
   everything else.
2. **A 3D that only appears during transitions is decoration.** The 3D
   placement must be persistent state the user arranged, and every view must
   be a camera pose over that state.
3. **The environment has to come from somewhere the user already chose.**
   visionOS ships hand-built environments; a desktop cannot. The wallpaper
   is the one image every user has already picked, so the scene is generated
   from it. That is the idea nobody has done on a monitor.

## What the tree already does

Check these before believing the rest:

- **Every window is already a texture in the shell's layer tree.**
  `DesktopWindow` draws its app as a `TextureWidget` (a DMA-BUF import on
  Linux) and already wraps it in a `Transform` — a Y flip today
  (`shell/…/Window/DesktopWindow.swift:22`). Mission Control scales the same
  live textures into cards through another `Transform`
  (`shell/…/Shell/MissionControl.swift:140`). A 3D pose is a different
  matrix in the same slot.
- **The whole 4x4 reaches the engine.** `SceneBuilder.pushTransform` takes
  16 doubles (`sdk/Sources/FlutterSwiftBridge/Compositing.swift:528`), the
  engine's `TransformLayer` carries a `DlMatrix`, and an external texture is
  painted with `DrawImageRect` under whatever canvas matrix is current
  (`engine/…/embedder/embedder_external_texture_gl.cc:69`). Skia rasterises
  a perspective quad from that. No engine change is needed to draw a window
  in 3D.
- **Hit-testing through perspective is ported, not approximated.**
  `RenderTransform.hitTestChildren` goes through `addWithPaintTransform`
  (`sdk/…/Rendering/ProxyBox.swift:4001`) and `MatrixUtils.transformPoint`
  does the homogeneous divide (`sdk/…/Painting/MatrixUtils.swift:147`). A
  `Listener` under a perspective `Transform` gets `localPosition` in the
  window's own space, which is exactly what `DesktopWindow` forwards to the
  client. A tilted browser is clickable at the right pixel with no new input
  code.
- **The wallpaper is one GL texture, and the shell already knows how to
  render into a texture on the raster thread.** `_loadWallpaperTexture`
  decodes the JPEG and uploads RGBA to a registered texture id
  (`shell/…/Shell/DesktopShell.swift:1464`); `makeWallpaper` composites it
  as a `TextureWidget` (`:3790`). Separately, `GLRenderer.renderToTexture`
  is called from the external-texture callback on the raster thread with
  the engine's EGL context current
  (`shell/…/Compositor/LinuxTextureRegistry.swift:539`), and every imported
  window is an ordinary `GL_TEXTURE_2D` name in that same context (`:515`).
  An environment renderer is a `GLRenderer`-shaped class behind the
  wallpaper's texture id. Nothing new has to be wired.
- **Window state is one struct.** `WindowInfo.rect` + `zIndex` is the flat
  pose (`shell/…/Shell/WindowManager.swift:20`). The 3D pose is a few more
  numbers beside it, and both are kept.
- **The chrome already reads the wallpaper.** `shellMica` is the
  wallpaper's average colour and the theme is a function of it
  (`DesktopShell.swift:1513`). Per-window lighting from the scene is the same
  idea, sampled locally.

## The design

### Two states, both persistent

```
   2D (default)                          3D
   ┌──────────────────────────┐          ┌──────────────────────────────┐
   │  flat wallpaper          │          │   environment built from     │
   │  ┌──────┐ ┌────────┐     │  toggle  │   the wallpaper (depth,      │
   │  │      │ │        │     │ ───────▶ │   wrap, floor, light)        │
   │  │      │ └────────┘     │ ◀─────── │     ╱‾‾╲   ╔══════╗   ╱‾‾╲   │
   │  └──────┘  ┌────┐        │          │    │ app │  ║ app  ║  │ app │  │
   │            └────┘        │          │     ╲__╱   ╚══════╝   ╲__╱   │
   └──────────────────────────┘          └──────────────────────────────┘
   WindowInfo.rect is truth                WindowInfo.pose is truth
```

Each window carries both a 2D `rect` and a 3D `pose` (position on the arc,
distance, yaw). Switching modes animates between them and never overwrites
one with the other, so leaving 3D puts every window back exactly where it
was, and re-entering finds the arrangement the user made in the scene.

### The environment

**Superseded — kept because its findings are still true.** The original
design generated the environment from the user's wallpaper, in three
tiers: a wrap, then a depth-map relief, then occlusion layers. What it
is now is above; what that attempt established, and which still holds
for anyone who revisits it:

- A cylinder centred on the eye cannot show depth (see "The road here").
- A monocular depth map of a LANDSCAPE photograph holds a ground plane
  and nothing else: 54% of the bundled wallpaper's map is in the darkest
  tenth, and sky, bridge and headland all sit between 0.00 and 0.19,
  because they genuinely are at infinity. The model is not failing.
- Inverse depth has to be inverted into distance before it is useful.
  The same numbers that read as "a ground plane and nothing else" open
  back out into a scene when they are: the water at 3 m, the sky at 420.
- The wallpaper is not gone. It hangs in the room, framed, over the
  fireplace — which is where a picture belongs.

### The windows, visionOS-style

Windows are **not** in the GL scene. They stay in the Flutter layer tree,
above the environment texture, each wrapped in `Transform(projection · view
· pose)`. That keeps input free (see above), keeps the chrome, dock and
menu bar crisp, and needs no depth test between windows because they never
intersect: they sit on an arc, facing the camera, at distinct positions.

- **The arc.** Poses live on a cylinder around the viewer at a comfortable
  distance; a window faces the camera wherever it is on the arc. Moving a
  window slides it along the arc and it re-orients on its own. Scrolling on
  its title bar pushes it away or pulls it closer. Minimise puts it on the
  floor, small, still live.
- **The crispness rule.** The focused window is drawn with its `Transform`
  *skipped* — not near-identity, skipped — at 1:1 device pixels, square to
  the camera, at the arc's front. A 0.999 scale resamples text; identity
  does not. Everything else is perspective-sampled with
  `FilterQuality.medium` (Mission Control's lesson: `.low` aliases when
  minifying). Imported textures have no mip chain, so `.medium` makes Skia
  copy into a mipmapped texture per frame per window; the spike measures
  that, and the fix if it costs is to build mips once per client commit in
  the texture callback.
- **Glass.** The window material's tint comes from the scene behind the
  window: the environment renderer writes a low-resolution "light" buffer
  the platform thread reads back once per pose change, and
  `windowGlassTint` is resolved per window instead of once from the
  wallpaper average. Fluent's Mica is the same idea already
  (`shellMica`), so the plumbing exists.
- **Parallax from the pointer.** With no headset there is no head tracking,
  so the camera borrows a degree or two of yaw and pitch from the pointer's
  position on screen (the Apple TV / iOS lock-screen trick). It is what
  makes depth *legible* on a monitor: as the pointer crosses the screen the
  floor slides against the wall and the far windows against the near ones.
  Off when a window is being dragged, so drags stay predictable.

### Entering and leaving

Entering: the flat wallpaper *becomes* the scene. The camera pulls back
into the picture as the wrap and floor unfold from it; the windows lift off
the plane and glide to their arc poses (first time: an arc layout derived
from their 2D rects, so nothing jumps). Leaving is the reverse. Both are
one camera path plus one pose tween per window, on the same
`AnimationController` pattern as `OpenAnimations.swift`, ~600 ms.

The toggle is a real mode beside Mission Control: the desktop context menu,
the control centre, and a chord. It is a per-desktop setting that persists
across sessions.

### Other views become camera moves

Once poses are state, the views the shell already has stop re-laying-out
and start moving the camera over unchanged poses:

- **Mission Control** dollies back. The overview is the user's own
  arrangement seen from further away, so spatial memory survives it.
- **Spaces** are regions along the panorama; a space switch pans the camera.
  The slide layers become a camera path.
- **Open / close** approach and recede along z instead of the scale zoom.

## Phases

### Phase 0 — the spike (prove the primitive)

A hidden chord in `DesktopShell` that lifts every *unfocused* window onto an
arc: in the window-stack builder (`DesktopShell.swift:3915` onward) wrap the
`Positioned` child in a `Transform` with `setEntry(3, 2, -1 / focal)`, a yaw
toward the centre and a push-back, aligned on the screen centre. The focused
window is untouched. The flat wallpaper stays. About 150 lines.

It passes when, on the DRM desktop with a real Wayland client in a tilted
slot (Chrome is the honest test: hover effects, text, scroll):

1. the tilted window composites (Skia perspective on an external texture);
2. hover moves the client's own cursor feedback to the right element;
3. a click lands on the right pixel;
4. text in the tilted window reads at `.medium`, and frame time with four
   tilted windows is measured against the flat baseline;
5. a title-bar drag on a tilted window moves it sensibly. It will not:
   `onMove` deltas are screen-space and the tilt changes the ratio. Fix by
   unprojecting the delta through the pose's inverse in `DesktopWindow`;
   the spike decides whether Stage needs it or only free placement does.

Run it on the Linux dev box, not the Mac: the macOS shell has not been
built since 0.2 and its texture path is Metal/IOSurface. The layer and
hit-test code are shared, so a macOS run proves less than it costs.

#### Results (2026-09-16, dev box, eDP 2560x1600 @ scale 2)

What landed: `Shell/Desktop3D.swift` (the pose: focal 1.5 × screen width,
yaw up to 35° toward the centre, pushed back to 0.7×, near-plane guard on
the four corners), the window-stack builder wraps every window's slot in a
`Transform` (identity when flat — it takes RenderTransform's plain
translation paint path, so a flat window is not resampled; always present
so the slot's widget TYPE never changes on focus, which would remount the
subtree), `DesktopWindow` samples the client texture at `.medium` only when
tilted, and three ways in: Ctrl+Shift+3, the broker op
`{"op":"desktop_3d","on":true|false}` (unauthenticated, for tooling), and
`STARLING_3D_SPIKE=1` to start in it. The scene: Chrome ×2 (Wayland
dma-buf), weston-terminal (wl_shm), Calculator (first-party), tiled.

1. **Composites.** Skia draws the imported external texture through the
   perspective matrix; chrome, shadow and border tilt with it. Both buffer
   paths (dma-buf and wl_shm) and the first-party child app render.
2. **Hover reaches the right element.** Hovering one screen point over the
   tilted Chrome lit the cell under it and Chrome reported page coordinates
   inside that cell; the same point unprojected differently from the flat
   layout, exactly as the tilt predicts.
3. **A click lands on the right pixel.** Clicking that same point selected
   the same cell (Chrome painted it green after it came forward and
   flattened). `RenderTransform.hitTestChildren`'s homogeneous divide is
   correct as ported; no input code was touched.
4. **Text reads at `.medium`.** Cell labels in a tilted window minified to
   ~0.6× stay legible. Cost, same pointer sweep with 3 tilted windows
   (one a 2560x1460 texture) vs flat, `STARLING_FRAME_LOG=1`: UI thread
   per frame 0.34 → 0.39 ms median (noise); raster thread 5% → 9% of a
   core over the sweep (~0.4 → 0.7 ms per hover frame). No mip cache was
   built; at this cost it is not needed yet. GPU time was not measured.
5. **Drag: the premise does not arise.** A press on a tilted window brings
   it to front, which focuses it, which flattens it on the same frame — so
   no window is ever dragged while tilted. The local-space delta fix was
   tried and is WRONG for this design: the framework freezes the hit-test
   transform at pointer-down for the whole gesture, so with the window
   already flat the unprojected deltas overshoot by 1/scale (measured: the
   window moved 1.43× the pointer). Screen-space deltas (unchanged code)
   are right. A window that stays posed while dragged is Phase 1's arc
   drag, and it has to keep the pose through the press for either fix to
   apply.

Also learned, none of it 3D's fault:

- Chrome opens at the full work area on a 1280x800 logical screen (its own
  small-display default; `--window-size` is ignored on Wayland), and
  weston-terminal did the same, so every new window stacked at one pose.
  Tiling is the quick way to a spread-out scene for tests.
- `app-run chrome` on `main` still passes `--force-device-scale-factor`
  and draws Chrome at 2× (dpr 4); the fix lives on `computer-use`.
  `STARLING_APP_SCALE=1` neutralises it for a test.
- The broker has no read-back for the mode; the op without `on` toggles.

### Phase 1 — tier 0 environment, and the mode

- `WindowInfo` gains `pose`; `rect` stays. A `Camera` per output.
- `EnvironmentRenderer` beside `GLRenderer`, behind the wallpaper texture id
  when 3D is on: cylinder wrap, blurred extension, reflective floor, camera
  from the platform-thread mailbox, pointer parallax.
- Enter / leave transitions. The toggle in the context menu and control
  centre; persisted per desktop.
- In 2D the output must be **bit-identical** to today's: screenshot-diff it
  in the functional tier.

#### Results (2026-09-16, dev box)

All four items landed. `EnvironmentRenderer` (Compositor/) draws the room
into the wallpaper's texture slot on the raster thread; `Desktop3D.swift`
carries the mode, the camera, the poses and the persistence.

- **The unfold is geometric, not a cross-fade.** Every vertex holds both
  its flat position — a quad that exactly fills the view — and its
  wrapped one, and the vertex shader mixes them by `t`. So `t = 0` IS the
  flat wallpaper rather than something that merely resembles it, and
  entering grows the room out of what was already on screen.
- **`_desktop3DT` is the one number everything reads**, tweened 600 ms
  both ways by a single controller: the window poses scale with it, the
  room unfolds with it, the parallax fades with it. That is what makes
  the end of a leave *exactly* the flat desktop instead of a
  near-identity that resamples every window for a frame.
- **The 2D contract holds, measured.** `test/functional.py`'s "3D
  desktop" check drives the toggle and screenshot-diffs it: entering
  moves the picture by ~20, leaving restores the flat desktop at a diff
  of **0.00**. Four consecutive runs.
- **Reachable four ways**: the desktop context menu, a control centre
  tile, Ctrl+Shift+3, and the broker's `desktop_3d` op (which also
  answers `query`). The choice persists like tiling — globally, not yet
  per desktop.
- Per-window depth (`WindowPose3D`) sits beside `rect`, never derived
  from it; a scroll on a title bar pushes a window back or pulls it in.
  Pointer parallax moves the eye (a translation, not a rotation — a
  rotation shifts everything equally and nothing slides against
  anything), quantised to 40 steps per axis so a still pointer means a
  still camera, and only on hover so a drag stays predictable.

**What was not right, and why no knob could fix it.** As first built the
room read almost exactly like the flat wallpaper. The diagnosis in the
tuning knobs was wrong: **a cylinder centred on the eye is depth-flat by
construction.** Every point on it is the same distance R from the viewer,
so it has no parallax and no perspective — only a slight barrel remap of
the texture, and through a 37°-wide desktop lens that is invisible. No
value of `kWrapOverscan`, `kWallLift` or `kFloorReach` changes that, and
widening the arc only pushes the curved part off the edges of the screen.

### Phase 1.5 — the room becomes a box (2026-09-16)

The wrap is now an **alcove**: the picture recedes to the far wall of a
box, and the floor, ceiling and two side walls grow out of its four edges
and come toward the viewer, carrying the picture's own colours mirrored
forward, blurred and falling into the dark. Depth reads because the
surfaces are at genuinely different distances — the near floor is a third
as far as the wall — which is the only thing that reads as depth on a
monitor.

What this settled, and is worth not re-deriving:

- **The room is defined against the frustum, not in world units**, so
  what reaches the screen does not depend on the lens or on how far away
  the wall is. That was worth knowing: the first look-dev pass concluded
  the shared 1.5-screen lens had to be shortened, and it does not. The
  windows' arc is untouched.
- **One knob decides the art direction: `kRoomCover`**, how much of the
  view the picture still fills once the room is open. 1.0 is the flat
  wallpaper; below about 0.55 the wallpaper stops being the subject of
  its own desktop. It ships at **0.66**.
- **The surfaces must meet the picture at nearly full brightness**
  (`lit` ≈ 0.9, falling off steeply with distance). A surface that meets
  it at half brightness draws a hard frame around the picture, and the
  effect stops being a room and becomes a poster hung on a dark wall.
  That one number is the difference between the two readings.
- The picture itself is never dimmed or blurred at any `t`, so the 2D
  contract is now structural rather than tuned: at t = 0 the back wall
  fills the view untouched and the other four surfaces have collapsed
  onto the quad's own edges, where they are zero-area and rasterise
  nothing. The functional check still measures it — leave restores the
  flat desktop at a diff of 0.00.
- Pointer parallax went from 2% to 3% of the screen width
  (`kEyeTravel` and `k3DEyeTravel`, which are the same eye and must move
  together). The wall shifts ~42 px across a full pointer sweep at 2560
  wide and the floor under the viewer ~68 px; that difference is what
  the cylinder could not produce at all.
- **Look-dev was done offline.** `~/tmp/room/room.py` (not in the tree)
  ray-traces the same geometry from the same wallpaper, so the art
  direction was settled by looking at pictures in seconds instead of
  rebuilding the shell. The live renderer then matched it to within a
  few percent per row, which is also how the shading was confirmed to be
  arriving — a screenshot alone is a bad judge of whether a fade is
  applied.

### Phase 2a — the windows take the room's light (2026-09-16)

Three cues, all on the window and all only while it is tilted, so the
flat desktop and the focused window's pixel-exactness are untouched:

- **Aerial haze.** A window further into the room is veiled toward the
  colour of the room behind it — 12% at the front of the arc, up to 30%
  at the back of its depth range. It is the one depth cue that works on
  a flat screen with one eye and a still head, which is why painters
  have used it for six centuries and visionOS recedes its background
  windows the same way.
- **Glass that takes the local light.** `windowGlassTint` was one colour
  for the whole desktop (the wallpaper's average, Mica's ingredient).
  For a tilted window it now leans 55% toward the part of the picture
  that window actually floats in front of.
- **A drop shadow**, in screen space, spilling outside the window onto
  the room and onto the windows below.

**The sampling point needs no world-space maths.** A window and the wall
point behind it lie on the same ray from the eye, and the picture covers
`kRoomCover` of the view — so the wall behind a window is just its
on-screen position divided by the cover, less the picture's lift. The
wallpaper is kept as a 48×30 grid of average colours when it decodes
(`_lightGrid`, a few kilobytes, built from the same pixels Mica already
uses), so a lookup is free and nothing is read back from the GPU. The
light is quantised before it reaches `_windowChildCache`, or a pointer
move would rebuild every window's subtree for a change nobody can see.

**Two things in the phase list were measured out rather than built, and
both should stay unbuilt at this geometry:**

- **A floor reflection lands off the bottom of the screen.** Mirror a
  window in the floor plane and the reflection appears at
  `(2·floorY − y)/(d·ty)` — for a window at the front of the arc that is
  −1.40 in NDC, well past the screen's edge, and it only crosses −1.0
  when the window is pushed nearly to the back wall. Windows float about
  a third of the way from the eye to the wall and sit well above the
  floor, so there is almost no floor between them and the viewer to
  reflect in. Correct, and invisible.
- **A shadow cast onto the wall behind is hidden by the window casting
  it.** The wall is further from the eye than the window, so the shadow
  projects SMALLER: 60% of the window's on-screen width at the front of
  the arc, 77% at the back. It lands entirely behind the window. Only a
  wildly oblique light would bring it out, and that draws a detached
  dark rectangle, not a shadow. This is why UI drop shadows are screen
  space, and why the one added here is too.

Both are worth revisiting only if windows ever sit ON the floor or right
against the wall, which no arrangement here does.

### Phase 2b — tier 1, and what a photograph's depth map actually holds

The pipeline is built and the bundled wallpaper's map is checked in:

- `build/tools/wallpaper-depth.py` runs Depth Anything V2 Small through
  ONNX Runtime on the CPU, about three seconds an image, and writes
  `<wallpaper>.depth.png` beside the picture — white nearest. It runs out
  of process, never in the shell, and the desktop gains no dependency: a
  wallpaper with no map beside it keeps the flat wall.
- `stage.sh` stages the maps with the pictures; the shell decodes one when
  it finds it, crops it exactly as it crops the picture, reduces it to a
  256×144 grid of floats and hands it to the renderer, which reads it on
  the CPU while building the mesh. No vertex texture fetch, no GPU
  readback, one rebuild.
- **The displacement runs along the view ray.** A wall vertex is simply
  scaled toward the eye by `1 − kRelief·depth`, so from the home eye
  position the picture is pixel-identical to a flat wall however deep the
  relief is. The shape exists only as parallax when the eye moves and as
  real distance when something must pass in front of it — which is the
  property that makes the whole thing safe to turn on.
- The relief is faded out at the top and side edges so the wall still
  meets the ceiling and side walls. **Not at the bottom**: the floor's
  back edge follows the wall's relief instead and levels off as it
  arrives at the viewer, so on a landscape the water runs into the room's
  floor with no fold at exactly the place the eye is looking.

#### And the finding, which changes what tier 2 is worth

**A monocular depth map of a landscape photograph contains a ground
plane and nothing else.** For the bundled wallpaper, 54% of the map is in
the darkest tenth and the whole structure is a ramp across the bottom
quarter — the water. Sky, bridge and headland all sit between 0.00 and
0.19, because they genuinely are at infinity: the bridge is two
kilometres away and a viewer moving their head gets no parallax off it
at all. The model is not failing; the scene is like that.

So the plan's open question — "whether a depth map from a photograph
reads as a place or as a pop-up book" — has an answer for this class of
image: **neither. It reads as a ground plane.** Measured against the
flat wall at the same eye positions, the far scene parallaxes 45 px
across a full pointer sweep and the near ground 52 px; the relief's
scale factor runs 0.585 to 1.000 across the picture.

That also settles tier 2. **Occlusion layers are not worth building for
a wallpaper like this**, and the reason is the same one: there is no
near subject to go behind. The only geometry in front of the wall is the
ground directly beneath the viewer, which on screen is a thin strip at
the picture's bottom edge — a window "occluded" by it would have a few
pixels of its lower edge clipped, which reads as a glitch, not as depth.
Tier 2 becomes interesting only for a wallpaper with a real near subject
(a portrait, an interior, a close-up), and the pipeline above is what it
would need.

Two traps paid for here:

- **A relief of all zeros is indistinguishable from no relief**, and
  both look exactly like a working flat wall. The mesh builder logs the
  range of the scale it computed (`scale 0.585-1.000`) and the wallpaper
  loader logs the map's near value and mean, because an hour went to
  measuring parallax that could not have been there — the depth map was
  not being staged at all, so the shell never found it beside the
  picture.
- **Cross-correlation lies on smooth content.** Measuring the parallax
  of the near water gave a 30 px bias against a known-shift calibration,
  because a smooth luminance ramp correlates on the ramp and not on the
  features, and because a band wide enough to include the side wall
  mixes two different depths. Calibrate the estimator on the actual
  content before believing it, and keep the band inside the picture.

Three traps paid for:

- **An eye-centred cylinder cannot show depth.** See above. If a surface
  is meant to read as far away or near, check that its distance from the
  eye actually varies across the screen before tuning anything.
- **GL's row 0 is the BOTTOM of an engine external texture.** The first
  build flipped y in the projection "so row 0 is the top" and drew the
  room upside down. The engine wraps these bottom-left up; measure,
  don't assume.
- **A varying's precision must match across stages** in GLSL ES 1.00, or
  the program fails to link with no compile error — `uniform float uT`
  in the vertex stage against `precision mediump float` in the fragment
  stage was enough. Always read the program info log; the shader logs
  are silent on this.

### Phase 3 — the room becomes a real asset (2026-09-17)

Hand-modelled boxes out, Poly Haven's CC0 library in, and the whole room
moved offline into `room-import.py`. See "How it is built". 144k
triangles, 12 MB of checked-in assets.

Assets had to be chosen against a triangle budget as much as a look:
Poly Haven's big potted plant is 176k triangles on its own and a set of
encyclopaedias is 67k. Both are lovely up close; neither survives being
seen from across a room.

### Phase 4 — lit by a real sky (2026-09-17)

One HDRI (`meadow_2`) is both the view through the windows and the
room's light. The importer reads the Radiance file directly, takes the
sun's direction and colour from the brightest region, and projects the
REST of the sky onto nine spherical harmonics for the ambient.

- **Remove the sun before projecting.** Leaving it in counts it twice;
  the symptom is an ambient several times too bright and shadows that
  have to be crushed to compensate.
- **A sky cannot light a ceiling**, which sees no sky at all. Bounce off
  the floor stays an explicit term, or the ceiling is black.
- The bake warns when the sun is not on the window side. It was not,
  first time, and the room came out with 0% of its surfaces in daylight.

### Phase 5 — the scene moves with the pointer (2026-09-17)

A monitor shows one image to a still head, so both of the depth cues a
person normally has — two eyes, and a head that moves — are gone. What
is left is MOTION parallax, and on a desktop the only thing that moves
is the pointer. So the eye now leans a few centimetres toward the
pointer and keeps looking at the far wall: `_desktop3DLeaned` in
`Shell/Desktop3D.swift`, folded into `_desktop3DEffectiveCamera`, so the
room and the windows ride the same eye and cannot disagree.

- **A translation, not a pan.** Turning the camera slides everything
  together and reads as a wobble. Translating it slides the near things
  against the far ones, which is the entire cue.
- **It costs nothing at rest.** The root Listener only records where the
  lean is heading; a ticker eases toward it (τ = 0.11 s) and STOPS when
  it arrives, because every moving frame rebuilds the window stack.
- **Frozen while a button is down**, so a window being dragged does not
  have the room swimming under it.

#### Results, measured on the dev box (eDP 2560x1600 @ scale 2)

Pointer swept from x = 200 to x = 1080 logical (69% of the screen),
which is 7.6 cm of lean. Shift of tracked features between the two
frames, by 2D template match:

| Feature | Distance | Shift |
|---|---|---|
| back wall, window frames | ~9 m | +2 px |
| left armchair | ~6 m | −4 px |
| coffee table rug | ~6 m | −7 px |
| plant on the side table | ~5 m | −19 px |
| an app window on the arc | 3.7 m | −54 to −95 px |

The wall holds still and everything nearer swings across it, more the
nearer it is. A tilted window's two ends move by different amounts
(−95 at the near edge, −66 at the far one), which is the pane turning
rather than sliding. A click with the lean active still focuses the
window under the pointer.

#### The pivot was wrong first, and the measurement is what caught it

Leaning by `s` slides a thing at distance `d` across the screen by
`focal·s/d`; turning back toward the pivot to hold the gaze slides
everything by a uniform `focal·s/pivot` the other way. So net motion
goes as `1/pivot − 1/d`, and the pivot is where the scene is nailed
down.

Pivoting on the arc (3.7 m, the obvious choice — it is where the
windows are) put every piece of furniture in the room BEYOND the pivot,
so the far wall swung 3.7× as far as the near sofa: +26 px at the wall
against +7 px at the side table. Every shift was in the same direction
and the gradient ran the wrong way, which is the exact inverse of what
leaning does and reads as the room sliding rather than the eye moving.
It looks plausible in a still frame and wrong in motion.

The pivot belongs on the far wall — `max(3, camera.z)`, since the
picture wall is at z = 0 — and then the numbers in the table above fall
out. **A parallax that is merely present is not the same as a parallax
that is correct**; the only way to tell them apart is to measure the
shift of near and far features separately and check the ORDER.

#### Still to decide

The focused window is not exempt. The crispness rule in the design says
the focused window should be drawn with its transform skipped, at 1:1;
what is implemented is that only a FULLSCREEN window stays flat, and
everything else is posed. So the window being read leans with the rest,
~54 px across a full pointer sweep — invisible while typing, because a
parked pointer means a still scene, but it does undo the pixel-exactness
that stepping up to a window buys. Damping the lean while the pointer is
over the focused window is the cheap answer if it proves annoying.

### Phase 6 — the panes get an edge (2026-09-17)

A window was a quad with no thickness, which is a decal: whatever is
behind it, it reads as stuck over the view rather than standing in the
room. It now has an edge — four strips two logical pixels wide, about
four millimetres of glass at the room's scale — and each one is lit by
the same sky as the room.

`_desktop3DSkyLight` mirrors the room's own fragment shader in Swift:
the nine spherical-harmonic coefficients, the share of the sky a room
can actually see, the bounce off the floor that no sky supplies, and
the sun. `_desktop3DPaneEdges` runs it for the four edge normals — top
and bottom straight up and down, left and right from the pane's yaw —
and hands the colours to `DesktopWindow` in `RoomLight`.

It depends on the pane's YAW and nothing else, so it survives every step
the viewer takes and only changes when a window is moved around the arc.
That matters: this feeds `_windowChildCache`.

#### Results

The room's sun is up and to the left (its baked direction is
−0.35, +0.45, −0.82), so a pane facing down the hall should be bright
along its top and left and dark along its bottom and right. Predicted
from the baked sky, then measured off the screen:

| Edge | Predicted | Measured |
|---|---|---|
| top | 216 | 206 |
| left | 201 | 191 |
| bottom | 79 | 81 |
| right | 53 | 59 |

The two lit edges come back a little under prediction because the haze
veils them, which is what it is for. Turning the camera 21° left the
lit edge at 179 — a diffuse edge belongs to the pane and the room's
light, not to where the viewer is standing, and it behaves that way.

#### The edge needs an albedo, and it is not optional

Treating the edge as a perfect reflector — returning all the light that
falls on it — drove the two lit sides clean past white, because the
baked sun colour runs to 9.9 and nothing was absorbing any of it. The
pane came out with a hard graphic border on two sides, which is worse
than no edge at all: a border is a 2D decoration and the whole point was
to stop the pane reading as 2D. At 0.55, which is about anodised metal,
the four sides land at 0.85, 0.79, 0.31 and 0.21 and it reads as a
bevel. The room's own surfaces never hit this because their albedo comes
out of a texture and their sunlight is multiplied by a traced visibility.

#### Not yet measured

The left and right edges depend on the pane's yaw, and that is derived
rather than confirmed: every window in the test scene faces down the
hall, because nothing in the shell can yet move a window around the arc.
The grab is what would let it be measured.

### Phase 7 — the room rendered by Filament (2026-09-17)

A spike, on the question "would a real renderer make this easier": the
same room, in the same wallpaper slot, from the same camera, drawn by
[Filament](https://github.com/google/filament) instead of the
hand-written GL and the offline bake. It works, on the desktop, and the
comparison is `~/tmp/filament/desk-filament2.png` against `desk-gl.png`.

**What it is.** Filament is a rendering library, not a game engine: it
does not own the process, the window or the input. It is created on the
engine's own EGL display with a context that SHARES the engine's, runs on
its own thread, and draws straight into the texture the registry made
for the wallpaper slot. `sr_room_render` waits for the GPU, so the
engine samples a finished picture on the same frame. Nothing about the
windows, the input or the chrome changed: they are still widgets under a
`Transform`, exactly as before.

```
  build/tools/room-glb.py      the room as ordinary glTF: the generated shell,
                               the CC0 furniture with its own textures, NO
                               baked light; plus the sky as two .hdr for cmgen
  cmgen (Filament's tool)      -> room_ibl.ktx (the light), room_skybox.ktx (the view)
  shell/Sources/StarlingRoom/  starling_room.{h,cpp}: a C surface over Filament
  build/build-room.sh          -> libstarling_room.so (+ roomtest, a stand-alone check)
  build/build-filament.sh      Filament itself, built the one way that can share
                               the engine's context
  Compositor/FilamentRoom.swift  EnvironmentRenderer subclass: dlopens the shim
                               and stands in the slot when STARLING_ROOM=filament
```

The shell finds the library beside its own binary (`stage.sh` copies it
from the scratch when it has been built) and the room's files in
`STARLING_ROOM_DIR`. Without either, the slot falls back to the GL room.

**What Filament gave for free that the bake did by hand**: shadow maps
(the chairs cast onto the floor, the window frames cut the sun patches
sharply — the bake's per-vertex daylight was a staircase), specular from
the sky on the chairs' varnish, ambient occlusion, bloom, tone mapping,
MSAA. The room reads brighter and more neutral than the GL one, which
the note above had already called brown and dim.

**Cost, measured** (2560x1600, dev box):

| | |
|---|---|
| engine up, context shared | 42 ms |
| room loaded (12 renderables, 11.5 MB glTF) | 84–115 ms |
| first frame (shader compile) | 70–190 ms |
| frame, every effect on | 8–13 ms |
| frame, `STARLING_ROOM_FX=lean` (no MSAA/AO/bloom) | 3.6 ms |
| library | 4.6 MB, plus `libc++1` at runtime |

A frame is only rendered when the camera moves; the scene clock is
ignored (`tick` is a no-op) because this room is still.

**Traps paid for, all silent:**

- **The prebuilt Linux release cannot be used.** Its OpenGL backend is
  GLX-only and desktop-GL-only; a context that shares the engine's
  textures must be an EGL context on the engine's GBM display. Build
  from source with `FILAMENT_SUPPORTS_EGL_ON_LINUX`, which is the GLES
  flavour of the backend over EGL — the engine's own API.
- **`FILAMENT_USE_EXTERNAL_GLES3` is not what its name says.** It
  EXCLUDES the OpenGL backend from the build. The libraries build, the
  shim's link fails on every `OpenGLDriver` symbol, and an hour goes to
  wondering why the backend archive has three object files in it.
- **Materials must be compiled for the MOBILE shader model** in that
  configuration, and the tree only does so when it thinks the target is
  a phone. `build-filament.sh` patches `MATC_TARGET`; without it every
  material fails to load at runtime.
- **A GBM display has no pbuffers.** Filament's headless swap chain logs
  `eglChooseConfig() didn't find any matching config` once and carries
  on with `EGL_NO_SURFACE` (Mesa supports surfaceless contexts); the
  frame goes into our render target, never to that surface. The line is
  noise, not a failure.
- **Filament is built `-fno-rtti`.** A class derived from one of its
  platforms in a translation unit WITH rtti needs typeinfo Filament
  never emitted (`undefined reference to typeinfo for PlatformEGLHeadless`).
  The shim compiles `-fno-rtti -fno-exceptions` to match.
- **`-fvisibility=hidden` hides the C API too.** The exported functions
  carry an explicit default-visibility attribute.
- **Mesa shares between GL and GLES contexts** (an ES 2 context and a GL
  4.6 core context on the same GBM display see each other's textures —
  measured, `~/tmp/filament/sharetest.c`), so the desktop-GL build would
  also have worked. The GLES build was kept because it is the engine's
  API and needs no bluegl.
- **cmgen's equirectangular convention is the mirror of `room_hdri`'s**
  (`(sin φ, ·, +cos φ)` against `(sin φ, ·, −cos φ)`). The exporter
  mirrors the columns and turns them half a circle before cmgen, so the
  sun found by `find_sun` is the sun the skybox shows. Do not add a
  second convention anywhere.
- **The light is not the whole sky.** Filament lights every surface from
  the full sphere, so the ceiling came out meadow-green and the walls
  sky-blue. The exporter paints the ground half of the LIGHT (not the
  view) with the floor's colour times what falls on it — the note's
  "a sky cannot light a ceiling; bounce off the floor stays an explicit
  term", one more time.
- **Filament writes the texture the way raw GL does** — clip y = −1 in
  row 0, which the engine shows at the bottom. `roomtest` first wrote
  its PPM bottom row first, the picture looked upside down, a y-flip was
  added, and the DESKTOP then showed the room upside down. Measure on the
  desktop; the tool now writes rows last-to-first so an upright PPM is an
  upright room.
- **The dev shell's broker socket is root-only** (`/tmp/xdg-starling-0`,
  mode 0700). An unprivileged driver silently finds the packaged
  session's STALE socket instead and gets `Connection refused`; run the
  broker call through `sudo`. And do not run `run-desktop.sh` itself
  from a root process: nested `sudo` makes `SUDO_USER` root and the
  stage step exits 2 with no output.

**Not done, in the order it would go:**

- The shell's surfaces are flat colours (floor, walls, ceiling, joinery);
  the GL room's procedural boards and plaster are gone. Poly Haven has
  CC0 textures for both; the glTF takes them like any other material.
- Exposure and light strengths are first guesses (`STARLING_ROOM_SUN_LUX`,
  `_IBL_LUX`, `_EXPOSURE` tune them live). The floor reads pale.
- The unfold is gone: this renderer ignores `t`, so entering pops from
  the wallpaper to the room at the home camera. The 2D contract holds
  (t = 0 still shows the plain wallpaper), but the 600 ms morph needs a
  camera path instead of the old vertex mix.
- The sky through the windows is a 512-per-face cubemap from the 1k
  HDRI; `room-fetch.py` can take the 4k one.
- Windows are still not in Filament's scene. That is the next question
  the plan asks, and it costs what the "3D composite" discussion said:
  input and chrome. Filament makes the drawing half of it a textured
  quad — `Texture::Builder::import` takes the client texture's GL name.
- Packaging: `libc++1` becomes a runtime dependency of the .deb, and
  `build-filament.sh` a one-off on the build box (docs/BUILDING.md).

### Phase 8 — the windows hang in the scene (2026-09-17)

With Filament drawing the room, the windows go INTO it: each one is a
pane in Filament's scene, hung flat on a side wall in a dark wood slab,
its client texture on an unlit quad. The widget the layer tree had for
that window stays exactly where it was, at exactly the same pose — it
just stops painting its content. That is the whole trick: the room draws
the picture (lit, framed, occluded, shadowed), the widget takes the
pointer, and because both are built from the same camera and the same
pose they coincide to the pixel. No new input code; the title bar is
still the shell's, drawn over the pane.

Verified on the desktop (`~/tmp/filament/panes5/`, `input1/`):

- Two windows hang on the side walls, title bars sitting on them.
- Space steps up to the pane ahead and the window is 1:1, crisp, its
  chrome aligned with the frame.
- A click on the Terminal pane from across the room focuses it, typed
  commands run, and the pane on the wall shows the output as it prints —
  the client's frames reach the scene live.

```
  shell/Sources/StarlingRoom/materials/   screen.mat (unlit, the client's picture)
                                          frame.mat (lit, the slab)
  sr_room_set_pane / sr_room_remove_pane  a pane per window, by texture id
  LinuxTextureRegistry.sceneTexture       the client texture, imported the way
                                          the engine's own callback imports it
  LinuxTextureRegistry.setSceneMirror     a client frame -> a room frame
  FilamentRoomRenderer.setPanes           the pane list, synced each frame
  Desktop3D._desktop3DPublishPanes        poses -> panes, before the widgets
  DesktopWindow(sceneContent:)            content area transparent, frost only
                                          under the title bar
```

**The layout**: side walls only, alternately left and right from the far
end toward the viewer, centre 1.6 m up, 2.7 m apart. From the door only
the far slots are in view — a wall is a wall — and Space or a turn
brings the rest round.

**Two bugs this uncovered that predate Filament, both invisible while
every pane faced straight down the hall:**

- **`Desktop3D._view` mirrored yaw and pitch** against the room
  renderer, the walking code and the step-up. The widgets and the room
  turned opposite ways; the first pane on a side wall vanished behind
  the near plane while the room showed it dead ahead. The SDK's
  `rotationY(θ)` maps +z to (sin θ, 0, cos θ), so a camera that looks
  along (sin yaw, 0, −cos yaw) needs `rotationY(+yaw)` — not the −yaw
  that "undo the heading" suggests. Checked numerically against
  `EnvironmentRenderer.view`.
- **Step-up turned the camera to face the pane's normal, not the
  pane.** The camera yaw is the pane's yaw NEGATED; for yaw 0 the two are
  the same number, which is why it worked.

**Traps paid for:**

- **An unlit material skips exposure.** Lights are pre-scaled by the
  camera's exposure; an unlit colour goes straight to the tone mapper.
  A screen "intensity" of 25 000 (the IBL's units) made every pane
  pure white with a coloured halo; 0.6 is a bright screen.
- **Filament's default `flipUV` puts texture row 0 at the TOP**, the
  opposite of the engine's external textures — so a buffer the widget
  flips (Wayland), the pane does not, and vice versa.
- **The widget's frosted-glass backdrop covers the pane.** With the
  content transparent, the window's own frost layer still filled the
  whole rect and showed a blurred room where the client should be. For
  a scene pane it now sits under the title bar only.
- **The engine only imports a client's buffer when it composites it.**
  A pane the engine no longer draws would keep its first frame forever;
  the registry now imports on the renderer's behalf and turns a client
  frame into a room frame (`setSceneMirror`).
- **Filament's shadow map is coarse on a wall**: the slab's shadow has a
  staircase edge. Cascades or a larger map are a setting away.
- Testing: the dev shell's broker socket is root-only; `key space` with
  a window focused goes to the window (click the floor first); a click
  meant for the floor lands on a 1:1 pane that fills the screen.

**Moving a pane (later the same day).** A title-bar drag slides the pane
along its wall, and a scroll on the title bar slides it in steps. The
drag is exact at any angle: where the pointer was and where it is are
both put through the pane's plane (`_desktop3DPlaneHit`, a ray from the
eye through the screen point, intersected with the plane), and the pane
moves by the difference in the plane's own axes. Measured: 300 px of
drag at the 1:1 spot became 0.58 m on the wall, sixteen events of
−0.036 m, exactly what the geometry predicts. The clamp is the room box
less half the pane, so it only bites along the axis the pane moves on.

Testing this found one more thing: **the pointer lean moves the target
as you reach for it.** Moving the pointer from the bottom of the screen
to a title bar near the top leans the eye up and shifts the pane about
45 px down, so a scripted press at the bar's old position lands on the
wall above it. The test reads the bar's live position from the placement
log; a person's hand corrects for it without noticing, which is the
lean working as designed, but the note above about damping the lean
over the focused window stands.

**The look (same day):** the floor is Poly Haven's `wood_floor` and the
walls and ceiling `white_plaster_02`, tiled by dividing the shell's
metre-valued texture coordinates (`room-fetch.py` downloads them,
`room-glb.py` assigns them). "White" plaster photographs mid-grey (sRGB
142, linear 0.27) with an occlusion map that takes another third off, so
the exporter brightens it 1.7× in linear light and halves the occlusion;
it still reads as concrete more than paint. The sun's shadow map now
covers 25 m in three cascades at 2048 instead of the camera's 4 km far
plane at 1024, which is what turned every shadow edge into a staircase.

**Entering and leaving (same day).** The GL room unfolds out of the
wallpaper geometrically; the Filament room has no picture wall to unfold
from, so it comes up THROUGH the wallpaper: through the 600 ms tween the
slot shows the flat wallpaper with the room over it at opacity `t`,
while the windows lift off the desktop to their walls exactly as before.
The widgets keep painting their content until t = 1 and only then hand
the picture to the pane beneath — so nothing dips — and the reverse on
the way out. The functional check's contract holds: t = 0 is the plain
wallpaper. Recorded with `shell-drive record-start/stop` and read as a
contact sheet (`ffmpeg … tile=5x3`), since a screenshot cannot catch a
600 ms fade.

**The first entry put every window on the arc.** `_setDesktop3D` laid
the windows out before it created the room renderer, and the layout
picks the arc or the walls by which renderer exists — on a session's
first entry there was none, so every window went to the arc, placed for
good. Earlier runs had the renderer alive from a previous toggle and
never showed it. The renderer is created first now.

**Occlusion, on show.** The big floor plant stands in front of the right
wall's first slot (`PLACEMENT_OVERRIDES` in the exporter — the bake keeps
its arrangement), scaled so its top is above eye level: from the door a
plant shorter than the viewer projects BELOW the pane's bottom edge and
overlaps nothing. The Terminal pane's lower half is behind the leaves,
which the layer tree could never have drawn.

**Still to do:** the 1:1 step-up distance is derived from the LOGICAL
width (1.74 m), which the arc layout shares; the pane's rounded corners
vs the slab's square ones; per-frame cost while a video plays in a pane
(every client frame is a room frame, 4–13 ms); a lighter wall texture
(`beige_wall_001` is the most-downloaded painted wall).

### Phase 9 — worlds, and the first one that is not a room: the orrery (2026-09-17)

The room is one world. A world is a directory: a sky baked by cmgen, an
optional glTF, and a `world.json` that says what kind it is and where its
hub is. `STARLING_ROOM_DIR` picks it; the renderer reads the kind and the
shell lays the desktop out to suit. The **orrery** is the first world
with no geometry of its own: open apps are planets round a sun, each
app's windows are moons round its planet, and there is no dock and no
status bar — only the sky.

```
  build/tools/orrery-world.py     a procedural star field (.hdr) -> cmgen -> the
                                  two cubemaps, plus world.json
  world.json                      kind, exposure, ibl_intensity, point_light,
                                  hub, sun/planet/moon radii, camera_home
  sr_room_set_orb / _label /      spheres (lit, or glowing for the sun), billboard
  _point_light                    labels that turn to the viewer, a light at the hub
  Desktop3D._desktop3DLayoutOrrery   the layout, recomputed every build
  Desktop3D._desktop3DAppLabelTexture  the app's tile and name, drawn once into a
                                  texture by the shell (IconPainter + a paragraph)
```

- **Planets** sit on a ring tilted 20° toward the viewer, like an orrery
  on a stand, so that from eye level it reads as an ellipse and not a
  line of beads. The tilt is on the ring, not the camera: the home camera
  must look level, because the flat pose that makes t = 0 the exact
  desktop assumes a level camera looking down −z.
- **Moons** are the windows' own panes at `moon_scale` (0.12), facing out
  from their planet, showing their live content in miniature. The one
  with the focus is drawn at full size and turned to the viewer; a click
  on a moon, or Space, steps the viewer up to it at 1:1 and it grows.
  Clicking the sky lets it shrink back onto its orbit.
- **Labels** are the app's dock tile and name, drawn by the shell into a
  256×300 texture (premultiplied; the material un-premultiplies, since
  Filament blends straight colour) and hung on a quad that wears the
  viewer's rotation every frame.
- **Moving**: Q/E/A/D orbit the sun, W/S move in and out, R/F rise and
  sink, Home returns. Drag on a pane does nothing here; a moon keeps its
  orbit.
- **Light**: a point light at the hub (candela) and a night exposure
  (f/2, 1/30, ISO 1600). Planets show phases. The sun is an unlit sphere
  above 1.0 so the bloom haloes it.

**Bugs this found, both older than the orrery:**

- **A session that starts with 3D already on could not leave.** The
  tween's controller is created lazily on the first animated toggle, at
  value 0, while t is already 1 — and a reverse from 0 is a no-op. The
  scene stayed up with `_desktop3DOn` false. In the room this passed for
  "the leave is instant"; with the orrery's chrome hidden it meant no
  dock ever came back and no app could be launched. The controller now
  starts at the current t.
- cmgen names its outputs after the DEPLOY directory, not the input
  file (`ibl/ibl_ibl.ktx`), which the world generator learned the hard way.

**Measured**: 8–10 ms a frame at 2560x1600 with three planets, their
moons and labels; the room's cost, since the sky and the panes dominate.

**Still to do:** an entering animation that suits space (the fade is
fine, a dolly in would be better); a label that does not sit over the
sun for the nearest planet; the moons' backs read as wood slabs — a
thinner frame or content on both faces; drag a moon to another planet
to move a window between apps' groups is meaningless, but drag to
reorder planets is not; the plaza next.

### Phase 10 — the voxel city (2026-09-17)

The orrery did not look good, and the next ask was a Minecraft-style
scene. A blocky world turns out to be the EASIEST kind to make look
right here: the geometry is cubes a script can lay out, the textures are
16×16 pixel art the same script draws, and Filament's sun and shadow
maps on flat faces are exactly what "Minecraft with shaders" means.

`build/tools/voxel-world.py` makes the whole world in ten seconds: a
street grid (asphalt with lane lines, pavements), concrete and brick
buildings with windows lit here and there and parapeted roofs, taller
toward the middle, and a square with a low pool, a lamp, and four trees.
Every visible block face is a quad with a tile from a 4×4 atlas sampled
NEAREST (the glTF sampler says so; pixels stay pixels). One material,
25k triangles, 1.9 MB. The sky is a gradient with a SQUARE sun, made in
cmgen's own equirect convention; the world's `sun` in world.json drives
the directional light so the sky's sun and the shadows agree.

The shell side is the third `World3D.Kind`, `voxel`: a walking world.
The camera rides the ground (`heightmap` in world.json: the surface y
per column, `World3D.ground(x, z)`) at `eye_height` 1.62, and the world
has edges instead of walls. The windows stand on an arc round the far
side of the square, facing in, one dead ahead and the rest fanned to
either side up to 200°, so a viewer coming in from the door sees every
window front-on over the pool and walks up to whichever they want; the
app's nameplate (the same shell-drawn label as the orrery, a metre wide
here) floats over each group. No dock and no status bar, as in the
orrery. Space and click step up as everywhere else.

**Measured**: 10–12 ms a frame at 2560x1600, the same as the room.

**Notes for the next world:**

- Nothing tall in the middle of the square: the first fountain had a
  three-block pillar and it hid the middle window from the door.
- A tree at the start spot fills the view with its trunk. Trees go in
  the corners.
- The walking clamp is the world's own size (`heightmap.size`), not
  `Room3D`'s constants — the room's numbers are the ROOM's.
- The trap from the orrery holds here too: the tilt or any slant belongs
  on the layout, never on the home camera.

### Phase 11 — the city gets doors, signs and its own frames (2026-09-17)

Two of the checkpoint's "next" items, both done in the generator's
ten-second loop plus one pane-style call.

**The city.** 96 blocks across (was 60), 75k triangles, still 10–12 ms
a frame. Eight building styles — concrete, brick, four plaster colours,
sandstone, glass curtain wall — each with its own window tile and
rhythm, and a third of the inner lots are towers with a setback and an
aerial. Every building has a door on the wall that faces the square,
two blocks tall, under a striped awning that sticks out over the
pavement, with a three-block sign above it whose "lettering" is random
runs of dark pixels — it reads as a sign from across the street and as
nothing up close, which is right. Half the buildings have a shopfront
ground floor (big glass, something warm lit inside). Roofs get a water
tank on legs or an air handler. Streets have crosswalks at the corners
and lane lines; a lamp post stands at every corner and a street tree on
one lot in seven. Trees were first on a third of the lots and it read
as a forest of trunks: what makes it a *city* is that the trunks are
few and thin.

**Not everything is a block.** Lamp posts as blocks were 1 m pillars
with a glowing cube on top and read as monuments. The generator now
also emits *props* — thin axis-aligned boxes (a 20 cm log post with a
50 cm lamp, a 16 cm mast with a crossbar) — into the same mesh, with
the tile stretched over each face. Same material, same pixels, and the
scene stops looking like it was built at one grid size.

**The sun moved.** It stood ahead of the viewer, so the facades across
the square and every window's front were back-lit, and the frames came
out near-black. Three candidates rendered headlessly in one tile: from
behind-right and high (`0.55, 0.75, 0.45`) lights the facades, the
plaza and the panes at once; side-on put the square in the shadow of
the buildings beside it; ahead-left back-lit the facades again. The
sky's square sun follows it, so the shadows still agree with the sky.

**Block frames.** `frame.mat` takes a tile texture and lays it over the
slab from the slab's *own* axes — the box has no UVs, its scale is in
the model matrix, so the vertex shader scales the unit-cube position by
the matrix's column lengths and picks the two axes each face lies in
from the object-space normal. One tile per `block` metres, sampled
NEAREST and REPEAT, so a wider window is more planks rather than
stretched ones. `sr_room_set_pane_style` sets the texture and the
margin/depth for every pane, present and future (a generation counter
on the room; each pane refreshes its material instance on its next
update). The shell reads `pane_frame` from world.json, decodes the
tile through the engine's codec into a registry texture (the label
path), and the renderer applies it on the raster thread the first
frame the texture resolves. `roomtest` takes `ROOMTEST_FRAME=tile.ppm`
and `ROOMTEST_PANE_AT=x,y,z,yaw` so the frame can be looked at without
the desktop. Focus is a brightness on the tile (1.0 / 0.72) instead of
a colour.

**Measured**: the city loads in 30–50 ms; frames 8–13 ms at 2560x1600
with three panes; the generator runs in 10 s (55 s of CPU — the mesh
is one pass of array arithmetic per face direction, not a loop over
cells).

**Traps:**

- An unset sampler parameter is a warning every frame (`[1] frameMap`)
  even when the shader never samples it; the shim binds a 1x1 white
  stand-in until a real tile arrives.
- `roomtest`'s pane test hangs the pane at the ROOM's coordinates; in
  the city that is inside the stone under the street. Hence
  `ROOMTEST_PANE_AT`.
- A `for … && break` loop in the shell breaks on the *pipe's* exit
  status — `tail` — not the renderer's, which is how the AMD render
  node "never ran". `/dev/dri` renumbered again today: the AMD node is
  `renderD128` and the NVIDIA device is gone from the list.

### Phase 12 — the entrance is a dolly (2026-09-17)

The fade was a cross-dissolve between two stills. Now the camera moves:
a world can ask for a dolly (`camera_home.dolly`, metres), and entering
starts that far behind the home spot and glides up to it over the tween
— 1 s for a dolly world, the room's 600 ms otherwise. Three things had
to move together for t = 0 to stay the exact 2D desktop:

- **The flat pose follows the camera.** It was "the plane in front of the
  HOME camera at one pixel per pixel"; it is now the plane in front of
  the *tween's* camera at t, so while the viewer is still six metres
  back the flat windows ride along in front of them, pixel-exact.
- **The camera the tween describes** runs from the dolly start to
  wherever the viewer is standing (the home spot on entry; on leave,
  wherever they walked to — so leaving still walks them back). The lean
  is applied on top, scaled by t as before.
- **The windows move on t².** With everything on t the windows shrank
  away in the first 150 ms, before the world was visible enough to
  receive them. On t² they stay on the desktop while the world comes up
  (the wallpaper's opacity ramp is 1.6·t, so the world is fully there by
  60%) and the glide begins, and fly to their places in the square as
  the viewer arrives — they get their block frames mid-flight. Leaving,
  the same curve brings them home first, while the world is still
  there under them.

Verified with `shell-drive record-start/stop` and an ffmpeg tile of
every frame of the moving second (`~/tmp/filament/city-enter.py`,
`enter2/`): 1023 ms measured from the frame differences, the staging
as described. The GL room and the Filament room are unchanged (dolly 0).

### Phase 13 — the window wears the world's chrome (2026-09-18)

The pane's frame was the world's planks, but the title bar on it was
still macOS glass with round traffic lights: two looks on one object.
Now a window standing in a block world (from the moment it arrives, and
one filling the screen there) gets `BlockyTitleBar`: the world's frame
tile laid two screen pixels to a texel, the title in white over a hard
one-texel shadow, and three block buttons — redstone, gold, emerald —
with a two-texel outline, a bevel that flips when pressed, and a white
glyph on hover. Square corners, no glass border, no frost. It is the
WORLD that asks for this look (`DesktopWindow.decoration`), the way the
world already supplies the frame — not a style, and not an `if style ==`
anywhere. The decoded tile is kept (`_worldFrameTile`) once the shell has
decoded it for the renderer.

In 3D a fullscreen window's revealed title bar is the window's alone:
the status bar is the desk's, and the viewer is not at their desk. (On
the flat desktop the revealed bar now sits BELOW the status bar — it was
drawn under it, lights and all, and there was no way out of fullscreen
with the mouse. Found by playing.)

**Also found by playing, and fixed:** a click on a window across the
square walked nowhere (wired for the orrery only); the walk-up was a cut
(now a 380 ms glide, Space too) and the click that asked for it went
through to the app (selected a folder on arrival — swallowed now).

**Trap, for the test harness:** every `shell-drive` invocation glides
the pointer from the SCREEN CENTRE to its first target, and that sweep
crosses the fullscreen reveal's hide zone — the revealed title bar was
"dead to clicks" for an hour because the click was in a second
invocation. Reveal and click in ONE invocation, or start each with a
move to the top edge. A real mouse never does this.

### Phase 14 — the app tower (2026-09-18)

"We should have a place to open apps, similar to the dock. In the
centre of the city?" — and then, "stack those icons like a building".
So: a sandstone tower, 3 blocks square and 8 tall, rises out of the
pool in the middle of the square, and the dock's apps hang on its
front face as signs, two columns, floor by floor from the pool up (the
dock's first apps lowest, nearest eye level; three columns past
fourteen). A sign is the app's tile and name — the nameplate texture —
and a click on it opens the app, which takes its place on the arc.
Hovering one grows it a fifth. The Launchpad has no sign: the square is
the launcher.

Three things had to give:

- **Labels could only face the viewer.** `sr_room_set_label` takes a
  `yaw` now (NaN = billboard); a sign on a wall keeps its facing, so
  from the side it is a sign on a wall and not a card that swivels
  through the stone. Hit-testing is the pane's ray-plane test for
  those, the projected-box test for billboards.
- **A label's id was its texture id**, and the signs share the
  nameplates' textures. `SceneLabel` carries `texture` separately; the
  signs' ids are offset by a million.
- **Nothing may stand straight behind the tower from the door.** The
  windows' arc no longer puts one dead ahead: the first flanks the
  tower at 32°, the next at −32°, then ±62°, and on round.

The world's `tower` in world.json (centre, half-width, base, top) is
what the shell hangs the signs on; a world without one gets the signs
in a row on the near side of its hub (rows of six, stacked like seats).
An arc of signs round the pool was tried first and rejected: from the
entrance the ends turn away and stack up.

The pointer reaches the world through a Listener round the
environment's texture — the wallpaper slot — in the city only; a click
that hits no sign still does what it did (drops the window's focus).

### Phase 15 — the sculpture (2026-09-18)

The tower "doesn't look good": signs on a wall are stickers, not a
thing. "Stack the icons like a statue or a sculpture." So the apps are
BLOCKS now — a new primitive, `sr_room_set_block`: a lit cube wearing a
shell-drawn face (the app's colour to the edges, its glyph in white) on
every side, shadowed and sky-lit like any block in the city — and they
stand in a rising spiral round a slim post in the pool: the first app
in front at the water, each next one a 45° turn round and 45 cm up,
each turned to face outward. From the entrance it is one twisting
column of colour; walk round it and every block comes to the front.
Hover one and it grows a sixth and wears its nameplate; click and the
app opens on the arc. The windows still flank the middle. The
generator's tower became a one-block sandstone post with a lamp, and
world.json carries `sculpture` (axis, radius, base) instead.

The block material is lit (`block.mat`, TANGENTS + UV0 on a 24-vertex
cube), not the label's unlit blend: an opaque cube in the transparent
pass draws its back faces through its front. Radius 2 m and a 45 cm
rise after 1.5 m / 55 cm put the top blocks out of the frame from the
entrance. The two blocks behind the post are hidden from the door —
that is what walking round is for. Signs (the row, the tower) remain
for a world without a sculpture.

### Phase 16 — the stack (2026-09-18)

The spiral of floating blocks was not it either: "stack the icons
together vertically, like Lego, but not straight vertical." So the
blocks are a STACK now — each rests on the one below, set 22 cm off it
in a direction that turns forty degrees a level and twisted fifteen —
a column of bricks put down by hand, curling as it rises, standing in
the pool with no post. 68 cm bricks, the bottom one a hand's depth in
the water, so eight of them fit the frame from the entrance (the eye's
view reaches 11.2 m at the home spot; the top brick tops out at 11.2).
The hovered brick grows an eighth and its nameplate hangs in FRONT of
it, toward the viewer — above it would be inside the next brick. The
world's `sculpture.radius` is the per-level offset now.

### Phase 17 — the building (2026-09-18)

"Too high. Stack them as a building." So the bricks are laid in
COURSES now, running bond, one brick deep, facing the entrance: a
course of k, one of k − 1 resting in its gaps, k again — with eight
apps, 3/2/3 — k the smallest that keeps it about as wide as tall.
90 cm bricks on the water, so it stands 2.7 m: a small block building
in the pool, the dock's first apps along the bottom. The brick under
the pointer comes 14 cm out of the wall, and its nameplate stands over
the roof above its column — over the brick would be inside the next
course, in front of it would hide its face. The offset walk and the
twist of the stack are gone; the running bond is what makes it not a
straight pile.

### Phase 18 — the bricks move (2026-09-18)

"Are those icons movable?" Now they are, the way the flat dock's are:
press a brick, move past eight pixels and it leaves the wall and rides
the pointer (where the pointer's ray meets a plane 40 cm in front of
the wall); the brick it is over comes forward and its name stands over
the roof; release and the two swap places in the dock's order — which
the building is laid out from, so the flat dock follows. A press that
never moves is still a click. A running app that is not pinned takes a
place in the order by being moved, as "Keep in Dock" gives it one.

**Harness trap (the second of the day):** `shell-drive down` in its own
invocation is a CLICK — the process exits, the virtual mouse goes with
it, and the kernel releases the button. A drag is `down`, the `move`s
and `up` in ONE invocation. The first run "didn't drag" and opened the
app instead, and the log said exactly that.

### Phase 19 — the bricks have weight (2026-09-18)

"If icons are moved at the bottom, the whole stack may collapse — need
to simulate that." So the bricks are bodies now, and the drag no
longer swaps: pull a brick out and it is gone from under whatever it
held; drop it and it falls from where you let go onto whatever is
under it. The physics is a small, honest one in the wall's plane
(`_desktop3DBrickStep`, on a ticker like the lean's): a resting brick
stands on the water or on the resting bricks directly under it; with
nothing under it, it falls; with its centre past the edge of what
holds it (the hull of its supports, 2 cm margin), it TIPS — a quarter
turn about that edge at 4.5 rad/s, drawn as a roll (`sr_room_set_block`
gained `roll`), after which it is a square again and falls from there.
A falling brick lands on the first resting top under it, slides off a
brick it is beside unless it is mostly over it, and stops at the
water; bricks stay within 2.2 m of the pool's middle. Everything
cascades: pull the bottom-left brick and the one on it tips off,
the one on that topples, and a brick balanced on the far side goes
too. A new app drops in from above the pile.

The initial building had to change for this: running bond's end
bricks sit exactly half on their support, which is neutral
equilibrium and tips at once under any honest rule. Courses of k now,
each course a quarter brick over from the one below, so every brick
rests three quarters on the one beneath and the end bricks overhang a
quarter — and pulling any bottom brick leaves the one above with a
quarter, which tips.

**Harness trap (the third):** a drag is `down`, `move`s and `up` in
ONE shell-drive invocation; and record the collapse as video — stills
half a second apart miss the whole tumble.

### Phase 20 — the door and the power (2026-09-18)

"Add an exit button to exit 3D to 2D, and power off." Two blocks on
the pool's front rim, right of the way in, the same primitive as the
app bricks with faces the shell draws: a door with an arrow leaving it,
and the power ring in red. Hover names them ("Back to the desktop",
"Shut down"); the door is `_setDesktop3D(false)` — the dolly out — and
the power puts up "Shut down the computer?" over a scrim in the middle
of the screen (the chromeless world has no status bar to hang the
usual panel from; a press on the scrim is a no; Shut Down runs the
same `systemctl poweroff` the status bar's panel does).

**The world's pointer handling moved to the root Listener.** It had
lived on the wallpaper slot, which is UNDER the windows: the exit
block stood in front of the Files pane on screen, and a press on it
walked up to Files instead, because the window's widget is what the
stack hit-tests first. Now the root sees every press, move and hover,
and a world thing is "there" for the pointer only when no pane is
nearer (`_desktop3DSignAtVisible`: the pane under the pointer via the
ray-plane test, its depth against the thing's). A window's walk-up
yields to a nearer brick or control the same way.

### Phase 21 — the signboard (2026-09-18)

"The dialog should be in 3D model style." The flat confirm is gone;
pressing the power block raises a SIGNBOARD 2.4 m in front of the
viewer, facing them: a plank panel (the world's frame tile, a dark
edge, the title and the question in the world's lettering — a label
with a fixed yaw) with two block buttons under it, Cancel in stone
grey and Shut Down in red, their words on their faces. They are
controls like the door and the power: hover brings one forward, a
press answers; a press anywhere else is a no. Placed once, where the
viewer stood when they pressed; walk round it and it is a board on
the square.

(A word on a block's top already read from the front; a screenshot
misread as upside-down cost two rebuilds "fixing" it. Crop and zoom
before believing a small render.)

### Phase 22 — just the door (2026-09-18)

"Maybe shouldn't add power off in the 3D model. Just exit." The power
block and its signboard are gone; one door block stands on the pool's
front rim, right of the way in, and is the way back to the flat
desktop. Shutting the machine down is the desk's business, where the
status bar's power menu still is. (The signboard machinery — a
fixed-yaw plank panel with block buttons under it — lived for one
commit, 5e883a8, if a world ever needs to ask a question.)

### Phase 23 — Escape (2026-09-18)

The first person to be left standing in front of a window with the
door behind them could not get out: "hold Alt and press Home" is a
three-key chord on a laptop whose Home is Fn+Left, and their press
never reached the shell as Home at all. So: **Escape** leaves the room
while nothing has the keyboard, and **Alt+Escape** leaves it at any
time. The door block stays for the mouse.

### Phase 24 — anywhere in the city (2026-09-18)

"We should allow moving the icon box to anywhere in the city." The
bricks leave the wall's plane: bodies in x, y and z over the whole
square. A carried brick rides the ground the pointer points at, a
little above it — plaza, street, the pool's water (a step higher) —
kept inside the world; let go, it falls and settles there, or on
whatever brick it is over. The physics generalises: supports are
rectangles in x and z, a brick tips along whichever axis its centre is
past the edge of (a tip along z is drawn as yaw 90° and a roll), and a
falling brick slides off a brick it is beside along the shorter way
out. The nameplate stands over the hovered brick's own column, and the
hovered brick comes toward the viewer rather than toward +z. The 2.2 m
reach is gone.

Buildings are not solid to bricks: one dropped over a shop lands on
the plaza level inside it. The heightmap is level and nothing in it is
a wall — the same thing that lets the viewer walk through walls.

### Phase 25 — the title bar goes into the scene (2026-09-18)

"On the media player icon I can see a brick strip; sometimes brick and
icon box are mixed." The strip was the Files window's plank title bar:
the window's picture is drawn by the renderer, where a brick in front
covers it, but the bar was still the WIDGET's, composited over the
whole scene with no depth — so a window behind the pile showed its bar
through the bricks. Now the bar is in the scene too: the shell paints
`BlockyTitleBar` into a texture (planks, title, the three blocks, the
hovered block's glyph — `_BlockyTitleBarState.paint`, the same painters
the widget uses) and hangs it on the pane as a fixed-yaw label 5 mm in
front of the picture, drawn again only when title, focus, width or
hovered block changes; the widget's bar paints nothing and is the
pointer's alone (`inScene`), reporting which block it is over
(`onHoverBlock`) so the scene's copy shows the hover. The lint's
window-chrome check learned that the report is not a control.

With that, nothing of a window in the scene is drawn by the widget
layer any more; the picture, the frame and the bar all sort against
the bricks and each other in the renderer.

### Phase 26 — a carried brick keeps its distance (2026-09-18)

"The depth of the mouse seems incorrect"; "when using the mouse to
move the box, it puts the box far away from my position." Two carry
models had put the brick where a ray through the pointer met
something — first a plane at the brick's own height, then the ground
or a brick top under the pointer. Both fling a brick to the horizon:
a brick in the building sits at eye level, so the ray through it is
nearly level, and whatever it meets is forty metres off (the world's
edge, clamped). Now a carried brick keeps the view depth it was picked
up at and follows the pointer across the view at that depth; the wheel
pushes it away or pulls it in (40 cm a notch, 1.2–30 m); pushed below
the ground it slides along the ground. Let go, it falls onto whatever
is under it. Verified with the pointer marked in the frame: a sideways
drag lands the brick beside the door at the same size; a downward drag
brings it down onto the water and no nearer.

### Phase 27 — no two bricks in one place (2026-09-18)

"Two boxes are merged into one. We should have physics for the box."
Two causes. Bricks at rest never pushed each other apart: a brick
that landed part-way into a neighbour (the "slide off" on landing
missed a second neighbour, or the fall ended on the ground in the same
step) stayed there. And the hover cue moved the brick 14 cm toward the
viewer — into whatever stood beside it.

Now the step ends with a resolver: every pair of overlapping boxes
(held and mid-tumble ones excepted) is pushed apart along the axis
they overlap least on — the upper one up, onto the lower, when that is
up (and it rests there, and tips if that is not enough to hold it);
half each sideways otherwise — four passes, so a push that makes a new
overlap is undone too, and nothing below its ground. A resting brick
pushed off its support finds out next step. The "mostly over" landing
rule is gone: a falling brick lands on any brick under it, and the
support test decides whether it stays. The hover is a HIGHLIGHT now — a
lighter face with a white rim, a second texture per app — and moves
nothing; the door block likewise.

Checked by dropping a brick half into another (pushed clear, climbed
onto the pile), hovering (lit, still), and dropping one onto the pile
from the side (settled beside, nothing merged).

### Phase 28 — footing, and the pool is solid (2026-09-18)

"The boxes still overlap." Reproducing with the harness and a
`bricks settled` log line (positions and modes when the ticker
stops) found the gap: a brick that LANDED came to rest in the same
step the ticker stopped, so its footing was never checked — a brick
landing with its centre past the edge of what it landed on hung there
for good, and whatever was done to its neighbours next started from a
wrong pile. One more step after any landing now (`landed`), and the
support test runs.

Two more things the numbers showed. The pool's blocks run from −3 to
+4 about the hub (a block covers [i, i+1)), so its centre is half a
metre past the hub — the ground test had it centred on the hub. And a
brick's ground support was decided at its CENTRE: set down on the rim's
edge, it stood as if the whole footprint were held, balanced on a
knife-edge. `_desktop3DGroundSupport` gives the footprint the ground
actually holds — on the pool, the part within its square; on the plaza,
the part not over the square, which is the rim's wall — so a brick on
the edge tips to the side its centre is on. And the pool is a box in
the resolver: a brick pushed into its rim comes out, up onto the pool
or sideways onto the plaza.

Checked by the numbers: a brick dropped hanging half a metre over
another tips off and lands beside it (0.9 m apart); a brick set on the
rim edge ends on the plaza; twelve random drops at random depths (the
wheel) leave no pair overlapping. A first stress run "passed" while
the desktop had quietly left 3D — a random press landed on the door —
so the harness now checks 3D is on every drop and keeps clear of the
door.

### Phase 29 — double-click opens, and the window pops up (2026-09-18)

"When double-clicking the box, a window shall pop up, similar to
double-clicking the dock." A single click on a brick now does nothing
(a press that moves is still a drag); the second click on the same
brick within half a second opens its app, and the window POPS UP: in
front of the viewer, at reading size, exactly where its flat rect is
on the screen they are looking at (`_desktop3DPoseInFront`: the plane
one pixel per pixel ahead of the camera, offset by the rect's place on
the screen, facing them), with the keyboard. An app with a window
already open has that window brought to the viewer the same way.

For that, the city's layout stopped moving windows every build: a
window gets its place when it ARRIVES (`_desktop3DPlaceWindows`, now
with a city branch — the next slot on the arc flanking the pile, or in
front of the viewer if its app was just double-clicked, remembered in
`_desktop3DPopUp`) and keeps it; the per-build layout only reads poses
for the nameplates. So a popped-up window stays where it popped up,
and a dragged pane stays where it was dragged.

Harness note: two `click`s in a row are too slow to be a double-click
(each spawns a process); use `dblclick`.

### Phase 30 — the grid (2026-09-18)

"The boxes still overlap" — and the numbers said they did not: the
one brick RESTED on the other, a third of a brick over its edge, and
from the entrance the two flush front faces read as one sunk lump. Two
answers. Bricks that have come to rest snap to a quarter-brick grid
(`_desktop3DSnapBricks`, when the ticker is about to stop: lowest
first, only to a free spot on the same ground, and one more step for
the footing after) — the building's courses are on that grid, a half
overhang tips (the centre on the edge is the tipping point), a quarter
stands, and nothing is ever a third over. And every face has a dark
edge now, so two bricks side by side are two. The replay of the user's
drop — editor to the plaza, settings a third over it — ends with the
two side by side, 0.9 m apart, on the grid.

### Phase 31 — a carried brick rides over the pile (2026-09-18)

"Take screenshot" — the purple brick inside the green one. The log's
order settled it: the user's mouse-up came one line AFTER the shot;
the brick was in their hand, carried through the other, which a held
brick did by design (it took no part in collisions). Now a carried
brick rides UP onto any brick it is moved into, and onto the one on
that (`_desktop3DBrickCarryPoint`, up to eight lifts), so it slides
over the pile the way a Lego brick does over studs, and never shows
inside another.

Found on the way, by the shell sitting at 27% CPU with nothing
moving: a brick set down beside the pool's rim fought for ever between
the grid (the hub's, with the pool half a metre off it) and the rim's
collider — snapped into the rim, pushed out, snapped in. The snap now
counts the pool as occupied, and a pile that has not settled in
twenty seconds stops and says so in the log rather than burn a core.

**Reading a screenshot of a drag:** check `[Input] UP` against the
shot's line in the log before calling a brick's position wrong. The
carry ends where the button does, not where the picture was taken.

### Phase 32 — one click opens (2026-09-18)

"Click box does not bring up window." The log showed what happened:
four presses on bricks over the session, each one a single click —
`sign terminal clicked`, and nothing after it — because Phase 29 had
made a single click do nothing and only a double-click open. A
double-click still worked when driven (`dblclick` → `open terminal`
→ the window in front at 1:1), so the mechanism was fine; the gesture
was the wrong one. Now a click on a brick — a press that never
becomes a drag — opens its app, the way one click on the dock does,
and the second click of a double-click is let through as nothing, so
a double-click opens once and never twice (`_desktop3DBrickClicked`).
Drag is untouched: it is still decided by the slop, before release.

Seen while proving it: a second window popped up onto the SAME plane
as the first (both "one pixel per pixel ahead"), and two panes on one
plane fight for every pixel — the Calculator's picture drawn over
the Terminal's while the Terminal had the keyboard, its orange keys
speckled where the depths crossed. Now a pop-up steps whatever
already stands on that plane back behind it (`_desktop3DPopUpWindow`:
the slab's depth plus five centimetres each, nearest first, the
higher of two at one depth first), so the newest window is the one in
front, exactly 1:1, and the others read as a pile behind it — the
flat desktop's stacking, given depth.

### Phase 33 — a clock in the city (2026-09-18)

"Add a clock in the city." A clock tower, where a square would have
one: on the far side from the door, straight behind the pool, in the
gap the windows' arc already kept clear (`k3DTowerClearDeg`). The
generator builds it — three blocks square, twelve high, sandstone on a
stone footing, a door toward the square, slit windows, a cornice, a
roof block and a mast — and writes `clock` into world.json: the
band's centre, how far its sides are, and how big a face to hang.
The shell hangs a face on each side, a hair off the stone, as
fixed-yaw labels sharing one texture: a dial drawn on a canvas (dark
rim, cream face, squared ticks, an hour and a minute hand; no second
hand — the desktop's own clock wakes once a minute and so does this,
`_desktop3DScheduleClock`, and not at all once 3D is off).

Three tries to make the hands move, each a lesson:

- **Redrawing into the same texture showed nothing new.** The labels
  were equal to the frame before, so the room drew no frame; and the
  upload happens in the raster thread's context while Filament samples
  from its own — a change to a shared texture is promised to the other
  context only after a flush here and a bind there.
- **A fresh texture every minute, the last one freed, vanished on the
  second minute.** The driver hands a freed name straight back to the
  next `glGenTextures`, so the new texture had the name the renderer
  already held for the old one, and it drew nothing.
- **What works:** two textures turn and turn about, never freed, so
  the label's texture id changes every minute (the room draws a frame,
  and binds the other name), plus a `glFlush` in
  `LinuxTextureRegistry.sceneTexture` after any upload it did — the
  panes never needed one because their pictures arrive as EGLImages.

Also found: fixed signs were two-sided (`label.mat` `culling : none`),
and a face on the tower's far side, seen from behind at a grazing
angle, showed as a mirrored sliver beside the wall. Labels are
one-sided now, like the panes' screens (the same quad); a billboard
always faces the viewer, so it loses nothing. And do not reach for
`RenderableManager::Builder::culling(true)` for this: that is FRUSTUM
culling, on by default for everything else — back faces are the
material's.

### Phase 34 — a third-party app in the city (2026-09-18)

"Test launch an app in 3D world" — "Launch chrome." Calculator from its
brick popped up in front as designed. Chrome, started through
`app-run` (it has no brick until it runs), arrived on the arc and a
click walked up to it, page readable and live — but its nameplate
read **"wayland-13"** over a generic glyph. The city grouped windows
by `win.appId`, the synthetic id a Wayland client gets, where the dock
resolves the OWNER through the registry (`_appOwning`: app_id, then
window class, then title). `_desktop3DAppId(of:)` does that now for
the nameplates, the brick's "bring its window to me" and the pop-up
match, so Chrome's pane says Chrome and its brick finds it.

And the bricks and nameplates of apps that have an icon file now wear
it: `_desktop3DIconImage` decodes the record's PNG once (the same file
the dock's tiles use, but as an image a canvas can draw rather than a
flipped GL texture), drops that app's glyph textures when it lands and
rebuilds, so the next build paints the icon. Chrome's brick — it drops
onto the pile the moment Chrome runs, as any running app does — and
the App Store's got theirs at once; first-party apps without a file
keep the catalog glyph. Dropping a texture and registering a new one
is safe HERE because the label's and block's scene ids are the texture
id, so the renderer sees a new entity — the clock's faces have fixed
ids, which is why they could not do this (Phase 33).

### Phase 35 — switching apps: the ring (2026-09-18)

"How to switch between apps in 3D mode? We'd better have some 3D
effects to switch." There was no switcher — not in the city, and none
on the flat desktop to borrow. Now Alt+Tab (Alt is already the room's
key) opens a RING: every open window glides onto a circle round the
viewer (`k3DSwitchRadius` 3.8 m, 30° between neighbours, each scaled
to at most 1.7 m wide so a browser and a calculator read as one thing
each), the one you had before straight ahead and nearer (2.8 m), all
facing in. Tab turns the ring a place; Shift+Tab the other way; Alt
up commits — the chosen window flies to the pop-up spot with the
keyboard and the others go back where they stood, the pile stepping
back behind it as a pop-up does (destinations are worked out on the
windows' OLD places, then everything tweens from the ring); Escape
puts all back. The handler sits ahead of everything else in the key
router so no keystroke leaks to an app mid-switch, and Alt+Escape
while the ring is up cancels rather than leaving the world.

For it, windows can MOVE: `_desktop3DTween` glides a pose to another
over 260 ms on a ticker (easeInOutCubic, yaw the short way round),
and everything that reads poses — the panes, the widgets' transforms,
the nameplates — follows, because the tween just writes `pose3D`.
Instant pose writes elsewhere are untouched.

Harness: `keydown alt`, `key tab` … `keyup alt` in ONE shell-drive
invocation; `[3D] switcher open/select/commit/cancel` in the log.

### Phase 36 — one window on screen (2026-09-18)

"We shouldn't have multiple apps shown up on the same screen. Only
one app has focus and is shown; other apps should be hidden from
screen. Alt+Tab can show the switcher to switch." So the city shows
ONE window now (`_desktop3DIsShown`): the focused one, else the last
shown, else the front-most (`_desktop3DUpdateShown`, run each build
before the layout). When the shown window changes to one that is not
in front of the viewer it is brought there — gliding, while the city
is up (a window closing hands the screen to the next, which flies in
from wherever it stood); placed outright during the entrance, before
anything is seen. Hidden windows have no widget, no pane, no
nameplate, and take no hit — every enumeration in the city filters
on the rule, and the rule says yes to a fullscreen window, to every
window on the ring, and to one still gliding back from it, so the
ring's windows fly home and vanish rather than blink out. Nothing is
hidden on the flat desktop nor while leaving, so on Escape they all
fly home with the rest. A click on a ring window chooses it.

The arc is still where arrivals are parked (out of sight) and where
the ring's windows fly in from — which reads well: Alt+Tab, and the
city's windows come in from around the square.

Trap, for the harness and for reading a test: the dev box is the
user's laptop and they are AT it. Five step-ups with no key in the
drive script were a held Space at the real keyboard, not a bug — the
log's `step up:` burst at key-repeat rate is the tell.

### Phase 37 — no nameplates over windows (2026-09-18)

"Do we need to show the text of each app on the top? I think it's
unnecessary." Gone: the icon-and-name that floated over each window's
roof (it dated from the arc, where windows were read from across the
square). The block title bar names the window, and on the ring each
window is read at once. A hovered brick still wears its name.

### Phase 38 — typing looked slow in the city (2026-09-18)

"When app is not in fullscreen, the response to keyboard is slow, you
can try terminal" — "or is it due to refresh rate in 3D not fast?" Not
the refresh rate: the city was presenting sixty frames a second while
idle (120 page flips in two seconds, by the debugfs fb-id oracle). It
was not REDRAWING the window's picture. The room renders into its
texture only when something marks it dirty (camera, panes, labels),
and a client's new frame did not: the scene mirror in the texture
registry told the engine the room's texture had a new frame, so the
engine composited the same stale room again. Typed text appeared only
when the pointer moved and the lean dirtied the camera. Proven with a
keyboard-only driver (no pointer) and a SIGUSR1 screenshot: the prompt
empty after "hello"; one pointer move later, "hello".

Two halves to the fix, and a third that was hiding behind them:

- The mirror now sets the room renderer dirty as well as telling the
  engine (`LinuxTextureRegistry.frameAvailable`).
- First-party apps never reached the mirror at all: the process
  manager announced a child's frames to the engine DIRECTLY
  (`FlutterEngineMarkExternalTextureFrameAvailable`), skipping the
  registry, so the first half alone fixed Chrome and not Terminal.
  `noteFrameAvailable` routes them through. (X11Integration has the
  same direct call and was left alone: X11 is out of scope unless
  asked.)
- The scene ticker was started for the Filament room too, whose tick
  is a no-op: sixty composites a second of the same frame, for
  nothing. It is not started for the Filament renderer now. Idle
  flips: 120 per two seconds → 3.

Measured after (installed session, Terminal as a pane, 12 keys):
key → first page flip median 24 ms, min 4, max 30 — one to two
frames — and the same with the window fullscreen. Rig:
`~/tmp/filament/lat/` (`rig.py` keyboard + fb-id poller, `still.py`
keyboard-only typing, `keylog.py` for the app side). Lessons: with
sixty idle flips a second the fb-id oracle cannot see a response, so
check the baseline first; and shell-drive's `main()` creates a mouse
on every invocation, which moves the pointer — a keyboard-only test
needs its own driver.

### Phase 39 — the city on WSL, and who has the keyboard on arrival (2026-09-18)

"Can you test in that remote Windows machine's WSL." Done on the
physical box (`starling@192.168.68.56`, WSL2 Ubuntu 26.04, no
`/dev/dri`, llvmpipe behind surfaceless EGL), with the shipped
launcher in RDP display mode and a real `xfreerdp3` on our own Xvfb,
driven by `xdotool`: `~/tmp/filament/wsl/wsl-3d.sh` (install, start,
connect, Terminal from the dock, enter, type, leave; shots to
`C:/dist/wsl3d-*.png`; `ask.py` beside it for the broker).

- **The city runs there.** Filament starts on llvmpipe: first frame
  0.7–4.4 s (shader compile), then ~165 ms a frame at 1280x800, the
  shell at ~390% CPU while it redraws. Slow, and correct: the
  building, the clock, the Terminal in its brick frame, typing shown.
- **Without `libc++1`/`libc++abi1` the renderer silently does not
  load** and the shell falls back to the GL living room — which on
  llvmpipe runs its scene ticker at sixty frames a second: **655%
  CPU.** The .deb declares both (dpkg-shlibdeps found them), so
  `apt install ./starling.deb` brings them; a bare `dpkg -i` does
  not, and `test/wsl/gate.sh`'s `dpkg -i || dpkg -i --force-all`
  installs over the unmet dependency and grades a PASS. `ldd
  libstarling_room.so | grep "not found"` is the check.
- **Typed text did not appear at first — the keys went to the
  camera.** Entering a walking world handed the keyboard to the camera
  (Phase 22-era: windows stood far off on the arc, and a focused app
  would have swallowed the first arrow). Now the window that had the
  keyboard is shown in front at full size, so it keeps the keyboard;
  "hello" on arrival walked the viewer (`e` turns right — the two
  shots differ by exactly that). Removed: the focused window stays
  focused on entry, the camera gets the keys only when nothing is
  focused, and Alt still drives it regardless. Verified on both boxes.

Harness notes for that machine: run scripts as FILES from
`/mnt/c/dist` (nested quoting through `wsl -- bash -c` fails with
"The system cannot find the path specified"); the broker socket is
`/tmp/xdg-starling-1000/…` after the launcher's re-exec, and a stale
root socket from a killed dev shell makes `ask.py` refuse the
connection — delete it; `xdotool mousemove --window <freerdp window>`
takes the dock's logical coordinates 1:1 at 1280x800.

### Phase 40 — the host GPU from WSL (2026-09-18)

"You should test it on Windows's RDP client, so it has graphics
acceleration?" The client cannot add any: the city is drawn where the
shell runs, inside WSL, and an RDP client only receives finished
pixels — FreeRDP and mstsc show the same frames at the same speed.
The acceleration that matters is on the WSL side, and WSL2 has it:
the host GPU is shared in as `/dev/dxg`, Mesa carries a D3D12 driver
for it (`d3d12_dri.so`, with `libd3d12.so`/`libdxcore.so` under
`/usr/lib/wsl/lib`), and on that box `GALLIUM_DRIVER=d3d12 eglinfo -B
-p surfaceless` reports **D3D12 (AMD Radeon 780M Graphics)** where the
default is llvmpipe. Mesa simply does not pick it by itself on the
surfaceless platform.

So the RDP display mode asks for it: `rdp_egl_create` sets
`GALLIUM_DRIVER=d3d12` when `/dev/dxg` and the driver are present and
nothing was asked for, falls back to Mesa's default if that display
will not initialise, and logs `[RdpEgl] renderer: …` so the choice is
never a guess. The first-party apps inherit the setting and render on
the GPU too. The launcher passes the environment through, so a user's
own `GALLIUM_DRIVER` still wins.

| in WSL, 1280x800 | room frame | first frame | shell CPU redrawing |
|---|---|---|---|
| llvmpipe (before) | ~165 ms | 0.7–4.4 s | ~390% |
| D3D12 on the 780M | 6.6–11.8 ms | 0.2–0.6 s | ~14% |

Idle in the city sits at ~13% there, spread over a dozen engine
threads at 1% each — not the 0.00% the flat desktop idles at in
display mode. Not chased yet.

**And through Windows' own client:** `mstsc /v:localhost:3390 /w:1280
/h:800`, run as an interactive scheduled task in the box's logged-in
session (`~/tmp/filament/wsl/mstsc-view.ps1` + `.vbs` runner, the
`capture-winshell.sh` shape), connected, activated (`NSCodec`), and
showed the GPU-rendered city — Terminal in its brick frame, the
street beyond — for the 45 s it was left open. Same frames as
FreeRDP, as it must be. Two traps on the way:

- **The WSL distro dies with the last `wsl.exe` session.** A shell
  started from an ssh'd `wsl -- bash script.sh` lives exactly as long
  as that command; once it returned, the distro shut down, `/tmp` and
  the log with it, and mstsc sat at "Configuring remote session…"
  against nothing. Keep the launching ssh open in the background for
  as long as the desktop is wanted, and `tail -F` the session log to
  `/mnt/c/dist` so a crash leaves evidence.
- **Never `SendKeys` blind on that box.** It is a live desktop: Edge
  was open on a GitHub issue when the first attempt typed "hello
  world" at whatever was in front (the page scrolled; nothing worse).
  mstsc is a viewer there; drive input from the WSL side.

### Still open

### Still open

- The room reads a little brown and dim; there is nothing on the walls.
  Both are 25-second experiments now rather than rebuilds.
- A second environment, to prove the pipeline moves. The CC0 library can
  furnish a clifftop over the sea, a pine forest, a workshop, a back
  alley or a lunar surface, and there are 997 skies.
- Making the environment a setting the user picks, the way wallpapers
  already are.
- Mission Control as a dolly back, spaces as pans, open/close along z —
  the views the shell already has, as camera moves over unchanged poses.

## Traps paid for

Every one of these cost real time, and every one is silent — no error,
no warning, just a wrong picture that looks like a different bug.

**Matrices and the layer tree**

- **A projection matrix with a trivial z row is SINGULAR**, and
  `RenderTransform` neither paints nor hit-tests a matrix it cannot
  invert. Every window vanished. Give the z row a real projection even
  though nothing reads the z.
- **`Transform` does no near-plane clipping.** Reject any pose whose
  corners project with w near zero; Skia draws garbage rather than
  clipping.
- **Drag deltas are in screen space and must stay so.** The framework
  freezes the hit-test transform at pointer-down for the whole gesture,
  so unprojecting deltas through it after a press has flattened the
  window overshoots by 1/scale (measured 1.43×).

**GL, inside the engine's context**

- **Skia leaves depth WRITES off**, so `glClear(GL_DEPTH_BUFFER_BIT)` is
  a no-op: the buffer keeps its garbage, every fragment fails the test,
  and nothing draws while the colour clear still works.
- **GL row 0 is the BOTTOM of an engine external texture.** Do not flip
  y in the projection. Measure, do not assume.
- **mediump is fp16.** Procedural noise that hashes uv in metres reaches
  hundreds of thousands over a room-sized floor, past fp16's 65504. It
  overflows to infinity, `sin(inf)` is NaN, and the fragment comes out
  pure black in a stepped patch that looks exactly like a geometry bug.
- **A uniform's precision must match across stages** in GLSL ES 1.00 or
  the program fails to LINK with no compile error. Read the program info
  log.
- **`packed` is a reserved word in GLSL.**
- **The engine's image codec returns PREMULTIPLIED RGBA.** Anything
  stored in an alpha channel as data has already been multiplied into
  the colour by the time it arrives. An HDR sky packed as RGB×alpha
  decodes to black.

**The bake**

- **Baked light is per VERTEX**, so a surface's subdivision is the
  resolution of every shadow on it. A wall at 28 cm per cell turns the
  edge of a sun patch into a staircase.
- **Ambient occlusion shows its sampling noise as blotches** the size of
  the mesh's cells. Fourteen rays looked fine on a graph and like dirt
  on a wall; 64 is enough.
- **A relief of all zeros is indistinguishable from no relief**, and
  both look like a working flat wall. The mesh builder logs the range of
  what it computed for exactly this reason.
- **The material numbering lives in the importer.** When the shader had
  an older copy, its "rides with the eye" test matched the CEILING
  instead of the sky, and the room simply had no ceiling.

**The shell around it**

- **A session that comes up with 3D ALREADY ON never runs the enter
  path**, so anything hung off that path never happens — the windows had
  no places in the room and the scene's clock never started. Hang setup
  off the thing it belongs to, not off the mode change.
- **The 3D functional check needs tiling OFF.** A maximised window
  covers the whole room and the focused window is drawn flat, so
  entering changes nothing a screenshot can see and it reads as a dead
  feature. The check refuses to run now.
- **A dirty session fails the 2D-contract check for no reason.** After
  an hour of driving, two screenshots of the same untouched desktop
  differed by 12,902 pixels (a blinking caret) while the real residue
  was 264. Restart the shell before believing a small diff.
- **Root-mode artefacts** (repo `CLAUDE.md`): a third-party client's
  input behaviour under a pose must be confirmed in the VM as `tester`
  before it is called a compositor bug.
- **macOS keeps 2D.** The renderer is GL and the macOS shell is not
  currently built at all.

## Measured out — do not build these

Each was tried or worked through and does not pay at this geometry. The
numbers are here so nobody re-derives them.

- **Floor reflections of windows.** Windows float about a third of the
  way to the far wall and well above the floor, so a mirrored image
  lands at −1.40 in NDC — off the bottom of the screen — and only
  arrives when a window is pushed nearly to the wall.
- **Shadows cast by windows onto what is behind them.** The surface
  behind is further from the eye, so the shadow projects at 60–77% of
  the window's on-screen size and lands entirely behind it. This is why
  every UI in the world fakes drop shadows in screen space.
- **Tier 2 occlusion layers for a photographic environment.** A
  landscape has no near subject for a window to go behind, only the
  ground under the viewer — a thin strip at the picture's bottom edge. A
  window clipped by it reads as a glitch.

## Open questions

- How much of the room should a user be able to change? The environment
  wants to be a setting, like wallpapers; whether the furniture should
  move is a different question.
- Whether a window should be able to rest ON something — a pane leaning
  on the console, a small one on the coffee table. It needs surface
  detection the bake could supply.
- Whether walking is the right verb. Stepping up to a window works well;
  free walking is pleasant but nobody needs it to get work done.

### Independent cities on multiple displays (2026-09-19)

Each output now renders its own city scene into a display-sized texture with a
centered lens. Camera position, pointer lean, orbit state, camera glides, hovered
sign and rail page belong to that output. Navigation follows the pointer's
output; widget builds explicitly scope their projection to the output being
built. Window placement and hit testing use that output's logical bounds, so
mixed DPI and offset monitors no longer inherit the primary monitor's lens.

The city assets are the same on each display. Native scenes, cameras and targets
are separate, while Filament's backend engine is shared on the raster thread.
The GPU regression exposed a renderer teardown hang with separate Engines.
Scene texture subscriptions now support multiple targets so client frames update
all previews that reference them. Retired scenes are destroyed on the raster
thread before deleting their imported textures. The native platform borrows
Flutter's EGL display: teardown releases its context without terminating that
display, so leaving and re-entering 3D remains safe.

`test/displays/README.md` documents the lens, offscreen GPU and live-input checks.
The `desktop_3d` broker query reports each output's camera, effective eye and
texture ID for checking independent navigation without relying on screenshots of
animated clouds or water.
