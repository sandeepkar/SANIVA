#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="${TMPDIR:-/tmp}/saniva-safety-checks"
mkdir -p "$BUILD_DIR"
swiftc "$SCRIPT_DIR/Sources/SANIVACore/DuplicateScanner.swift" "$SCRIPT_DIR/Tests/DuplicateScannerChecks.swift" -o "$BUILD_DIR/DuplicateScannerChecks"
"$BUILD_DIR/DuplicateScannerChecks"
