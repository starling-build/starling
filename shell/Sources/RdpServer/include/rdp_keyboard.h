// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_keyboard.h — RDP scancodes into the shape the engine expects.
//
// The pipeline has one canonical representation and it is NOT what RDP
// sends. The engine takes a HID usage code as `physical`, an xkb keysym as
// `logical`, and UTF-8 as `character`; Wayland clients then get evdev back
// out through the shell's HidEvdev table. RDP delivers PC/AT set-1
// scancodes, so display mode converts scancode → evdev here and lets Swift
// finish the job with the same table the Wayland path uses. Feeding RDP
// scancodes in raw would break letters for every Wayland client — the trap
// CLAUDE.md documents for this exact pair of mappings.
//
// xkb lives here rather than in Swift because the engine's own keyboard
// path uses xkbcommon and this has to agree with it, character for
// character, including dead keys and modifier latching.

#ifndef STARLING_RDP_KEYBOARD_H_
#define STARLING_RDP_KEYBOARD_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RdpKeyboard RdpKeyboard;

// Default (us pc105) keymap, matching what wayland_seat.c hands clients.
RdpKeyboard* rdp_keyboard_create(void);
void rdp_keyboard_destroy(RdpKeyboard* k);

// One key from the client. |scancode| is the RDP set-1 code and |extended|
// its 0xE0 prefix flag; |down| is 1 for press. Fills the engine's three
// fields: |evdev_out| (which Swift maps to HID), |keysym_out|, and
// |utf8_out| (NUL-terminated, empty for non-printing keys).
// Returns 0 if the scancode has no evdev equivalent — drop it rather than
// send the engine a key that does not exist.
int rdp_keyboard_key(RdpKeyboard* k, uint32_t scancode, int extended,
                     int down, uint32_t* evdev_out, uint32_t* keysym_out,
                     char* utf8_out, int utf8_len);

// Client-reported lock state at connect (MS-RDPBCGR sync event): bit 0
// scroll lock, 1 num lock, 2 caps lock. Without this a session inherits
// none of the client's locks and Caps Lock silently disagrees.
void rdp_keyboard_sync(RdpKeyboard* k, uint32_t toggle_flags);

// Every key still held, so a disconnect can release them. Writes evdev
// codes into |out| (capacity |max|) and returns how many. A client that
// vanishes mid-chord otherwise leaves Ctrl down forever — the stuck-modifier
// failure the engine's ReleaseAllKeys exists to prevent.
int rdp_keyboard_pressed(RdpKeyboard* k, uint32_t* out, int max);
void rdp_keyboard_reset(RdpKeyboard* k);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_RDP_KEYBOARD_H_
