#!/bin/zsh
# MaxBox - Build and run script
# Credentials are read from Secrets.xcconfig at build time (baked into Info.plist).
# Usage: ./scripts/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check that Secrets.xcconfig exists (needed at build time)
if [[ ! -f "$PROJECT_DIR/Secrets.xcconfig" ]]; then
    echo "Error: Secrets.xcconfig not found."
    echo ""
    echo "Run ./scripts/gcp-setup.sh to create it, or copy the template:"
    echo "  cp Secrets.xcconfig.template Secrets.xcconfig"
    echo "  # Then fill in your OAuth credentials"
    echo ""
    echo "See GCP_SETUP.md for full instructions."
    exit 1
fi

"$SCRIPT_DIR/build.sh"

APP_PATH="$PROJECT_DIR/build/Debug/MaxBox.app"

if [[ -d "$APP_PATH" ]]; then
    echo "Launching MaxBox..."
    open "$APP_PATH"
else
    echo "Error: MaxBox.app not found at $APP_PATH"
    exit 1
fi
