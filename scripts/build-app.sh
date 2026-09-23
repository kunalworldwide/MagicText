#!/bin/bash
# Assembles MagicText.app from a release build and packages a DMG.
# Usage: scripts/build-app.sh [output-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-build}"
APP_NAME="MagicText"
VERSION="$(git describe --tags --always 2>/dev/null || echo 0.0.1)"

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/${APP_NAME}"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

echo "==> assembling ${APP_DIR}"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# App icon: 1024px PNG from repo assets -> icns via iconutil
ICON_PNG="assets/icon.png"
if [ -f "${ICON_PNG}" ]; then
    ICONSET="${OUT_DIR}/icon.iconset"
    rm -rf "${ICONSET}"
    mkdir -p "${ICONSET}"
    for SIZE in 16 32 64 128 256 512; do
        sips -z ${SIZE} ${SIZE} "${ICON_PNG}" --out "${ICONSET}/icon_${SIZE}x${SIZE}.png" >/dev/null
        DOUBLE=$((SIZE * 2))
        sips -z ${DOUBLE} ${DOUBLE} "${ICON_PNG}" --out "${ICONSET}/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    done
    sips -z 1024 1024 "${ICON_PNG}" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" >/dev/null
    rm -rf "${ICONSET}"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MagicText</string>
    <key>CFBundleDisplayName</key><string>MagicText</string>
    <key>CFBundleIdentifier</key><string>dev.kunalworldwide.magictext</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>MagicText</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --sign - "${APP_DIR}"

echo "==> creating DMG"
DMG_PATH="${OUT_DIR}/MagicText-${VERSION}-macOS.dmg"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

echo "✓ ${DMG_PATH}"
