#!/bin/zsh
# MaxBox - Interactive GCP Setup Script
# Automates Google Cloud Platform project configuration for Gmail API OAuth2.
# Usage: ./scripts/gcp-setup.sh

set -euo pipefail

# ─── Color Scheme ───────────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'

# ─── Globals ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GCP_PROJECT_ID=""
CLIENT_ID=""
CLIENT_SECRET=""
ACCOUNT_EMAIL=""

# ─── Helpers ────────────────────────────────────────────────────────────────────

print_banner() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}║                                                              ║${RESET}"
    echo "${CYAN}║${BOLD}            MaxBox — GCP Setup Assistant                      ${CYAN}║${RESET}"
    echo "${CYAN}║                                                              ║${RESET}"
    echo "${CYAN}║${DIM}   Automates Google Cloud configuration for Gmail OAuth2     ${CYAN}║${RESET}"
    echo "${CYAN}║                                                              ║${RESET}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

step_header() {
    local step_num="$1"
    local title="$2"
    echo ""
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${CYAN}${BOLD}  Step ${step_num}: ${title}${RESET}"
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

success() {
    echo "${GREEN}  ✔ $1${RESET}"
}

warn() {
    echo "${YELLOW}  ⚠ $1${RESET}"
}

error() {
    echo "${RED}  ✖ $1${RESET}"
}

info() {
    echo "${DIM}  $1${RESET}"
}

prompt_msg() {
    echo "${BLUE}  $1${RESET}"
}

instruction() {
    echo "${MAGENTA}  $1${RESET}"
}

confirm_continue() {
    echo ""
    prompt_msg "Press Enter to continue..."
    read -r
}

confirm_yes_no() {
    local message="$1"
    local answer
    while true; do
        echo -n "${BLUE}  ${message} [y/n]: ${RESET}"
        read -r answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

mask_string() {
    local str="$1"
    local visible="${2:-8}"
    local len=${#str}
    if (( len <= visible )); then
        echo "$str"
    else
        echo "${str:0:$visible}$(printf '*%.0s' {1..$((len - visible))})"
    fi
}

run_gcloud() {
    local description="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        echo "$output"
        return 0
    else
        error "${description} failed."
        if [[ -n "$output" ]]; then
            echo "${DIM}    ${output}${RESET}"
        fi
        return 1
    fi
}

# ─── Trap Handler ───────────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo ""
    warn "Setup interrupted. You can re-run this script at any time to resume."
    echo "${DIM}  Progress is not lost — gcloud changes are already applied.${RESET}"
    echo ""
    exit 130
}

trap cleanup INT TERM

# ─── Step 0: Pre-flight ────────────────────────────────────────────────────────

preflight() {
    step_header "0" "Pre-flight Checks"

    # Check gcloud installed
    if ! command -v gcloud &>/dev/null; then
        error "gcloud CLI is not installed."
        echo ""
        info "Install it from: https://cloud.google.com/sdk/docs/install"
        info "On macOS with Homebrew:  brew install --cask google-cloud-sdk"
        echo ""
        exit 1
    fi
    success "gcloud CLI found: $(gcloud version 2>/dev/null | head -1)"

    # Check authenticated
    local auth_output
    if ! auth_output=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>&1); then
        error "Could not check gcloud authentication."
        echo "${DIM}    ${auth_output}${RESET}"
        exit 1
    fi

    if [[ -z "$auth_output" ]]; then
        error "No authenticated gcloud account found."
        echo ""
        info "Run: gcloud auth login"
        echo ""
        exit 1
    fi

    ACCOUNT_EMAIL="$auth_output"
    success "Authenticated as: ${BOLD}${ACCOUNT_EMAIL}${RESET}"
}

# ─── Step 1: GCP Project ───────────────────────────────────────────────────────

select_project() {
    step_header "1" "Select or Create a GCP Project"

    info "Fetching your GCP projects..."
    echo ""

    local projects_output
    if ! projects_output=$(gcloud projects list --format="value(projectId,name)" --sort-by="name" 2>&1); then
        error "Failed to list projects."
        echo "${DIM}    ${projects_output}${RESET}"
        exit 1
    fi

    # Parse projects into arrays
    local -a project_ids=()
    local -a project_names=()
    while IFS=$'\t' read -r pid pname; do
        [[ -z "$pid" ]] && continue
        project_ids+=("$pid")
        project_names+=("${pname:-$pid}")
    done <<< "$projects_output"

    if (( ${#project_ids[@]} == 0 )); then
        warn "No existing projects found."
    else
        info "Available projects:"
        echo ""
        local i
        for (( i = 1; i <= ${#project_ids[@]}; i++ )); do
            echo "    ${BOLD}${i})${RESET}  ${project_names[$i]}  ${DIM}(${project_ids[$i]})${RESET}"
        done
    fi

    local create_opt=$(( ${#project_ids[@]} + 1 ))
    echo "    ${BOLD}${create_opt})${RESET}  ${GREEN}Create a new project${RESET}"
    echo ""

    local choice
    while true; do
        echo -n "${BLUE}  Select a project [1-${create_opt}]: ${RESET}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= create_opt )); then
            break
        fi
        warn "Invalid selection. Enter a number between 1 and ${create_opt}."
    done

    if (( choice == create_opt )); then
        create_project
    else
        GCP_PROJECT_ID="${project_ids[$choice]}"
        success "Selected project: ${BOLD}${GCP_PROJECT_ID}${RESET}"
    fi

    # Set active project
    info "Setting active project..."
    if gcloud config set project "$GCP_PROJECT_ID" &>/dev/null; then
        success "Active project set to ${BOLD}${GCP_PROJECT_ID}${RESET}"
    else
        error "Failed to set active project."
        exit 1
    fi
}

create_project() {
    local new_id
    echo ""
    while true; do
        echo -n "${BLUE}  Enter a project ID (lowercase, hyphens ok, e.g. maxbox-gmail): ${RESET}"
        read -r new_id
        if [[ "$new_id" =~ ^[a-z][a-z0-9-]{5,29}$ ]]; then
            break
        fi
        warn "Project ID must be 6-30 chars, start with a letter, lowercase + hyphens only."
    done

    local new_name
    echo -n "${BLUE}  Enter a display name [MaxBox]: ${RESET}"
    read -r new_name
    new_name="${new_name:-MaxBox}"

    info "Creating project ${BOLD}${new_id}${RESET}..."
    if gcloud projects create "$new_id" --name="$new_name" 2>&1 | while read -r line; do
        info "$line"
    done; then
        success "Project ${BOLD}${new_id}${RESET} created."
        GCP_PROJECT_ID="$new_id"
    else
        error "Failed to create project. The ID may already be taken."
        exit 1
    fi
}

# ─── Step 2: Billing ───────────────────────────────────────────────────────────

check_billing() {
    step_header "2" "Check Billing"

    info "Checking billing status for ${BOLD}${GCP_PROJECT_ID}${RESET}..."

    local billing_info
    if ! billing_info=$(gcloud billing projects describe "$GCP_PROJECT_ID" --format="value(billingEnabled,billingAccountName)" 2>&1); then
        warn "Could not check billing status."
        echo "${DIM}    ${billing_info}${RESET}"
        warn "Billing may be required to enable APIs. Continuing anyway..."
        confirm_continue
        return
    fi

    local billing_enabled
    billing_enabled=$(echo "$billing_info" | head -1)

    if [[ "$billing_enabled" == "True" ]]; then
        success "Billing is already enabled."
        return
    fi

    warn "Billing is not enabled for this project."
    info "Some APIs require billing to be enabled."
    echo ""

    if ! confirm_yes_no "Would you like to link a billing account now?"; then
        warn "Skipping billing setup. Some API calls may fail without billing."
        confirm_continue
        return
    fi

    # List billing accounts
    local accounts_output
    if ! accounts_output=$(gcloud billing accounts list --format="value(name,displayName)" --filter="open=true" 2>&1); then
        warn "Could not list billing accounts."
        echo "${DIM}    ${accounts_output}${RESET}"
        warn "You may need to set up billing at: https://console.cloud.google.com/billing"
        confirm_continue
        return
    fi

    local -a account_ids=()
    local -a account_names=()
    while IFS=$'\t' read -r aid aname; do
        [[ -z "$aid" ]] && continue
        account_ids+=("$aid")
        account_names+=("${aname:-$aid}")
    done <<< "$accounts_output"

    if (( ${#account_ids[@]} == 0 )); then
        warn "No billing accounts found."
        info "Set up billing at: https://console.cloud.google.com/billing"
        confirm_continue
        return
    fi

    info "Available billing accounts:"
    echo ""
    local i
    for (( i = 1; i <= ${#account_ids[@]}; i++ )); do
        echo "    ${BOLD}${i})${RESET}  ${account_names[$i]}  ${DIM}(${account_ids[$i]})${RESET}"
    done
    echo ""

    local choice
    while true; do
        echo -n "${BLUE}  Select a billing account [1-${#account_ids[@]}]: ${RESET}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#account_ids[@]} )); then
            break
        fi
        warn "Invalid selection."
    done

    local selected_account="${account_ids[$choice]}"
    info "Linking billing account..."

    if gcloud billing projects link "$GCP_PROJECT_ID" --billing-account="$selected_account" &>/dev/null; then
        success "Billing account linked: ${account_names[$choice]}"
    else
        error "Failed to link billing account."
        warn "You may need to do this manually at: https://console.cloud.google.com/billing"
        confirm_continue
    fi
}

# ─── Step 3: Enable Gmail API ──────────────────────────────────────────────────

enable_gmail_api() {
    step_header "3" "Enable Gmail API"

    info "Checking if Gmail API is already enabled..."

    local enabled_services
    if ! enabled_services=$(gcloud services list --enabled --format="value(config.name)" --project="$GCP_PROJECT_ID" 2>&1); then
        warn "Could not list enabled services. Attempting to enable Gmail API anyway..."
    fi

    if echo "$enabled_services" | grep -q "gmail.googleapis.com"; then
        success "Gmail API is already enabled."
        return
    fi

    info "Enabling Gmail API..."
    if gcloud services enable gmail.googleapis.com --project="$GCP_PROJECT_ID" 2>&1 | while read -r line; do
        info "$line"
    done; then
        success "Gmail API enabled."
    else
        error "Failed to enable Gmail API."
        echo ""
        info "You can enable it manually at:"
        info "https://console.cloud.google.com/apis/library/gmail.googleapis.com?project=${GCP_PROJECT_ID}"
        echo ""
        if ! confirm_yes_no "Continue anyway?"; then
            exit 1
        fi
    fi
}

# ─── Step 4: OAuth Consent Screen ──────────────────────────────────────────────

configure_consent_screen() {
    step_header "4" "Configure OAuth Consent Screen"

    info "This step must be done in the browser. The Cloud Console will open automatically."
    echo ""

    local consent_url="https://console.cloud.google.com/apis/credentials/consent?project=${GCP_PROJECT_ID}"

    instruction "Follow these steps in the browser:"
    echo ""
    instruction "  1. Select ${BOLD}External${RESET}${MAGENTA} user type, then click ${BOLD}Create${RESET}"
    instruction "  2. Set ${BOLD}App name${RESET}${MAGENTA} to: ${BOLD}MaxBox${RESET}"
    instruction "  3. Set ${BOLD}User support email${RESET}${MAGENTA} to: ${BOLD}${ACCOUNT_EMAIL}${RESET}"
    instruction "  4. Set ${BOLD}Developer contact email${RESET}${MAGENTA} to: ${BOLD}${ACCOUNT_EMAIL}${RESET}"
    instruction "  5. Click ${BOLD}Save and Continue${RESET}"
    instruction "  6. On the ${BOLD}Scopes${RESET}${MAGENTA} page, click ${BOLD}Add or Remove Scopes${RESET}${MAGENTA} and add:"
    echo ""
    instruction "     • openid"
    instruction "     • .../auth/userinfo.email   ${DIM}(or type: email)${RESET}"
    instruction "     • .../auth/userinfo.profile ${DIM}(or type: profile)${RESET}"
    instruction "     • https://www.googleapis.com/auth/gmail.readonly"
    instruction "     • https://www.googleapis.com/auth/gmail.modify"
    instruction "     • https://www.googleapis.com/auth/gmail.compose"
    instruction "     • https://www.googleapis.com/auth/gmail.labels"
    echo ""
    instruction "  7. Click ${BOLD}Save and Continue${RESET}"
    instruction "  8. On ${BOLD}Test users${RESET}${MAGENTA}, add: ${BOLD}${ACCOUNT_EMAIL}${RESET}"
    instruction "  9. Click ${BOLD}Save and Continue${RESET}${MAGENTA}, then ${BOLD}Back to Dashboard${RESET}"
    echo ""

    info "Opening browser..."
    open "$consent_url" 2>/dev/null || warn "Could not open browser. Visit: ${consent_url}"

    echo ""
    prompt_msg "Complete the steps above, then press Enter to continue..."
    read -r

    success "OAuth consent screen configured."
}

# ─── Step 5: OAuth Credentials ─────────────────────────────────────────────────

create_credentials() {
    step_header "5" "Create OAuth 2.0 Credentials"

    info "This step must also be done in the browser."
    echo ""

    local creds_url="https://console.cloud.google.com/apis/credentials/oauthclient?project=${GCP_PROJECT_ID}"

    instruction "Follow these steps in the browser:"
    echo ""
    instruction "  1. Set ${BOLD}Application type${RESET}${MAGENTA} to: ${BOLD}Desktop app${RESET}"
    instruction "  2. Set ${BOLD}Name${RESET}${MAGENTA} to: ${BOLD}MaxBox Desktop${RESET}"
    instruction "  3. Click ${BOLD}Create${RESET}"
    instruction "  4. Copy the ${BOLD}Client ID${RESET}${MAGENTA} and ${BOLD}Client Secret${RESET}${MAGENTA} from the dialog"
    echo ""

    info "Opening browser..."
    open "$creds_url" 2>/dev/null || warn "Could not open browser. Visit: ${creds_url}"

    echo ""
    prompt_msg "Complete the steps above, then enter the credentials below."
    echo ""

    # Client ID
    while true; do
        echo -n "${BLUE}  Client ID: ${RESET}"
        read -r CLIENT_ID
        CLIENT_ID="${CLIENT_ID// /}"  # strip whitespace
        if [[ "$CLIENT_ID" == *.apps.googleusercontent.com ]]; then
            break
        fi
        warn "Client ID should end with '.apps.googleusercontent.com'. Please try again."
    done

    # Client Secret
    while true; do
        echo -n "${BLUE}  Client Secret: ${RESET}"
        read -r CLIENT_SECRET
        CLIENT_SECRET="${CLIENT_SECRET// /}"  # strip whitespace
        if [[ -n "$CLIENT_SECRET" && ${#CLIENT_SECRET} -ge 10 ]]; then
            break
        fi
        warn "Client Secret seems too short. Please try again."
    done

    echo ""
    info "You entered:"
    echo "    ${DIM}Client ID:     ${RESET}$(mask_string "$CLIENT_ID" 16)"
    echo "    ${DIM}Client Secret: ${RESET}$(mask_string "$CLIENT_SECRET" 6)"
    echo ""

    if ! confirm_yes_no "Are these correct?"; then
        warn "Let's try again."
        create_credentials
        return
    fi

    success "Credentials captured."
}

# ─── Step 6: Configure Environment ─────────────────────────────────────────────

configure_environment() {
    step_header "6" "Configure Environment"

    info "How would you like to store your OAuth credentials?"
    echo ""
    echo "    ${BOLD}1)${RESET}  Write to ${BOLD}scripts/.env.local${RESET}  ${DIM}(recommended — source before running)${RESET}"
    echo "    ${BOLD}2)${RESET}  Append to ${BOLD}~/.zshrc${RESET}  ${DIM}(available in all terminal sessions)${RESET}"
    echo "    ${BOLD}3)${RESET}  Display only  ${DIM}(copy and configure manually)${RESET}"
    echo ""

    local choice
    while true; do
        echo -n "${BLUE}  Select an option [1-3]: ${RESET}"
        read -r choice
        case "$choice" in
            1|2|3) break ;;
            *) warn "Invalid selection. Enter 1, 2, or 3." ;;
        esac
    done

    case "$choice" in
        1) write_env_file ;;
        2) append_zshrc ;;
        3) display_only ;;
    esac
}

write_env_file() {
    local env_file="$SCRIPT_DIR/.env.local"

    # Write the file
    cat > "$env_file" <<EOF
# MaxBox OAuth2 Credentials
# Generated by gcp-setup.sh on $(date +%Y-%m-%d)
# GCP Project: ${GCP_PROJECT_ID}

export MAXBOX_GMAIL_CLIENT_ID="${CLIENT_ID}"
export MAXBOX_GMAIL_CLIENT_SECRET="${CLIENT_SECRET}"
EOF

    chmod 600 "$env_file"
    success "Written to ${BOLD}${env_file}${RESET} (permissions: 600)"

    # Ensure .gitignore has the entry
    ensure_gitignore

    echo ""
    info "Usage:"
    echo "    ${DIM}source scripts/.env.local && ./scripts/run.sh${RESET}"
}

append_zshrc() {
    local zshrc="$HOME/.zshrc"
    local marker="# MaxBox OAuth2 Credentials"

    # Check if already present
    if [[ -f "$zshrc" ]] && grep -q "MAXBOX_GMAIL_CLIENT_ID" "$zshrc" 2>/dev/null; then
        warn "MAXBOX_GMAIL_CLIENT_ID already exists in ~/.zshrc."
        if ! confirm_yes_no "Overwrite the existing entries?"; then
            info "Skipped. Existing values preserved."
            return
        fi
        # Remove old entries
        local tmpfile
        tmpfile=$(mktemp)
        grep -v "MAXBOX_GMAIL_CLIENT_ID\|MAXBOX_GMAIL_CLIENT_SECRET\|${marker}" "$zshrc" > "$tmpfile"
        mv "$tmpfile" "$zshrc"
    fi

    cat >> "$zshrc" <<EOF

${marker}
# GCP Project: ${GCP_PROJECT_ID} (added by gcp-setup.sh on $(date +%Y-%m-%d))
export MAXBOX_GMAIL_CLIENT_ID="${CLIENT_ID}"
export MAXBOX_GMAIL_CLIENT_SECRET="${CLIENT_SECRET}"
EOF

    success "Appended to ${BOLD}~/.zshrc${RESET}"
    echo ""
    info "Run: source ~/.zshrc"
    info "Then: ./scripts/run.sh"
}

display_only() {
    echo ""
    info "Add these to your shell profile or run them before launching MaxBox:"
    echo ""
    echo "    export MAXBOX_GMAIL_CLIENT_ID=\"${CLIENT_ID}\""
    echo "    export MAXBOX_GMAIL_CLIENT_SECRET=\"${CLIENT_SECRET}\""
    echo ""
}

ensure_gitignore() {
    local gitignore="$PROJECT_DIR/.gitignore"
    local entry="scripts/.env.local"

    if [[ -f "$gitignore" ]] && grep -qF "$entry" "$gitignore" 2>/dev/null; then
        info ".gitignore already includes ${entry}"
        return
    fi

    echo "" >> "$gitignore"
    echo "# OAuth credentials (generated by gcp-setup.sh)" >> "$gitignore"
    echo "$entry" >> "$gitignore"

    success "Added ${BOLD}${entry}${RESET} to .gitignore"
}

# ─── Step 7: Summary ───────────────────────────────────────────────────────────

print_summary() {
    step_header "7" "Setup Complete"

    echo "${CYAN}  ┌────────────────────┬────────────────────────────────────────┐${RESET}"
    echo "${CYAN}  │${BOLD} Setting            ${CYAN}│${BOLD} Value                                  ${CYAN}│${RESET}"
    echo "${CYAN}  ├────────────────────┼────────────────────────────────────────┤${RESET}"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "GCP Project" "$GCP_PROJECT_ID"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "Gmail API" "Enabled"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "Consent Screen" "Configured (External)"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "Client ID" "$(mask_string "$CLIENT_ID" 16)"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "Client Secret" "$(mask_string "$CLIENT_SECRET" 6)"
    printf "${CYAN}  │${RESET} %-18s ${CYAN}│${RESET} %-38s ${CYAN}│${RESET}\n" "Account" "$ACCOUNT_EMAIL"
    echo "${CYAN}  └────────────────────┴────────────────────────────────────────┘${RESET}"

    echo ""
    echo "${GREEN}${BOLD}  What's next:${RESET}"
    echo ""
    echo "    ${DIM}1.${RESET} Build MaxBox:        ${DIM}./scripts/build.sh${RESET}"
    echo "    ${DIM}2.${RESET} Run MaxBox:          ${DIM}source scripts/.env.local && ./scripts/run.sh${RESET}"
    echo "    ${DIM}3.${RESET} Add your account:    ${DIM}Click \"Add Account\" in the sidebar${RESET}"
    echo ""
    echo "${DIM}  For troubleshooting, see GCP_SETUP.md.${RESET}"
    echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────────────

main() {
    print_banner
    preflight
    select_project
    check_billing
    enable_gmail_api
    configure_consent_screen
    create_credentials
    configure_environment
    print_summary
}

main "$@"
