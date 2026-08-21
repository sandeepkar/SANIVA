#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
if [[ ! -x "$SCRIPT_DIR/SANIVA.app/Contents/MacOS/SANIVA" ]]; then
  "$SCRIPT_DIR/build-app.sh"
fi
exec "$SCRIPT_DIR/SANIVA.app/Contents/MacOS/SANIVA"
