#!/bin/zsh
# MaxBox - Build script
# Usage: ./scripts/build.sh [release]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/MaxBox.xcodeproj"
SCHEME="MaxBox"

CONFIG="${1:-Debug}"
if [[ "$CONFIG" == "release" ]]; then
    CONFIG="Release"
fi

echo "Building MaxBox ($CONFIG)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    build \
    2>&1 | tail -5

echo "Build complete."
