#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 homecla
# Builds Sommelier and creates the .app bundle.
# Usage: ./build-app.sh [destination-folder]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DEST="${1:-$HERE/build}"
APP="$DEST/Sommelier.app"
VERSION="1.0.0"
# Message language: SOMMELIER_LANG=en|it, otherwise the Mac's language (fallback: English)
case "${SOMMELIER_LANG:-}" in en|it) UI_LANG="$SOMMELIER_LANG";; *)
  case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')" in it*) UI_LANG=it;; *) UI_LANG=en;; esac;; esac
t() { if [ "$UI_LANG" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }


# With the macOS 27 SDK, @State is a macro that needs Xcode (license accepted): when Xcode
# isn't usable we build with the Command Line Tools and the newest SDK that doesn't need it.
# The resulting app still runs on macOS 27.
pick_sdk() {
  if [ -n "${SDKROOT:-}${DEVELOPER_DIR:-}" ]; then return; fi
  local x
  for x in /Applications/Xcode*.app; do
    if [ -d "$x" ] && DEVELOPER_DIR="$x/Contents/Developer" xcodebuild -license check >/dev/null 2>&1; then
      export DEVELOPER_DIR="$x/Contents/Developer"; return
    fi
  done
  local sdk
  sdk=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk 2>/dev/null | sort -V | tail -1)
  [ -n "$sdk" ] && export SDKROOT="$sdk"
  return 0
}
pick_sdk
echo "==> $(t "Compilo l'app" 'Building the app')${SDKROOT:+ (SDK: $(basename "$SDKROOT"))}"
cd "$HERE"
swift build -c release 2>&1 | grep -E "error:|Compiling|Build complete" || true
BIN="$HERE/.build/release/Sommelier"
[ -x "$BIN" ] || { echo "$(t 'errore: compilazione non riuscita' 'error: build failed')" >&2; swift build -c release; exit 1; }

echo "==> $(t 'Creo il bundle' 'Creating the bundle')"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/Sommelier.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/Sommelier"
cp "$ROOT/sommelier" "$STAGE/Contents/Resources/sommelier"
chmod +x "$STAGE/Contents/Resources/sommelier"
cp -R "$ROOT/presets" "$STAGE/Contents/Resources/presets"
# Language folders, so system menus (Edit, Window…) follow the chosen language
mkdir -p "$STAGE/Contents/Resources/en.lproj" "$STAGE/Contents/Resources/it.lproj"
printf '"CFBundleDisplayName" = "Sommelier";\n' | tee "$STAGE/Contents/Resources/en.lproj/InfoPlist.strings" > "$STAGE/Contents/Resources/it.lproj/InfoPlist.strings"

# Icon
swift "$HERE/make-icon.swift" "$WORK/icon.png" >/dev/null
ICONSET="$WORK/AppIcon.iconset"; mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sommelier</string>
  <key>CFBundleDisplayName</key><string>Sommelier</string>
  <key>CFBundleIdentifier</key><string>io.github.homecla.sommelier</string>
  <key>CFBundleExecutable</key><string>Sommelier</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 homecla · AGPL-3.0-or-later</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Sommelier apre il Terminale con l'ambiente Wine della bottiglia.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Programma Windows</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>exe</string><string>msi</string><string>bat</string><string>lnk</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$STAGE" 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$APP"
mv "$STAGE" "$APP"
# Refresh Launch Services (icon, "Open with")
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "==> $(t 'Pronto' 'Ready'): $APP"
