// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A pseudo-terminal on Windows, for TerminalApp.
//
// Windows' equivalent of forkpty is ConPTY (Windows 10 1809+): a pseudoconsole
// object plus two anonymous pipes, with the child attached through a process
// thread attribute. This lives in C rather than in Swift-over-WinSDK for two
// reasons that are not stylistic:
//
//   - PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE is not a constant but a
//     ProcThreadAttributeValue(...) macro that computes a value from a
//     bitfield. Swift imports no such macro.
//   - InitializeProcThreadAttributeList takes a caller-allocated,
//     variable-sized opaque buffer whose size it reports through a failing
//     first call. That is awkward from Swift and idiomatic from C.
//
// Keeping <windows.h> behind this header also keeps its several thousand
// macros away from the C++-interop importer, exactly as FlutterWin32Bridge
// does for the host.

#ifndef STARLING_CONPTY_H
#define STARLING_CONPTY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct StarlingConPty StarlingConPty;

// Opens a pseudoconsole of `cols` x `rows` and starts `command_utf8` attached
// to it, with the working directory `cwd_utf8` (NULL for the process default).
// `command_utf8` is a full command line, not an argv — CreateProcessW parses
// it itself, which is the Windows convention.
//
// Returns NULL on failure; the reason lands on stderr.
StarlingConPty* starling_conpty_open(int32_t cols,
                                     int32_t rows,
                                     const char* command_utf8,
                                     const char* cwd_utf8);

// Blocking read of up to `len` bytes of child output. Returns the number of
// bytes read, 0 at end of output (the child closed the console or exited), or
// -1 on error. Safe to call from a dedicated reader thread while another
// thread writes.
int32_t starling_conpty_read(StarlingConPty* pty, uint8_t* buf, int32_t len);

// Bytes already queued on the output pipe, readable without blocking. 0 when
// the pipe is empty, closed, or on any error — so a caller can treat it purely
// as "is there more right now?" and never has to handle a failure separately.
//
// This exists for the reader's drain loop: ConPTY hands back small reads even
// during a flood, and publishing each one costs a ring pass. Peeking lets the
// reader keep filling one buffer while bytes are already waiting, and stop the
// instant the pipe runs dry — so batching never adds latency to a lone
// keystroke echo.
int32_t starling_conpty_avail(StarlingConPty* pty);

// Writes `len` bytes to the child's input. Returns bytes written, or -1.
int32_t starling_conpty_write(StarlingConPty* pty, const uint8_t* buf, int32_t len);

// Resizes the pseudoconsole. There is no SIGWINCH on Windows: ConPTY tells
// the attached application itself.
void starling_conpty_resize(StarlingConPty* pty, int32_t cols, int32_t rows);

// Non-zero while the child process is still running.
int32_t starling_conpty_alive(StarlingConPty* pty);

// Closes the pseudoconsole and pipes and terminates the child if it is still
// running. A reader parked in starling_conpty_read is unblocked and returns 0.
// Does NOT free `pty`, so the reader's in-flight call stays valid — freeing
// here would be a use-after-free on exactly the thread this is meant to wake.
// Idempotent.
void starling_conpty_shutdown(StarlingConPty* pty);

// Frees `pty`, shutting it down first if that has not happened. Call only once
// no thread can still be inside starling_conpty_read — i.e. after joining the
// reader.
void starling_conpty_free(StarlingConPty* pty);

// ---------------------------------------------------------------- child pipe
//
// Busy-waits `ns` nanoseconds. Sub-microsecond, so it cannot be a sleep:
// Windows timer granularity rounds a 1 us Sleep up by three orders of
// magnitude, which is the same reason Darwin's paced reader cannot use
// mach_wait_until.
//
// This exists for the pty reader's pace. A reader that re-arms its read the
// instant the last one returned catches the console's queue EMPTY and pays a
// full writer-wake round trip for the privilege; waiting about a microsecond
// first means the next read finds a batch already waiting. On Darwin that one
// change was worth 29% on the unicode cat (see Pty._startReaderPaced), and
// ConPTY has the same shape — it hands back small reads mid-flood, which is
// why the reader coalesces on PeekNamedPipe at all.
//
// Same placement argument as the child-spawn API below: this is Win32
// plumbing (QueryPerformanceCounter), not a pseudoconsole feature.
void starling_conpty_pace(uint64_t ns);

// A child process on two anonymous pipes, with NO pseudoconsole: the exact
// opposite of the above. RemoteTerminal runs `ssh host starling-termd --stdio`
// and the wire is a framed byte protocol, so a console in the middle would
// rewrite the very bytes being framed — the transport wants a raw pipe, which
// is what `ssh -T` asks for on the far side too.
//
// It is in this target because that is where Windows process plumbing already
// lives (CreateProcessW, handle inheritance, PeekNamedPipe), not because it
// has anything to do with ConPTY.

typedef struct StarlingChild StarlingChild;

// Starts `command_utf8` (a full command line, CreateProcessW convention) with
// its stdin and stdout on pipes back to us. stderr is left on the parent's, so
// ssh's diagnostics — host key prompts, "Permission denied" — reach the log
// instead of being framed as protocol data and rejected as garbage.
//
// Returns NULL on failure; the reason lands on stderr.
StarlingChild* starling_child_spawn(const char* command_utf8);

// Bytes readable without blocking. 0 when empty, closed, or on error.
int32_t starling_child_avail(StarlingChild* c);

// Blocking read of up to `len` bytes. Returns bytes read, 0 at end of stream,
// -1 on error.
int32_t starling_child_read(StarlingChild* c, uint8_t* buf, int32_t len);

// Writes `len` bytes to the child's stdin. Returns bytes written, or -1.
int32_t starling_child_write(StarlingChild* c, const uint8_t* buf, int32_t len);

// Non-zero while the child is still running.
int32_t starling_child_alive(StarlingChild* c);

// Closes both pipes, terminates the child if still running, and frees `c`.
// Unlike the ConPTY pair this is a single call: the transport's reader owns
// the handle for its whole life and is joined before teardown.
void starling_child_close(StarlingChild* c);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_CONPTY_H
