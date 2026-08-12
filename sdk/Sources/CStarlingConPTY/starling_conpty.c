// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#include "include/starling_conpty.h"

#include <stdio.h>
#include <stdlib.h>

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

// ConPTY arrived in Windows 10 1809 and its declarations are gated on the
// target version, so ask for Windows 10 before pulling the headers in.
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>

struct StarlingConPty {
  HPCON pc;
  // The ends we keep: what we write to becomes the child's input, what we
  // read from is the child's output. The other end of each pipe belongs to
  // the pseudoconsole and is closed right after CreatePseudoConsole — ConPTY
  // duplicates what it needs, and holding them open would mean a read never
  // sees end-of-file when the child exits.
  HANDLE input_write;
  HANDLE output_read;
  HANDLE process;
  HANDLE thread;
  LONG closing;  // set before closing handles, so a racing read reports EOF
};

// UTF-8 -> UTF-16. Caller frees. NULL in, NULL out.
static wchar_t* to_wide(const char* utf8) {
  if (utf8 == NULL) {
    return NULL;
  }
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (n <= 0) {
    return NULL;
  }
  wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
  if (out == NULL) {
    return NULL;
  }
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
  return out;
}

StarlingConPty* starling_conpty_open(int32_t cols,
                                     int32_t rows,
                                     const char* command_utf8,
                                     const char* cwd_utf8) {
  if (cols <= 0) {
    cols = 80;
  }
  if (rows <= 0) {
    rows = 24;
  }

  HANDLE in_read = NULL, in_write = NULL;
  HANDLE out_read = NULL, out_write = NULL;
  if (!CreatePipe(&in_read, &in_write, NULL, 0) ||
      !CreatePipe(&out_read, &out_write, NULL, 0)) {
    fprintf(stderr, "[conpty] CreatePipe failed (%lu)\n", GetLastError());
    return NULL;
  }

  COORD size;
  size.X = (SHORT)cols;
  size.Y = (SHORT)rows;

  HPCON pc = NULL;
  HRESULT hr = CreatePseudoConsole(size, in_read, out_write, 0, &pc);
  // ConPTY has duplicated whatever it needs; these ends are the console's, not
  // ours. Closing out_write in particular is what lets our read see EOF when
  // the child goes away.
  CloseHandle(in_read);
  CloseHandle(out_write);
  if (FAILED(hr)) {
    fprintf(stderr, "[conpty] CreatePseudoConsole failed (hr=0x%08lx)\n",
            (unsigned long)hr);
    CloseHandle(in_write);
    CloseHandle(out_read);
    return NULL;
  }

  // Attribute list carrying the pseudoconsole. The first call fails by
  // design and reports the size to allocate.
  SIZE_T attr_size = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
  LPPROC_THREAD_ATTRIBUTE_LIST attrs =
      (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_size);
  if (attrs == NULL ||
      !InitializeProcThreadAttributeList(attrs, 1, 0, &attr_size) ||
      !UpdateProcThreadAttribute(attrs, 0,
                                 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                 pc, sizeof(pc), NULL, NULL)) {
    fprintf(stderr, "[conpty] attribute list failed (%lu)\n", GetLastError());
    if (attrs != NULL) {
      free(attrs);
    }
    ClosePseudoConsole(pc);
    CloseHandle(in_write);
    CloseHandle(out_read);
    return NULL;
  }

  STARTUPINFOEXW si;
  ZeroMemory(&si, sizeof(si));
  si.StartupInfo.cb = sizeof(STARTUPINFOEXW);
  si.lpAttributeList = attrs;

  // CreateProcessW with a NULL environment gives the child a copy of ours, so
  // setting these here is how they reach it. Native console programs ignore
  // TERM and ask the console what it can do, but plenty of ported ones (git,
  // vim and the rest of the Git-for-Windows tree) still consult it, and
  // without it they fall back to a dumb terminal. Mutating our own
  // environment is a real side effect, but an invisible one in a process
  // whose whole purpose is hosting this child.
  SetEnvironmentVariableW(L"TERM", L"xterm-256color");
  SetEnvironmentVariableW(L"COLORTERM", L"truecolor");

  // CreateProcessW may write to the command line buffer, so it cannot be the
  // caller's string — to_wide already gives us a private copy.
  wchar_t* cmd = to_wide(command_utf8);
  wchar_t* cwd = to_wide(cwd_utf8);
  if (cmd == NULL) {
    fprintf(stderr, "[conpty] no command\n");
    DeleteProcThreadAttributeList(attrs);
    free(attrs);
    ClosePseudoConsole(pc);
    CloseHandle(in_write);
    CloseHandle(out_read);
    free(cwd);
    return NULL;
  }

  // Stop our own standard handles reaching the child.
  //
  // bInheritHandles=FALSE is not enough, and neither is clearing
  // HANDLE_FLAG_INHERIT: this is not handle inheritance. When the parent has
  // a console and says nothing about standard handles, CreateProcess hands a
  // console child the parent's — and if ours are redirected to a file (the app
  // started as `TerminalApp > log`), the shell writes there instead of to the
  // pseudoconsole. The terminal then renders nothing while the shell appears
  // to run perfectly. Found exactly that way.
  //
  // Saying STARTF_USESTDHANDLES with all three NULL is what stops it: the
  // child is told it has no standard handles to adopt, and the pseudoconsole
  // it is attached to supplies them instead.
  si.StartupInfo.dwFlags |= STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput = NULL;
  si.StartupInfo.hStdOutput = NULL;
  si.StartupInfo.hStdError = NULL;

  PROCESS_INFORMATION pi;
  ZeroMemory(&pi, sizeof(pi));
  BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, FALSE,
                           EXTENDED_STARTUPINFO_PRESENT, NULL, cwd,
                           &si.StartupInfo, &pi);
  DWORD spawn_error = GetLastError();
  DeleteProcThreadAttributeList(attrs);
  free(attrs);
  free(cmd);
  free(cwd);

  if (!ok) {
    fprintf(stderr, "[conpty] CreateProcessW failed (%lu)\n", spawn_error);
    ClosePseudoConsole(pc);
    CloseHandle(in_write);
    CloseHandle(out_read);
    return NULL;
  }

  StarlingConPty* pty = (StarlingConPty*)calloc(1, sizeof(StarlingConPty));
  if (pty == NULL) {
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    ClosePseudoConsole(pc);
    CloseHandle(in_write);
    CloseHandle(out_read);
    return NULL;
  }
  pty->pc = pc;
  pty->input_write = in_write;
  pty->output_read = out_read;
  pty->process = pi.hProcess;
  pty->thread = pi.hThread;
  pty->closing = 0;
  return pty;
}

int32_t starling_conpty_read(StarlingConPty* pty, uint8_t* buf, int32_t len) {
  if (pty == NULL || buf == NULL || len <= 0) {
    return -1;
  }
  DWORD got = 0;
  if (!ReadFile(pty->output_read, buf, (DWORD)len, &got, NULL)) {
    // BROKEN_PIPE is the ordinary end: the child exited and the console
    // dropped its write end. Anything during close is also an ordinary end.
    DWORD err = GetLastError();
    if (err == ERROR_BROKEN_PIPE || InterlockedCompareExchange(&pty->closing, 0, 0)) {
      return 0;
    }
    return -1;
  }
  return (int32_t)got;
}

int32_t starling_conpty_write(StarlingConPty* pty, const uint8_t* buf, int32_t len) {
  if (pty == NULL || buf == NULL || len <= 0) {
    return -1;
  }
  DWORD put = 0;
  if (!WriteFile(pty->input_write, buf, (DWORD)len, &put, NULL)) {
    return -1;
  }
  return (int32_t)put;
}

void starling_conpty_resize(StarlingConPty* pty, int32_t cols, int32_t rows) {
  if (pty == NULL || cols <= 0 || rows <= 0) {
    return;
  }
  COORD size;
  size.X = (SHORT)cols;
  size.Y = (SHORT)rows;
  ResizePseudoConsole(pty->pc, size);
}

int32_t starling_conpty_alive(StarlingConPty* pty) {
  if (pty == NULL) {
    return 0;
  }
  return WaitForSingleObject(pty->process, 0) == WAIT_TIMEOUT ? 1 : 0;
}

void starling_conpty_shutdown(StarlingConPty* pty) {
  if (pty == NULL || InterlockedExchange(&pty->closing, 1) != 0) {
    return;  // already shut down
  }

  // Order matters: closing the pseudoconsole signals the attached application
  // to exit and releases the console's copy of the output pipe, which is what
  // wakes a reader parked in ReadFile.
  ClosePseudoConsole(pty->pc);
  pty->pc = NULL;
  CloseHandle(pty->input_write);
  pty->input_write = NULL;
  CloseHandle(pty->output_read);
  pty->output_read = NULL;

  if (WaitForSingleObject(pty->process, 2000) == WAIT_TIMEOUT) {
    TerminateProcess(pty->process, 1);
  }
}

void starling_conpty_free(StarlingConPty* pty) {
  if (pty == NULL) {
    return;
  }
  starling_conpty_shutdown(pty);
  CloseHandle(pty->process);
  CloseHandle(pty->thread);
  free(pty);
}
