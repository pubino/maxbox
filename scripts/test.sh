#!/bin/zsh
# MaxBox - Test script
# Usage: ./scripts/test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/MaxBox.xcodeproj"
SCHEME="MaxBox"

echo "Running MaxBox tests..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    test \
    2>&1 | tail -15

echo "Tests complete."
