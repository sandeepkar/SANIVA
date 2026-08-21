#!/bin/zsh
set -euo pipefail

# Produces the canonical local app bundle. The ad-hoc signature is for personal use.
SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"
swift build -c release

FINAL_APP_PATH="$SCRIPT_DIR/SANIVA.app"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/saniva-build.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_PATH="$STAGE_DIR/SANIVA.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/bin"
cp "$SCRIPT_DIR/.build/release/SANIVA" "$APP_PATH/Contents/MacOS/SANIVA"
cp "$SCRIPT_DIR/.build/release/saniva-scan" "$APP_PATH/Contents/Resources/bin/saniva-scan"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/SanivaLogo.png" "$APP_PATH/Contents/Resources/SanivaLogo.png"
cp "$SCRIPT_DIR/Resources/SanivaLogoWhite.png" "$APP_PATH/Contents/Resources/SanivaLogoWhite.png"
cp "$SCRIPT_DIR/Resources/Saniva.icns" "$APP_PATH/Contents/Resources/Saniva.icns"
cp "$SCRIPT_DIR/PRIVACY.md" "$APP_PATH/Contents/Resources/PRIVACY.md"
cp "$SCRIPT_DIR/CHANGELOG.md" "$APP_PATH/Contents/Resources/CHANGELOG.md"
xattr -cr "$APP_PATH"
SIGN_IDENTITY="${SANIVA_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"
rm -rf "$FINAL_APP_PATH"
ditto "$APP_PATH" "$FINAL_APP_PATH"
echo "Built: $FINAL_APP_PATH"
