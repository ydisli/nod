#!/bin/bash
# Builds Nod.app into ./build. Universal (Apple silicon + Intel) by default.
#
#   scripts/build-app.sh                 release, universal, ad-hoc signed
#   ARCHS=arm64 scripts/build-app.sh     faster, Apple silicon only
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done

echo "› Building Nod $VERSION ($BUILD_NUMBER) for $ARCHS"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/Nod.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Nod" "$APP/Contents/MacOS/Nod"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Support/Info.plist > "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› Signing ($([ "$SIGN_IDENTITY" = "-" ] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
codesign --force --options runtime --entitlements Support/Nod.entitlements --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP"
