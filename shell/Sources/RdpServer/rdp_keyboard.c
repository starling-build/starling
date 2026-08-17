// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_keyboard.c — RDP scancode → evdev + xkb (see rdp_keyboard.h).

#include "include/rdp_keyboard.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>

// evdev's keycode space is xkb's minus 8, throughout.
#define EVDEV_OFFSET 8

struct RdpKeyboard {
    struct xkb_context* ctx;
    struct xkb_keymap* keymap;
    struct xkb_state* state;
    // Held keys, so a vanishing client can be made to release them.
    uint32_t pressed[64];
    int pressed_count;
};

// The unprefixed block of PC/AT set 1 *is* evdev's numbering: scancode 0x01
// is Escape and evdev 1 is Escape, and it stays aligned to 0x53 (Delete on
// the keypad). That is not a coincidence — Linux's atkbd map was built from
// it — so the main keyboard needs no table at all.
//
// The 0xE0-prefixed keys are where it diverges, because evdev put them
// wherever there was room. Those are enumerated below; anything absent is
// refused rather than guessed.
static uint32_t extended_to_evdev(uint32_t sc) {
    switch (sc) {
        case 0x1C: return 96;   // KP Enter
        case 0x1D: return 97;   // Right Ctrl
        case 0x35: return 98;   // KP Slash
        case 0x37: return 99;   // Print Screen
        case 0x38: return 100;  // Right Alt
        case 0x47: return 102;  // Home
        case 0x48: return 103;  // Up
        case 0x49: return 104;  // Page Up
        case 0x4B: return 105;  // Left
        case 0x4D: return 106;  // Right
        case 0x4F: return 107;  // End
        case 0x50: return 108;  // Down
        case 0x51: return 109;  // Page Down
        case 0x52: return 110;  // Insert
        case 0x53: return 111;  // Delete
        case 0x5B: return 125;  // Left Meta
        case 0x5C: return 126;  // Right Meta
        case 0x5D: return 127;  // Menu
        case 0x1F: return 142;  // Sleep
        case 0x20: return 113;  // Mute
        case 0x2E: return 114;  // Volume Down
        case 0x30: return 115;  // Volume Up
        default: return 0;
    }
}

RdpKeyboard* rdp_keyboard_create(void) {
    RdpKeyboard* k = calloc(1, sizeof(RdpKeyboard));
    if (!k) {
        return NULL;
    }
    k->ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!k->ctx) {
        fprintf(stderr, "[RdpKbd] xkb_context_new failed\n");
        goto fail;
    }
    // Same default the compositor hands Wayland clients (wayland_seat.c), so
    // the shell and its clients agree on the layout.
    k->keymap = xkb_keymap_new_from_names(k->ctx, NULL,
                                          XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!k->keymap) {
        fprintf(stderr, "[RdpKbd] xkb_keymap_new_from_names failed\n");
        goto fail;
    }
    k->state = xkb_state_new(k->keymap);
    if (!k->state) {
        fprintf(stderr, "[RdpKbd] xkb_state_new failed\n");
        goto fail;
    }
    return k;

fail:
    rdp_keyboard_destroy(k);
    return NULL;
}

void rdp_keyboard_destroy(RdpKeyboard* k) {
    if (!k) {
        return;
    }
    if (k->state) xkb_state_unref(k->state);
    if (k->keymap) xkb_keymap_unref(k->keymap);
    if (k->ctx) xkb_context_unref(k->ctx);
    free(k);
}

static void track_pressed(RdpKeyboard* k, uint32_t evdev, int down) {
    for (int i = 0; i < k->pressed_count; i++) {
        if (k->pressed[i] == evdev) {
            if (!down) {
                k->pressed[i] = k->pressed[--k->pressed_count];
            }
            return;
        }
    }
    if (down && k->pressed_count < (int)(sizeof(k->pressed) / sizeof(k->pressed[0]))) {
        k->pressed[k->pressed_count++] = evdev;
    }
}

int rdp_keyboard_key(RdpKeyboard* k, uint32_t scancode, int extended,
                     int down, uint32_t* evdev_out, uint32_t* keysym_out,
                     char* utf8_out, int utf8_len) {
    if (!k || !evdev_out) {
        return 0;
    }
    uint32_t evdev = extended ? extended_to_evdev(scancode)
                              : (scancode <= 0x53 ? scancode : 0);
    if (evdev == 0) {
        return 0;
    }

    const xkb_keycode_t xkb_code = evdev + EVDEV_OFFSET;
    // Read the symbol BEFORE updating state for a press: xkb's own clients
    // do the same, and it is what makes a shifted key report its shifted
    // symbol rather than the next one's.
    xkb_keysym_t sym = xkb_state_key_get_one_sym(k->state, xkb_code);
    if (utf8_out && utf8_len > 0) {
        utf8_out[0] = '\0';
        if (down) {
            xkb_state_key_get_utf8(k->state, xkb_code, utf8_out, utf8_len);
        }
    }
    xkb_state_update_key(k->state, xkb_code, down ? XKB_KEY_DOWN : XKB_KEY_UP);
    track_pressed(k, evdev, down);

    *evdev_out = evdev;
    if (keysym_out) {
        *keysym_out = sym;
    }
    return 1;
}

void rdp_keyboard_sync(RdpKeyboard* k, uint32_t toggle_flags) {
    if (!k || !k->state) {
        return;
    }
    // Rebuild the state with the client's locks, since xkb has no "set lock"
    // call — the mods are applied as latched/locked directly.
    // Only Caps has a portable name (XKB_MOD_NAME_CAPS == "Lock"). Num and
    // Scroll are conventional bindings — Mod2 and Mod3 on every standard
    // keymap — and this xkbcommon has no macros for them, so they are named
    // directly. A keymap that disagrees returns XKB_MOD_INVALID and the lock
    // is simply not applied, which is the right failure.
    xkb_mod_mask_t locked = 0;
    static const struct {
        uint32_t bit;
        const char* name;
    } kLockMods[] = {
        {0x01, "Mod3"},              // Scroll Lock
        {0x02, "Mod2"},              // Num Lock
        {0x04, XKB_MOD_NAME_CAPS},   // Caps Lock
    };
    for (size_t i = 0; i < sizeof(kLockMods) / sizeof(kLockMods[0]); i++) {
        if (!(toggle_flags & kLockMods[i].bit)) {
            continue;
        }
        xkb_mod_index_t idx =
            xkb_keymap_mod_get_index(k->keymap, kLockMods[i].name);
        if (idx != XKB_MOD_INVALID) {
            locked |= (xkb_mod_mask_t)1 << idx;
        }
    }
    xkb_state_update_mask(k->state, 0, 0, locked, 0, 0, 0);
}

int rdp_keyboard_pressed(RdpKeyboard* k, uint32_t* out, int max) {
    if (!k || !out) {
        return 0;
    }
    int n = k->pressed_count < max ? k->pressed_count : max;
    memcpy(out, k->pressed, (size_t)n * sizeof(uint32_t));
    return n;
}

void rdp_keyboard_reset(RdpKeyboard* k) {
    if (!k) {
        return;
    }
    k->pressed_count = 0;
    if (k->keymap) {
        struct xkb_state* fresh = xkb_state_new(k->keymap);
        if (fresh) {
            if (k->state) {
                xkb_state_unref(k->state);
            }
            k->state = fresh;
        }
    }
}
