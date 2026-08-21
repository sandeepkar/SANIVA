#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
PROFILE_NAME="${1:?Usage: ./notarize-app.sh KEYCHAIN_PROFILE}"
APP_PATH="$SCRIPT_DIR/SANIVA.app"
ZIP_PATH="$SCRIPT_DIR/SANIVA-notarization.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE_NAME" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "Notarized: $APP_PATH"
