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

#ifdef __cplusplus
}
#endif

#endif  // STARLING_CONPTY_H
