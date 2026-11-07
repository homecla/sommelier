// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla
//
// Test program for the steam-webhelper fix. Built twice, as steamwebhelper.exe and other.exe:
// it imports winmm (like Chromium) and prints the command line it sees.
// Expected with the fix installed: steamwebhelper.exe gets " --in-process-gpu" appended,
// "steamwebhelper.exe --type=gpu-process" and other.exe are unchanged.

#include <windows.h>
#include <stdio.h>

int main(void)
{
    timeBeginPeriod(1);                 // forces the winmm import, like Chromium does
    DWORD t = timeGetTime();            // forwarded call must still work
    timeEndPeriod(1);
    wprintf(L"cmdline=%ls\n", GetCommandLineW());
    wprintf(L"winmm_forwarding=%ls\n", t ? L"ok" : L"zero");
    return 0;
}
