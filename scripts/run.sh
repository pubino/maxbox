#!/bin/zsh
# MaxBox - Build and run script
# Usage: MAXBOX_GMAIL_CLIENT_ID=... MAXBOX_GMAIL_CLIENT_SECRET=... ./scripts/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/MaxBox.xcodeproj"
SCHEME="MaxBox"

# Check for required env vars
if [[ -z "${MAXBOX_GMAIL_CLIENT_ID:-}" ]]; then
    echo "Warning: MAXBOX_GMAIL_CLIENT_ID is not set. OAuth sign-in will fail."
    echo "See GCP_SETUP.md for instructions."
fi

if [[ -z "${MAXBOX_GMAIL_CLIENT_SECRET:-}" ]]; then
    echo "Warning: MAXBOX_GMAIL_CLIENT_SECRET is not set. OAuth sign-in will fail."
    echo "See GCP_SETUP.md for instructions."
fi

echo "Building MaxBox..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    build \
    2>&1 | tail -3

# Find and launch the built app
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -showBuildSettings 2>/dev/null \
    | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

APP_PATH="$BUILD_DIR/MaxBox.app"

if [[ -d "$APP_PATH" ]]; then
    echo "Launching MaxBox..."
    open "$APP_PATH"
else
    echo "Error: MaxBox.app not found at $APP_PATH"
    exit 1
fi
