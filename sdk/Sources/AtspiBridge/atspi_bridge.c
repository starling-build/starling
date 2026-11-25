#define _GNU_SOURCE
#include "AtspiBridge.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <systemd/sd-bus.h>

// The vtable macros point at libsystemd's format number. We do not link it (it is dlopen'd), so we
// carry our own copy of the same constant; sd-bus only compares the value (242 since systemd 242).
__attribute__((visibility("hidden"))) const unsigned sd_bus_object_vtable_format = 242;

// ---- sd-bus, loaded at run time ------------------------------------------------------------------

#define SYMBOLS(X) \
    X(sd_bus_open_user) X(sd_bus_new) X(sd_bus_set_address) X(sd_bus_set_bus_client) X(sd_bus_start) \
    X(sd_bus_call_method) X(sd_bus_add_fallback_vtable) X(sd_bus_process) X(sd_bus_wait) \
    X(sd_bus_get_unique_name) X(sd_bus_message_read) X(sd_bus_message_append) \
    X(sd_bus_message_open_container) X(sd_bus_message_close_container) X(sd_bus_message_get_path) \
    X(sd_bus_message_append_array) X(sd_bus_reply_method_return) X(sd_bus_message_unref) \
    X(sd_bus_message_new_method_return) X(sd_bus_message_new_signal) X(sd_bus_send) X(sd_bus_error_free) X(sd_bus_error_set_const) X(sd_bus_flush_close_unref)

#define DECLARE(n) static __typeof__(&n) p_##n;
SYMBOLS(DECLARE)

static int load_sdbus(void) {
    static const char *names[] = {"libsystemd.so.0", "libbasu.so.0", "libbasu.so", NULL};
    void *h = NULL;
    for (int i = 0; names[i] && !h; i++) h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (!h) return -1;
#define LOAD(n) if (!(p_##n = (__typeof__(&n))dlsym(h, #n))) return -1;
    SYMBOLS(LOAD)
    return 0;
}

// ---- state ---------------------------------------------------------------------------------------

#define ROOT_PATH "/org/a11y/atspi/accessible/root"
#define NODE_PREFIX "/org/a11y/atspi/accessible/"
#define NULL_PATH "/org/a11y/atspi/null"

static volatile int g_listening;
static atspi_bridge_host g_host;
static char *g_app_name;
static sd_bus *g_bus;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static atspi_bridge_node *g_nodes;
static int g_count;
static struct timespec g_taken;
static char g_desktop_name[128] = "";
static char g_desktop_path[128] = NULL_PATH;

static double age_ms(void) {
    struct timespec n; clock_gettime(CLOCK_MONOTONIC, &n);
    return (n.tv_sec - g_taken.tv_sec) * 1000.0 + (n.tv_nsec - g_taken.tv_nsec) / 1e6;
}

static void free_nodes(void) {
    for (int i = 0; i < g_count; i++) { free((void *)g_nodes[i].name); free((void *)g_nodes[i].description); free((void *)g_nodes[i].text); }
    free(g_nodes); g_nodes = NULL; g_count = 0;
}

// The nodes as of a moment ago (a client asks many small questions in a row). Call with g_lock held.
static void refresh(void) {
    g_listening = 1;   // someone is asking: start telling them what changes
    if (g_nodes && age_ms() < 250) return;
    atspi_bridge_node *fresh = NULL;
    int n = g_host.snapshot ? g_host.snapshot(g_host.ctx, &fresh) : 0;
    free_nodes();
    g_nodes = fresh; g_count = n < 0 ? 0 : n;
    clock_gettime(CLOCK_MONOTONIC, &g_taken);
}

// Which node a path names: -1 the root, >= 0 a node, -2 nothing.
static int node_of(const char *path) {
    if (!strcmp(path, ROOT_PATH)) return -1;
    size_t pl = strlen(NODE_PREFIX);
    if (strncmp(path, NODE_PREFIX, pl)) return -2;
    char *end; long v = strtol(path + pl, &end, 10);
    if (*end || end == path + pl || v < 0 || v >= g_count) return -2;
    return (int)v;
}

static void path_of(int idx, char *out, size_t cap) {
    if (idx < 0) snprintf(out, cap, "%s", ROOT_PATH); else snprintf(out, cap, NODE_PREFIX "%d", idx);
}

static const char *uname(sd_bus *b) { const char *n = NULL; p_sd_bus_get_unique_name(b, &n); return n; }

static int append_ref(sd_bus_message *m, int idx) {
    char p[96]; path_of(idx, p, sizeof p);
    return p_sd_bus_message_append(m, "(so)", uname(g_bus), p);
}

// ---- Accessible ----------------------------------------------------------------------------------

static const char *name_of(int idx) { return idx < 0 ? g_app_name : (g_nodes[idx].name ? g_nodes[idx].name : ""); }

static int prop_name(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = p_sd_bus_message_append(r, "s", n == -2 ? "" : name_of(n));
    pthread_mutex_unlock(&g_lock); return rc;
}
static int prop_description(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    const char *d = n >= 0 && g_nodes[n].description ? g_nodes[n].description : "";
    int rc = p_sd_bus_message_append(r, "s", d);
    pthread_mutex_unlock(&g_lock); return rc;
}
static int prop_parent(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = n >= 0 ? append_ref(r, -1) : p_sd_bus_message_append(r, "(so)", g_desktop_name, g_desktop_path);
    pthread_mutex_unlock(&g_lock); return rc;
}
static int prop_childcount(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = p_sd_bus_message_append(r, "i", (int32_t)(n == -1 ? g_count : 0));
    pthread_mutex_unlock(&g_lock); return rc;
}
static int prop_locale(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "s", "");
}
static int prop_id(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "s", "");
}

// A method's reply is built by hand so that handlers can fill it under the lock.
static int send_reply(sd_bus_message *r) {
    int rc = p_sd_bus_send(NULL, r, NULL);
    p_sd_bus_message_unref(r);
    return rc < 0 ? rc : 1;
}

static int m_child_at(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t i;
    if (p_sd_bus_message_read(m, "i", &i) < 0) return -1;
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    if (n != -1 || i < 0 || i >= g_count) {
        pthread_mutex_unlock(&g_lock);
        return p_sd_bus_error_set_const(e, "org.freedesktop.DBus.Error.InvalidArgs", "no such child");
    }
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    append_ref(r, i);
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int m_children(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_open_container(r, 'a', "(so)");
    if (n == -1) for (int i = 0; i < g_count; i++) append_ref(r, i);
    p_sd_bus_message_close_container(r);
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int m_index_in_parent(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "i", (int32_t)(n >= 0 ? n : -1));
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int role_of(int n) { return n < 0 ? 75 /* application */ : g_nodes[n].role; }

static int m_role(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "u", (uint32_t)role_of(node_of(p_sd_bus_message_get_path(m))));
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static const char *role_name(int role) {
    switch (role) {
    case 75: return "application"; case ATSPI_BRIDGE_ROLE_PUSH_BUTTON: return "push button";
    case ATSPI_BRIDGE_ROLE_LABEL: return "label"; case ATSPI_BRIDGE_ROLE_ENTRY: return "text";
    case ATSPI_BRIDGE_ROLE_HEADING: return "heading"; case ATSPI_BRIDGE_ROLE_CHECK_BOX: return "check box";
    case ATSPI_BRIDGE_ROLE_TOGGLE_BUTTON: return "toggle button"; case ATSPI_BRIDGE_ROLE_MENU_ITEM: return "menu item";
    case ATSPI_BRIDGE_ROLE_DIALOG: return "dialog"; case ATSPI_BRIDGE_ROLE_FRAME: return "frame";
    default: return "panel";
    }
}

static int m_role_name(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "s", role_name(role_of(node_of(p_sd_bus_message_get_path(m)))));
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int m_state(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    uint64_t st = n >= 0 ? g_nodes[n].states : (1ull << ATSPI_BRIDGE_STATE_ENABLED) | (1ull << ATSPI_BRIDGE_STATE_SENSITIVE)
                                                  | (1ull << ATSPI_BRIDGE_STATE_VISIBLE) | (1ull << ATSPI_BRIDGE_STATE_SHOWING);
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    uint32_t words[2] = {(uint32_t)st, (uint32_t)(st >> 32)};
    p_sd_bus_message_append_array(r, 'u', words, sizeof words);
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int m_attributes(sd_bus_message *m, void *u, sd_bus_error *e) {
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_open_container(r, 'a', "{ss}");
    p_sd_bus_message_close_container(r);
    return send_reply(r);
}

static int m_application(sd_bus_message *m, void *u, sd_bus_error *e) {
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    append_ref(r, -1);
    return send_reply(r);
}

static int m_interfaces(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_open_container(r, 'a', "s");
    p_sd_bus_message_append(r, "s", "org.a11y.atspi.Accessible");
    if (n == -1) p_sd_bus_message_append(r, "s", "org.a11y.atspi.Application");
    if (n >= 0) {
        p_sd_bus_message_append(r, "s", "org.a11y.atspi.Component");
        if (g_nodes[n].can_press) p_sd_bus_message_append(r, "s", "org.a11y.atspi.Action");
        if (g_nodes[n].text) p_sd_bus_message_append(r, "s", "org.a11y.atspi.Text");
        if (g_nodes[n].can_edit) p_sd_bus_message_append(r, "s", "org.a11y.atspi.EditableText");
    }
    p_sd_bus_message_close_container(r);
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

// ---- Action --------------------------------------------------------------------------------------

static int prop_nactions(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = p_sd_bus_message_append(r, "i", (int32_t)(n >= 0 && g_nodes[n].can_press ? 1 : 0));
    pthread_mutex_unlock(&g_lock); return rc;
}

static int m_action_name(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t i; p_sd_bus_message_read(m, "i", &i);
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "s", i == 0 ? "press" : "");
    return send_reply(r);
}

static int m_actions(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_open_container(r, 'a', "(sss)");
    if (n >= 0 && g_nodes[n].can_press) p_sd_bus_message_append(r, "(sss)", "press", "", "");
    p_sd_bus_message_close_container(r);
    pthread_mutex_unlock(&g_lock);
    return send_reply(r);
}

static int m_do_action(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t i; if (p_sd_bus_message_read(m, "i", &i) < 0) return -1;
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    int ok = n >= 0 && i == 0 && g_nodes[n].can_press;
    pthread_mutex_unlock(&g_lock);
    int did = ok && g_host.press ? g_host.press(g_host.ctx, n) : 0;   // not under the lock: it may ask for a snapshot
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "b", did);
    return send_reply(r);
}

// ---- Component -----------------------------------------------------------------------------------

static int m_extents(sd_bus_message *m, void *u, sd_bus_error *e) {
    uint32_t coord; p_sd_bus_message_read(m, "u", &coord);
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    int x = 0, y = 0, w = 0, h = 0;
    if (n >= 0) { x = g_nodes[n].x; y = g_nodes[n].y; w = g_nodes[n].w; h = g_nodes[n].h; }
    pthread_mutex_unlock(&g_lock);
    if (coord == 0 && n >= 0 && g_host.origin) {   // ATSPI_COORD_TYPE_SCREEN: add the window's place on the screen
        int ox = 0, oy = 0;
        if (g_host.origin(g_host.ctx, &ox, &oy)) { x += ox; y += oy; }
    }
    p_sd_bus_message_append(r, "(iiii)", x, y, w, h);
    return send_reply(r);
}

static int m_grab_focus(sd_bus_message *m, void *u, sd_bus_error *e) {
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "b", 0);
    return send_reply(r);
}

// ---- Text ----------------------------------------------------------------------------------------

// Runs an edit on the node the message is addressed to (not under the lock: the host hops to the main thread).
static int do_edit(sd_bus_message *m, int op, int a, int b, const char *s) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    int ok = n >= 0 && g_nodes[n].can_edit && g_host.edit;
    pthread_mutex_unlock(&g_lock);
    int did = ok ? g_host.edit(g_host.ctx, n, op, a, b, s) : 0;
    if (did) { pthread_mutex_lock(&g_lock); g_taken.tv_sec = 0; g_taken.tv_nsec = 0; pthread_mutex_unlock(&g_lock); }
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "b", did);
    return send_reply(r);
}
static int m_set_caret(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t o = 0; p_sd_bus_message_read(m, "i", &o);
    return do_edit(m, 3, o, o, NULL);
}
static int m_set_selection(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t num = 0, a = 0, b = 0; p_sd_bus_message_read(m, "iii", &num, &a, &b);
    return num == 0 ? do_edit(m, 4, a, b, NULL) : do_edit(m, -1, 0, 0, NULL);
}
static int m_insert_text(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t pos = 0, len = 0; const char *s = ""; p_sd_bus_message_read(m, "isi", &pos, &s, &len);
    return do_edit(m, 1, pos, pos, s);
}
static int m_delete_text(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t a = 0, b = 0; p_sd_bus_message_read(m, "ii", &a, &b);
    return do_edit(m, 2, a, b, NULL);
}
static int m_set_contents(sd_bus_message *m, void *u, sd_bus_error *e) {
    const char *s = ""; p_sd_bus_message_read(m, "s", &s);
    return do_edit(m, 5, 0, 0, s);
}

static int text_len(const char *s) {   // characters, not bytes
    int n = 0; for (; *s; s++) if (((unsigned char)*s & 0xC0) != 0x80) n++;
    return n;
}
static const char *text_at(const char *s, int chars) {   // byte position of the chars-th character
    for (; *s && chars > 0; s++) if (((unsigned char)s[1] & 0xC0) != 0x80) chars--;
    return s;
}

static int prop_charcount(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = p_sd_bus_message_append(r, "i", (int32_t)(n >= 0 && g_nodes[n].text ? text_len(g_nodes[n].text) : 0));
    pthread_mutex_unlock(&g_lock); return rc;
}
static int prop_caret(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh(); int n = node_of(path);
    int rc = p_sd_bus_message_append(r, "i", (int32_t)(n >= 0 ? g_nodes[n].caret : -1));
    pthread_mutex_unlock(&g_lock); return rc;
}

static int m_get_text(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t a, b; if (p_sd_bus_message_read(m, "ii", &a, &b) < 0) return -1;
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    char *out = strdup("");
    if (n >= 0 && g_nodes[n].text) {
        int len = text_len(g_nodes[n].text);
        if (b < 0 || b > len) b = len;
        if (a < 0) a = 0;
        if (a < b) {
            const char *p = text_at(g_nodes[n].text, a), *q = text_at(g_nodes[n].text, b);
            free(out); out = strndup(p, (size_t)(q - p));
        }
    }
    pthread_mutex_unlock(&g_lock);
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "s", out); free(out);
    return send_reply(r);
}

static int m_char_at(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t off; if (p_sd_bus_message_read(m, "i", &off) < 0) return -1;
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    int32_t cp = 0;
    if (n >= 0 && g_nodes[n].text && off >= 0 && off < text_len(g_nodes[n].text)) {
        const unsigned char *p = (const unsigned char *)text_at(g_nodes[n].text, off);
        if (p[0] < 0x80) cp = p[0];
        else if (p[0] < 0xE0) cp = (p[0] & 0x1F) << 6 | (p[1] & 0x3F);
        else if (p[0] < 0xF0) cp = (p[0] & 0x0F) << 12 | (p[1] & 0x3F) << 6 | (p[2] & 0x3F);
        else cp = (p[0] & 0x07) << 18 | (p[1] & 0x3F) << 12 | (p[2] & 0x3F) << 6 | (p[3] & 0x3F);
    }
    pthread_mutex_unlock(&g_lock);
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "i", cp);
    return send_reply(r);
}

static int m_nselections(sd_bus_message *m, void *u, sd_bus_error *e) {
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    int c = n >= 0 && g_nodes[n].text && g_nodes[n].sel_start != g_nodes[n].sel_end;
    pthread_mutex_unlock(&g_lock);
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "i", (int32_t)c);
    return send_reply(r);
}

static int m_get_selection(sd_bus_message *m, void *u, sd_bus_error *e) {
    int32_t idx; if (p_sd_bus_message_read(m, "i", &idx) < 0) return -1;
    pthread_mutex_lock(&g_lock); refresh();
    int n = node_of(p_sd_bus_message_get_path(m));
    int ok = idx == 0 && n >= 0 && g_nodes[n].text && g_nodes[n].sel_start != g_nodes[n].sel_end;
    int a = ok ? g_nodes[n].sel_start : 0, b = ok ? g_nodes[n].sel_end : 0;
    pthread_mutex_unlock(&g_lock);
    if (!ok) return p_sd_bus_error_set_const(e, "org.freedesktop.DBus.Error.InvalidArgs", "no such selection");
    sd_bus_message *r = NULL; p_sd_bus_message_new_method_return(m, &r);
    p_sd_bus_message_append(r, "ii", a < b ? a : b, a < b ? b : a);
    return send_reply(r);
}

// ---- Application ---------------------------------------------------------------------------------

static int prop_toolkit(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "s", "starling");
}
static int prop_version(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "s", "1");
}
static int prop_atspi_version(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "s", "2.1");
}
static int prop_app_id(sd_bus *b, const char *path, const char *i, const char *pr, sd_bus_message *r, void *u, sd_bus_error *e) {
    return p_sd_bus_message_append(r, "i", (int32_t)0);
}

// ---- vtables -------------------------------------------------------------------------------------

#define RO SD_BUS_VTABLE_ABSOLUTE_OFFSET
static const sd_bus_vtable accessible_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("Name", "s", prop_name, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Description", "s", prop_description, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Parent", "(so)", prop_parent, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("ChildCount", "i", prop_childcount, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Locale", "s", prop_locale, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("AccessibleId", "s", prop_id, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_METHOD("GetChildAtIndex", "i", "(so)", m_child_at, 0),
    SD_BUS_METHOD("GetChildren", "", "a(so)", m_children, 0),
    SD_BUS_METHOD("GetIndexInParent", "", "i", m_index_in_parent, 0),
    SD_BUS_METHOD("GetRole", "", "u", m_role, 0),
    SD_BUS_METHOD("GetRoleName", "", "s", m_role_name, 0),
    SD_BUS_METHOD("GetLocalizedRoleName", "", "s", m_role_name, 0),
    SD_BUS_METHOD("GetState", "", "au", m_state, 0),
    SD_BUS_METHOD("GetAttributes", "", "a{ss}", m_attributes, 0),
    SD_BUS_METHOD("GetApplication", "", "(so)", m_application, 0),
    SD_BUS_METHOD("GetInterfaces", "", "as", m_interfaces, 0),
    SD_BUS_VTABLE_END
};
static const sd_bus_vtable action_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("NActions", "i", prop_nactions, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_METHOD("GetName", "i", "s", m_action_name, 0),
    SD_BUS_METHOD("GetActions", "", "a(sss)", m_actions, 0),
    SD_BUS_METHOD("DoAction", "i", "b", m_do_action, 0),
    SD_BUS_VTABLE_END
};
static const sd_bus_vtable component_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("GetExtents", "u", "(iiii)", m_extents, 0),
    SD_BUS_METHOD("GrabFocus", "", "b", m_grab_focus, 0),
    SD_BUS_VTABLE_END
};
static const sd_bus_vtable text_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("CharacterCount", "i", prop_charcount, 0, 0),
    SD_BUS_PROPERTY("CaretOffset", "i", prop_caret, 0, 0),
    SD_BUS_METHOD("GetText", "ii", "s", m_get_text, 0),
    SD_BUS_METHOD("GetCharacterAtOffset", "i", "i", m_char_at, 0),
    SD_BUS_METHOD("GetNSelections", "", "i", m_nselections, 0),
    SD_BUS_METHOD("GetSelection", "i", "ii", m_get_selection, 0),
    SD_BUS_METHOD("SetCaretOffset", "i", "b", m_set_caret, 0),
    SD_BUS_METHOD("SetSelection", "iii", "b", m_set_selection, 0),
    SD_BUS_VTABLE_END
};
static const sd_bus_vtable editable_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("SetTextContents", "s", "b", m_set_contents, 0),
    SD_BUS_METHOD("InsertText", "isi", "b", m_insert_text, 0),
    SD_BUS_METHOD("DeleteText", "ii", "b", m_delete_text, 0),
    SD_BUS_VTABLE_END
};
static const sd_bus_vtable application_vt[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("ToolkitName", "s", prop_toolkit, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Version", "s", prop_version, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("AtspiVersion", "s", prop_atspi_version, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Id", "i", prop_app_id, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

// ---- connection ----------------------------------------------------------------------------------

// ---- events --------------------------------------------------------------------------------------
// A screen reader only speaks what it is told changed, so the bridge looks at the app a few times a
// second and sends AT-SPI signals for what differs from the last look: a node's name, its states
// (focused, checked, enabled ...), and nodes that came or went.

static void emit_object_event(const char *member, const char *path, const char *kind, int d1, int d2,
                              const char *variant_sig, int ref_idx) {
    sd_bus_message *m = NULL;
    if (p_sd_bus_message_new_signal(g_bus, &m, path, "org.a11y.atspi.Event.Object", member) < 0) return;
    p_sd_bus_message_append(m, "sii", kind, d1, d2);
    if (variant_sig && variant_sig[0] == '(') {
        char p[64]; path_of(ref_idx, p, sizeof p);
        p_sd_bus_message_append(m, "v", "(so)", uname(g_bus), p);
    } else {
        p_sd_bus_message_append(m, "v", "i", 0);
    }
    p_sd_bus_message_append(m, "a{sv}", 0);
    p_sd_bus_send(g_bus, m, NULL);
    p_sd_bus_message_unref(m);
}

static const char *state_kind(int bit) {
    switch (bit) {
    case ATSPI_BRIDGE_STATE_CHECKED: return "checked";
    case ATSPI_BRIDGE_STATE_ENABLED: return "enabled";
    case ATSPI_BRIDGE_STATE_FOCUSED: return "focused";
    case ATSPI_BRIDGE_STATE_PRESSED: return "pressed";
    case ATSPI_BRIDGE_STATE_SELECTED: return "selected";
    case ATSPI_BRIDGE_STATE_SHOWING: return "showing";
    default: return NULL;
    }
}

static int text_len(const char *s);
static void poll_events(void) {
    atspi_bridge_node *fresh = NULL;
    int n = g_host.snapshot ? g_host.snapshot(g_host.ctx, &fresh) : 0;
    if (n < 0) n = 0;
    pthread_mutex_lock(&g_lock);
    atspi_bridge_node *old = g_nodes; int oc = g_count;
    for (int i = 0; i < n && i < oc; i++) {
        char p[64]; path_of(i, p, sizeof p);
        const char *a = old[i].name ? old[i].name : "", *b = fresh[i].name ? fresh[i].name : "";
        if (strcmp(a, b)) emit_object_event("PropertyChange", p, "accessible-name", 0, 0, NULL, -1);
        if (fresh[i].text && old[i].text && strcmp(fresh[i].text, old[i].text))
            emit_object_event("TextChanged", p, "insert", 0, text_len(fresh[i].text), NULL, -1);
        if (fresh[i].caret != old[i].caret && fresh[i].caret >= 0)
            emit_object_event("TextCaretMoved", p, "", fresh[i].caret, 0, NULL, -1);
        uint64_t diff = old[i].states ^ fresh[i].states;
        for (int bit = 0; bit < 64; bit++) {
            if (!(diff >> bit & 1)) continue;
            const char *k = state_kind(bit);
            if (k) emit_object_event("StateChanged", p, k, (int)(fresh[i].states >> bit & 1), 0, NULL, -1);
        }
    }
    for (int i = oc; i < n; i++) emit_object_event("ChildrenChanged", ROOT_PATH, "add", i, 0, "(so)", i);
    for (int i = n; i < oc; i++) emit_object_event("ChildrenChanged", ROOT_PATH, "remove", i, 0, "(so)", i);
    g_nodes = old; g_count = oc;
    free_nodes();
    g_nodes = fresh; g_count = n;
    clock_gettime(CLOCK_MONOTONIC, &g_taken);
    pthread_mutex_unlock(&g_lock);
}

// Announcements: the app asks from its own thread; the bus is only touched by the serving thread, so the
// text waits in a short queue until the next turn of the loop (which is woken at least every 0.4 s).
#define ANN_MAX 8
static char *g_ann_text[ANN_MAX];
static int g_ann_level[ANN_MAX];
static int g_ann_n;

static void flush_announcements(void) {
    char *texts[ANN_MAX]; int levels[ANN_MAX]; int n;
    pthread_mutex_lock(&g_lock);
    n = g_ann_n;
    for (int i = 0; i < n; i++) { texts[i] = g_ann_text[i]; levels[i] = g_ann_level[i]; }
    g_ann_n = 0;
    pthread_mutex_unlock(&g_lock);
    for (int i = 0; i < n; i++) {
        sd_bus_message *m = NULL;
        if (p_sd_bus_message_new_signal(g_bus, &m, ROOT_PATH, "org.a11y.atspi.Event.Object", "Announcement") >= 0) {
            p_sd_bus_message_append(m, "sii", "", levels[i], 0);
            p_sd_bus_message_append(m, "v", "s", texts[i]);
            p_sd_bus_message_append(m, "a{sv}", 0);
            p_sd_bus_send(g_bus, m, NULL);
            p_sd_bus_message_unref(m);
        }
        free(texts[i]);
    }
}

// assertive: 0 polite, 1 interrupts what is being read. Returns 0 when queued, -1 when the bridge is not
// running or the queue is full.
int atspi_bridge_announce(const char *text, int assertive) {
    if (!g_bus || !text || !text[0]) return -1;
    int ok = -1;
    pthread_mutex_lock(&g_lock);
    if (g_ann_n < ANN_MAX) {
        g_ann_text[g_ann_n] = strdup(text); g_ann_level[g_ann_n] = assertive ? 1 : 0; g_ann_n++; ok = 0;
    }
    pthread_mutex_unlock(&g_lock);
    return ok;
}

static void *serve(void *arg) {
    (void)arg;
    for (;;) {
        int r;
        while ((r = p_sd_bus_process(g_bus, NULL)) > 0) {}
        if (r < 0) break;
        p_sd_bus_wait(g_bus, 400000);
        if (g_listening) poll_events();
        flush_announcements();
    }
    return NULL;
}

void atspi_bridge_set_events(int on) { g_listening = on; }

int atspi_bridge_start(const atspi_bridge_host *host, const char *app_name) {
    if (g_bus) return 0;
    if (load_sdbus() < 0) return -1;
    sd_bus *session = NULL;
    if (p_sd_bus_open_user(&session) < 0) return -2;
    sd_bus_error err = SD_BUS_ERROR_NULL;
    sd_bus_message *reply = NULL;
    int rc = p_sd_bus_call_method(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", &err, &reply, "");
    const char *addr = NULL;
    if (rc < 0 || p_sd_bus_message_read(reply, "s", &addr) < 0) { p_sd_bus_error_free(&err); p_sd_bus_flush_close_unref(session); return -3; }
    sd_bus *bus = NULL;
    if (p_sd_bus_new(&bus) < 0 || p_sd_bus_set_address(bus, addr) < 0 || p_sd_bus_set_bus_client(bus, 1) < 0 || p_sd_bus_start(bus) < 0) {
        p_sd_bus_message_unref(reply); p_sd_bus_flush_close_unref(session); return -4;
    }
    p_sd_bus_message_unref(reply);
    p_sd_bus_flush_close_unref(session);

    g_host = *host; g_app_name = strdup(app_name ? app_name : "app"); g_bus = bus;
    const char *ifaces[] = {"org.a11y.atspi.Accessible", "org.a11y.atspi.Action", "org.a11y.atspi.Component", "org.a11y.atspi.Text", "org.a11y.atspi.EditableText"};
    const sd_bus_vtable *vts[] = {accessible_vt, action_vt, component_vt, text_vt, editable_vt};
    for (int i = 0; i < 5; i++)
        if (p_sd_bus_add_fallback_vtable(bus, NULL, "/org/a11y/atspi/accessible", ifaces[i], vts[i], NULL, NULL) < 0) return -5;
    if (p_sd_bus_add_fallback_vtable(bus, NULL, ROOT_PATH, "org.a11y.atspi.Application", application_vt, NULL, NULL) < 0) return -5;

    // Tell the registry we exist; it answers with the desktop that is our root's parent.
    sd_bus_message *er = NULL;
    rc = p_sd_bus_call_method(bus, "org.a11y.atspi.Registry", ROOT_PATH, "org.a11y.atspi.Socket", "Embed", &err, &er,
                              "(so)", uname(bus), ROOT_PATH);
    if (rc >= 0) {
        const char *dn = NULL, *dp = NULL;
        if (p_sd_bus_message_read(er, "(so)", &dn, &dp) >= 0) {
            snprintf(g_desktop_name, sizeof g_desktop_name, "%s", dn);
            snprintf(g_desktop_path, sizeof g_desktop_path, "%s", dp);
        }
        p_sd_bus_message_unref(er);
    } else p_sd_bus_error_free(&err);

    pthread_t t;
    if (pthread_create(&t, NULL, serve, NULL) != 0) return -6;
    pthread_detach(t);
    return 0;
}

const char *atspi_bridge_bus_name(void) { return g_bus ? uname(g_bus) : NULL; }
