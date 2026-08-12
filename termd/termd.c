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
// POSIX only, no dependencies: this is meant to be one static binary you
// scp to a machine that has nothing else on it.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

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
    int used;
    int master;      // pty master, -1 once the child is gone
    pid_t child;
    int alive;
    int status;      // wait status once !alive
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
    int fd;
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

static struct session g_sessions[MAX_SESSIONS];
static struct client g_clients[MAX_CLIENTS];
static uint32_t g_next_id = 1;

static struct session *session_by_id(uint32_t id) {
    for (int i = 0; i < MAX_SESSIONS; i++)
        if (g_sessions[i].used && g_sessions[i].id == id) return &g_sessions[i];
    return NULL;
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

static const char *shell_path(void) {
    const char *sh = getenv("STARLING_DEV_SHELL");
    if (sh && *sh && access(sh, X_OK) == 0) return sh;
    sh = getenv("SHELL");
    if (sh && *sh && access(sh, X_OK) == 0) return sh;
    if (access("/bin/bash", X_OK) == 0) return "/bin/bash";
    return "/bin/sh";
}

static struct session *session_open(uint16_t cols, uint16_t rows,
                                    const char *command) {
    struct session *s = NULL;
    for (int i = 0; i < MAX_SESSIONS; i++)
        if (!g_sessions[i].used) { s = &g_sessions[i]; break; }
    if (!s) return NULL;

    memset(s, 0, sizeof(*s));
    s->ring = malloc(TERMD_RING_BYTES);
    if (!s->ring) return NULL;

    struct winsize ws = {.ws_row = rows ? rows : 24,
                         .ws_col = cols ? cols : 80};
    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) {
        free(s->ring);
        memset(s, 0, sizeof(*s));
        return NULL;
    }
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        const char *sh = shell_path();
        if (command && *command) {
            execl(sh, sh, "-c", command, (char *)NULL);
        } else {
            // A login-ish interactive shell, the way a terminal would.
            const char *base = strrchr(sh, '/');
            base = base ? base + 1 : sh;
            execl(sh, base, (char *)NULL);
        }
        _exit(127);
    }

    // Non-blocking: one slow session must not stall the loop.
    int fl = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, fl | O_NONBLOCK);

    s->used = 1;
    s->id = g_next_id++;
    s->master = master;
    s->child = pid;
    s->alive = 1;
    s->cols = ws.ws_col;
    s->rows = ws.ws_row;
    logf_("session %u opened (pid %d, %ux%u)", s->id, (int)pid, s->cols, s->rows);
    return s;
}

static void session_close(struct session *s) {
    if (!s->used) return;
    logf_("session %u closed", s->id);
    if (s->master >= 0) close(s->master);
    if (s->alive) kill(-s->child, SIGHUP);
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
    close(c->fd);
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
        uint8_t buf[2 + MAX_SESSIONS * 17];
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
            count++;
        }
        put_u16(buf, count);
        client_out(c, TERMD_LIST_REPLY, buf, n);
        break;
    }
    case TERMD_OPEN: {
        uint16_t cols = len >= 2 ? get_u16(p) : 80;
        uint16_t rows = len >= 4 ? get_u16(p + 2) : 24;
        char command[4096];
        size_t clen = len > 4 ? len - 4 : 0;
        if (clen >= sizeof(command)) clen = sizeof(command) - 1;
        memcpy(command, p + 4, clen);
        command[clen] = 0;
        struct session *s = session_open(cols, rows, command);
        if (!s) {
            client_error(c, TERMD_ERR_OPEN_FAILED, "could not open a session");
            return;
        }
        c->session = s->id;
        c->sent = 0;
        c->acked = 0;
        uint8_t reply[12];
        put_u32(reply, s->id);
        put_u64(reply + 4, 0);
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
            struct winsize ws = {.ws_row = rows, .ws_col = cols};
            ioctl(s->master, TIOCSWINSZ, &ws);
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
        if (!s || !s->alive) return;
        size_t off = 0;
        while (off < len) {
            ssize_t n = write(s->master, p + off, len - off);
            if (n > 0) { off += (size_t)n; continue; }
            if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
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
        if (s->alive) {
            struct winsize ws = {.ws_row = rows, .ws_col = cols};
            ioctl(s->master, TIOCSWINSZ, &ws);
        }
        break;
    }
    case TERMD_ACK:
        if (len >= 8) c->acked = get_u64(p);
        break;
    case TERMD_DETACH:
        c->session = 0;
        break;
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
    ssize_t n = read(c->fd, buf, sizeof(buf));
    if (n == 0) { c->dead = 1; return; }
    if (n < 0) {
        if (errno == EAGAIN || errno == EINTR) return;
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
        ssize_t n = write(c->fd, c->out + c->out_sent, c->out_len - c->out_sent);
        if (n > 0) { c->out_sent += (size_t)n; continue; }
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) return;
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
    const char *run = getenv("XDG_RUNTIME_DIR");
    if (run && *run) { snprintf(out, len, "%s/starling-termd.sock", run); return; }
    snprintf(out, len, "/tmp/starling-termd-%d.sock", (int)getuid());
}

static int listen_socket(void) {
    char path[256];
    socket_path(path, sizeof(path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);

    // A stale socket from a daemon that died is not a reason to refuse to
    // start; a LIVE one is. Probe by connecting before unlinking.
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        if (connect(probe, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            close(probe);
            close(fd);
            errno = EADDRINUSE;
            return -1;
        }
        close(probe);
    }
    unlink(path);
    mode_t old = umask(0077);   // the socket is this user's business only
    int rc = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    umask(old);
    if (rc < 0 || listen(fd, 16) < 0) { close(fd); return -1; }
    return fd;
}

static int connect_socket(void) {
    char path[256];
    socket_path(path, sizeof(path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void reap_children(void) {
    int status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        for (int i = 0; i < MAX_SESSIONS; i++) {
            struct session *s = &g_sessions[i];
            if (s->used && s->child == pid) {
                s->alive = 0;
                s->status = status;
                logf_("session %u child exited", s->id);
            }
        }
    }
}

static int serve(int idle_exit_seconds) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);   // reaped explicitly below via waitpid
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigaction(SIGCHLD, &sa, NULL);

    int lfd = listen_socket();
    if (lfd < 0) {
        if (errno == EADDRINUSE) return 0;   // someone else is already serving
        perror("termd: listen");
        return 1;
    }
    logf_("serving");

    time_t last_activity = time(NULL);
    for (;;) {
        struct pollfd pfds[1 + MAX_CLIENTS + MAX_SESSIONS];
        int map_client[MAX_CLIENTS], map_session[MAX_SESSIONS];
        int n = 0;
        pfds[n].fd = lfd;
        pfds[n].events = POLLIN;
        pfds[n].revents = 0;
        n++;
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (!g_clients[i].used) continue;
            map_client[n] = i;
            pfds[n].fd = g_clients[i].fd;
            pfds[n].events = (g_clients[i].closing ? 0 : POLLIN)
                           | (g_clients[i].out_len ? POLLOUT : 0);
            pfds[n].revents = 0;
            n++;
        }
        for (int i = 0; i < MAX_SESSIONS; i++) {
            if (!g_sessions[i].used || g_sessions[i].master < 0) continue;
            map_session[n] = i;
            pfds[n].fd = g_sessions[i].master;
            pfds[n].events = POLLIN;
            pfds[n].revents = 0;
            n++;
        }

        int rc = poll(pfds, (nfds_t)n, 1000);
        reap_children();
        if (rc < 0 && errno != EINTR) break;

        if (pfds[0].revents & POLLIN) {
            int cfd = accept(lfd, NULL, NULL);
            if (cfd >= 0) {
                struct client *c = NULL;
                for (int i = 0; i < MAX_CLIENTS; i++)
                    if (!g_clients[i].used) { c = &g_clients[i]; break; }
                if (!c) { close(cfd); }
                else {
                    memset(c, 0, sizeof(*c));
                    c->used = 1;
                    c->fd = cfd;
                    int fl = fcntl(cfd, F_GETFL, 0);
                    fcntl(cfd, F_SETFL, fl | O_NONBLOCK);
                    logf_("client connected");
                }
                last_activity = time(NULL);
            }
        }

        for (int k = 1; k < n; k++) {
            if (pfds[k].fd == lfd) continue;
            // sessions
            int si = -1, ci = -1;
            for (int i = 0; i < MAX_SESSIONS; i++)
                if (g_sessions[i].used && g_sessions[i].master == pfds[k].fd) si = i;
            for (int i = 0; i < MAX_CLIENTS; i++)
                if (g_clients[i].used && g_clients[i].fd == pfds[k].fd) ci = i;
            (void)map_client; (void)map_session;

            if (si >= 0 && (pfds[k].revents & (POLLIN | POLLHUP))) {
                struct session *s = &g_sessions[si];
                uint8_t buf[READ_CHUNK];
                for (;;) {
                    ssize_t got = read(s->master, buf, sizeof(buf));
                    if (got > 0) { ring_append(s, buf, (size_t)got); continue; }
                    if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
                    if (got < 0 && errno == EINTR) continue;
                    // EOF: the child is gone. Keep the session (and its ring)
                    // so a client can still attach and read the last words.
                    close(s->master);
                    s->master = -1;
                    s->alive = 0;
                    break;
                }
                last_activity = time(NULL);
            }
            if (ci >= 0) {
                struct client *c = &g_clients[ci];
                if ((pfds[k].revents & POLLIN) && !c->closing) client_readable(c);
                if (!c->dead && (pfds[k].revents & POLLOUT)) client_flush(c);
                last_activity = time(NULL);
            }
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

        if (idle_exit_seconds > 0) {
            int any_client = 0, any_session = 0;
            for (int i = 0; i < MAX_CLIENTS; i++) any_client |= g_clients[i].used;
            for (int i = 0; i < MAX_SESSIONS; i++) any_session |= g_sessions[i].used;
            if (!any_client && !any_session &&
                time(NULL) - last_activity > idle_exit_seconds) {
                logf_("idle, exiting");
                break;
            }
        }
    }
    close(lfd);
    char path[256];
    socket_path(path, sizeof(path));
    unlink(path);
    return 0;
}

// ── the ssh-side bridge ─────────────────────────────────────────────────

// Starts a daemon if one is not running, then relays stdin/stdout to its
// socket. This is what `ssh host starling-termd --stdio` runs, so the
// client's transport is one process away from the sessions and nothing
// needs a network port.
static int stdio_bridge(void) {
    int fd = connect_socket();
    if (fd < 0) {
        pid_t pid = fork();
        if (pid == 0) {
            setsid();
            int null = open("/dev/null", O_RDWR);
            if (null >= 0) {
                dup2(null, 0);
                if (!g_verbose) { dup2(null, 1); dup2(null, 2); }
                if (null > 2) close(null);
            }
            // exec rather than serve() in this process: a forked daemon keeps
            // the bridge's argv, so `ps` shows two --stdio processes and any
            // pkill aimed at the bridge takes the daemon (and every session)
            // with it. Re-exec puts --serve on the command line, where both a
            // human and a script can see it.
            execl("/proc/self/exe", "starling-termd", "--serve",
                  "--idle-exit", "3600", (char *)NULL);
            _exit(serve(3600));   // /proc unavailable: fall back in-process
        }
        for (int i = 0; i < 100 && fd < 0; i++) {
            struct timespec ts = {.tv_nsec = 20 * 1000 * 1000};
            nanosleep(&ts, NULL);
            fd = connect_socket();
        }
        if (fd < 0) {
            fprintf(stderr, "termd: could not start or reach the daemon\n");
            return 1;
        }
    }
    signal(SIGPIPE, SIG_IGN);
    struct pollfd pfds[2];
    uint8_t buf[READ_CHUNK];
    for (;;) {
        pfds[0].fd = 0;   pfds[0].events = POLLIN; pfds[0].revents = 0;
        pfds[1].fd = fd;  pfds[1].events = POLLIN; pfds[1].revents = 0;
        if (poll(pfds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (pfds[0].revents & POLLIN) {
            ssize_t n = read(0, buf, sizeof(buf));
            if (n <= 0) break;
            for (ssize_t off = 0; off < n; ) {
                ssize_t w = write(fd, buf + off, (size_t)(n - off));
                if (w > 0) { off += w; continue; }
                if (errno == EINTR) continue;
                goto done;
            }
        }
        if (pfds[1].revents & POLLIN) {
            ssize_t n = read(fd, buf, sizeof(buf));
            if (n <= 0) break;
            for (ssize_t off = 0; off < n; ) {
                ssize_t w = write(1, buf + off, (size_t)(n - off));
                if (w > 0) { off += w; continue; }
                if (errno == EINTR) continue;
                goto done;
            }
        }
        if (pfds[0].revents & (POLLHUP | POLLERR)) break;
        if (pfds[1].revents & (POLLHUP | POLLERR)) break;
    }
done:
    close(fd);
    return 0;
}

// ── main ────────────────────────────────────────────────────────────────

static int list_sessions(void) {
    int fd = connect_socket();
    if (fd < 0) { printf("no daemon running\n"); return 0; }
    uint8_t hello[TERMD_HEADER_LEN + 2];
    hello[0] = TERMD_HELLO; hello[1] = 0;
    put_u16(hello + 2, 0);
    put_u32(hello + 4, 2);
    put_u16(hello + TERMD_HEADER_LEN, TERMD_PROTOCOL_VERSION);
    (void)!write(fd, hello, sizeof(hello));
    uint8_t list[TERMD_HEADER_LEN];
    list[0] = TERMD_LIST; list[1] = 0;
    put_u16(list + 2, 0);
    put_u32(list + 4, 0);
    (void)!write(fd, list, sizeof(list));

    uint8_t buf[8192];
    size_t have = 0;
    time_t deadline = time(NULL) + 2;
    while (time(NULL) < deadline) {
        ssize_t n = read(fd, buf + have, sizeof(buf) - have);
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
                for (uint16_t i = 0; i < count; i++) {
                    const uint8_t *e = p + 2 + i * 17;
                    printf("session %u  %ux%u  %s  %llu bytes\n",
                           get_u32(e), get_u16(e + 4), get_u16(e + 6),
                           e[8] ? "running" : "exited",
                           (unsigned long long)get_u64(e + 9));
                }
                close(fd);
                return 0;
            }
            off += TERMD_HEADER_LEN + len;
        }
        memmove(buf, buf + off, have - off);
        have -= off;
    }
    close(fd);
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "starling-termd — terminal sessions that outlive their client\n"
        "\n"
        "  starling-termd --serve [--idle-exit S]   run the daemon\n"
        "  starling-termd --stdio                   bridge stdin/stdout to it\n"
        "  starling-termd --list                    show sessions\n"
        "\n"
        "The socket is $STARLING_TERMD_SOCKET, else\n"
        "$XDG_RUNTIME_DIR/starling-termd.sock.\n");
}

int main(int argc, char **argv) {
    int idle = 0;
    const char *mode = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--serve") || !strcmp(argv[i], "--stdio")
            || !strcmp(argv[i], "--list")) {
            mode = argv[i];
        } else if (!strcmp(argv[i], "--idle-exit") && i + 1 < argc) {
            idle = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-v") || !strcmp(argv[i], "--verbose")) {
            g_verbose = 1;
        } else {
            usage();
            return 2;
        }
    }
    if (!mode) { usage(); return 2; }
    if (!strcmp(mode, "--serve")) return serve(idle);
    if (!strcmp(mode, "--stdio")) return stdio_bridge();
    return list_sessions();
}
