// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The 3D desktop's room, rendered by Filament. A C surface over a C++
// library, so the shell can dlopen it: Filament is built against clang's
// C++ library and nothing else in the shell is, so the two never meet
// except through these calls.
//
// Threading: Filament runs its own render thread with its own EGL
// context, shared with the one handed to sr_room_create. Every call here
// is made from ONE thread (the engine's raster thread, inside the texture
// callback); sr_room_render blocks until the GPU has finished writing
// the output texture, so the caller may sample it as soon as it returns.
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The library is built with hidden visibility; only these are exported.
#define SR_EXPORT __attribute__((visibility("default")))

typedef struct sr_room sr_room;

/// Creates the renderer on an EGL display, sharing objects with a context
/// that belongs to the caller. NULL on failure (reason on stderr).
SR_EXPORT sr_room* sr_room_create(void* egl_display, void* shared_egl_context);

/// Loads the room: a glTF binary, and the sky as two KTX cubemaps made by
/// cmgen — the prefiltered light (without its sun) and the picture the
/// windows look out on (with it). 0 on success.
SR_EXPORT int sr_room_load(sr_room*, const char* glb_path, const char* ibl_ktx_path,
                 const char* skybox_ktx_path);

/// The light. `sun_dir` points TO the sun, in the room's world (Filament's
/// world; +y up). Colour is linear RGB; lux as Filament counts it: ~100k
/// for direct sun, ~30k for a clear sky's ambient.
SR_EXPORT void sr_room_set_light(sr_room*, const float sun_dir[3], const float sun_colour[3],
                       float sun_lux, float ibl_lux);

/// Camera exposure: aperture (f-stop), shutter (seconds), ISO.
SR_EXPORT void sr_room_set_exposure(sr_room*, float aperture, float shutter, float iso);

/// Optional height-based haze; density <= 0 disables it. Distances are metres,
/// falloff is inverse metres, and colour tints the environment's scattered light.
/// New rooms have fog disabled. The skybox is excluded.
SR_EXPORT void sr_room_set_fog(sr_room*, float density, float start, float height,
                              float falloff, float maximum_opacity, const float colour[3]);

/// Where the picture goes: a GL texture that already exists in the shared
/// context, RGBA8, width x height. May be called again with a new name.
SR_EXPORT int sr_room_set_output(sr_room*, uint32_t gl_texture, int width, int height);

/// Column-major 4x4 matrices: `view` maps world to eye, `proj` eye to clip.
/// Near and far are what `proj` was built with.
SR_EXPORT void sr_room_set_camera(sr_room*, const float view[16], const float proj[16],
                        float near_plane, float far_plane);

/// Optional screen-space reflections; disabled by default.
SR_EXPORT void sr_room_set_reflections(sr_room*, int enabled);

/// Evaluate animations at a fixed time for previews; negative restores real time.
SR_EXPORT void sr_room_set_animation_time(sr_room*, double seconds);

/// Renders one frame into the output and waits for it. 0 on success.
SR_EXPORT int sr_room_render(sr_room*);

/// The direction a pixel of an equirectangular sky maps to, in the same
/// convention cmgen used to build the cubemaps — so a sun found in the
/// picture lands where the skybox shows it. u,v in [0,1), v down.
SR_EXPORT void sr_room_equirect_direction(float u, float v, float out_dir[3]);

/// A window hung in the room. `centre` is the WINDOW's centre (title bar
/// included) in world metres, `yaw` its facing (0 faces +z), `width`/
/// `height` the whole window in metres; the client's picture fills a
/// rectangle `content_w` x `content_h` whose centre sits `content_dy`
/// below the window's (the title bar is the shell's, drawn by the shell).
/// `gl_texture` is the client's texture in the shared context; `flip_y`
/// for buffers whose first row is the top of the picture. Calling again
/// with the same id updates the pane. 0 on success.
SR_EXPORT int sr_room_set_pane(sr_room*, int64_t id, const float centre[3], float yaw,
                               float width, float height, float content_dy,
                               float content_w, float content_h,
                               uint32_t gl_texture, int tex_w, int tex_h,
                               int flip_y, int focused);
SR_EXPORT void sr_room_remove_pane(sr_room*, int64_t id);

/// What the panes' frames are made of. By default a plain dark slab a few
/// centimetres round the window; given a world's block tile (`gl_texture`
/// in the shared context, sampled nearest and repeated every `block`
/// metres), the frames are built of that block instead, `margin` metres
/// round the window and `depth` metres deep. `gl_texture` 0 restores the
/// plain slab. Applies to every pane, present and future.
SR_EXPORT void sr_room_set_pane_style(sr_room*, uint32_t gl_texture, int tex_w, int tex_h,
                                      float block, float margin, float depth);

/// How bright a white pixel of a pane is, in the room's light units.
SR_EXPORT void sr_room_set_screen_intensity(sr_room*, float intensity);

/// A light at a point in the room — the orrery's sun. Candela; colour
/// linear RGB. Calling again moves it; candela <= 0 removes it.
SR_EXPORT void sr_room_set_point_light(sr_room*, const float pos[3], const float colour[3],
                                       float candela);

/// A sphere: a planet (lit, in the app's colour) or, with `glow` > 0,
/// something that shines by itself at that intensity (the sun).
SR_EXPORT int sr_room_set_orb(sr_room*, int64_t id, const float centre[3], float radius,
                              const float colour[3], float glow);
SR_EXPORT void sr_room_remove_orb(sr_room*, int64_t id);

/// A label: a texture with alpha on a quad `width` x `height` metres
/// centred on `centre`. With `yaw` NaN it always faces the viewer (a
/// nameplate); otherwise it faces that way (0 = +z), fixed, like a sign
/// on a wall.
SR_EXPORT int sr_room_set_label(sr_room*, int64_t id, const float centre[3],
                                float width, float height, float yaw,
                                uint32_t gl_texture, int tex_w, int tex_h);
SR_EXPORT void sr_room_remove_label(sr_room*, int64_t id);

/// A block: a cube `size` metres on a side, centred on `centre`, turned
/// `yaw` (0: a face toward +z) and rolled `roll` about its own z (a
/// brick tipping over), wearing `gl_texture` on every face — an app's
/// icon as a thing in the world, lit like the rest of it.
SR_EXPORT int sr_room_set_block(sr_room*, int64_t id, const float centre[3], float yaw,
                                float roll, float size,
                                uint32_t gl_texture, int tex_w, int tex_h);
SR_EXPORT void sr_room_remove_block(sr_room*, int64_t id);

SR_EXPORT void sr_room_destroy(sr_room*);

#ifdef __cplusplus
}
#endif
