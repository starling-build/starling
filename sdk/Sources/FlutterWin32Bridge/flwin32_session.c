// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_session.c -- ending the session: sign out, sleep, restart, shut down.
 *
 * Four calls, and a privilege.
 *
 * Signing out and locking need nothing special. Shutting down and restarting
 * need SE_SHUTDOWN_NAME, which every process has in its token and NONE has
 * enabled by default -- the privilege is present and disabled, so
 * ExitWindowsEx does not fail loudly, it fails with ERROR_ACCESS_DENIED after
 * appearing to be perfectly reachable. AdjustTokenPrivileges turns it on for
 * this process, and its own return value lies: it reports success when it
 * enabled NOTHING, and the only honest answer is GetLastError() ==
 * ERROR_SUCCESS afterwards.
 *
 * Sleep is powrprof's SetSuspendState rather than a SendMessage of
 * WM_SYSCOMMAND/SC_MONITORPOWER, which only turns the display off.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <powrprof.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "powrprof.lib")
#pragma comment(lib, "advapi32.lib")

/* Enables SE_SHUTDOWN_NAME on this process. Needed for shutdown and restart,
 * and for nothing else here. */
static int enable_shutdown_privilege(void) {
    HANDLE token = NULL;
    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &token)) {
        return 0;
    }

    TOKEN_PRIVILEGES privileges;
    ZeroMemory(&privileges, sizeof(privileges));
    privileges.PrivilegeCount = 1;
    privileges.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    int ok = 0;
    if (LookupPrivilegeValueW(NULL, SE_SHUTDOWN_NAME,
                              &privileges.Privileges[0].Luid)) {
        SetLastError(ERROR_SUCCESS);
        AdjustTokenPrivileges(token, FALSE, &privileges, 0, NULL, NULL);
        /* Not the return value: AdjustTokenPrivileges reports success when it
         * enabled none of what was asked for. */
        ok = (GetLastError() == ERROR_SUCCESS) ? 1 : 0;
    }
    CloseHandle(token);
    return ok;
}

int32_t flwin32_session_can_power_off(void) {
    return enable_shutdown_privilege();
}

int32_t flwin32_session_action(int32_t action) {
    /* EWX_FORCEIFHUNG rather than EWX_FORCE: a hung app should not be able to
     * veto a shutdown the user asked for, but an app with unsaved work should
     * still get to put its dialog up. EWX_FORCE discards both. */
    switch (action) {
        case FLWIN32_SESSION_LOCK:
            return LockWorkStation() ? 1 : 0;

        case FLWIN32_SESSION_SIGN_OUT:
            return ExitWindowsEx(EWX_LOGOFF | EWX_FORCEIFHUNG, 0) ? 1 : 0;

        case FLWIN32_SESSION_SLEEP:
            /* (hibernate = FALSE, force = FALSE, disableWakeEvent = FALSE) */
            return SetSuspendState(FALSE, FALSE, FALSE) ? 1 : 0;

        case FLWIN32_SESSION_RESTART:
            if (!enable_shutdown_privilege()) return 0;
            return ExitWindowsEx(EWX_REBOOT | EWX_FORCEIFHUNG,
                                 SHTDN_REASON_MAJOR_OTHER
                                     | SHTDN_REASON_MINOR_OTHER
                                     | SHTDN_REASON_FLAG_PLANNED)
                       ? 1 : 0;

        case FLWIN32_SESSION_SHUT_DOWN:
            if (!enable_shutdown_privilege()) return 0;
            /* POWEROFF, not SHUTDOWN: the latter stops the machine and leaves
             * it powered, which on a desktop looks like a failed shutdown. */
            return ExitWindowsEx(EWX_SHUTDOWN | EWX_POWEROFF | EWX_FORCEIFHUNG,
                                 SHTDN_REASON_MAJOR_OTHER
                                     | SHTDN_REASON_MINOR_OTHER
                                     | SHTDN_REASON_FLAG_PLANNED)
                       ? 1 : 0;

        default:
            return 0;
    }
}
