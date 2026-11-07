// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla
//
// winmm.dll proxy that fixes the black Steam window under Wine on macOS.
//
// Steam's user interface is Chromium (steamwebhelper.exe). Chromium draws in a separate GPU
// process, and Wine's macOS driver cannot show what another process draws into a window, so
// the window stays black. With --in-process-gpu Chromium draws inside the browser process,
// which Wine can display. Steam has no option to pass that flag, so this DLL adds it.
//
// How it works: Sommelier installs this file as system32\winmm.dll and Wine's own winmm as
// system32\winmm_orig.dll, and enables it only for steamwebhelper.exe through
//   HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides  winmm = native,builtin
// When steamwebhelper.exe starts, its imports load before its code runs; DllMain appends
// --in-process-gpu to the process command line, which Chromium reads with GetCommandLineW.
// Child processes (their command line contains --type=) are left alone. Every winmm
// function is forwarded to winmm_orig.dll (see winmm.def). Steam's own files are never changed.

#include <windows.h>
#include <winternl.h>

static const wchar_t FLAG[] = L" --in-process-gpu";

static int contains(const wchar_t *haystack, const wchar_t *needle)
{
    return haystack && wcsstr(haystack, needle) != NULL;
}

static int is_steam_browser_process(const wchar_t *cmdline)
{
    wchar_t exe[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;
    CharLowerW(exe);
    if (!contains(exe, L"steamwebhelper.exe")) return 0;   // only Steam's browser
    if (contains(cmdline, L"--type=")) return 0;            // not renderer/GPU/utility children
    if (contains(cmdline, L"--in-process-gpu")) return 0;   // already there
    return 1;
}

static void append_flag(void)
{
    RTL_USER_PROCESS_PARAMETERS *params = NtCurrentTeb()->ProcessEnvironmentBlock->ProcessParameters;
    UNICODE_STRING *cl = &params->CommandLine;
    if (!cl->Buffer || !is_steam_browser_process(cl->Buffer)) return;

    size_t old_chars = cl->Length / sizeof(wchar_t);
    size_t flag_chars = (sizeof(FLAG) / sizeof(wchar_t)) - 1;
    size_t total = old_chars + flag_chars;
    if ((total + 1) * sizeof(wchar_t) > 0xFFFF) return;     // UNICODE_STRING limit

    wchar_t *buf = HeapAlloc(GetProcessHeap(), 0, (total + 1) * sizeof(wchar_t));
    if (!buf) return;
    memcpy(buf, cl->Buffer, old_chars * sizeof(wchar_t));
    memcpy(buf + old_chars, FLAG, flag_chars * sizeof(wchar_t));
    buf[total] = 0;

    // Wine's GetCommandLineW returns ProcessParameters->CommandLine.Buffer
    cl->Buffer = buf;
    cl->Length = (USHORT)(total * sizeof(wchar_t));
    cl->MaximumLength = (USHORT)((total + 1) * sizeof(wchar_t));
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        append_flag();
    }
    return TRUE;
}
