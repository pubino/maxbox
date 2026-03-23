#!/bin/zsh
# MaxBox - Interactive Notarization Script
# Notarizes MaxBox.app against Apple's notary service.
# Pulls signing identity and team ID from Keychain when possible.
# Uses stored keychain profile "notary" (create with: xcrun notarytool store-credentials "notary")
#
# Usage: ./scripts/notarize.sh [path/to/MaxBox.app]

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { printf "${BLUE}ℹ${RESET}  %s\n" "$*"; }
success() { printf "${GREEN}✔${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }
error()   { printf "${RED}✖${RESET}  %s\n" "$*" >&2; }
step()    { printf "\n${MAGENTA}━━━${RESET} ${BOLD}%s${RESET} ${MAGENTA}━━━${RESET}\n\n" "$*"; }
prompt()  { printf "${CYAN}?${RESET}  %s " "$1"; read -r "$2"; }

spin() {
    local pid=$1 msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%s${RESET}  %s" "${frames[$((i % ${#frames[@]}))]}" "$msg"
        i=$((i + 1))
        sleep 0.1
    done
    printf "\r"
}

# ─── Prerequisites ───────────────────────────────────────────────────────────
step "Checking prerequisites"

if ! command -v xcrun &>/dev/null; then
    error "Xcode command-line tools not found. Install with: xcode-select --install"
    exit 1
fi
success "Xcode command-line tools available"

if ! command -v codesign &>/dev/null; then
    error "codesign not found"
    exit 1
fi
success "codesign available"

# ─── Locate the app bundle ──────────────────────────────────────────────────
step "Locating app bundle"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
    # Try default build locations
    if [[ -d "$PROJECT_DIR/build/Release/MaxBox.app" ]]; then
        APP_PATH="$PROJECT_DIR/build/Release/MaxBox.app"
        info "Found Release build: $APP_PATH"
    elif [[ -d "$PROJECT_DIR/build/Debug/MaxBox.app" ]]; then
        APP_PATH="$PROJECT_DIR/build/Debug/MaxBox.app"
        warn "Using Debug build (Release recommended for distribution)"
    else
        error "No MaxBox.app found. Build first with: ./scripts/build.sh release"
        exit 1
    fi
fi

if [[ ! -d "$APP_PATH" ]]; then
    error "App bundle not found at: $APP_PATH"
    exit 1
fi
success "App bundle: ${BOLD}$APP_PATH${RESET}"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [[ -n "$BUNDLE_ID" ]]; then
    info "Bundle ID: $BUNDLE_ID"
fi

# ─── Detect signing identity ────────────────────────────────────────────────
step "Detecting code signing identity"

info "Searching Keychain for Developer ID certificates..."
IDENTITIES=()
while IFS= read -r line; do
    [[ -n "$line" ]] && IDENTITIES+=("$line")
done < <(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | sed 's/^[[:space:]]*[0-9]*)[[:space:]]*//' | sed 's/^[A-F0-9]* "/"/;s/"$//')

SIGNING_IDENTITY=""
if [[ ${#IDENTITIES[@]} -gt 0 ]]; then
    if [[ ${#IDENTITIES[@]} -eq 1 ]]; then
        SIGNING_IDENTITY="${IDENTITIES[1]}"
        success "Found signing identity: ${BOLD}$SIGNING_IDENTITY${RESET}"
    else
        warn "Multiple Developer ID certificates found:"
        for i in "${!IDENTITIES[@]}"; do
            printf "  ${CYAN}%d${RESET}) %s\n" "$((i))" "${IDENTITIES[$i]}"
        done
        prompt "Select certificate number [1]:" CERT_NUM
        CERT_NUM="${CERT_NUM:-1}"
        SIGNING_IDENTITY="${IDENTITIES[$CERT_NUM]}"
        success "Selected: ${BOLD}$SIGNING_IDENTITY${RESET}"
    fi
else
    warn "No Developer ID Application certificate found in Keychain"
    prompt "Enter signing identity (e.g., 'Developer ID Application: Name (TEAMID)'):" SIGNING_IDENTITY
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        error "Signing identity is required for notarization"
        exit 1
    fi
fi

# ─── Detect Team ID ─────────────────────────────────────────────────────────
step "Detecting Team ID"

TEAM_ID=""
# Try to extract from the signing identity string
if [[ "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\) ]]; then
    TEAM_ID="${match[1]}"
    success "Team ID from certificate: ${BOLD}$TEAM_ID${RESET}"
fi

if [[ -z "$TEAM_ID" ]]; then
    prompt "Enter your Apple Developer Team ID (10-character alphanumeric):" TEAM_ID
    if [[ -z "$TEAM_ID" ]]; then
        error "Team ID is required"
        exit 1
    fi
fi

# ─── Check notarytool keychain profile ───────────────────────────────────────
step "Checking notarytool credentials"

PROFILE_NAME="notary"
PROFILE_EXISTS=false

# Test if the keychain profile works by doing a dry history lookup
if xcrun notarytool history --keychain-profile "$PROFILE_NAME" 2>/dev/null | head -1 | grep -q ""; then
    PROFILE_EXISTS=true
    success "Keychain profile '${BOLD}$PROFILE_NAME${RESET}' is configured"
else
    warn "Keychain profile '$PROFILE_NAME' not found or not working"
    echo ""
    info "You can store credentials with:"
    printf "  ${DIM}xcrun notarytool store-credentials \"notary\" \\${RESET}\n"
    printf "  ${DIM}  --apple-id YOUR_APPLE_ID \\${RESET}\n"
    printf "  ${DIM}  --team-id $TEAM_ID \\${RESET}\n"
    printf "  ${DIM}  --password APP_SPECIFIC_PASSWORD${RESET}\n"
    echo ""
    printf "${CYAN}?${RESET}  Set up credentials now? [Y/n] "
    read -r SETUP_CREDS
    SETUP_CREDS="${SETUP_CREDS:-Y}"

    if [[ "$SETUP_CREDS" =~ ^[Yy] ]]; then
        prompt "Apple ID (email):" APPLE_ID
        if [[ -z "$APPLE_ID" ]]; then
            error "Apple ID is required"
            exit 1
        fi

        echo ""
        info "You need an app-specific password from https://appleid.apple.com/account/manage"
        prompt "App-specific password:" APP_PASSWORD
        if [[ -z "$APP_PASSWORD" ]]; then
            error "App-specific password is required"
            exit 1
        fi

        echo ""
        info "Storing credentials in Keychain as profile '${BOLD}$PROFILE_NAME${RESET}'..."
        xcrun notarytool store-credentials "$PROFILE_NAME" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD"

        if [[ $? -eq 0 ]]; then
            PROFILE_EXISTS=true
            success "Credentials stored successfully"
        else
            error "Failed to store credentials"
            exit 1
        fi
    else
        error "Notarytool credentials are required for notarization"
        exit 1
    fi
fi

# ─── Code Sign ──────────────────────────────────────────────────────────────
step "Code signing"

info "Signing ${BOLD}$(basename "$APP_PATH")${RESET} with hardened runtime..."

codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_PATH" 2>&1

if [[ $? -eq 0 ]]; then
    success "Code signing complete"
else
    error "Code signing failed"
    exit 1
fi

# Verify signature
info "Verifying signature..."
codesign --verify --deep --strict "$APP_PATH" 2>&1
if [[ $? -eq 0 ]]; then
    success "Signature verified"
else
    error "Signature verification failed"
    exit 1
fi

# ─── Create ZIP for notarization ─────────────────────────────────────────────
step "Preparing submission"

ZIP_PATH="$(dirname "$APP_PATH")/MaxBox.zip"
info "Creating ZIP archive..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
success "Archive created: ${BOLD}$ZIP_PATH${RESET} ($(du -h "$ZIP_PATH" | cut -f1 | xargs))"

# ─── Submit for notarization ─────────────────────────────────────────────────
step "Submitting to Apple notary service"

info "Uploading to Apple (this may take a few minutes)..."
echo ""

SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PROFILE_NAME" \
    --wait \
    2>&1)

SUBMIT_STATUS=$?
echo "$SUBMIT_OUTPUT"
echo ""

# Extract submission ID
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)

if [[ $SUBMIT_STATUS -eq 0 ]] && echo "$SUBMIT_OUTPUT" | grep -qi "accepted"; then
    success "Notarization ${GREEN}${BOLD}ACCEPTED${RESET}"
else
    error "Notarization failed or was rejected"
    if [[ -n "$SUBMISSION_ID" ]]; then
        echo ""
        info "Fetching detailed log..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --keychain-profile "$PROFILE_NAME" \
            "$(dirname "$APP_PATH")/notarize-log-${SUBMISSION_ID}.json" 2>&1 || true
        info "Log saved to: $(dirname "$APP_PATH")/notarize-log-${SUBMISSION_ID}.json"
    fi
    rm -f "$ZIP_PATH"
    exit 1
fi

# ─── Staple the ticket ──────────────────────────────────────────────────────
step "Stapling notarization ticket"

info "Stapling ticket to app bundle..."
xcrun stapler staple "$APP_PATH" 2>&1

if [[ $? -eq 0 ]]; then
    success "Ticket stapled to ${BOLD}$(basename "$APP_PATH")${RESET}"
else
    warn "Stapling failed — the app is still notarized, but users may see a delay on first launch"
fi

# ─── Verify everything ──────────────────────────────────────────────────────
step "Final verification"

info "Running spctl assessment..."
spctl --assess --type exec --verbose "$APP_PATH" 2>&1

if [[ $? -eq 0 ]]; then
    success "Gatekeeper assessment: ${GREEN}${BOLD}PASSED${RESET}"
else
    warn "spctl assessment returned warnings (may still work)"
fi

# ─── Cleanup ─────────────────────────────────────────────────────────────────
rm -f "$ZIP_PATH"

# ─── Summary ─────────────────────────────────────────────────────────────────
step "Done"

printf "${GREEN}${BOLD}"
printf "  ╔══════════════════════════════════════════╗\n"
printf "  ║   MaxBox notarization complete!          ║\n"
printf "  ╚══════════════════════════════════════════╝\n"
printf "${RESET}\n"
info "App:      $APP_PATH"
info "Identity: $SIGNING_IDENTITY"
info "Team:     $TEAM_ID"
[[ -n "${SUBMISSION_ID:-}" ]] && info "Ticket:   $SUBMISSION_ID"
echo ""
success "Ready for distribution!"
