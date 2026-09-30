// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_RUNTIME_CALLBACKS_H_
#define FLUTTER_SWIFT_RUNTIME_CALLBACKS_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A pure C callback table defining the contract between the Flutter engine
/// and the Swift runtime. The engine calls through these function pointers
/// to deliver Shell-to-Framework events. The Swift side fills them in at
/// startup via `createRuntimeCallbacks()`.
///
/// This eliminates the circular dependency where swift_runtime_controller.cc
/// needed the generated SwiftRuntime-Swift.h header.
typedef struct {
  /// Opaque context pointer passed as the first argument to every callback.
  /// Typically points to a retained SwiftRuntimeDelegate instance.
  void* context;

  // -- Frame scheduling ---------------------------------------------------

  void (*begin_frame)(void* context,
                      int64_t frame_time_micros,
                      uint64_t frame_number);
  void (*draw_frame)(void* context);
  void (*report_timings)(void* context,
                         const int64_t* timings,
                         size_t count);

  // -- View management ----------------------------------------------------

  void (*add_view)(void* context,
                   int64_t view_id,
                   double width,
                   double height,
                   double pixel_ratio,
                   int64_t display_id);
  void (*remove_view)(void* context, int64_t view_id);
  void (*send_view_focus_event)(void* context,
                                int64_t view_id,
                                int32_t state,
                                int32_t direction);
  void (*set_viewport_metrics)(void* context,
                               int64_t view_id,
                               double width,
                               double height,
                               double pixel_ratio,
                               double pad_top,
                               double pad_right,
                               double pad_bottom,
                               double pad_left,
                               double inset_top,
                               double inset_right,
                               double inset_bottom,
                               double inset_left,
                               double gesture_top,
                               double gesture_right,
                               double gesture_bottom,
                               double gesture_left,
                               double touch_slop,
                               int64_t display_id);
  void (*set_displays)(void* context,
                       const double* display_data,
                       size_t count);

  // -- Input --------------------------------------------------------------

  void (*dispatch_pointer_data_packet)(void* context,
                                       const uint8_t* data,
                                       size_t data_len);
  void (*dispatch_key_data)(void* context,
                             const uint8_t* data,
                             size_t data_len);
  void (*dispatch_semantics_action)(void* context,
                                    int32_t view_id,
                                    int32_t node_id,
                                    int32_t action,
                                    const uint8_t* args,
                                    size_t args_len);

  // -- Configuration ------------------------------------------------------

  void (*set_semantics_enabled)(void* context, bool enabled);
  void (*set_accessibility_features)(void* context, int32_t flags);
  void (*set_locales)(void* context,
                      const char** locale_data,
                      size_t count);
  void (*set_user_settings_data)(void* context, const char* data);
  void (*set_initial_lifecycle_state)(void* context, const char* data);

  // -- Platform messages --------------------------------------------------

  void (*dispatch_platform_message)(void* context,
                                    const char* channel,
                                    const uint8_t* data,
                                    size_t data_len,
                                    int32_t response_id);
} SwiftRuntimeCallbacks;

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_SWIFT_RUNTIME_CALLBACKS_H_
