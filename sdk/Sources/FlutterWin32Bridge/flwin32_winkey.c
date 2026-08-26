// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_winkey.c -- the Windows key opens OUR Start menu.
 *
 * A shell that draws Start and cannot be opened by the key labelled with the
 * Windows logo is a demo. Explorer's taskbar is hidden by then, but explorer
 * itself is still running and still owns that key, so a bare tap brings up
 * Windows' Start over the top of ours.
 *
 * RegisterHotKey cannot help: MOD_WIN is a MODIFIER there, and a hotkey needs
 * a second key to modify. The only way to see a lone Windows key is a
 * low-level keyboard hook.
 *
 * WHAT WE DO NOT DO: swallow the key on the way DOWN. Every Win+<key> in the
 * system -- Win+E, Win+D, Win+L, Win+Shift+S -- is dispatched by Windows off
 * the real key state, so a shell that eats the keydown has to re-synthesize
 * the entire shortcut table, and gets to keep whichever ones Microsoft adds
 * next. The keydown passes through untouched and every combination keeps
 * working with no help from us.
 *
 * WHAT WE DO: Windows opens Start on the key UP, and only when nothing
 * happened in between. So on a bare tap -- and only then -- the real keyup is
 * swallowed and replayed behind an unassigned virtual key, which is what
 * makes the tap not-bare as far as explorer is concerned. AutoHotkey has
 * masked the Windows key this way for twenty years; 0xE8 is unassigned in
 * every Windows version and is the key it uses.
 *
 * Masking on the tap rather than on every keydown is the point of the
 * swallow-and-replay: the mask key is real input and goes to whatever has
 * focus, so injecting it on every Win press would sprinkle a spurious keydown
 * through every Win+<key> the user types. On a bare tap the foreground window
 * is about to lose focus to the launcher anyway.
 *
 * THE THREAD RULE. A WH_KEYBOARD_LL hook needs no DLL -- Windows calls it back
 * on the thread that installed it, as that thread pumps messages. So this must
 * be installed on the UI thread, and it means the hook runs INSIDE the input
 * path: everything the system types goes through it. LowLevelHooksTimeout is
 * 300ms by default and a hook that overruns it is silently unhooked, at which
 * point the Windows key goes quietly back to opening Microsoft's Start. Hence
 * the callback is POSTED to a message-only window rather than run here; the
 * hook itself does bookkeeping, one SendInput and one PostMessage.
 *
 * WHAT IT CANNOT REACH: UIPI. An unelevated shell's hook is not called for
 * input going to a higher-integrity window, so tapping Windows while Task
 * Manager has focus opens Windows' Start. Running the shell elevated is the
 * fix, and that is a decision for the phase that replaces Winlogon\Shell.
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

#include "include/FlutterWin32Bridge.h"

/* Unassigned in every Windows version, and the one AutoHotkey masks with.
 * It has to be a key no application acts on and no shortcut table contains. */
#define kMaskVk 0xE8

/* Stamped into dwExtraInfo on everything we inject, so the hook can tell its
 * own replay from the user's typing. Without it the synthesized keyup looks
 * like a second tap and the launcher toggles twice per press. */
#define kInjectTag 0x53544152u /* 'STAR' */

#define WM_STARLING_WINKEY_TAP (WM_USER + 0x52)
#define WM_STARLING_WINKEY_CHORD (WM_USER + 0x53)

static HHOOK g_hook;
static HWND g_sink;
/* Held for as long as this process owns the key -- see the mutex note in
 * flwin32_winkey_capture. */
static HANDLE g_owner;
static void (*g_callback)(void* user);
static void* g_user;

/* Whether a Windows key is physically down, which one, and whether anything
 * else has happened since -- the whole of "was this a bare tap". */
static BOOL g_win_down;
static DWORD g_win_vk;
static BOOL g_win_used;

/* CHORDS THE SHELL TAKES FOR ITSELF -- the exception to "the keydown passes
 * through untouched" above, and a narrow one. Win+A is Quick Settings and
 * Win+N is the notification centre: both open EXPLORER surfaces we have
 * replaced, so letting Windows dispatch them puts Microsoft's panel over
 * ours -- the one case where re-synthesizing is not optional. Only the keys
 * in g_chord_vks are eaten; Win+E and the rest still go to Windows.
 *
 * Both the down and the up of the chorded letter are swallowed: the down is
 * what Windows acts on, and the up left behind would arrive at the focused
 * window as a spurious bare-letter keyup. The Win keyup that follows is
 * already not-bare (g_win_used), so it replays through the normal path. */
static void (*g_chord_cb)(void* user, int32_t vk);
static void* g_chord_user;
static DWORD g_chord_vks[8];
static int g_chord_count;
/* The letter whose keyup we still owe a swallow. */
static DWORD g_chord_eating;
/* Modifier state for the Ctrl+Esc chord: Windows sends SC_TASKLIST to the
 * TASKMAN owner, and with the explorer service running that owner is
 * explorer (flwin32_shell_take_taskman_window declines the claim there, and
 * a foreign claim is what broke packaged-app presentation) -- so this hook
 * is what keeps Ctrl+Esc pointed at OUR Start. */
static BOOL g_ctrl_down;
static BOOL g_shift_down;
/* Whether an eaten Ctrl+Esc still owes its keyup (and its auto-repeats) a
 * swallow. */
static BOOL g_esc_eating;
/* Whether THIS hold of the Windows key had one of our chords eaten out of
 * it. The Win keyup after that must be masked from Windows too: we ate the
 * letter, so from Explorer's seat the hold was empty -- a bare tap -- and it
 * would open Microsoft's Start over the panel our chord just opened. */
static BOOL g_win_chorded;

/* mask, mask-up, then the keyup we swallowed. Returns whether the whole
 * sequence was accepted: if it was not, the caller must let the real keyup
 * through, because a Windows key the system still believes is held down turns
 * the next letter the user types into a shortcut. */
static BOOL replay_masked_keyup(DWORD win_vk) {
  INPUT in[3];
  ZeroMemory(in, sizeof(in));
  in[0].type = INPUT_KEYBOARD;
  in[0].ki.wVk = kMaskVk;
  in[0].ki.dwExtraInfo = kInjectTag;
  in[1] = in[0];
  in[1].ki.dwFlags = KEYEVENTF_KEYUP;
  in[2].type = INPUT_KEYBOARD;
  in[2].ki.wVk = (WORD)win_vk;
  /* LWIN and RWIN are extended keys (E0 5B / E0 5C). The state Windows keeps
   * is per virtual key, so the flag is not what clears it -- it is here so
   * the event we replay is the same shape as the one we ate. */
  in[2].ki.dwFlags = KEYEVENTF_KEYUP | KEYEVENTF_EXTENDEDKEY;
  in[2].ki.dwExtraInfo = kInjectTag;
  return SendInput(3, in, sizeof(INPUT)) == 3;
}

static LRESULT CALLBACK winkey_hook(int code, WPARAM wparam, LPARAM lparam) {
  if (code != HC_ACTION) {
    return CallNextHookEx(NULL, code, wparam, lparam);
  }
  KBDLLHOOKSTRUCT* ev = (KBDLLHOOKSTRUCT*)lparam;
  if (ev == NULL || ev->dwExtraInfo == kInjectTag) {
    return CallNextHookEx(NULL, code, wparam, lparam);
  }

  BOOL is_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
  BOOL is_up = (wparam == WM_KEYUP || wparam == WM_SYSKEYUP);
  BOOL is_win = (ev->vkCode == VK_LWIN || ev->vkCode == VK_RWIN);

  if (is_win && is_down) {
    /* Auto-repeat: holding the key sends this over and over, and only the
     * first one starts a tap. */
    if (!g_win_down) {
      g_win_down = TRUE;
      g_win_vk = ev->vkCode;
      g_win_used = FALSE;
    }
  } else if (is_win && is_up) {
    BOOL bare = g_win_down && ev->vkCode == g_win_vk && !g_win_used;
    BOOL chorded = g_win_down && g_win_chorded;
    g_win_down = FALSE;
    g_win_chorded = FALSE;
    if (bare && replay_masked_keyup(ev->vkCode)) {
      if (g_sink != NULL) PostMessageW(g_sink, WM_STARLING_WINKEY_TAP, 0, 0);
      return 1; /* eaten -- the replay above is the keyup the system sees */
    }
    /* A hold we took a chord out of: Windows saw the down and nothing since,
     * so this keyup reads to Explorer as a bare tap and opens ITS Start over
     * the surface our chord opened. Mask it the same way -- but post
     * nothing: the chord already did its work. */
    if (chorded && replay_masked_keyup(ev->vkCode)) {
      return 1;
    }
  } else if (is_down || is_up) {
    /* Modifier bookkeeping for the Ctrl+Esc chord below. */
    if (ev->vkCode == VK_LCONTROL || ev->vkCode == VK_RCONTROL) {
      g_ctrl_down = is_down;
    } else if (ev->vkCode == VK_LSHIFT || ev->vkCode == VK_RSHIFT) {
      g_shift_down = is_down;
    }
    /* Ctrl+Esc opens Start, and Windows acts on the DOWN: eaten here, the
     * system never sees the chord and explorer's Start stays closed; our
     * launcher toggles instead. The up (and any auto-repeat) owes a swallow
     * too, or the focused window gets an Esc it never saw pressed.
     * Ctrl+Shift+Esc is Task Manager and passes untouched. */
    if (ev->vkCode == VK_ESCAPE && !g_win_down) {
      if (is_up && g_esc_eating) {
        g_esc_eating = FALSE;
        return 1;
      }
      if (is_down && g_ctrl_down && !g_shift_down) {
        BOOL repeat = g_esc_eating;
        g_esc_eating = TRUE;
        if (!repeat && g_sink != NULL) {
          PostMessageW(g_sink, WM_STARLING_WINKEY_TAP, 0, 0);
        }
        return 1;
      }
    }
    /* The keyup owed from a chord eaten below -- swallow it even if the
     * Windows key has already been released, or the focused window gets a
     * keyup for a key it never saw go down. */
    if (is_up && g_chord_eating != 0 && ev->vkCode == g_chord_eating) {
      g_chord_eating = 0;
      return 1;
    }
    /* A chord of ours: eat it and tell the shell, before the generic
     * bookkeeping -- though that still runs, because the Win keyup after
     * this must not read as a bare tap. */
    if (is_down && g_win_down && g_chord_cb != NULL) {
      for (int i = 0; i < g_chord_count; i++) {
        if (ev->vkCode == g_chord_vks[i]) {
          g_win_used = TRUE;
          g_win_chorded = TRUE;
          g_chord_eating = ev->vkCode;
          PostMessageW(g_sink, WM_STARLING_WINKEY_CHORD, (WPARAM)ev->vkCode, 0);
          return 1;
        }
      }
    }
    /* Any other key, down or up, and this was a shortcut rather than a tap.
     * The UP matters as much as the down: Win+E released in the other order
     * (E first, then Win) would otherwise still read as bare. */
    g_win_used = TRUE;
  }
  return CallNextHookEx(NULL, code, wparam, lparam);
}

static LRESULT CALLBACK winkey_sink_proc(HWND hwnd, UINT message, WPARAM wparam,
                                         LPARAM lparam) {
  if (message == WM_STARLING_WINKEY_TAP) {
    if (g_callback != NULL) g_callback(g_user);
    return 0;
  }
  if (message == WM_STARLING_WINKEY_CHORD) {
    if (g_chord_cb != NULL) g_chord_cb(g_chord_user, (int32_t)wparam);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

/* A message-only window: never visible, never in the z-order, and it exists
 * so the tap runs on the message loop instead of inside the hook. */
static HWND make_sink(void) {
  static const wchar_t kClass[] = L"StarlingWinKeySink";
  static BOOL registered = FALSE;
  if (!registered) {
    WNDCLASSEXW wc;
    ZeroMemory(&wc, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = winkey_sink_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = kClass;
    if (RegisterClassExW(&wc) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return NULL;
    }
    registered = TRUE;
  }
  return CreateWindowExW(0, kClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL,
                         GetModuleHandleW(NULL), NULL);
}

int32_t flwin32_winkey_capture(void (*callback)(void* user), void* user) {
  /* ONE hook per SESSION, not per process. A dock per monitor is an ordinary
   * invocation (`--monitor N`), and two hooks would each swallow-and-replay
   * the same tap: the launcher would be toggled twice and never appear, which
   * reads as "the Windows key does nothing" rather than as two shells
   * fighting. First one started keeps it. Local\ scopes the name to this
   * logon session, so a second user's shell is not blocked by ours. */
  if (g_owner == NULL) {
    g_owner = CreateMutexW(NULL, TRUE, L"Local\\StarlingWinKeyHook");
    if (g_owner == NULL || GetLastError() == ERROR_ALREADY_EXISTS) {
      if (g_owner != NULL) {
        CloseHandle(g_owner);
        g_owner = NULL;
      }
      return 0;
    }
  }
  if (g_hook != NULL) {
    /* Already ours. Re-point it rather than stacking a second hook: two hooks
     * both replaying the keyup is two toggles per tap. */
    g_callback = callback;
    g_user = user;
    return 1;
  }
  if (g_sink == NULL) g_sink = make_sink();
  if (g_sink == NULL) return 0;
  g_callback = callback;
  g_user = user;
  g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, winkey_hook,
                             GetModuleHandleW(NULL), 0);
  if (g_hook == NULL) {
    DestroyWindow(g_sink);
    g_sink = NULL;
    g_callback = NULL;
    ReleaseMutex(g_owner);
    CloseHandle(g_owner);
    g_owner = NULL;
    return 0;
  }
  return 1;
}

void flwin32_winkey_release(void) {
  if (g_hook != NULL) {
    UnhookWindowsHookEx(g_hook);
    g_hook = NULL;
  }
  if (g_sink != NULL) {
    DestroyWindow(g_sink);
    g_sink = NULL;
  }
  if (g_owner != NULL) {
    ReleaseMutex(g_owner);
    CloseHandle(g_owner);
    g_owner = NULL;
  }
  g_callback = NULL;
  g_user = NULL;
  g_win_down = FALSE;
  g_win_used = FALSE;
  g_chord_cb = NULL;
  g_chord_user = NULL;
  g_chord_count = 0;
  g_chord_eating = 0;
  g_win_chorded = FALSE;
  g_ctrl_down = FALSE;
  g_shift_down = FALSE;
  g_esc_eating = FALSE;
}

int32_t flwin32_winkey_set_chords(const int32_t* vks, int32_t count,
                                  void (*callback)(void* user, int32_t vk),
                                  void* user) {
  /* Chords ride the tap hook: without it there is nothing watching the
   * keyboard, and quietly installing a second hook here would break the
   * one-hook-per-session rule the mutex enforces. */
  if (g_hook == NULL) return 0;
  if (count > (int32_t)(sizeof(g_chord_vks) / sizeof(g_chord_vks[0]))) {
    count = (int32_t)(sizeof(g_chord_vks) / sizeof(g_chord_vks[0]));
  }
  for (int32_t i = 0; i < count; i++) g_chord_vks[i] = (DWORD)vks[i];
  g_chord_count = (int)count;
  g_chord_cb = callback;
  g_chord_user = user;
  return 1;
}
