// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The platform layer: everything about starling-termd that is not the same
// on Linux and Windows, and nothing else.
//
// The split exists because of one fact. The daemon has to wait on two kinds
// of thing at once — its unix socket and its ptys — and on Windows those are
// a SOCKET and a pipe HANDLE. WSAPoll takes only sockets and
// WaitForMultipleObjects only handles; there is no call that waits on both.
// So the pty side moves off the wait entirely: every session gets a reader
// thread that blocks in plat_pty_read, and the main loop polls sockets alone.
//
// That shape is used on BOTH platforms rather than only where it is forced.
// Two control flows for one daemon would mean every future change to the
// session lifetime has to be reasoned about twice, and the version nobody
// develops on is the one that rots. POSIX gets pthreads as readily as it gets
// forkpty, so the cost is nil.
//
// Consequently `plat_pty_read` is BLOCKING on both, which is what a dedicated
// thread wants; the fd is never handed out, so nothing above can poll it.

#ifndef TERMD_PLAT_H
#define TERMD_PLAT_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <afunix.h>
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
typedef WSAPOLLFD plat_pollfd;
#else
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
typedef int sock_t;
#define BAD_SOCK (-1)
typedef struct pollfd plat_pollfd;
#endif

// ── process-wide setup ──────────────────────────────────────────────────
// WSAStartup on Windows, SIGPIPE on POSIX. Idempotent.
int plat_init(void);

// Remove a variable from this process's environment, so no child inherits it.
// Separate from the pty spawn on purpose: a POSIX child could unsetenv between
// fork and exec, but the Windows one cannot — CreateProcessW is handed
// lpEnvironment = NULL and copies the daemon's block wholesale. Scrubbing the
// daemon itself is the one place that works the same on both.
void plat_env_unset(const char *name);

// Set the name this process reports to `ps`/`pgrep`. plat_spawn_daemon execs
// /proc/self/exe, and the kernel takes the comm from THAT path's last
// component — so an auto-started daemon calls itself "exe" and `pkill -x
// starling-termd` misses it while `ps` shows the right thing, argv[0] being
// correct. A no-op where the concept does not exist.
void plat_set_process_name(const char *name);

// ── sockets ─────────────────────────────────────────────────────────────
// Thin wrappers because Windows sockets are not file descriptors: they need
// closesocket/ioctlsocket/WSAGetLastError rather than close/fcntl/errno.

void plat_sock_close(sock_t s);
// Breaks both directions without releasing the handle, so a thread parked in
// a blocking read on it returns instead of waiting for a peer that is never
// going to speak again. Safe to call from another thread; close() is not.
void plat_sock_shutdown(sock_t s);
int  plat_sock_nonblock(sock_t s);
// Both return >0 for bytes moved, 0 for end of stream, -1 for error (check
// plat_would_block()).
long plat_sock_read(sock_t s, void *buf, size_t n);
long plat_sock_write(sock_t s, const void *buf, size_t n);
// True when the last socket call failed only because it would have blocked.
int  plat_would_block(void);
int  plat_poll(plat_pollfd *fds, int nfds, int timeout_ms);
// Listening/connecting on the unix socket at `path`. BAD_SOCK on failure;
// plat_addr_in_use() distinguishes "someone else is already serving".
sock_t plat_listen_unix(const char *path);
sock_t plat_connect_unix(const char *path);
int    plat_addr_in_use(void);
void   plat_unlink(const char *path);
// Where the socket lives when the environment does not say.
void plat_default_socket_path(char *out, size_t len);

// ── ptys ────────────────────────────────────────────────────────────────
// forkpty on POSIX, ConPTY on Windows. `command` NULL/empty means an
// interactive login shell.

typedef struct plat_pty plat_pty;

plat_pty *plat_pty_open(uint16_t cols, uint16_t rows, const char *command);
// BLOCKING. >0 bytes, 0 at end of output (the child is gone), -1 on error.
long plat_pty_read(plat_pty *p, void *buf, size_t n);
long plat_pty_write(plat_pty *p, const void *buf, size_t n);
void plat_pty_resize(plat_pty *p, uint16_t cols, uint16_t rows);
// Non-zero once the child has exited, filling *status with its exit code.
int  plat_pty_exited(plat_pty *p, int *status);
// Ends the child and unblocks a reader parked in plat_pty_read. Does NOT
// free `p` — the reader thread may still be inside a call on it.
void plat_pty_shutdown(plat_pty *p);
void plat_pty_free(plat_pty *p);

// ── threads and mutexes ─────────────────────────────────────────────────

typedef struct plat_mutex plat_mutex;
plat_mutex *plat_mutex_new(void);
void plat_mutex_lock(plat_mutex *m);
void plat_mutex_unlock(plat_mutex *m);

// Detached: the daemon never joins a reader, it shuts the pty down and lets
// the thread fall out of its read.
int plat_thread_spawn(void (*fn)(void *), void *arg);

void plat_sleep_ms(int ms);

// The bridge's own stdin/stdout. NOT fread/fwrite: fread blocks until it has
// the whole requested count, so a bridge built on it forwards nothing until
// 64 KB has piled up, which for an interactive session is never. These
// return as soon as anything is available — >0 bytes, 0 at end, -1 on error.
long plat_stdin_read(void *buf, size_t n);
long plat_stdout_write(const void *buf, size_t n);

// The attaching client's own terminal.
//
// Raw mode is what makes the tunnel byte-exact, and it matters in BOTH
// directions: turning off canonical mode and echo stops the line discipline
// eating keys on the way in, and turning off output post-processing (ONLCR)
// stops it rewriting newlines on the way out — without that second half a
// session tunnelled through ssh prints a staircase. Returns -1 when there is
// no terminal (piped stdin), which is not an error: the caller carries on
// without it.
int  plat_tty_raw(void);
void plat_tty_restore(void);
// Current window size. The attach loop polls this rather than handling
// SIGWINCH: an ioctl every few hundred ms costs nothing, a resize is a
// human-speed event, and it keeps one control flow across both platforms —
// Windows has no such signal to handle.
int  plat_tty_size(uint16_t *cols, uint16_t *rows);

// Starts this same binary as a detached `--serve --idle-exit S`, for the
// stdio bridge to fall back on when no daemon is listening. Re-execs rather
// than serving in-process on purpose: a forked daemon would keep the
// bridge's argv, so `ps` would show two --stdio processes and a pkill aimed
// at the bridge would take the daemon and every session with it.
int plat_spawn_daemon(int idle_seconds);

#endif  // TERMD_PLAT_H
