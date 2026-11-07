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
// When steamwebhelper.exe starts, its imports load before its code runs; DllMain builds the
// command line with --in-process-gpu appended and makes GetCommandLineW (which Chromium uses)
// return it.
// Child processes (their command line contains --type=) are left alone. Every winmm
// function is forwarded to winmm_orig.dll (see winmm.def). Steam's own files are never changed.

#include <windows.h>
#include <winternl.h>

static const wchar_t FLAG[] = L" --in-process-gpu";
static wchar_t *new_cmdline;

static LPWSTR WINAPI hooked_GetCommandLineW(void) { return new_cmdline; }

static int is_padding(const unsigned char *p, size_t n)
{
    for (size_t i = 0; i < n; i++) if (p[i] != 0xCC && p[i] != 0x90) return 0;
    return 1;
}

// Wine's GetCommandLineW returns a pointer cached when the process starts
// (kernelbase: "static WCHAR *command_lineW; ... return command_lineW;"), so changing the
// process parameters is not enough: GetCommandLineW must return the new buffer.
static void redirect_get_command_line(void)
{
    HMODULE kb = GetModuleHandleW(L"kernelbase.dll");
    unsigned char *fn = kb ? (unsigned char *)GetProcAddress(kb, "GetCommandLineW") : NULL;
    if (!fn) fn = (unsigned char *)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetCommandLineW");
    if (!fn) return;

    // Preferred: the function is "mov rax, [rip+disp32]; ret" (48 8B 05 xx xx xx xx C3):
    // update the cached pointer it reads. Data only, no code is changed.
    if (fn[0] == 0x48 && fn[1] == 0x8B && fn[2] == 0x05 && fn[7] == 0xC3) {
        INT32 disp;
        memcpy(&disp, fn + 3, sizeof(disp));
        wchar_t **cached = (wchar_t **)(fn + 7 + disp);
        DWORD old;
        if (VirtualProtect(cached, sizeof(*cached), PAGE_READWRITE, &old)) {
            *cached = new_cmdline;
            VirtualProtect(cached, sizeof(*cached), old, &old);
        }
        return;
    }

    // Fallback: jump to our function (mov rax, imm64; jmp rax = 12 bytes), only when the
    // bytes we overwrite end with the function's "ret" followed by alignment padding.
    unsigned char *ret = memchr(fn, 0xC3, 12);
    if (!ret || !is_padding(ret + 1, (size_t)(fn + 12 - (ret + 1)))) return;
    unsigned char jump[12] = { 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xE0 };
    void *target = (void *)hooked_GetCommandLineW;
    memcpy(jump + 2, &target, sizeof(target));
    DWORD old;
    if (VirtualProtect(fn, sizeof(jump), PAGE_EXECUTE_READWRITE, &old)) {
        memcpy(fn, jump, sizeof(jump));
        VirtualProtect(fn, sizeof(jump), old, &old);
        FlushInstructionCache(GetCurrentProcess(), fn, sizeof(jump));
    }
}

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

    cl->Buffer = buf;
    cl->Length = (USHORT)(total * sizeof(wchar_t));
    cl->MaximumLength = (USHORT)((total + 1) * sizeof(wchar_t));
    new_cmdline = buf;
    redirect_get_command_line();
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
