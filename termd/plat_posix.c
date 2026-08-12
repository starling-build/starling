// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The POSIX half of plat.h. This is the code that was inline in termd.c
// before Windows existed; it is unchanged in behaviour except that the pty
// master is now read blocking from a per-session thread instead of being
// polled alongside the sockets.

#define _GNU_SOURCE
#include "plat.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

int plat_init(void) {
    // A client that vanishes mid-write must not take the daemon with it.
    signal(SIGPIPE, SIG_IGN);
    return 0;
}

void plat_sock_close(sock_t s) { if (s >= 0) close(s); }

void plat_sock_shutdown(sock_t s) { if (s >= 0) shutdown(s, SHUT_RDWR); }

int plat_sock_nonblock(sock_t s) {
    int fl = fcntl(s, F_GETFL, 0);
    if (fl < 0) return -1;
    return fcntl(s, F_SETFL, fl | O_NONBLOCK);
}

long plat_sock_read(sock_t s, void *buf, size_t n) {
    return (long)read(s, buf, n);
}

long plat_sock_write(sock_t s, const void *buf, size_t n) {
    return (long)write(s, buf, n);
}

int plat_would_block(void) {
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR;
}

int plat_poll(plat_pollfd *fds, int nfds, int timeout_ms) {
    return poll(fds, (nfds_t)nfds, timeout_ms);
}

int plat_addr_in_use(void) { return errno == EADDRINUSE; }

void plat_unlink(const char *path) { unlink(path); }

void plat_default_socket_path(char *out, size_t len) {
    const char *run = getenv("XDG_RUNTIME_DIR");
    if (run && *run) {
        snprintf(out, len, "%s/starling-termd.sock", run);
        return;
    }
    snprintf(out, len, "/tmp/starling-termd-%d.sock", (int)getuid());
}

sock_t plat_listen_unix(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return BAD_SOCK;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);

    // A stale socket from a daemon that died uncleanly would otherwise make
    // every future start fail; probe it, and only unlink if nobody answers.
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        if (connect(probe, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            close(probe);
            close(fd);
            errno = EADDRINUSE;
            return BAD_SOCK;
        }
        close(probe);
    }
    unlink(path);

    mode_t old = umask(0077);
    int rc = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    umask(old);
    if (rc < 0 || listen(fd, 16) < 0) {
        close(fd);
        return BAD_SOCK;
    }
    return fd;
}

sock_t plat_connect_unix(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return BAD_SOCK;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return BAD_SOCK;
    }
    return fd;
}

// ── ptys ────────────────────────────────────────────────────────────────

struct plat_pty {
    int master;
    pid_t child;
    int exited;
    int status;
};

static const char *shell_path(void) {
    const char *sh = getenv("STARLING_DEV_SHELL");
    if (sh && *sh && access(sh, X_OK) == 0) return sh;
    sh = getenv("SHELL");
    if (sh && *sh && access(sh, X_OK) == 0) return sh;
    if (access("/bin/bash", X_OK) == 0) return "/bin/bash";
    return "/bin/sh";
}

plat_pty *plat_pty_open(uint16_t cols, uint16_t rows, const char *command) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = rows ? rows : 24;
    ws.ws_col = cols ? cols : 80;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) return NULL;
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

    plat_pty *p = calloc(1, sizeof(*p));
    if (!p) {
        close(master);
        kill(pid, SIGKILL);
        return NULL;
    }
    p->master = master;
    p->child = pid;
    return p;
}

long plat_pty_read(plat_pty *p, void *buf, size_t n) {
    if (!p || p->master < 0) return 0;
    for (;;) {
        ssize_t got = read(p->master, buf, n);
        if (got >= 0) return (long)got;
        if (errno == EINTR) continue;
        // EIO is how Linux reports the far side of a pty closing.
        return (errno == EIO) ? 0 : -1;
    }
}

long plat_pty_write(plat_pty *p, const void *buf, size_t n) {
    if (!p || p->master < 0) return -1;
    for (;;) {
        ssize_t put = write(p->master, buf, n);
        if (put >= 0) return (long)put;
        if (errno == EINTR) continue;
        return -1;
    }
}

void plat_pty_resize(plat_pty *p, uint16_t cols, uint16_t rows) {
    if (!p || p->master < 0) return;
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = rows;
    ws.ws_col = cols;
    ioctl(p->master, TIOCSWINSZ, &ws);
}

int plat_pty_exited(plat_pty *p, int *status) {
    if (!p) return 1;
    if (p->exited) {
        if (status) *status = p->status;
        return 1;
    }
    int st = 0;
    pid_t r = waitpid(p->child, &st, WNOHANG);
    if (r == p->child) {
        p->exited = 1;
        p->status = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
        if (status) *status = p->status;
        return 1;
    }
    return 0;
}

void plat_pty_shutdown(plat_pty *p) {
    if (!p) return;
    if (p->child > 0 && !p->exited) {
        // The whole job, not just the shell: killpg reaches what it started.
        kill(-p->child, SIGHUP);
    }
    if (p->master >= 0) {
        close(p->master);
        p->master = -1;   // unblocks the reader thread's read()
    }
}

void plat_pty_free(plat_pty *p) {
    if (!p) return;
    plat_pty_shutdown(p);
    if (p->child > 0 && !p->exited) {
        int st = 0;
        waitpid(p->child, &st, WNOHANG);
    }
    free(p);
}

// ── threads and mutexes ─────────────────────────────────────────────────

struct plat_mutex { pthread_mutex_t m; };

plat_mutex *plat_mutex_new(void) {
    plat_mutex *m = calloc(1, sizeof(*m));
    if (!m) return NULL;
    pthread_mutex_init(&m->m, NULL);
    return m;
}

void plat_mutex_lock(plat_mutex *m) { if (m) pthread_mutex_lock(&m->m); }
void plat_mutex_unlock(plat_mutex *m) { if (m) pthread_mutex_unlock(&m->m); }

struct thunk { void (*fn)(void *); void *arg; };

static void *trampoline(void *v) {
    struct thunk t = *(struct thunk *)v;
    free(v);
    t.fn(t.arg);
    return NULL;
}

int plat_thread_spawn(void (*fn)(void *), void *arg) {
    struct thunk *t = malloc(sizeof(*t));
    if (!t) return -1;
    t->fn = fn;
    t->arg = arg;
    pthread_t th;
    if (pthread_create(&th, NULL, trampoline, t) != 0) {
        free(t);
        return -1;
    }
    pthread_detach(th);
    return 0;
}

void plat_sleep_ms(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int plat_spawn_daemon(int idle_seconds) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid != 0) return 0;

    setsid();
    int null = open("/dev/null", O_RDWR);
    if (null >= 0) {
        dup2(null, 0);
        dup2(null, 1);
        dup2(null, 2);
        if (null > 2) close(null);
    }
    char idle[32];
    snprintf(idle, sizeof(idle), "%d", idle_seconds);
    execl("/proc/self/exe", "starling-termd", "--serve", "--idle-exit", idle,
          (char *)NULL);
    _exit(127);
}

long plat_stdin_read(void *buf, size_t n) {
    for (;;) {
        ssize_t got = read(0, buf, n);
        if (got >= 0) return (long)got;
        if (errno == EINTR) continue;
        return -1;
    }
}

long plat_stdout_write(const void *buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        ssize_t put = write(1, (const char *)buf + off, n - off);
        if (put > 0) { off += (size_t)put; continue; }
        if (put < 0 && errno == EINTR) continue;
        return -1;
    }
    return (long)off;
}
