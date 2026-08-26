/* A crash log that names the function.
 *
 * The shell is a supervised background process: when it dies the supervisor
 * puts up a new one and the only trace left is a WER report and a dump. That
 * is a poor trade for a desktop that has to stay up, because the dump is
 * ~900 MB, lives on the machine that crashed, and answers nothing on its own
 * -- a release build carries no symbols, so `!analyze` prints a column of
 * `WinShellBar+0x63a90a` and the work of turning that into a source location
 * is hours per crash.
 *
 * Worse, the exception code is nearly always 0xC000001D, ILLEGAL INSTRUCTION,
 * which reads like a corrupted binary and is nothing of the sort: Swift emits
 * `ud2` for a failed precondition, so every force-unwrapped nil, out-of-range
 * index and overflowing conversion in the shell arrives as "illegal
 * instruction" at an address in the middle of a function. The code says only
 * that Swift gave up; it never says where.
 *
 * So: catch it on the way out and write the stack, with names when a .pdb is
 * beside the binary (build with `tools\build-windows.ps1 -DebugInfo`) and
 * module+offset always. The filter returns EXCEPTION_CONTINUE_SEARCH, so WER
 * still runs and still writes its dump -- this adds a legible record, it does
 * not replace the one that was there.
 */

#include <windows.h>
#include <dbghelp.h>
#include <stdio.h>

#pragma comment(lib, "dbghelp.lib")

/* Everything the handler touches is preallocated. A crash handler that
 * allocates can fail exactly when it is needed -- and for a stack overflow it
 * runs on a thread with almost no stack left. */
static wchar_t g_log_path[MAX_PATH];
static int g_installed = 0;
static LPTOP_LEVEL_EXCEPTION_FILTER g_previous = NULL;
static CRITICAL_SECTION g_lock;

/* SYMBOL_INFO is a variable-length struct: the name is written past its end,
 * so the buffer has to carry room for it. */
typedef struct {
    SYMBOL_INFO info;
    char name[512];
} SymbolBuffer;
static SymbolBuffer g_symbol;
static char g_line[1024];

static void write_line(HANDLE file, const char* text) {
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD written = 0;
    WriteFile(file, text, (DWORD)strlen(text), &written, NULL);
}

/* What the address belongs to, when no symbol is available: the module name
 * and the offset into it. That pair stays decodable later against the same
 * binary, which is the whole point of writing it down. */
static void describe_module(void* address, char* out, size_t out_size) {
    HMODULE module = NULL;
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                                | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)address, &module)
        || module == NULL) {
        _snprintf_s(out, out_size, _TRUNCATE, "0x%p", address);
        return;
    }
    char path[MAX_PATH];
    if (GetModuleFileNameA(module, path, MAX_PATH) == 0) {
        _snprintf_s(out, out_size, _TRUNCATE, "0x%p", address);
        return;
    }
    const char* base = strrchr(path, '\\');
    base = (base != NULL) ? base + 1 : path;
    _snprintf_s(out, out_size, _TRUNCATE, "%s+0x%llx", base,
                (unsigned long long)((char*)address - (char*)module));
}

/* Names the exception codes this process actually dies of, so the log leads
 * with the meaning rather than a number to go and look up. */
static const char* describe_code(DWORD code) {
    switch (code) {
        /* Swift's failed preconditions, and by far the most common: the
         * compiler lowers Builtin.condfail to `ud2`. Nothing is wrong with
         * the instruction stream. */
        case EXCEPTION_ILLEGAL_INSTRUCTION:
            return "illegal instruction -- a Swift runtime trap "
                   "(force-unwrapped nil, index out of range, overflow, or an "
                   "explicit precondition/fatalError)";
        case EXCEPTION_STACK_OVERFLOW:
            return "stack overflow -- unbounded recursion";
        case EXCEPTION_ACCESS_VIOLATION:
            return "access violation";
        case EXCEPTION_INT_DIVIDE_BY_ZERO:
            return "integer divide by zero";
        case EXCEPTION_PRIV_INSTRUCTION:
            return "privileged instruction";
        case 0xE06D7363:
            return "an unhandled C++ exception";
        default:
            return "unhandled exception";
    }
}

static void write_stack(HANDLE file, EXCEPTION_POINTERS* ep) {
    HANDLE process = GetCurrentProcess();
    HANDLE thread = GetCurrentThread();

    CONTEXT context = *ep->ContextRecord;
    STACKFRAME64 frame;
    memset(&frame, 0, sizeof(frame));
    frame.AddrPC.Offset = context.Rip;
    frame.AddrPC.Mode = AddrModeFlat;
    frame.AddrFrame.Offset = context.Rbp;
    frame.AddrFrame.Mode = AddrModeFlat;
    frame.AddrStack.Offset = context.Rsp;
    frame.AddrStack.Mode = AddrModeFlat;

    for (int i = 0; i < 64; i++) {
        if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame,
                         &context, NULL, SymFunctionTableAccess64,
                         SymGetModuleBase64, NULL)) {
            break;
        }
        if (frame.AddrPC.Offset == 0) break;

        char where[600];
        describe_module((void*)(uintptr_t)frame.AddrPC.Offset, where,
                        sizeof(where));

        memset(&g_symbol, 0, sizeof(g_symbol));
        g_symbol.info.SizeOfStruct = sizeof(SYMBOL_INFO);
        g_symbol.info.MaxNameLen = sizeof(g_symbol.name) - 1;
        DWORD64 displacement = 0;
        const char* name = NULL;
        if (SymFromAddr(process, frame.AddrPC.Offset, &displacement,
                        &g_symbol.info)) {
            name = g_symbol.info.Name;
        }

        IMAGEHLP_LINE64 line;
        memset(&line, 0, sizeof(line));
        line.SizeOfStruct = sizeof(line);
        DWORD line_displacement = 0;
        int have_line = SymGetLineFromAddr64(process, frame.AddrPC.Offset,
                                             &line_displacement, &line);

        if (name != NULL && have_line) {
            _snprintf_s(g_line, sizeof(g_line), _TRUNCATE,
                        "  %02d  %s  (%s:%lu)  [%s]\r\n", i, name,
                        line.FileName, (unsigned long)line.LineNumber, where);
        } else if (name != NULL) {
            _snprintf_s(g_line, sizeof(g_line), _TRUNCATE,
                        "  %02d  %s +0x%llx  [%s]\r\n", i, name,
                        (unsigned long long)displacement, where);
        } else {
            _snprintf_s(g_line, sizeof(g_line), _TRUNCATE, "  %02d  %s\r\n", i,
                        where);
        }
        write_line(file, g_line);
    }
}

static LONG WINAPI crash_filter(EXCEPTION_POINTERS* ep) {
    /* One writer, and only the first crash: a second thread faulting while
     * this one walks its stack would interleave two reports into one file,
     * and the first is the one that explains the death. */
    static LONG writing = 0;
    if (InterlockedCompareExchange(&writing, 1, 0) != 0) {
        return EXCEPTION_CONTINUE_SEARCH;
    }

    HANDLE file = CreateFileW(g_log_path, FILE_APPEND_DATA, FILE_SHARE_READ,
                              NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        SYSTEMTIME now;
        GetSystemTime(&now);
        DWORD code = ep->ExceptionRecord->ExceptionCode;
        char where[600];
        describe_module(ep->ExceptionRecord->ExceptionAddress, where,
                        sizeof(where));
        _snprintf_s(g_line, sizeof(g_line), _TRUNCATE,
                    "\r\n=== %04d-%02d-%02dT%02d:%02d:%02dZ  pid %lu  "
                    "thread %lu\r\n"
                    "    0x%08lx  %s\r\n"
                    "    at %s\r\n",
                    now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
                    now.wSecond, (unsigned long)GetCurrentProcessId(),
                    (unsigned long)GetCurrentThreadId(), (unsigned long)code,
                    describe_code(code), where);
        write_line(file, g_line);

        /* A stack overflow gets the header and nothing else. The filter runs
         * on the thread that just ran out of stack, and dbghelp is not frugal
         * -- walking here is how a crash report turns into a second crash and
         * no report at all. The header still names the thread, which with the
         * dump is enough. */
        if (code == EXCEPTION_STACK_OVERFLOW) {
            write_line(file, "  (stack exhausted -- no walk; see the WER "
                             "dump for frames)\r\n");
        } else {
            write_stack(file, ep);
        }
        FlushFileBuffers(file);
        CloseHandle(file);
    }

    /* Hand it on: WER writes the dump it always wrote, and any filter
     * installed before this one still runs. */
    if (g_previous != NULL) return g_previous(ep);
    return EXCEPTION_CONTINUE_SEARCH;
}

void flwin32_crashlog_install(const char* utf8_path) {
    if (g_installed || utf8_path == NULL) return;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, g_log_path, MAX_PATH)
        == 0) {
        return;
    }
    InitializeCriticalSection(&g_lock);

    /* Symbols are initialised HERE, not in the filter: SymInitialize reads
     * the PDB off disk and allocates, which is work a crashing process should
     * not be discovering it has to do. Deferred loads keep the cost to
     * nothing until a symbol is actually asked for -- which is only ever
     * inside the filter. */
    SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_UNDNAME | SYMOPT_LOAD_LINES);
    SymInitialize(GetCurrentProcess(), NULL, TRUE);

    g_previous = SetUnhandledExceptionFilter(crash_filter);
    g_installed = 1;
}
