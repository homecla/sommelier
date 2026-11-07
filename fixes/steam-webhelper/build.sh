#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 homecla
#
# Builds the steam-webhelper fix (64-bit Windows DLL) and its test programs with mingw-w64.
# Usage: ./build.sh [output-dir]      (requires x86_64-w64-mingw32-gcc)
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-build}"
CC="${CC:-x86_64-w64-mingw32-gcc}"
mkdir -p "$OUT"

# Reproducible, small output: no timestamps, no debug info, static libgcc
# shellcheck disable=SC2054  # the comma belongs to the linker option -Wl,--no-insert-timestamp
CFLAGS=(-O2 -s -Wall -Wextra -static-libgcc -Wl,--no-insert-timestamp)

"$CC" "${CFLAGS[@]}" -shared -o "$OUT/winmm.dll" proxy.c winmm.def -lkernel32 -luser32
"$CC" "${CFLAGS[@]}" -o "$OUT/steamwebhelper.exe" test/cmdline.c -lwinmm
cp "$OUT/steamwebhelper.exe" "$OUT/other.exe"

( cd "$OUT" && sha256sum winmm.dll steamwebhelper.exe > SHA256SUMS && cat SHA256SUMS )
