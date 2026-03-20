# MaxBox

A native macOS Gmail client built with SwiftUI and the Gmail REST API.

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
├── Models/          Account, Mailbox, Message
├── Views/           ContentView, SidebarView, MessageListView,
│                    MessageDetailView, ComposeView, SearchBar
├── ViewModels/      MailboxViewModel, MessageListViewModel,
│                    MessageDetailViewModel, ComposeViewModel
└── Services/        AuthenticationService, GmailAPIService,
                     KeychainService
```

### OAuth Flow

MaxBox uses the Google-recommended loopback redirect flow for desktop apps:

1. A local HTTP server binds to `127.0.0.1` on a random port
2. The default browser opens to Google's consent screen
3. After authorization, Google redirects to `http://127.0.0.1:{port}` with the auth code
4. The app exchanges the code for access and refresh tokens
5. Tokens are stored in the macOS Keychain

**Scopes:** `openid`, `email`, `profile`, `gmail.readonly`, `gmail.modify`, `gmail.compose`, `gmail.labels`

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/gcp-setup.sh` | Interactive GCP project setup (OAuth, billing, APIs) |
| `scripts/build.sh` | Build the app (`Debug` or `release`) |
| `scripts/run.sh` | Build and launch the app |
| `scripts/test.sh` | Run the test suite (74 unit tests) |

## Testing

```bash
./scripts/test.sh
```

The test suite uses mock services for all models and ViewModels, requiring no network access or GCP credentials.

## License

Private — all rights reserved.
