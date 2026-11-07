# Fix: Steam's black window

**English** · [Italiano](README.it.md)

Under Wine on macOS, Steam opens but its window stays black. Steam's interface is Chromium
(`steamwebhelper.exe`), and Chromium draws in a separate GPU process. Wine's macOS driver
cannot show what another process draws into a window. With `--in-process-gpu`, Chromium
draws inside the browser process instead, which Wine can display. Steam has no option to
pass that flag, so this fix adds it.

## How it works

- `proxy.c` builds a `winmm.dll` that Sommelier installs in the bottle's `system32`, next
  to Wine's own winmm (copied as `winmm_orig.dll`). Every winmm function is forwarded to
  the original (`winmm.def`, generated from Wine's `winmm.spec`).
- A per-program Wine setting loads it **only** for `steamwebhelper.exe`:
  `HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides` → `winmm = native,builtin`.
- When the browser process starts, the DLL makes `GetCommandLineW` return the command line
  with `--in-process-gpu` appended. Chromium's child processes (`--type=…`) and every
  other program are left alone. Steam's files are never modified, so Steam can keep
  updating itself.

## Build and release

GitHub Actions builds it with mingw-w64 (`build.sh`,
[workflow](../../.github/workflows/steam-webhelper-fix.yml)). A `steam-webhelper-v*` tag
publishes the DLL as a release. `sommelier` downloads it only for recipes with
`FIXES="steam-webhelper"` and checks the SHA-256 pinned in the script.

`test/cmdline.c` is a test program: built as `steamwebhelper.exe` it must see
`--in-process-gpu`, while `steamwebhelper.exe --type=gpu-process` and `other.exe` must not.

License: AGPL-3.0-or-later.
