# MaxBox

A native macOS Gmail client built with SwiftUI and the Gmail REST API.

MaxBox provides a fast, keyboard-driven email experience with multi-account support, multi-window composition, background message caching, and full offline persistence — all without a web browser.

## Features

- **Multi-Account** — Add and manage multiple Gmail accounts; toggle visibility per-account or browse "All Accounts" in a unified view
- **Multi-Window** — Open messages in their own windows (double-click), compose in separate windows (Cmd+N), open additional main windows (Cmd+Shift+N)
- **Search** — Animated expandable search bar with instant results
- **Compose & Drafts** — Rich text editor, auto-save drafts, resume editing by double-clicking a draft, To/Cc/Bcc fields
- **Message Actions** — Reply, Reply All, Forward, Archive, Delete — from the toolbar or message windows
- **Background Caching** — Messages are cached locally on account creation with a 1-hour TTL for fast access
- **Persistence** — Last-selected mailbox, account preferences, and message caches are restored on relaunch
- **Keyboard Shortcuts** — Cmd+N (compose), Cmd+Shift+N (new window), Cmd+Option+0 (activity), Cmd+Option+B (toggle Bcc), Escape (close search)
- **Activity Monitor** — Background task progress visible in the sidebar

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- A Google Cloud Platform project with Gmail API enabled

## Quick Start

```bash
# 1. Configure GCP (interactive — creates project, enables API, sets up OAuth)
./scripts/gcp-setup.sh

# 2. Source credentials and run
source scripts/.env.local && ./scripts/run.sh
```

See [GCP_SETUP.md](GCP_SETUP.md) for manual setup instructions.

## Architecture

MaxBox follows the MVVM pattern with a service layer for API and keychain access.

```
MaxBox/
├── Models/          Account, Mailbox, Message, DraftComposeContext,
│                    MessageWindowContext, PersistableTypes
├── Views/           ContentView, SidebarView, MessageListView,
│                    MessageDetailView, ComposeView, SearchBar,
│                    MessageWindowView, ActivityView, SettingsView
├── ViewModels/      MailboxViewModel, MessageListViewModel,
│                    MessageDetailViewModel, ComposeViewModel,
│                    ActivityManager
└── Services/        AuthenticationService, GmailAPIService,
                     KeychainService, PersistenceService
```

### OAuth Flow

MaxBox uses the Google-recommended loopback redirect flow for desktop apps:

1. A local HTTP server binds to `127.0.0.1` on a random port
2. The default browser opens to Google's consent screen
3. After authorization, Google redirects to `http://127.0.0.1:{port}` with the auth code
4. The app exchanges the code for access and refresh tokens
5. Tokens are stored securely in the macOS Keychain

**Scopes:** `openid`, `email`, `profile`, `gmail.readonly`, `gmail.modify`, `gmail.compose`, `gmail.labels`

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/gcp-setup.sh` | Interactive GCP project setup (OAuth, billing, APIs) |
| `scripts/build.sh` | Build the app (`Debug` or `release`) |
| `scripts/run.sh` | Build and launch the app |
| `scripts/test.sh` | Run the test suite |
| `scripts/notarize.sh` | Interactive notarization against Apple's notary service |

## Testing

```bash
./scripts/test.sh
```

The test suite uses mock services for all models and ViewModels, requiring no network access or GCP credentials.

## Notarization

```bash
# Build release, then notarize
./scripts/build.sh release
./scripts/notarize.sh
```

The notarization script auto-detects your Developer ID certificate from Keychain, manages the `notary` keychain profile, signs with hardened runtime, submits to Apple, and staples the ticket.

## Developer

Developed at [Princeton University](https://www.princeton.edu).

Built with Swift 5.9, SwiftUI, and [xcodegen](https://github.com/yonaskolb/XcodeGen) for project generation.

```bash
# Regenerate Xcode project from project.yml
xcodegen generate
```

## License

MIT — see [LICENSE.md](LICENSE.md) for details.

Copyright &copy; 2026 Princeton University.
