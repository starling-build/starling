// A small AT-SPI server: lets a screen reader (Orca, Accerciser, any AT-SPI client) see an app's
// accessibility nodes on the desktop accessibility bus. It speaks D-Bus through libsystemd's sd-bus,
// loaded at run time (dlopen), so nothing links against it and a machine without it just gets no bridge.
//
// The host (Swift) describes the app as a flat list of nodes under one application root and says what to
// do when a client presses one. Both callbacks are called on the bridge's own thread; the host must hop
// to its UI thread itself.
#ifndef ATSPI_BRIDGE_H
#define ATSPI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// AT-SPI role numbers used by the bridge (Atspi.Role).
enum {
    ATSPI_BRIDGE_ROLE_CHECK_BOX = 7,
    ATSPI_BRIDGE_ROLE_DIALOG = 16,
    ATSPI_BRIDGE_ROLE_FRAME = 23,
    ATSPI_BRIDGE_ROLE_LABEL = 29,
    ATSPI_BRIDGE_ROLE_MENU_ITEM = 35,
    ATSPI_BRIDGE_ROLE_PANEL = 39,
    ATSPI_BRIDGE_ROLE_PUSH_BUTTON = 43,
    ATSPI_BRIDGE_ROLE_TOGGLE_BUTTON = 62,
    ATSPI_BRIDGE_ROLE_ENTRY = 79,
    ATSPI_BRIDGE_ROLE_HEADING = 83,
};

// State bits (Atspi.StateType numbers); a node's `states` is a mask built as (1ull << state).
enum {
    ATSPI_BRIDGE_STATE_CHECKED = 4,
    ATSPI_BRIDGE_STATE_EDITABLE = 7,
    ATSPI_BRIDGE_STATE_ENABLED = 8,
    ATSPI_BRIDGE_STATE_FOCUSABLE = 11,
    ATSPI_BRIDGE_STATE_FOCUSED = 12,
    ATSPI_BRIDGE_STATE_PRESSED = 20,
    ATSPI_BRIDGE_STATE_SELECTED = 23,
    ATSPI_BRIDGE_STATE_SENSITIVE = 24,
    ATSPI_BRIDGE_STATE_SHOWING = 25,
    ATSPI_BRIDGE_STATE_SINGLE_LINE = 26,
    ATSPI_BRIDGE_STATE_VISIBLE = 30,
};

typedef struct {
    const char *name;        // what the screen reader says
    const char *description; // may be NULL
    int role;
    uint64_t states;
    int can_press;           // has a "press" action
    int x, y, w, h;          // screen rectangle, 0 when unknown
    const char *text;        // a text box's contents (UTF-8), NULL for nodes that are not text
    int caret;               // caret and selection, in characters (not bytes); -1 when unknown
    int sel_start, sel_end;  // equal when nothing is selected
    int can_edit;            // a screen reader may insert, delete and move the caret (EditableText)
} atspi_bridge_node;

typedef struct {
    void *ctx;
    // Fills *out with a malloc'd array and returns its length. The bridge frees the array with free()
    // and each name/description/text with free() too (so the host strdup()s them).
    int (*snapshot)(void *ctx, atspi_bridge_node **out);
    // Press node `index` (0-based, as in the last snapshot). Returns 1 when something happened.
    int (*press)(void *ctx, int index);
    // Edit text node `index`. Offsets are in characters (code points). op: 1 insert `s` at a; 2 delete a..b;
    // 3 put the caret at a; 4 select a..b; 5 replace the whole contents with `s`. Returns 1 when done.
    int (*edit)(void *ctx, int index, int op, int a, int b, const char *s);
    // The window's top-left corner on the screen; returns 0 when the app does not know it.
    int (*origin)(void *ctx, int *x, int *y);
} atspi_bridge_host;

// Connects to the accessibility bus, registers the app under `app_name` and serves requests on a
// background thread. Returns 0 on success; negative when there is no bus or sd-bus is missing.
int atspi_bridge_start(const atspi_bridge_host *host, const char *app_name);

// Turns the change signals (name, state, nodes added or removed) on or off. Off by default; they cost a
// look at the whole app a few times a second.
void atspi_bridge_set_events(int on);

// Asks the screen reader to say `text` (AT-SPI Announcement event). assertive 1 interrupts, 0 waits its turn.
// 0 when queued, -1 when the bridge is not running.
int atspi_bridge_announce(const char *text, int assertive);

// The bus connection's unique name once started (for tests), or NULL.
const char *atspi_bridge_bus_name(void);

#ifdef __cplusplus
}
#endif
#endif
