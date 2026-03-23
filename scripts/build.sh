#!/bin/zsh
# MaxBox - Build script
# Usage: ./scripts/build.sh [release]
# Produces: build/{Debug,Release}/MaxBox.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/MaxBox.xcodeproj"
SCHEME="MaxBox"
DERIVED="$PROJECT_DIR/build/DerivedData"

CONFIG="Debug"
if [[ "${1:-}" == "release" ]]; then
    CONFIG="Release"
fi

OUTPUT_DIR="$PROJECT_DIR/build/$CONFIG"

echo "Building MaxBox ($CONFIG)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    build \
    2>&1 | tail -5

# Copy app bundle to a stable output path
PRODUCTS_DIR="$DERIVED/Build/Products/$CONFIG"
APP_SRC="$PRODUCTS_DIR/MaxBox.app"

if [[ -d "$APP_SRC" ]]; then
    mkdir -p "$OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR/MaxBox.app"
    cp -R "$APP_SRC" "$OUTPUT_DIR/MaxBox.app"
    echo "Build complete: $OUTPUT_DIR/MaxBox.app"
else
    echo "Error: MaxBox.app not found at $APP_SRC"
    exit 1
fi
