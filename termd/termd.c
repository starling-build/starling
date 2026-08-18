// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// starling-termd — terminal sessions that outlive their client.
//
// The daemon owns ptys. Everything it reads from one is appended to that
// session's ring buffer and numbered by byte offset, and every attached
// client is sent the tail. A client that disappears changes nothing: the
// shell keeps running, the ring keeps filling, and the next ATTACH resumes
// at whatever offset the client got to. See docs/plans/remote-terminal.md.
//
// It never renders a screen. The wire format is the pty byte stream, so
// there is no second emulator here to disagree with the client's.
//
//   starling-termd --serve     run the daemon (idempotent; exits if one is up)
//   starling-termd --stdio     bridge stdin/stdout to it (what ssh runs)
//   starling-termd --list      one line per session, for humans
//
// No dependencies beyond libc and the platform layer: this is meant to be one
// binary you scp to a machine that has nothing else on it. Everything that
// differs between Linux and Windows lives in plat.h and its two
// implementations; this file is the same code on both.
//
// Every session's pty is read by its own thread (see plat.h for why), so the
// tables below are touched from more than one thread and every access goes
// through g_lock.

#define _GNU_SOURCE
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "plat.h"
#include "protocol.h"

#ifndef TERMD_RING_BYTES
// Eight megabytes of history per session: enough that a detached session
// replays exactly for any ordinary workload, and small enough that a dozen
// idle sessions cost nothing worth measuring.
#define TERMD_RING_BYTES (8u << 20)
#endif

#define MAX_SESSIONS 64
#define MAX_CLIENTS 64
#define READ_CHUNK 65536

// ── logging ─────────────────────────────────────────────────────────────

static int g_verbose = 0;

static void logf_(const char *fmt, ...) {
    if (!g_verbose) return;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[termd] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

// ── sessions ────────────────────────────────────────────────────────────

struct session {
    uint32_t id;
    // How a human addresses this session: "iOS dev", not 12. Empty for a
    // session opened without one. Unique across live sessions — the name
    // lookup has to be unambiguous for a named OPEN to reattach.
    char name[TERMD_MAX_NAME];
    int used;
    plat_pty *pty;   // NULL once the reader has seen end of output
    int alive;
    int status;      // exit code once !alive
    uint16_t cols, rows;

    // The ring. `head` is the total number of bytes this session has ever
    // produced, which is also the offset just past the newest byte; the
    // oldest byte still held is at `head - filled`.
    uint8_t *ring;
    uint64_t head;
    uint64_t filled;
};

struct client {
    int used;
    sock_t fd;
    uint32_t session;   // 0 = not attached
    uint64_t sent;      // next byte offset to send
    uint64_t acked;
    // Inbound framing state
    uint8_t hdr[TERMD_HEADER_LEN];
    size_t hdr_have;
    uint8_t *payload;
    size_t payload_len, payload_have;
    // Outbound buffer (a slow client must not block the daemon)
    uint8_t *out;
    size_t out_len, out_cap, out_sent;
    int dead;      // transport is broken — drop now
    int closing;   // we are done with it, but its last frame must still go
};

// A workspace: a name, the sessions in it, and a blob the daemon stores and
// never reads. See protocol.h — the whole point is that adding a layout
// feature later touches the client and not this file.
struct workspace {
    int used;
    uint32_t id;
    char name[TERMD_MAX_NAME];
    uint32_t sessions[MAX_SESSIONS];
    uint16_t nsessions;
    uint8_t *blob;
    uint32_t blob_len;
};

static struct session g_sessions[MAX_SESSIONS];
static struct client g_clients[MAX_CLIENTS];
static struct workspace g_workspaces[TERMD_MAX_WORKSPACES];
static uint32_t g_next_id = 1;
static uint32_t g_next_ws_id = 1;

// Guards both tables. Held by the main loop whenever it is not parked in
// plat_poll, and by every reader thread while it appends and pumps. The
// reader threads are the reason this exists at all.
static plat_mutex *g_lock;

static struct session *session_by_id(uint32_t id) {
    for (int i = 0; i < MAX_SESSIONS; i++)
        if (g_sessions[i].used && g_sessions[i].id == id) return &g_sessions[i];
    return NULL;
}

static struct session *session_by_name(const char *name) {
    if (!name || !*name) return NULL;
    for (int i = 0; i < MAX_SESSIONS; i++)
        if (g_sessions[i].used && !strcmp(g_sessions[i].name, name))
            return &g_sessions[i];
    return NULL;
}

static struct workspace *ws_by_id(uint32_t id) {
    for (int i = 0; i < TERMD_MAX_WORKSPACES; i++)
        if (g_workspaces[i].used && g_workspaces[i].id == id)
            return &g_workspaces[i];
    return NULL;
}

static struct workspace *ws_by_name(const char *name) {
    if (!name || !*name) return NULL;
    for (int i = 0; i < TERMD_MAX_WORKSPACES; i++)
        if (g_workspaces[i].used && !strcmp(g_workspaces[i].name, name))
            return &g_workspaces[i];
    return NULL;
}

// A name arrives from a human and leaves through --list and every client's
// UI, so control bytes are dropped rather than trusted — a name carrying an
// escape sequence would repaint the screen of whoever listed it. Edge
// whitespace goes too: "iOS dev " and "iOS dev" are the same handle to the
// person typing them, and a name that only matches when invisible padding
// matches is a name that mysteriously opens a second session. The rest is
// opaque bytes; the daemon never interprets the encoding.
static void name_sanitize(char *dst, const uint8_t *src, size_t len) {
    while (len && (src[0] == ' ' || src[0] == '\t')) { src++; len--; }
    while (len && (src[len - 1] == ' ' || src[len - 1] == '\t')) len--;
    size_t n = 0;
    for (size_t i = 0; i < len && n + 1 < TERMD_MAX_NAME; i++) {
        if (src[i] < 0x20 || src[i] == 0x7f) continue;
        dst[n++] = (char)src[i];
    }
    dst[n] = 0;
}

static void ring_append(struct session *s, const uint8_t *data, size_t len) {
    if (len >= TERMD_RING_BYTES) {
        // A single read bigger than the ring: keep only its tail.
        data += len - TERMD_RING_BYTES;
        len = TERMD_RING_BYTES;
    }
    size_t off = (size_t)(s->head % TERMD_RING_BYTES);
    size_t first = TERMD_RING_BYTES - off;
    if (first > len) first = len;
    memcpy(s->ring + off, data, first);
    if (len > first) memcpy(s->ring, data + first, len - first);
    s->head += len;
    s->filled += len;
    if (s->filled > TERMD_RING_BYTES) s->filled = TERMD_RING_BYTES;
}

// Copies up to `max` bytes starting at absolute offset `from` into `dst`.
// Returns how many, and clamps `from` up to the oldest byte still held.
static size_t ring_read(struct session *s, uint64_t *from, uint8_t *dst,
                        size_t max) {
    uint64_t oldest = s->head - s->filled;
    if (*from < oldest) *from = oldest;
    if (*from >= s->head) return 0;
    uint64_t avail = s->head - *from;
    size_t n = avail > max ? max : (size_t)avail;
    size_t off = (size_t)(*from % TERMD_RING_BYTES);
    size_t first = TERMD_RING_BYTES - off;
    if (first > n) first = n;
    memcpy(dst, s->ring + off, first);
    if (n > first) memcpy(dst + first, s->ring, n - first);
    return n;
}

struct reader_arg {
    uint32_t id;
    plat_pty *pty;
};

static void session_reader(void *arg);

// Called with g_lock held.
static struct session *session_open(uint16_t cols, uint16_t rows,
                                    const char *name, const char *command) {
    struct session *s = NULL;
    for (int i = 0; i < MAX_SESSIONS; i++)
        if (!g_sessions[i].used) { s = &g_sessions[i]; break; }
    if (!s) return NULL;

    memset(s, 0, sizeof(*s));
    s->ring = malloc(TERMD_RING_BYTES);
    if (!s->ring) return NULL;

    plat_pty *pty = plat_pty_open(cols, rows, command);
    if (!pty) {
        free(s->ring);
        memset(s, 0, sizeof(*s));
        return NULL;
    }

    s->used = 1;
    s->id = g_next_id++;
    if (name) snprintf(s->name, sizeof(s->name), "%s", name);
    s->pty = pty;
    s->alive = 1;
    s->cols = cols ? cols : 80;
    s->rows = rows ? rows : 24;

    // The reader owns the pty and knows its session only by id. It cannot
    // hold the slot pointer: by the time it wakes, the session may have been
    // closed and the slot reused, and the pointer would be aimed at a
    // different session. It cannot look the pty up either — it has to be able
    // to free it after the slot is gone.
    struct reader_arg *ra = malloc(sizeof(*ra));
    if (!ra) {
        plat_pty_shutdown(pty);
        plat_pty_free(pty);
        free(s->ring);
        memset(s, 0, sizeof(*s));
        return NULL;
    }
    ra->id = s->id;
    ra->pty = pty;
    if (plat_thread_spawn(session_reader, ra) != 0) {
        free(ra);
        plat_pty_shutdown(pty);
        plat_pty_free(pty);
        free(s->ring);
        memset(s, 0, sizeof(*s));
        return NULL;
    }
    logf_("session %u opened (%ux%u)", s->id, s->cols, s->rows);
    return s;
}

// Called with g_lock held.
static void session_close(struct session *s) {
    if (!s->used) return;
    logf_("session %u closed", s->id);
    // Shut down but do not free: the reader thread may be parked inside
    // plat_pty_read on this very handle. The shutdown is what wakes it, and
    // it frees the pty itself on the way out.
    if (s->pty) plat_pty_shutdown(s->pty);
    free(s->ring);
    memset(s, 0, sizeof(*s));
}

// ── framing ─────────────────────────────────────────────────────────────

static void put_u16(uint8_t *p, uint16_t v) { p[0] = v & 0xff; p[1] = v >> 8; }
static void put_u32(uint8_t *p, uint32_t v) {
    p[0] = v & 0xff; p[1] = (v >> 8) & 0xff;
    p[2] = (v >> 16) & 0xff; p[3] = (v >> 24) & 0xff;
}
static void put_u64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}
static uint16_t get_u16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t get_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}
static uint64_t get_u64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= (uint64_t)p[i] << (8 * i);
    return v;
}

static void client_out(struct client *c, uint8_t type, const uint8_t *payload,
                       size_t len) {
    if (c->dead) return;
    size_t need = c->out_len + TERMD_HEADER_LEN + len;
    if (need > c->out_cap) {
        size_t cap = c->out_cap ? c->out_cap : 65536;
        while (cap < need) cap *= 2;
        uint8_t *grown = realloc(c->out, cap);
        if (!grown) { c->dead = 1; return; }
        c->out = grown;
        c->out_cap = cap;
    }
    uint8_t *p = c->out + c->out_len;
    p[0] = type;
    p[1] = 0;
    put_u16(p + 2, 0);
    put_u32(p + 4, (uint32_t)len);
    if (len) memcpy(p + TERMD_HEADER_LEN, payload, len);
    c->out_len += TERMD_HEADER_LEN + len;
}

// Two payload pieces in one frame, so a blob is not copied into a scratch
// buffer only to be copied again into the out queue.
static void client_out_two(struct client *c, uint8_t type,
                           const uint8_t *a, size_t alen,
                           const uint8_t *b, size_t blen) {
    if (c->dead) return;
    size_t len = alen + blen;
    size_t need = c->out_len + TERMD_HEADER_LEN + len;
    if (need > c->out_cap) {
        size_t cap = c->out_cap ? c->out_cap : 65536;
        while (cap < need) cap *= 2;
        uint8_t *grown = realloc(c->out, cap);
        if (!grown) { c->dead = 1; return; }
        c->out = grown;
        c->out_cap = cap;
    }
    uint8_t *p = c->out + c->out_len;
    p[0] = type;
    p[1] = 0;
    put_u16(p + 2, 0);
    put_u32(p + 4, (uint32_t)len);
    if (alen) memcpy(p + TERMD_HEADER_LEN, a, alen);
    if (blen) memcpy(p + TERMD_HEADER_LEN + alen, b, blen);
    c->out_len += TERMD_HEADER_LEN + len;
}

// The reply to every workspace WRITE: the client learns the id (which it may
// not have known, on an idempotent create) and that the write landed.
static void ws_send_info(struct client *c, const struct workspace *w) {
    uint8_t buf[6 + TERMD_MAX_NAME];
    size_t nlen = strlen(w->name);
    put_u32(buf, w->id);
    put_u16(buf + 4, (uint16_t)nlen);
    memcpy(buf + 6, w->name, nlen);
    client_out(c, TERMD_WS_INFO, buf, 6 + nlen);
}

static void client_error(struct client *c, uint16_t code, const char *msg) {
    uint8_t buf[256];
    size_t n = strlen(msg);
    if (n > sizeof(buf) - 2) n = sizeof(buf) - 2;
    put_u16(buf, code);
    memcpy(buf + 2, msg, n);
    client_out(c, TERMD_ERROR, buf, 2 + n);
}

static void client_drop(struct client *c) {
    if (!c->used) return;
    logf_("client detached from session %u", c->session);
    plat_sock_close(c->fd);
    free(c->payload);
    free(c->out);
    memset(c, 0, sizeof(*c));
}

// ── client requests ─────────────────────────────────────────────────────

static void handle_frame(struct client *c, uint8_t type, const uint8_t *p,
                         size_t len) {
    switch (type) {
    case TERMD_HELLO: {
        uint16_t version = len >= 2 ? get_u16(p) : 0;
        if (version != TERMD_PROTOCOL_VERSION) {
            // closing, not dead: an error the client never receives is the
            // same as a silent disconnect, which is what this frame exists
            // to avoid.
            client_error(c, TERMD_ERR_VERSION, "protocol version mismatch");
            c->closing = 1;
            return;
        }
        uint16_t count = 0;
        for (int i = 0; i < MAX_SESSIONS; i++) if (g_sessions[i].used) count++;
        uint8_t reply[4];
        put_u16(reply, TERMD_PROTOCOL_VERSION);
        put_u16(reply + 2, count);
        client_out(c, TERMD_HELLO_OK, reply, sizeof(reply));
        break;
    }
    case TERMD_LIST: {
        uint8_t buf[2 + MAX_SESSIONS * (19 + TERMD_MAX_NAME)];
        size_t n = 2;
        uint16_t count = 0;
        for (int i = 0; i < MAX_SESSIONS; i++) {
            struct session *s = &g_sessions[i];
            if (!s->used) continue;
            put_u32(buf + n, s->id);          n += 4;
            put_u16(buf + n, s->cols);        n += 2;
            put_u16(buf + n, s->rows);        n += 2;
            buf[n++] = (uint8_t)s->alive;
            put_u64(buf + n, s->head);        n += 8;
            size_t nlen = strlen(s->name);
            put_u16(buf + n, (uint16_t)nlen); n += 2;
            memcpy(buf + n, s->name, nlen);   n += nlen;
            count++;
        }
        put_u16(buf, count);
        client_out(c, TERMD_LIST_REPLY, buf, n);
        break;
    }
    case TERMD_OPEN: {
        uint16_t cols = len >= 2 ? get_u16(p) : 80;
        uint16_t rows = len >= 4 ? get_u16(p + 2) : 24;
        char name[TERMD_MAX_NAME] = {0};
        size_t off = 4;
        if (len >= 6) {
            uint16_t nlen = get_u16(p + 4);
            off = 6;
            if (nlen > len - off) nlen = (uint16_t)(len - off);
            name_sanitize(name, p + off, nlen);
            off += nlen;
        }
        char command[4096];
        size_t clen = len > off ? len - off : 0;
        if (clen >= sizeof(command)) clen = sizeof(command) - 1;
        memcpy(command, p + off, clen);
        command[clen] = 0;

        // A named OPEN is attach-or-create: the name is the handle, so
        // asking for one that exists resumes it rather than forking a
        // second shell beside it. Resuming from the oldest byte still held
        // is what a human means by "get me back into iOS dev" — the client
        // replays it into its emulator and the screen comes back.
        struct session *s = session_by_name(name);
        uint64_t from = 0;
        if (s) {
            from = s->head - s->filled;
            if (cols && rows && s->alive) {
                plat_pty_resize(s->pty, cols, rows);
                s->cols = cols;
                s->rows = rows;
            }
            logf_("client re-opened session %u by name \"%s\" from %llu", s->id,
                  s->name, (unsigned long long)from);
        } else {
            s = session_open(cols, rows, name, command);
            if (!s) {
                client_error(c, TERMD_ERR_OPEN_FAILED, "could not open a session");
                return;
            }
        }
        c->session = s->id;
        c->sent = from;
        c->acked = from;
        uint8_t reply[12];
        put_u32(reply, s->id);
        put_u64(reply + 4, from);
        client_out(c, TERMD_ATTACHED, reply, sizeof(reply));
        break;
    }
    case TERMD_ATTACH: {
        if (len < 16) { client_error(c, TERMD_ERR_BAD_FRAME, "short attach"); return; }
        uint32_t id = get_u32(p);
        uint64_t from = get_u64(p + 4);
        uint16_t cols = get_u16(p + 12), rows = get_u16(p + 14);
        struct session *s = session_by_id(id);
        if (!s) { client_error(c, TERMD_ERR_NO_SESSION, "no such session"); return; }
        // Clamp to what the ring still holds and tell the client where it
        // will actually resume — a gap is visible, never silent.
        uint64_t oldest = s->head - s->filled;
        if (from < oldest) from = oldest;
        if (from > s->head) from = s->head;
        c->session = id;
        c->sent = from;
        c->acked = from;
        if (cols && rows && s->alive) {
            plat_pty_resize(s->pty, cols, rows);
            s->cols = cols;
            s->rows = rows;
        }
        uint8_t reply[12];
        put_u32(reply, id);
        put_u64(reply + 4, from);
        client_out(c, TERMD_ATTACHED, reply, sizeof(reply));
        logf_("client attached to session %u from %llu (head %llu)", id,
              (unsigned long long)from, (unsigned long long)s->head);
        break;
    }
    case TERMD_INPUT: {
        struct session *s = session_by_id(c->session);
        if (!s || !s->alive || !s->pty) return;
        size_t off = 0;
        while (off < len) {
            long n = plat_pty_write(s->pty, p + off, len - off);
            if (n > 0) { off += (size_t)n; continue; }
            break;
        }
        break;
    }
    case TERMD_RESIZE: {
        struct session *s = session_by_id(c->session);
        if (!s || len < 4) return;
        uint16_t cols = get_u16(p), rows = get_u16(p + 2);
        if (!cols || !rows) return;
        s->cols = cols;
        s->rows = rows;
        if (s->alive) plat_pty_resize(s->pty, cols, rows);
        break;
    }
    case TERMD_ACK:
        if (len >= 8) c->acked = get_u64(p);
        break;
    case TERMD_DETACH:
        c->session = 0;
        break;
    // --- workspaces -----------------------------------------------------
    // Five frames, all thin, and none of them looks inside the blob. The
    // reply to a write is WS_INFO rather than silence, so a client knows the
    // daemon took it.
    case TERMD_WS_CREATE: {
        char name[TERMD_MAX_NAME] = {0};
        if (len >= 2) {
            uint16_t nlen = get_u16(p);
            if (nlen > len - 2) nlen = (uint16_t)(len - 2);
            name_sanitize(name, p + 2, nlen);
        }
        if (!*name) { client_error(c, TERMD_ERR_BAD_FRAME, "workspace needs a name"); return; }
        // Idempotent by name, exactly like a named OPEN: a client that lost
        // its id reconnects with the name alone and gets the same workspace
        // rather than a second one beside it.
        struct workspace *w = ws_by_name(name);
        if (!w) {
            for (int i = 0; i < TERMD_MAX_WORKSPACES; i++) {
                if (!g_workspaces[i].used) { w = &g_workspaces[i]; break; }
            }
            if (!w) { client_error(c, TERMD_ERR_TOO_MANY, "too many workspaces"); return; }
            memset(w, 0, sizeof(*w));
            w->used = 1;
            w->id = g_next_ws_id++;
            snprintf(w->name, sizeof(w->name), "%s", name);
            logf_("workspace %u created \"%s\"", w->id, w->name);
        }
        ws_send_info(c, w);
        return;
    }

    case TERMD_WS_ADD: {
        if (len < 8) { client_error(c, TERMD_ERR_BAD_FRAME, "short ws_add"); return; }
        struct workspace *w = ws_by_id(get_u32(p));
        if (!w) { client_error(c, TERMD_ERR_NO_WORKSPACE, "no such workspace"); return; }
        uint32_t sid = get_u32(p + 4);
        if (!session_by_id(sid)) { client_error(c, TERMD_ERR_NO_SESSION, "no such session"); return; }
        int already = 0;
        for (uint16_t i = 0; i < w->nsessions; i++) if (w->sessions[i] == sid) already = 1;
        if (!already) {
            if (w->nsessions >= MAX_SESSIONS) {
                client_error(c, TERMD_ERR_TOO_MANY, "workspace full"); return;
            }
            w->sessions[w->nsessions++] = sid;
        }
        ws_send_info(c, w);
        return;
    }

    case TERMD_WS_SET_META: {
        if (len < 4) { client_error(c, TERMD_ERR_BAD_FRAME, "short ws_set_meta"); return; }
        struct workspace *w = ws_by_id(get_u32(p));
        if (!w) { client_error(c, TERMD_ERR_NO_WORKSPACE, "no such workspace"); return; }
        size_t blen = len - 4;
        if (blen > TERMD_MAX_BLOB) { client_error(c, TERMD_ERR_BAD_FRAME, "blob too large"); return; }
        uint8_t *fresh = NULL;
        if (blen) {
            fresh = malloc(blen);
            if (!fresh) { client_error(c, TERMD_ERR_BAD_FRAME, "out of memory"); return; }
            memcpy(fresh, p + 4, blen);
        }
        free(w->blob);
        w->blob = fresh;
        w->blob_len = (uint32_t)blen;
        ws_send_info(c, w);
        return;
    }

    case TERMD_WS_GET_META: {
        if (len < 4) { client_error(c, TERMD_ERR_BAD_FRAME, "short ws_get_meta"); return; }
        struct workspace *w = ws_by_id(get_u32(p));
        if (!w) { client_error(c, TERMD_ERR_NO_WORKSPACE, "no such workspace"); return; }
        uint8_t hdr[4];
        put_u32(hdr, w->id);
        // Two pieces rather than one buffer: a blob is up to 16 KB and there
        // is no reason to copy it again on the way out.
        client_out_two(c, TERMD_WS_META, hdr, 4, w->blob, w->blob_len);
        return;
    }

    case TERMD_WS_LIST: {
        uint16_t count = 0;
        for (int i = 0; i < TERMD_MAX_WORKSPACES; i++) if (g_workspaces[i].used) count++;
        size_t cap = 2 + (size_t)TERMD_MAX_WORKSPACES
                   * (12 + MAX_SESSIONS * 4 + TERMD_MAX_NAME);
        uint8_t *buf = malloc(cap);
        if (!buf) { client_error(c, TERMD_ERR_BAD_FRAME, "out of memory"); return; }
        size_t off = 0;
        put_u16(buf, count); off = 2;
        for (int i = 0; i < TERMD_MAX_WORKSPACES; i++) {
            struct workspace *w = &g_workspaces[i];
            if (!w->used) continue;
            put_u32(buf + off, w->id); off += 4;
            put_u32(buf + off, w->blob_len); off += 4;
            put_u16(buf + off, w->nsessions); off += 2;
            for (uint16_t k = 0; k < w->nsessions; k++) {
                put_u32(buf + off, w->sessions[k]); off += 4;
            }
            size_t nlen = strlen(w->name);
            put_u16(buf + off, (uint16_t)nlen); off += 2;
            memcpy(buf + off, w->name, nlen); off += nlen;
        }
        client_out(c, TERMD_WS_LIST_REPLY, buf, off);
        free(buf);
        return;
    }

    case TERMD_PING:
        client_out(c, TERMD_PONG, p, len);
        break;
    case TERMD_PONG:
        break;
    default:
        client_error(c, TERMD_ERR_BAD_FRAME, "unknown frame");
        break;
    }
}

static void client_readable(struct client *c) {
    uint8_t buf[READ_CHUNK];
    long n = plat_sock_read(c->fd, buf, sizeof(buf));
    if (n == 0) { c->dead = 1; return; }
    if (n < 0) {
        if (plat_would_block()) return;
        c->dead = 1;
        return;
    }
    size_t off = 0;
    while (off < (size_t)n) {
        if (c->hdr_have < TERMD_HEADER_LEN) {
            size_t want = TERMD_HEADER_LEN - c->hdr_have;
            size_t have = (size_t)n - off;
            size_t take = want < have ? want : have;
            memcpy(c->hdr + c->hdr_have, buf + off, take);
            c->hdr_have += take;
            off += take;
            if (c->hdr_have < TERMD_HEADER_LEN) return;
            uint32_t plen = get_u32(c->hdr + 4);
            if (plen > TERMD_MAX_PAYLOAD) { c->dead = 1; return; }
            c->payload_len = plen;
            c->payload_have = 0;
            free(c->payload);
            c->payload = plen ? malloc(plen) : NULL;
            if (plen && !c->payload) { c->dead = 1; return; }
        }
        size_t want = c->payload_len - c->payload_have;
        size_t have = (size_t)n - off;
        size_t take = want < have ? want : have;
        if (take) {
            memcpy(c->payload + c->payload_have, buf + off, take);
            c->payload_have += take;
            off += take;
        }
        if (c->payload_have == c->payload_len) {
            handle_frame(c, c->hdr[0], c->payload, c->payload_len);
            c->hdr_have = 0;
            c->payload_len = 0;
            c->payload_have = 0;
            if (c->dead) return;
        }
    }
}

static void client_flush(struct client *c) {
    while (c->out_sent < c->out_len) {
        long n = plat_sock_write(c->fd, c->out + c->out_sent,
                                 c->out_len - c->out_sent);
        if (n > 0) { c->out_sent += (size_t)n; continue; }
        if (n < 0 && plat_would_block()) return;
        c->dead = 1;
        return;
    }
    c->out_len = 0;
    c->out_sent = 0;
}

// Everything a session has that this client has not been sent yet.
static void client_pump(struct client *c) {
    struct session *s = session_by_id(c->session);
    if (!s) return;
    uint8_t chunk[READ_CHUNK];
    while (c->sent < s->head) {
        uint64_t from = c->sent;
        size_t n = ring_read(s, &from, chunk + 8, sizeof(chunk) - 8);
        if (!n) break;
        put_u64(chunk, from);
        client_out(c, TERMD_DATA, chunk, n + 8);
        c->sent = from + n;
        // Backpressure: a client that is not draining gets one pass and then
        // waits, rather than growing the buffer without bound.
        if (c->out_len > (4u << 20)) break;
    }
}

// ── the daemon ──────────────────────────────────────────────────────────

static void socket_path(char *out, size_t len) {
    const char *dir = getenv("STARLING_TERMD_SOCKET");
    if (dir && *dir) { snprintf(out, len, "%s", dir); return; }
    plat_default_socket_path(out, len);
}

static sock_t listen_socket(void) {
    char path[256];
    socket_path(path, sizeof(path));
    return plat_listen_unix(path);
}

static sock_t connect_socket(void) {
    char path[256];
    socket_path(path, sizeof(path));
    return plat_connect_unix(path);
}

// One per session, for the reason in plat.h: the pty cannot join the socket
// wait on Windows, so it gets its own thread on both platforms.
//
// Delivery happens here rather than being left for the main loop to notice.
// The loop is parked in plat_poll on sockets alone and nothing in that set
// becomes readable when a pty produces output, so waiting for it would add a
// whole poll timeout of latency to every keystroke's echo.
static void session_reader(void *arg) {
    struct reader_arg *ra = arg;
    uint8_t buf[READ_CHUNK];

    for (;;) {
        long n = plat_pty_read(ra->pty, buf, sizeof(buf));
        if (n <= 0) break;      // 0 = the child is gone; <0 = the pty broke

        plat_mutex_lock(g_lock);
        struct session *s = session_by_id(ra->id);
        if (!s) { plat_mutex_unlock(g_lock); break; }   // closed under us
        ring_append(s, buf, (size_t)n);
        for (int i = 0; i < MAX_CLIENTS; i++) {
            struct client *c = &g_clients[i];
            if (c->used && !c->dead && !c->closing && c->session == ra->id) {
                client_pump(c);
                client_flush(c);
            }
        }
        plat_mutex_unlock(g_lock);
    }

    // End of output. Keep the session and its ring — reattaching to read the
    // last words is the point — but let go of the pty.
    plat_mutex_lock(g_lock);
    struct session *s = session_by_id(ra->id);
    if (s) {
        plat_pty_exited(ra->pty, &s->status);
        s->alive = 0;
        s->pty = NULL;
        logf_("session %u child exited", ra->id);
    }
    plat_mutex_unlock(g_lock);

    // Safe now: the slot no longer points at it, so session_close cannot
    // reach this pty and no other thread is inside a call on it.
    plat_pty_free(ra->pty);
    free(ra);
}

// Markers a terminal multiplexer leaves in the environment of whatever it
// started. They are inherited by every pty this daemon forks and BELIEVED
// there: a daemon started from inside tmux hands each session a TMUX and a
// TERM_PROGRAM=tmux, and full-screen programs that adapt their drawing to
// their host — Claude Code among them — then draw for a tmux that is not
// there. Setting TERM alone does not cover it, which is what makes the
// symptom look like a rendering bug in the client rather than an environment
// leak in the server.
//
// Scrubbed once here rather than per spawn because the daemon outlives the
// shell that started it, so this is the only moment the leak can enter. Same
// list as build/run-desktop.sh and build/session/starling-session, which fixed
// this for the desktop's own launchers; termd is the third and was missed.
static void scrub_multiplexer_env(void) {
    static const char *const markers[] = {
        "TMUX", "TMUX_PANE", "TERM_PROGRAM", "TERM_PROGRAM_VERSION",
        "STY", "WINDOW",
    };
    for (size_t i = 0; i < sizeof(markers) / sizeof(*markers); i++)
        plat_env_unset(markers[i]);
}

static int serve(int idle_exit_seconds) {
    plat_init();
    plat_set_process_name("starling-termd");
    scrub_multiplexer_env();
    if (!g_lock) g_lock = plat_mutex_new();

    sock_t lfd = listen_socket();
    if (lfd == BAD_SOCK) {
        if (plat_addr_in_use()) return 0;   // someone else is already serving
        fprintf(stderr, "termd: cannot listen on the socket\n");
        return 1;
    }
    logf_("serving");

    time_t last_activity = time(NULL);
    for (;;) {
        // Only sockets. The ptys are on their own threads, so there is
        // nothing else this call could usefully wait on.
        plat_pollfd pfds[1 + MAX_CLIENTS];
        int map_client[1 + MAX_CLIENTS];

        plat_mutex_lock(g_lock);
        int n = 0;
        pfds[n].fd = lfd;
        pfds[n].events = POLLIN;
        pfds[n].revents = 0;
        map_client[n] = -1;
        n++;
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (!g_clients[i].used) continue;
            map_client[n] = i;
            pfds[n].fd = g_clients[i].fd;
            pfds[n].events = (short)((g_clients[i].closing ? 0 : POLLIN)
                           | (g_clients[i].out_len ? POLLOUT : 0));
            pfds[n].revents = 0;
            n++;
        }
        plat_mutex_unlock(g_lock);

        int rc = plat_poll(pfds, n, 1000);
        if (rc < 0 && !plat_would_block()) break;

        plat_mutex_lock(g_lock);

        if (pfds[0].revents & POLLIN) {
            sock_t cfd = accept(lfd, NULL, NULL);
            if (cfd != BAD_SOCK) {
                struct client *c = NULL;
                for (int i = 0; i < MAX_CLIENTS; i++)
                    if (!g_clients[i].used) { c = &g_clients[i]; break; }
                if (!c) { plat_sock_close(cfd); }
                else {
                    memset(c, 0, sizeof(*c));
                    c->used = 1;
                    c->fd = cfd;
                    plat_sock_nonblock(cfd);
                    logf_("client connected");
                }
                last_activity = time(NULL);
            }
        }

        // Indexed by the map built above rather than by matching on the fd:
        // a reader thread may have dropped a client while we were in poll,
        // and a recycled slot would otherwise be mistaken for the old one.
        for (int k = 1; k < n; k++) {
            int ci = map_client[k];
            if (ci < 0) continue;
            struct client *c = &g_clients[ci];
            if (!c->used || c->fd != pfds[k].fd) continue;
            if ((pfds[k].revents & POLLIN) && !c->closing) client_readable(c);
            if (!c->dead && (pfds[k].revents & POLLOUT)) client_flush(c);
            last_activity = time(NULL);
        }

        for (int i = 0; i < MAX_CLIENTS; i++) {
            struct client *c = &g_clients[i];
            if (!c->used) continue;
            if (!c->dead && !c->closing) client_pump(c);
            if (!c->dead && c->out_len) client_flush(c);
            if (c->dead || (c->closing && c->out_len == 0)) client_drop(c);
        }

        // A session whose child is gone and whose bytes have all been read
        // by nobody in particular is kept: reattaching to read the exit is
        // the point. It goes when a client asks, or when the daemon exits.

        int stop = 0;
        if (idle_exit_seconds > 0) {
            int any_client = 0, any_session = 0;
            for (int i = 0; i < MAX_CLIENTS; i++) any_client |= g_clients[i].used;
            for (int i = 0; i < MAX_SESSIONS; i++) any_session |= g_sessions[i].used;
            if (!any_client && !any_session &&
                time(NULL) - last_activity > idle_exit_seconds) {
                logf_("idle, exiting");
                stop = 1;
            }
        }

        // Every path out of the loop leaves the lock released, which is why
        // the decision is a flag rather than a break from inside the section.
        plat_mutex_unlock(g_lock);
        if (stop) break;
    }
    plat_sock_close(lfd);
    char path[256];
    socket_path(path, sizeof(path));
    plat_unlink(path);
    return 0;
}

// ── the ssh-side bridge ─────────────────────────────────────────────────

// Starts a daemon if one is not running, then relays stdin/stdout to its
// socket. This is what `ssh host starling-termd --stdio` runs, so the
// client's transport is one process away from the sessions and nothing
// needs a network port.
// stdin is not a socket on either platform, and on Windows it cannot be
// waited on together with one at all. So the bridge is two halves: this
// thread carries stdin to the daemon, the main thread carries the daemon to
// stdout. Either half ending takes the process down, which is what closes
// the ssh channel.
struct bridge {
    sock_t fd;
    int done;
};

static void bridge_stdin(void *arg) {
    struct bridge *b = arg;
    uint8_t buf[READ_CHUNK];
    for (;;) {
        long got = plat_stdin_read(buf, sizeof(buf));
        if (got <= 0) break;
        size_t off = 0;
        while (off < (size_t)got) {
            long w = plat_sock_write(b->fd, buf + off, (size_t)got - off);
            if (w > 0) { off += (size_t)w; continue; }
            if (w < 0 && plat_would_block()) { plat_sleep_ms(1); continue; }
            goto out;
        }
    }
out:
    b->done = 1;
    // Wake the other half: it is parked in a blocking read on this socket and
    // would otherwise sit there until the daemon happened to say something.
    plat_sock_shutdown(b->fd);
}

static int stdio_bridge(void) {
    plat_init();
    sock_t fd = connect_socket();
    if (fd == BAD_SOCK) {
        if (plat_spawn_daemon(3600) != 0) {
            fprintf(stderr, "termd: could not start the daemon\n");
            return 1;
        }
        for (int i = 0; i < 100 && fd == BAD_SOCK; i++) {
            plat_sleep_ms(20);
            fd = connect_socket();
        }
        if (fd == BAD_SOCK) {
            fprintf(stderr, "termd: could not start or reach the daemon\n");
            return 1;
        }
    }

    struct bridge b;
    b.fd = fd;
    b.done = 0;
    if (plat_thread_spawn(bridge_stdin, &b) != 0) {
        plat_sock_close(fd);
        return 1;
    }

    uint8_t buf[READ_CHUNK];
    while (!b.done) {
        long n = plat_sock_read(fd, buf, sizeof(buf));
        if (n == 0) break;
        if (n < 0) {
            if (plat_would_block()) { plat_sleep_ms(1); continue; }
            break;
        }
        if (plat_stdout_write(buf, (size_t)n) < 0) break;
    }
    plat_sock_close(fd);
    return 0;
}

// ── attach: put a session on this terminal ──────────────────────────────
//
// What `starling-termd "iOS dev"` runs. It behaves like a terminal without
// being one: it renders NOTHING. DATA payloads go to stdout verbatim and
// whatever emulator the user is actually looking at does the drawing — over
// ssh that is the one on their own machine, at the far end of the link. All
// this does is tty plumbing: raw mode so keys travel byte-exact, the window
// size on a RESIZE, and one stolen key so there is a way back out.
//
// Structured like the stdio bridge, and for the same reason: a thread on
// stdin rather than polling it, because Windows cannot poll a console
// handle alongside a socket. Two threads write to the socket here (INPUT
// from the reader, RESIZE and ACK from the main loop), so those writes take
// a lock the bridge did not need.

// C-] (0x1d). A prefix has to be a byte nobody wants; this is telnet's old
// escape and essentially nothing binds it today. Deliberately NOT tmux's
// C-b, which is backward-char in readline and page-up in vim — and which
// would collide in the very case this exists for, attaching to a box that
// already runs tmux. $STARLING_TERMD_PREFIX overrides it, "C-b" included,
// for fingers that already know the other spelling.
#define TERMD_PREFIX_DEFAULT 0x1d

struct attach {
    sock_t fd;
    plat_mutex *wlock;
    uint8_t prefix;
    int detached;   // the user asked to leave, so the exit note says so
};

static uint8_t attach_prefix(void) {
    const char *s = getenv("STARLING_TERMD_PREFIX");
    if (!s || !*s) return TERMD_PREFIX_DEFAULT;
    char c = 0;
    if ((s[0] == 'C' || s[0] == 'c') && s[1] == '-' && s[2]) c = s[2];
    else if (s[0] == '^' && s[1]) c = s[1];
    else if (!s[1]) return (uint8_t)s[0];   // a lone character, taken as itself
    else return TERMD_PREFIX_DEFAULT;
    if (c >= 'a' && c <= 'z') c = (char)(c - 32);
    return (uint8_t)(c & 0x1f);
}

static void attach_write_all(sock_t fd, const uint8_t *p, size_t n) {
    size_t off = 0;
    while (off < n) {
        long put = plat_sock_write(fd, p + off, n - off);
        if (put > 0) { off += (size_t)put; continue; }
        if (put < 0 && plat_would_block()) { plat_sleep_ms(2); continue; }
        return;
    }
}

static void attach_send(struct attach *a, uint8_t type,
                        const void *payload, size_t n) {
    uint8_t hdr[TERMD_HEADER_LEN];
    hdr[0] = type;
    hdr[1] = 0;
    put_u16(hdr + 2, 0);
    put_u32(hdr + 4, (uint32_t)n);
    plat_mutex_lock(a->wlock);
    attach_write_all(a->fd, hdr, sizeof(hdr));
    if (n) attach_write_all(a->fd, (const uint8_t *)payload, n);
    plat_mutex_unlock(a->wlock);
}

// One win32-input-mode key event: ESC [ Vk ; Sc ; Uc ; Kd ; Cs ; Rc _
//
// Windows consoles under a ConPTY report keys this way rather than as bytes
// (see plat_tty_raw), so on that path the prefix never appears as a byte and
// has to be recognised here instead. Standard VT sequences end in a letter;
// this one ends in '_', so nothing else in a terminal stream looks like it
// and the check is safe to run over every platform's input.
//
// Returns the length of the event at `p`, 0 if it is not one. `*partial` is
// set when the buffer ends mid-event, so the caller can carry the tail into
// the next read rather than forwarding half a sequence.
static size_t w32_key(const uint8_t *p, size_t n, uint32_t *vk, uint32_t *uc,
                      int *down, int *partial) {
    *partial = 0;
    if (n == 0) return 0;
    if (p[0] != 0x1b) return 0;
    if (n < 2) { *partial = 1; return 0; }
    if (p[1] != '[') return 0;
    uint32_t f[6] = {0, 0, 0, 0, 0, 0};
    int nf = 0;
    size_t i = 2;
    for (;;) {
        uint32_t v = 0;
        while (i < n && p[i] >= '0' && p[i] <= '9') {
            v = v * 10 + (uint32_t)(p[i] - '0');
            i++;
        }
        if (i >= n) { *partial = 1; return 0; }
        if (nf < 6) f[nf] = v;
        nf++;
        if (p[i] == ';') { i++; continue; }
        if (p[i] == '_') {
            i++;
            if (nf < 4) return 0;         // too few fields to be one of ours
            *vk = f[0];
            *uc = f[2];
            *down = f[3] != 0;
            return i;
        }
        return 0;                          // some other escape sequence
    }
}

// The byte spelling of a key event that carries no character: arrows,
// navigation, function keys. A terminal that speaks bytes would have sent
// exactly these, so this is reconstruction, not invention. Everything else
// with no character — a bare Ctrl going down, a dead key — has no byte
// spelling, and NULL here means "say nothing".
static const char *w32_vk_bytes(uint32_t vk) {
    switch (vk) {
    case 0x25: return "\x1b[D";     // left
    case 0x26: return "\x1b[A";     // up
    case 0x27: return "\x1b[C";     // right
    case 0x28: return "\x1b[B";     // down
    case 0x24: return "\x1b[H";     // home
    case 0x23: return "\x1b[F";     // end
    case 0x21: return "\x1b[5~";    // page up
    case 0x22: return "\x1b[6~";    // page down
    case 0x2D: return "\x1b[2~";    // insert
    case 0x2E: return "\x1b[3~";    // delete
    case 0x70: return "\x1bOP";     // F1
    case 0x71: return "\x1bOQ";     // F2
    case 0x72: return "\x1bOR";     // F3
    case 0x73: return "\x1bOS";     // F4
    case 0x74: return "\x1b[15~";   // F5
    case 0x75: return "\x1b[17~";   // F6
    case 0x76: return "\x1b[18~";   // F7
    case 0x77: return "\x1b[19~";   // F8
    case 0x78: return "\x1b[20~";   // F9
    case 0x79: return "\x1b[21~";   // F10
    case 0x7A: return "\x1b[23~";   // F11
    case 0x7B: return "\x1b[24~";   // F12
    default:   return NULL;
    }
}

// One code point as UTF-8 — the bytes a pty would have carried.
static size_t utf8_put(uint32_t cp, uint8_t *o) {
    if (cp < 0x80) { o[0] = (uint8_t)cp; return 1; }
    if (cp < 0x800) {
        o[0] = (uint8_t)(0xC0 | (cp >> 6));
        o[1] = (uint8_t)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        o[0] = (uint8_t)(0xE0 | (cp >> 12));
        o[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
        o[2] = (uint8_t)(0x80 | (cp & 0x3F));
        return 3;
    }
    o[0] = (uint8_t)(0xF0 | (cp >> 18));
    o[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));
    o[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
    o[3] = (uint8_t)(0x80 | (cp & 0x3F));
    return 4;
}

// One byte of terminal input, with the prefix key intercepted on the way
// past. Returns 1 when the user has completed the detach command.
static int feed_byte(struct attach *a, uint8_t ch, uint8_t *out, size_t *m,
                     int *held) {
    if (*held) {
        *held = 0;
        if (ch == 'd' || ch == 'D') return 1;
        if (ch == a->prefix) { out[(*m)++] = ch; return 0; }   // literal
        // Any other key: the prefix was not a command after all, so neither
        // byte belongs to us. Pass both rather than eating a keystroke the
        // user meant for the far side.
        out[(*m)++] = a->prefix;
        out[(*m)++] = ch;
        return 0;
    }
    if (ch == a->prefix) { *held = 1; return 0; }
    out[(*m)++] = ch;
    return 0;
}

// stdin → INPUT frames.
//
// A Windows console under a ConPTY reports key EVENTS rather than key bytes
// (see plat_tty_raw), so ASCII ones are turned back into the bytes a pty
// would have produced. Two things depend on it:
//
//   - the prefix. ^] is an event carrying code point 29, never a 0x1d byte,
//     so without this the scan below cannot match and ^] d never detaches.
//   - cursor keys. ssh delivers one as its raw bytes; the client's console
//     re-spells those as THREE events carrying 27, 91 and 65, and forwarding
//     them verbatim — what this did before — makes the far end replay three
//     separate keystrokes. The shell sees Escape, then '[', then 'A', so
//     every arrow key clears the line and types "[A" into it. Decoding
//     restores ESC [ A.
//
// EVERY event becomes bytes — UTF-8 for characters (surrogate halves are
// paired back into one code point first), the standard VT sequences for
// arrows and function keys, nothing at all for a bare modifier. No event
// text ever reaches the wire, and that is the design, not tidiness: the
// wire is the pty byte stream, a POSIX daemon can be on the far end of it,
// and — measured — a Windows daemon cannot digest the event spelling
// either. Forwarding é's event put ├⌐ in the shell's line while ReadKey in
// the same session read the event correctly as U+00E9: the event survives
// into the input queue and dies in the cooked-read path, immune to chcp,
// to [Console]::InputEncoding, and to which console host is running. The
// configuration that measurably works end to end is the one sshd itself
// uses — UTF-8 bytes into a console set to code page 65001 — so the client
// produces exactly those bytes, and the daemon sets exactly that code page
// (see plat_pty_open in plat_win32.c).
static void attach_stdin(void *arg) {
    struct attach *a = arg;
    uint8_t work[4160];
    uint8_t out[sizeof(work) * 2];   // worst case: every byte is a held prefix
    size_t ncarry = 0;
    int held = 0;
    uint32_t hi_sur = 0;   // the high half of a surrogate pair, awaiting its low

    for (;;) {
        long n = plat_stdin_read(work + ncarry, sizeof(work) - ncarry);
        if (n <= 0) break;
        size_t total = ncarry + (size_t)n;
        ncarry = 0;

        size_t m = 0, i = 0;
        int detach = 0;
        while (i < total) {
            uint32_t vk = 0, uc = 0;
            int down = 0, partial = 0;
            size_t seq = w32_key(work + i, total - i, &vk, &uc, &down, &partial);

            if (partial) {
                // Hold the tail back for the next read rather than forwarding
                // half an event. Anything longer than an event could ever be
                // is not one, so it goes through as bytes.
                size_t rest = total - i;
                if (rest < sizeof(work) / 2) {
                    memmove(work, work + i, rest);
                    ncarry = rest;
                    break;
                }
            }

            if (seq) {
                i += seq;
                // Characters ride on key-DOWN events — except those with no
                // key of their own, which the console delivers Alt+Numpad
                // style: an Alt press whose key-UP carries the code point.
                // An emoji arrives as exactly two such pairs, one per
                // surrogate half (vk 18 is Alt; measured, not theorised).
                // Every other key-up is dropped: a byte stream has no
                // key-ups, and an ordinary key carries its character on
                // both edges — forwarding the up would double every letter.
                if (!down && !(vk == 18 && uc != 0)) continue;
                if (uc == 0) {
                    const char *vs = w32_vk_bytes(vk);
                    for (; vs && *vs && !detach; vs++)
                        detach = feed_byte(a, (uint8_t)*vs, out, &m, &held);
                    if (detach) break;
                    continue;
                }
                if (uc >= 0xD800 && uc <= 0xDBFF) { hi_sur = uc; continue; }
                uint32_t cp = uc;
                if (uc >= 0xDC00 && uc <= 0xDFFF) {
                    if (!hi_sur) continue;      // a lone low half says nothing
                    cp = 0x10000 + ((hi_sur - 0xD800) << 10) + (uc - 0xDC00);
                }
                hi_sur = 0;
                uint8_t enc[4];
                size_t k = utf8_put(cp, enc);
                for (size_t z = 0; z < k && !detach; z++)
                    detach = feed_byte(a, enc[z], out, &m, &held);
                if (detach) break;
                continue;
            }

            detach = feed_byte(a, work[i], out, &m, &held);
            i++;
            if (detach) break;
        }

        if (detach) {
            if (m) attach_send(a, TERMD_INPUT, out, m);
            a->detached = 1;
            attach_send(a, TERMD_DETACH, NULL, 0);
            // Wake the main loop out of its poll; the session and its shell
            // are untouched by any of this.
            plat_sock_shutdown(a->fd);
            return;
        }
        if (m) attach_send(a, TERMD_INPUT, out, m);
    }
    plat_sock_shutdown(a->fd);
}

// Blocks until a frame of `want` arrives (or the link dies). Anything else
// is dropped: nothing but the handshake runs before the pump starts.
static int attach_await(sock_t fd, uint8_t want, uint8_t *buf, size_t cap,
                        uint32_t *out_len) {
    size_t have = 0;
    for (;;) {
        size_t off = 0;
        while (have - off >= TERMD_HEADER_LEN) {
            uint32_t len = get_u32(buf + off + 4);
            if (len > cap - TERMD_HEADER_LEN) return -1;
            if (have - off < TERMD_HEADER_LEN + len) break;
            uint8_t type = buf[off];
            if (type == want || type == TERMD_ERROR) {
                memmove(buf, buf + off + TERMD_HEADER_LEN, len);
                *out_len = len;
                return type == want ? 0 : -2;
            }
            off += TERMD_HEADER_LEN + len;
        }
        if (off) { memmove(buf, buf + off, have - off); have -= off; }
        if (have == cap) return -1;
        long n = plat_sock_read(fd, buf + have, cap - have);
        if (n <= 0) {
            if (n < 0 && plat_would_block()) { plat_sleep_ms(5); continue; }
            return -1;
        }
        have += (size_t)n;
    }
}

static int attach_session(const char *target) {
    if (!target || !*target) {
        fprintf(stderr, "termd: name a session — starling-termd <name|id>\n"
                        "       (starling-termd --list shows them)\n");
        return 2;
    }
    sock_t fd = connect_socket();
    if (fd == BAD_SOCK) {
        // No daemon yet: start one, the way the stdio bridge does. Asking
        // for a session by name on a cold machine should just work.
        if (plat_spawn_daemon(3600) != 0) {
            fprintf(stderr, "termd: could not start the daemon\n");
            return 1;
        }
        for (int i = 0; i < 100 && fd == BAD_SOCK; i++) {
            plat_sleep_ms(20);
            fd = connect_socket();
        }
        if (fd == BAD_SOCK) {
            fprintf(stderr, "termd: could not start or reach the daemon\n");
            return 1;
        }
    }

    // The size to open or resume at is this terminal's, so the shell is
    // shaped like the window it is about to appear in.
    uint16_t cols = 80, rows = 24;
    (void)plat_tty_size(&cols, &rows);

    // NOT on the stack: a megabyte-and-change local is fine against Linux's
    // 8 MB stack and fatal against Windows' 1 MB default. Worse, it is fatal
    // for EVERY mode rather than this one — clang inlines the four one-shot
    // mode functions into main at -O2, merging their frames, so main's
    // prologue touches the whole megabyte and `--list` dies on entry with
    // STATUS_STACK_OVERFLOW (0xC00000FD) before printing a byte. That reads
    // as "the Windows build is broken", not as "one buffer is too big"; at
    // -O0, where the inlining cannot happen, everything but attach works.
    // Static rather than malloc'd because this path runs once per process,
    // from main, on one thread — so there is no free() to get wrong.
    static uint8_t buf[TERMD_MAX_PAYLOAD + TERMD_HEADER_LEN];
    uint32_t rlen = 0;
    uint8_t hello[2];
    put_u16(hello, TERMD_PROTOCOL_VERSION);
    uint8_t hdr[TERMD_HEADER_LEN];
    hdr[0] = TERMD_HELLO; hdr[1] = 0; put_u16(hdr + 2, 0); put_u32(hdr + 4, 2);
    attach_write_all(fd, hdr, sizeof(hdr));
    attach_write_all(fd, hello, sizeof(hello));
    if (attach_await(fd, TERMD_HELLO_OK, buf, sizeof(buf), &rlen) != 0) {
        fprintf(stderr, "termd: the daemon refused the handshake"
                        " (version %d here)\n", TERMD_PROTOCOL_VERSION);
        plat_sock_close(fd);
        return 1;
    }

    // All digits is an id and re-attaches exactly; anything else is a name,
    // and a named OPEN is attach-or-create — so the same command starts
    // "iOS dev" the first time and resumes it every time after.
    int numeric = 1;
    for (const char *q = target; *q; q++) if (*q < '0' || *q > '9') numeric = 0;
    uint8_t req[TERMD_HEADER_LEN + 16 + TERMD_MAX_NAME];
    size_t n = 0;
    if (numeric) {
        put_u32(req + n, (uint32_t)strtoul(target, NULL, 10)); n += 4;
        put_u64(req + n, 0); n += 8;             // from 0: the daemon clamps
        put_u16(req + n, cols); n += 2;          // to the oldest byte it holds
        put_u16(req + n, rows); n += 2;
    } else {
        size_t nl = strlen(target);
        if (nl > TERMD_MAX_NAME - 1) nl = TERMD_MAX_NAME - 1;
        put_u16(req + n, cols); n += 2;
        put_u16(req + n, rows); n += 2;
        put_u16(req + n, (uint16_t)nl); n += 2;
        memcpy(req + n, target, nl); n += nl;
    }
    hdr[0] = numeric ? TERMD_ATTACH : TERMD_OPEN;
    put_u32(hdr + 4, (uint32_t)n);
    attach_write_all(fd, hdr, sizeof(hdr));
    attach_write_all(fd, req, n);

    int rc = attach_await(fd, TERMD_ATTACHED, buf, sizeof(buf), &rlen);
    if (rc == -2) {
        fprintf(stderr, "termd: %.*s\n", (int)(rlen > 2 ? rlen - 2 : 0), buf + 2);
        plat_sock_close(fd);
        return 1;
    }
    if (rc != 0) {
        fprintf(stderr, "termd: no answer from the daemon\n");
        plat_sock_close(fd);
        return 1;
    }
    uint64_t consumed = rlen >= 12 ? get_u64(buf + 4) : 0;

    struct attach a;
    a.fd = fd;
    a.prefix = attach_prefix();
    a.detached = 0;
    a.wlock = plat_mutex_new();
    if (!a.wlock) { plat_sock_close(fd); return 1; }

    int raw = plat_tty_raw() == 0;
    // \r\n, not \n: OPOST is off now, so a bare newline would leave the
    // cursor mid-line.
    fprintf(stderr, "termd: attached to %s — press ^%c d to detach\r\n",
            target, (char)(a.prefix + 64));
    fflush(stderr);

    if (plat_thread_spawn(attach_stdin, &a) != 0) {
        if (raw) plat_tty_restore();
        plat_sock_close(fd);
        return 1;
    }

    uint64_t acked = consumed;
    size_t have = 0;
    int ended = 0;
    for (;;) {
        plat_pollfd pf;
        pf.fd = fd;
        pf.events = POLLIN;
        pf.revents = 0;
        int pr = plat_poll(&pf, 1, 250);
        if (pr < 0 && !plat_would_block()) break;

        if (pr > 0 && (pf.revents & (POLLIN | POLLHUP | POLLERR))) {
            long got = plat_sock_read(fd, buf + have, sizeof(buf) - have);
            if (got == 0) break;
            if (got < 0) {
                if (plat_would_block()) goto tick;
                break;
            }
            have += (size_t)got;
            size_t off = 0;
            while (have - off >= TERMD_HEADER_LEN) {
                uint32_t len = get_u32(buf + off + 4);
                if (len > sizeof(buf) - TERMD_HEADER_LEN) { ended = 1; break; }
                if (have - off < TERMD_HEADER_LEN + len) break;
                uint8_t type = buf[off];
                const uint8_t *p = buf + off + TERMD_HEADER_LEN;
                if (type == TERMD_DATA && len > 8) {
                    // The payload past its seq, straight out. This is the
                    // only place session bytes are touched, and they are not
                    // read — only forwarded.
                    (void)plat_stdout_write(p + 8, len - 8);
                    consumed = get_u64(p) + (len - 8);
                } else if (type == TERMD_EXIT) {
                    ended = 1;
                } else if (type == TERMD_PING) {
                    attach_send(&a, TERMD_PONG, p, len);
                } else if (type == TERMD_ERROR) {
                    ended = 1;
                }
                off += TERMD_HEADER_LEN + len;
            }
            if (off) { memmove(buf, buf + off, have - off); have -= off; }
            if (ended) break;
        }

    tick:
        if (a.detached) break;
        if (consumed != acked) {
            uint8_t ack[8];
            put_u64(ack, consumed);
            attach_send(&a, TERMD_ACK, ack, sizeof(ack));
            acked = consumed;
        }
        // Polled, not signal-driven: see plat_tty_size.
        uint16_t c2 = cols, r2 = rows;
        if (plat_tty_size(&c2, &r2) == 0 && (c2 != cols || r2 != rows)) {
            cols = c2; rows = r2;
            uint8_t rs[4];
            put_u16(rs, cols);
            put_u16(rs + 2, rows);
            attach_send(&a, TERMD_RESIZE, rs, sizeof(rs));
        }
    }

    if (raw) plat_tty_restore();
    plat_sock_close(fd);
    fprintf(stderr, "termd: %s\n",
            a.detached ? "detached — the session is still running"
                       : (ended ? "session ended" : "link closed"));
    return 0;
}

// ── main ────────────────────────────────────────────────────────────────

static int list_sessions(void) {
    plat_init();
    sock_t fd = connect_socket();
    if (fd == BAD_SOCK) { printf("no daemon running\n"); return 0; }
    uint8_t hello[TERMD_HEADER_LEN + 2];
    hello[0] = TERMD_HELLO; hello[1] = 0;
    put_u16(hello + 2, 0);
    put_u32(hello + 4, 2);
    put_u16(hello + TERMD_HEADER_LEN, TERMD_PROTOCOL_VERSION);
    (void)plat_sock_write(fd, hello, sizeof(hello));
    uint8_t list[TERMD_HEADER_LEN];
    list[0] = TERMD_LIST; list[1] = 0;
    put_u16(list + 2, 0);
    put_u32(list + 4, 0);
    (void)plat_sock_write(fd, list, sizeof(list));

    uint8_t buf[8192];
    size_t have = 0;
    time_t deadline = time(NULL) + 2;
    while (time(NULL) < deadline) {
        long n = plat_sock_read(fd, buf + have, sizeof(buf) - have);
        if (n <= 0) break;
        have += (size_t)n;
        size_t off = 0;
        while (have - off >= TERMD_HEADER_LEN) {
            uint32_t len = get_u32(buf + off + 4);
            if (have - off < TERMD_HEADER_LEN + len) break;
            uint8_t type = buf[off];
            const uint8_t *p = buf + off + TERMD_HEADER_LEN;
            if (type == TERMD_LIST_REPLY) {
                uint16_t count = get_u16(p);
                if (!count) printf("no sessions\n");
                const uint8_t *e = p + 2;
                const uint8_t *end = p + len;
                for (uint16_t i = 0; i < count && e + 19 <= end; i++) {
                    uint16_t nlen = get_u16(e + 17);
                    if (e + 19 + nlen > end) break;
                    char name[TERMD_MAX_NAME] = {0};
                    size_t n = nlen < sizeof(name) ? nlen : sizeof(name) - 1;
                    memcpy(name, e + 19, n);
                    printf("session %-3u %-20s %ux%u  %s  %llu bytes\n",
                           get_u32(e), name[0] ? name : "-",
                           get_u16(e + 4), get_u16(e + 6),
                           e[8] ? "running" : "exited",
                           (unsigned long long)get_u64(e + 9));
                    e += 19 + nlen;
                }
                plat_sock_close(fd);
                return 0;
            }
            off += TERMD_HEADER_LEN + len;
        }
        memmove(buf, buf + off, have - off);
        have -= off;
    }
    plat_sock_close(fd);
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "starling-termd — terminal sessions that outlive their client\n"
        "\n"
        "  starling-termd <name|id>                 attach to a session,\n"
        "                                           creating it if the name is new\n"
        "  starling-termd --serve [--idle-exit S]   run the daemon\n"
        "  starling-termd --stdio                   bridge stdin/stdout to it\n"
        "  starling-termd --list                    show sessions\n"
        "\n"
        "Attached, ^] d detaches and leaves the session running\n"
        "($STARLING_TERMD_PREFIX picks another key, e.g. C-b).\n"
        "The socket is $STARLING_TERMD_SOCKET, else\n"
        "$XDG_RUNTIME_DIR/starling-termd.sock.\n");
}

int main(int argc, char **argv) {
    int idle = 0;
    const char *mode = NULL;
    const char *target = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--serve") || !strcmp(argv[i], "--stdio")
            || !strcmp(argv[i], "--list")) {
            mode = argv[i];
        } else if (!strcmp(argv[i], "--attach")) {
            mode = "--attach";
            if (i + 1 < argc && argv[i + 1][0] != '-') target = argv[++i];
        } else if (!strcmp(argv[i], "--idle-exit") && i + 1 < argc) {
            idle = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-v") || !strcmp(argv[i], "--verbose")) {
            g_verbose = 1;
        } else if (argv[i][0] != '-' && !mode && !target) {
            // A bare word is a session: `starling-termd "iOS dev"`. The
            // common case deserves the short spelling.
            mode = "--attach";
            target = argv[i];
        } else {
            usage();
            return 2;
        }
    }
    if (!mode) { usage(); return 2; }
    plat_init();
    if (!strcmp(mode, "--serve")) return serve(idle);
    if (!strcmp(mode, "--stdio")) return stdio_bridge();
    if (!strcmp(mode, "--attach")) return attach_session(target);
    return list_sessions();
}
