// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The Windows half of plat.h.
//
// Two things here are not obvious:
//
//   - AF_UNIX is real on Windows (10 1803+) and `afunix.h` gives the same
//     sockaddr_un, so the protocol and its socket path are unchanged. What
//     differs is that a SOCKET is not a file descriptor: closesocket,
//     ioctlsocket and WSAGetLastError, never close/fcntl/errno. Nothing
//     binds a unix socket without WSAStartup having run first.
//
//   - ConPTY replaces forkpty. PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE is a
//     macro that computes a value from a bitfield, and the attribute list is
//     a caller-allocated opaque buffer sized by a deliberately failing first
//     call -- which is why this is C and not Swift, the same reasoning the
//     SDK's CStarlingConPTY records.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00     // ConPTY is gated on Windows 10
#endif

#include "plat.h"

#include <windows.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void plat_daemon_harden(void) { /* durability is in plat_spawn_daemon's flags */ }

int plat_init(void) {
    static int done = 0;
    if (done) return 0;
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return -1;
    done = 1;
    return 0;
}

void plat_sock_close(sock_t s) {
    if (s != INVALID_SOCKET) closesocket(s);
}

void plat_sock_shutdown(sock_t s) {
    if (s != INVALID_SOCKET) shutdown(s, SD_BOTH);
}

int plat_sock_nonblock(sock_t s) {
    u_long on = 1;
    return ioctlsocket(s, FIONBIO, &on) == 0 ? 0 : -1;
}

long plat_sock_read(sock_t s, void *buf, size_t n) {
    int got = recv(s, (char *)buf, (int)n, 0);
    return (long)got;
}

long plat_sock_write(sock_t s, const void *buf, size_t n) {
    int put = send(s, (const char *)buf, (int)n, 0);
    return (long)put;
}

int plat_would_block(void) {
    return WSAGetLastError() == WSAEWOULDBLOCK;
}

int plat_poll(plat_pollfd *fds, int nfds, int timeout_ms) {
    return WSAPoll(fds, (ULONG)nfds, timeout_ms);
}

// Both halves matter. SetEnvironmentVariable owns the block CreateProcessW
// copies into a child, and _putenv_s owns the CRT's own copy that getenv here
// reads; neither updates the other, so a variable dropped from one alone is
// still live in the other.
void plat_env_unset(const char *name) {
    SetEnvironmentVariableA(name, NULL);
    _putenv_s(name, "");
}

// Windows has no comm: a process is named by its image file, which is already
// starling-termd.exe however it was started.
void plat_set_process_name(const char *name) { (void)name; }

int plat_addr_in_use(void) {
    int e = WSAGetLastError();
    return e == WSAEADDRINUSE;
}

void plat_unlink(const char *path) { DeleteFileA(path); }

void plat_default_socket_path(char *out, size_t len) {
    // %LOCALAPPDATA% is per-user and not roamed, which is what the socket
    // wants: it is machine-local state, and two users must not collide on it.
    const char *base = getenv("LOCALAPPDATA");
    if (!base || !*base) base = getenv("TEMP");
    if (!base || !*base) base = ".";
    snprintf(out, len, "%s\\starling-termd.sock", base);
}

static void fill_addr(struct sockaddr_un *addr, const char *path) {
    memset(addr, 0, sizeof(*addr));
    addr->sun_family = AF_UNIX;
    snprintf(addr->sun_path, sizeof(addr->sun_path), "%s", path);
}

sock_t plat_listen_unix(const char *path) {
    plat_init();
    SOCKET fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == INVALID_SOCKET) return BAD_SOCK;
    struct sockaddr_un addr;
    fill_addr(&addr, path);

    // Same stale-socket probe as POSIX: a daemon that died uncleanly leaves
    // the file behind, and bind() would fail forever after.
    SOCKET probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe != INVALID_SOCKET) {
        if (connect(probe, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            closesocket(probe);
            closesocket(fd);
            WSASetLastError(WSAEADDRINUSE);
            return BAD_SOCK;
        }
        closesocket(probe);
    }
    DeleteFileA(path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
        listen(fd, 16) != 0) {
        closesocket(fd);
        return BAD_SOCK;
    }
    return fd;
}

sock_t plat_connect_unix(const char *path) {
    plat_init();
    SOCKET fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == INVALID_SOCKET) return BAD_SOCK;
    struct sockaddr_un addr;
    fill_addr(&addr, path);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        closesocket(fd);
        return BAD_SOCK;
    }
    return fd;
}

// ── ptys ────────────────────────────────────────────────────────────────

struct plat_pty {
    HPCON pc;
    HANDLE in_write;    // what we type into
    HANDLE out_read;    // what the child draws
    HANDLE process;
    HANDLE thread;
    int exited;
    int status;
};

// The inbox console host, deliberately — do not "fix" this by bundling
// conpty.dll and OpenConsole.exe the way the SDK's terminal does.
//
// It is a tempting change, because CreatePseudoConsole always launches
// %SystemRoot%\System32\conhost.exe and the bundled host from
// Microsoft.Windows.Console.ConPTY is years newer (and, for the terminal,
// measurably cheaper). It was written, wired through create/resize/close,
// and measured here, and it was reverted for two reasons:
//
//   - it does not fix what it was built for. A typed é still arrives as
//     `caf├⌐` — the two UTF-8 bytes read in CP437 — under OpenConsole
//     exactly as under conhost, whether the client sends the character as a
//     key event or as UTF-8 bytes, and whether or not the session ran
//     `chcp 65001` first. The session's input decoding is not the host's to
//     decide, so a newer host changes nothing.
//   - it breaks history replay. With the bundled host loaded, reattaching
//     to a session whose previous client was killed outright replays
//     nothing, reproducibly; with conpty.dll renamed away the same run
//     passes. test-ssh-attach.py catches it.
//
// The actual cause turned out to be the session console's code page at byte
// arrival — the same on both hosts, which is why swapping hosts changed
// nothing. The fix lives in plat_pty_open below: the console is set to
// UTF-8 the way sshd sets its own, and the client sends UTF-8 bytes.

static wchar_t *to_wide(const char *utf8) {
    if (!utf8) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *out = malloc(sizeof(wchar_t) * (size_t)n);
    if (!out) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

// What a session runs when the client asked for "a shell". PowerShell is the
// Windows equivalent of the login shell forkpty would have given us.
static const char *shell_command(void) {
    const char *sh = getenv("STARLING_DEV_SHELL");
    if (sh && *sh) return sh;
    const char *comspec = getenv("COMSPEC");
    return comspec && *comspec ? "powershell.exe -NoLogo" : "cmd.exe";
}

plat_pty *plat_pty_open(uint16_t cols, uint16_t rows, const char *command) {
    plat_pty *p = calloc(1, sizeof(*p));
    if (!p) return NULL;

    HANDLE in_read = NULL, out_write = NULL;
    if (!CreatePipe(&in_read, &p->in_write, NULL, 0) ||
        !CreatePipe(&p->out_read, &out_write, NULL, 0)) {
        free(p);
        return NULL;
    }

    COORD size;
    size.X = (SHORT)(cols ? cols : 80);
    size.Y = (SHORT)(rows ? rows : 24);
    if (CreatePseudoConsole(size, in_read, out_write, 0, &p->pc) != S_OK) {
        CloseHandle(in_read); CloseHandle(out_write);
        CloseHandle(p->in_write); CloseHandle(p->out_read);
        free(p);
        return NULL;
    }
    // The pseudoconsole owns these now; ours must go or the child's end of
    // the stream never reports EOF.
    CloseHandle(in_read);
    CloseHandle(out_write);

    STARTUPINFOEXW si;
    ZeroMemory(&si, sizeof(si));
    si.StartupInfo.cb = sizeof(si);
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);   // sizing call
    si.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(bytes);
    if (!si.lpAttributeList ||
        !InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &bytes) ||
        !UpdateProcThreadAttribute(si.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   p->pc, sizeof(p->pc), NULL, NULL)) {
        free(si.lpAttributeList);
        ClosePseudoConsole(p->pc);
        CloseHandle(p->in_write); CloseHandle(p->out_read);
        free(p);
        return NULL;
    }

    // When the parent has a console and says nothing about standard handles,
    // CreateProcess hands a console child the PARENT's — so the shell writes
    // to whatever the daemon inherited instead of to the pseudoconsole, and
    // the session produces nothing but ConPTY's own opening paint while the
    // child runs perfectly. It cost a round of chasing the fixture here, and
    // the SDK's CStarlingConPTY carries the same note from the same bug.
    //
    // STARTF_USESTDHANDLES with all three NULL is the cure: the child is told
    // it has no handles to adopt, and the pseudoconsole supplies them.
    si.StartupInfo.dwFlags |= STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = NULL;
    si.StartupInfo.hStdOutput = NULL;
    si.StartupInfo.hStdError = NULL;

    const char *cmd = (command && *command) ? command : shell_command();
    wchar_t *wcmd = to_wide(cmd);
    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));
    BOOL ok = wcmd && CreateProcessW(NULL, wcmd, NULL, NULL, FALSE,
                                     EXTENDED_STARTUPINFO_PRESENT,
                                     NULL, NULL, &si.StartupInfo, &pi);
    free(wcmd);
    DeleteProcThreadAttributeList(si.lpAttributeList);
    free(si.lpAttributeList);

    if (!ok) {
        ClosePseudoConsole(p->pc);
        CloseHandle(p->in_write); CloseHandle(p->out_read);
        free(p);
        return NULL;
    }

    // The session's console must decode input as UTF-8, and there is no flag
    // on CreatePseudoConsole for it: a fresh conhost comes up at the OEM code
    // page (CP437 on an en-US box), input bytes are decoded with it on
    // arrival, and the two UTF-8 bytes of a typed é become ├⌐ before any
    // process has read anything. Nothing downstream can repair that —
    // measured: `chcp 65001` in the session, a fresh shell started after it,
    // and [Console]::InputEncoding all leave é broken, because they run after
    // the decode. Sending the é as a win32-input key EVENT dodges the arrival
    // decode and still fails: the event reaches the input queue intact
    // (ReadKey reads U+00E9), then dies in cooked reads, in PowerShell and in
    // cmd alike.
    //
    // What measurably works, end to end, with this same shell on this same
    // machine, is what sshd runs: UTF-8 bytes into a console whose code page
    // IS 65001 before the shell starts. The attach client produces exactly
    // those bytes; this makes the console side true. A code page belongs to a
    // console, not a process, and only an attached process can set it — so
    // attach to the child's console for the moment it takes. The daemon
    // ordinarily has no console of its own (spawned DETACHED); when someone
    // runs `--serve` from a terminal by hand it does, so that console is let
    // go first and re-attached after, best effort.
    //
    // Sessions are opened with g_lock held, which is what makes this
    // process-wide attach/free dance safe against a second session opening.
    //
    // Re-attach to the old console only if there WAS one. An unconditional
    // AttachConsole(ATTACH_PARENT_PROCESS) looks like a tidy restore and is
    // a live bug: an auto-spawned daemon's parent is the ATTACH CLIENT, so
    // the daemon quietly joined the client's ssh console — and an ssh
    // session does not tear down while another process holds its console,
    // which turned every ^] d into a hang with the client's own exit path
    // measuring innocent.
    int had_console = GetConsoleWindow() != NULL;
    FreeConsole();
    for (int tries = 0; tries < 40; tries++) {
        if (AttachConsole(pi.dwProcessId)) {
            SetConsoleCP(CP_UTF8);
            SetConsoleOutputCP(CP_UTF8);
            FreeConsole();
            break;
        }
        Sleep(25);
    }
    if (had_console) AttachConsole(ATTACH_PARENT_PROCESS);

    p->process = pi.hProcess;
    p->thread = pi.hThread;
    return p;
}

long plat_pty_read(plat_pty *p, void *buf, size_t n) {
    if (!p || !p->out_read) return 0;
    DWORD got = 0;
    if (!ReadFile(p->out_read, buf, (DWORD)n, &got, NULL)) {
        DWORD e = GetLastError();
        return (e == ERROR_BROKEN_PIPE || e == ERROR_HANDLE_EOF) ? 0 : -1;
    }
    return (long)got;
}

long plat_pty_write(plat_pty *p, const void *buf, size_t n) {
    if (!p || !p->in_write) return -1;
    DWORD put = 0;
    if (!WriteFile(p->in_write, buf, (DWORD)n, &put, NULL)) return -1;
    return (long)put;
}

void plat_pty_resize(plat_pty *p, uint16_t cols, uint16_t rows) {
    if (!p || !p->pc) return;
    COORD size;
    size.X = (SHORT)cols;
    size.Y = (SHORT)rows;
    // No SIGWINCH here: ConPTY tells the attached application itself.
    ResizePseudoConsole(p->pc, size);
}

int plat_pty_exited(plat_pty *p, int *status) {
    if (!p) return 1;
    if (p->exited) {
        if (status) *status = p->status;
        return 1;
    }
    if (!p->process) return 0;
    if (WaitForSingleObject(p->process, 0) == WAIT_OBJECT_0) {
        DWORD code = 0;
        GetExitCodeProcess(p->process, &code);
        p->exited = 1;
        p->status = (int)code;
        if (status) *status = p->status;
        return 1;
    }
    return 0;
}

void plat_pty_shutdown(plat_pty *p) {
    if (!p) return;
    if (p->pc) {
        // Closing the pseudoconsole ends the child's console and lets the
        // output pipe hit EOF, which is what unblocks the reader thread.
        ClosePseudoConsole(p->pc);
        p->pc = NULL;
    }
    if (p->in_write) { CloseHandle(p->in_write); p->in_write = NULL; }
    if (p->process && !p->exited) {
        if (WaitForSingleObject(p->process, 500) == WAIT_TIMEOUT) {
            TerminateProcess(p->process, 1);
        }
    }
}

void plat_pty_free(plat_pty *p) {
    if (!p) return;
    plat_pty_shutdown(p);
    if (p->out_read) { CloseHandle(p->out_read); p->out_read = NULL; }
    if (p->process) { CloseHandle(p->process); p->process = NULL; }
    if (p->thread) { CloseHandle(p->thread); p->thread = NULL; }
    free(p);
}

// ── threads and mutexes ─────────────────────────────────────────────────

struct plat_mutex { CRITICAL_SECTION cs; };

plat_mutex *plat_mutex_new(void) {
    plat_mutex *m = calloc(1, sizeof(*m));
    if (!m) return NULL;
    InitializeCriticalSection(&m->cs);
    return m;
}

void plat_mutex_lock(plat_mutex *m) { if (m) EnterCriticalSection(&m->cs); }
void plat_mutex_unlock(plat_mutex *m) { if (m) LeaveCriticalSection(&m->cs); }

struct thunk { void (*fn)(void *); void *arg; };

static unsigned __stdcall trampoline(void *v) {
    struct thunk t = *(struct thunk *)v;
    free(v);
    t.fn(t.arg);
    return 0;
}

int plat_thread_spawn(void (*fn)(void *), void *arg) {
    struct thunk *t = malloc(sizeof(*t));
    if (!t) return -1;
    t->fn = fn;
    t->arg = arg;
    uintptr_t h = _beginthreadex(NULL, 0, trampoline, t, 0, NULL);
    if (!h) { free(t); return -1; }
    CloseHandle((HANDLE)h);   // detached: nothing ever joins a reader
    return 0;
}

void plat_sleep_ms(int ms) { Sleep((DWORD)ms); }

int plat_posix_shell(void) { return 0; }

int plat_cwd_supported(void) { return 0; }

// Not implemented here. Reading another process's current directory on Windows
// means injecting into it or walking undocumented PEB structures — neither is
// worth it for a convenience, and the daemon says so in HELLO_OK's caps rather
// than answering with a guess.
int plat_pty_cwd(plat_pty *p, char *out, size_t len) {
    (void)p; (void)out; (void)len;
    return 0;
}

int plat_spawn_daemon(int idle_seconds) {
    wchar_t self[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return -1;

    wchar_t cmd[MAX_PATH + 64];
    _snwprintf(cmd, MAX_PATH + 64, L"\"%s\" --serve --idle-exit %d",
               self, idle_seconds);

    STARTUPINFOW si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    // DETACHED_PROCESS keeps the daemon off the bridge's console, and
    // CREATE_BREAKAWAY_FROM_JOB is what actually keeps it alive.
    //
    // Windows OpenSSH runs each session inside a JOB OBJECT and kills the job
    // when the connection drops, which takes every descendant with it —
    // detached or not, new process group or not. Without breakaway a session
    // does not outlive its ssh client, which is the one thing this program
    // exists to do: measured, `--list` from a second connection went from one
    // daemon to "no daemon running" the moment the first client's ssh died.
    // It is invisible locally, where nothing puts us in a job.
    //
    // Breakaway needs the job to permit it (JOB_OBJECT_LIMIT_BREAKAWAY_OK);
    // when it does not, CreateProcess fails with ERROR_ACCESS_DENIED rather
    // than silently ignoring the flag, so retry without it and leave the
    // daemon in the job. That is worse than nothing only in the sense that it
    // is what we had before — a session that dies with its client beats no
    // session at all.
    DWORD flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
                | CREATE_BREAKAWAY_FROM_JOB;
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, flags,
                        NULL, NULL, &si, &pi)) {
        if (GetLastError() != ERROR_ACCESS_DENIED) return -1;
        // The command line buffer may have been written to by the failed call.
        _snwprintf(cmd, MAX_PATH + 64, L"\"%s\" --serve --idle-exit %d",
                   self, idle_seconds);
        flags &= ~(DWORD)CREATE_BREAKAWAY_FROM_JOB;
        if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, flags,
                            NULL, NULL, &si, &pi)) {
            return -1;
        }
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return 0;
}

long plat_stdin_read(void *buf, size_t n) {
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    DWORD got = 0;
    if (!ReadFile(h, buf, (DWORD)n, &got, NULL)) {
        DWORD e = GetLastError();
        return (e == ERROR_BROKEN_PIPE || e == ERROR_HANDLE_EOF) ? 0 : -1;
    }
    return (long)got;
}

long plat_stdout_write(const void *buf, size_t n) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    size_t off = 0;
    while (off < n) {
        DWORD put = 0;
        if (!WriteFile(h, (const char *)buf + off, (DWORD)(n - off), &put, NULL))
            return -1;
        if (put == 0) return -1;
        off += put;
    }
    return (long)off;
}

// ── the attaching client's terminal ─────────────────────────────────────

static DWORD g_con_in_saved, g_con_out_saved;
static UINT g_con_cp_in_saved, g_con_cp_out_saved;
static int g_con_is_raw = 0;

// ENABLE_VIRTUAL_TERMINAL_INPUT stays ON here, and what it delivers is not
// what its name suggests. Under a ConPTY — which is every ssh session, since
// Windows OpenSSH runs one — it does not hand the client key BYTES, it hands
// it key EVENTS in win32-input-mode: `x` arrives as ESC [88;45;120;1;0;…_
// (virtual key, scan code, code point, down flag, modifiers, repeat) and one
// Ctrl-] keypress arrives as four such events, the useful one carrying code
// point 29. No 0x1d byte is ever in that stream, which is why the client's
// prefix scan has to read the events rather than the bytes (see w32_key in
// termd.c).
//
// Clearing the flag was tried first and is WRONG, though it looks like a
// one-line fix and does make ^] d work: without it the console falls back to
// translating key events into characters, and characters are all you get —
// measured over ssh, the arrow keys, Home and F1 produce NOTHING at all, and
// é arrives as a single code-page byte instead of its two UTF-8 ones. A
// terminal tunnel that cannot carry an arrow key or a non-ASCII character is
// not worth a working detach key.
int plat_tty_raw(void) {
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!GetConsoleMode(in, &g_con_in_saved)) return -1;   // piped, not a console
    if (!GetConsoleMode(out, &g_con_out_saved)) return -1;
    // The console's own equivalents of ICANON/ECHO/ISIG, plus the flag that
    // makes it hand us the key bytes rather than input records.
    DWORD im = g_con_in_saved;
    im &= (DWORD)~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT);
    im |= ENABLE_VIRTUAL_TERMINAL_INPUT;
    if (!SetConsoleMode(in, im)) return -1;
    // DISABLE_NEWLINE_AUTO_RETURN is OPOST's counterpart: without it the
    // console adds a carriage return to every LF we pass through.
    DWORD om = g_con_out_saved | ENABLE_VIRTUAL_TERMINAL_PROCESSING
             | DISABLE_NEWLINE_AUTO_RETURN;
    SetConsoleMode(out, om);
    // UTF-8 both ways for the duration, because raw mode IS byte-exact mode:
    // everything this client writes to its console is the session's byte
    // stream, and the session emits UTF-8 (ConPTY output always is). At the
    // OEM default the two bytes of an é coming BACK from a session render as
    // ├⌐ — measured with the session's ring holding perfect UTF-8, which is
    // what pinned the last mojibake on this side of the wire rather than
    // that one. Saved and restored like the modes: the code page belongs to
    // the console, which belongs to whoever ran us.
    g_con_cp_in_saved = GetConsoleCP();
    g_con_cp_out_saved = GetConsoleOutputCP();
    SetConsoleCP(CP_UTF8);
    SetConsoleOutputCP(CP_UTF8);
    g_con_is_raw = 1;
    return 0;
}

void plat_tty_restore(void) {
    if (!g_con_is_raw) return;
    SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), g_con_in_saved);
    SetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), g_con_out_saved);
    SetConsoleCP(g_con_cp_in_saved);
    SetConsoleOutputCP(g_con_cp_out_saved);
    g_con_is_raw = 0;
}

int plat_tty_size(uint16_t *cols, uint16_t *rows) {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (!GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi))
        return -1;
    // The WINDOW, not the buffer: the buffer is usually far taller, and a
    // session sized to it would draw most of itself out of sight.
    int c = csbi.srWindow.Right - csbi.srWindow.Left + 1;
    int r = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
    if (c <= 0 || r <= 0) return -1;
    *cols = (uint16_t)c;
    *rows = (uint16_t)r;
    return 0;
}
