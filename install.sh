#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 homecla
# Installa (o aggiorna) tutto con un solo comando / Install (or update) everything with one command:
#   1. il comando / the command `sommelier` → ~/.local/bin
#   2. l'app / the app "Sommelier" → /Applications
#   3. Wine (ramo predefinito / default branch), oppure aggiorna / or update the installed versions
#
# Uso / Usage: ./install.sh [--no-wine] [--branch stable|devel|staging]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Message language: SOMMELIER_LANG=en|it, otherwise the Mac's language (fallback: English)
case "${SOMMELIER_LANG:-}" in en|it) UI_LANG="$SOMMELIER_LANG";; *)
  case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')" in it*) UI_LANG=it;; *) UI_LANG=en;; esac;; esac
t() { if [ "$UI_LANG" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
WITH_WINE=1; BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-wine) WITH_WINE=0;;
    --branch|-b) BRANCH="${2:-}"; shift;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "$(t 'opzione sconosciuta' 'unknown option'): $1" >&2; exit 1;;
  esac
  shift
done

say() { printf '\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# 0. Move the install made under the old name ("WineHQ Manager") to the Trash
for old in "$HOME/.local/bin/winehq" "$HOME/.local/share/winehq" "/Applications/WineHQ Manager.app" "$HOME/Applications/WineHQ Manager.app"; do
  if [ -e "$old" ]; then
    pkill -x "WineHQ Manager" 2>/dev/null || true
    mv "$old" "$HOME/.Trash/$(printf '%s' "${old#"$HOME"/}" | tr '/' '_')-$(date +%s)" && echo "    $(t 'vecchia versione spostata nel Cestino' 'old version moved to the Trash'): $old"
  fi
done

# 1. Command
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/sommelier" "$BIN_DIR/sommelier"
PRESETS_DIR="$HOME/.local/share/sommelier/presets"
mkdir -p "$PRESETS_DIR"
cp "$HERE"/presets/*.preset "$PRESETS_DIR/"
say "$(t 'Comando installato' 'Command installed'): $BIN_DIR/sommelier"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *)
  echo "    $(t 'Aggiungi ~/.local/bin al PATH' 'Add ~/.local/bin to your PATH'):  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zprofile";;
esac

# 2. Rosetta (required by Wine on Apple Silicon)
if [ "$(uname -m)" = arm64 ] && ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  say "$(t 'Installo Rosetta 2' 'Installing Rosetta 2')"
  softwareupdate --install-rosetta --agree-to-license || echo "    ($(t "non riuscito: riprova con 'sommelier rosetta'" "failed: try again with 'sommelier rosetta'"))"
fi

# 3. App
APPS=/Applications; [ -w "$APPS" ] || { APPS="$HOME/Applications"; mkdir -p "$APPS"; }
if pgrep -xq "Sommelier"; then osascript -e 'quit app "Sommelier"' 2>/dev/null || true; sleep 1; fi
"$HERE/app/build-app.sh" "$APPS"

# 4. Wine
if [ $WITH_WINE = 1 ]; then
  [ -n "$BRANCH" ] && "$BIN_DIR/sommelier" default "$BRANCH"
  say "$(t 'Controllo Wine' 'Checking Wine')"
  if [ -n "$BRANCH" ]; then "$BIN_DIR/sommelier" install "$BRANCH"; else "$BIN_DIR/sommelier" update; fi
fi

echo
say "$(t 'Tutto pronto!' 'All set!')"
echo "    • $(t 'Apri «Sommelier» dal Launchpad o da' 'Open “Sommelier” from Launchpad or from') $APPS"
echo "    • $(t 'Da terminale: sommelier help   (aggiornare Wine: sommelier update)' 'From the terminal: sommelier help   (update Wine: sommelier update)')"
