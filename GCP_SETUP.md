# MaxBox - GCP Project Setup & Testing Guide

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- A Google account with Gmail
- Access to [Google Cloud Console](https://console.cloud.google.com)

## 1. Create a GCP Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click the project dropdown (top bar) and select **New Project**
3. Name it `MaxBox` (or your preferred name) and click **Create**
4. Select the new project from the project dropdown

## 2. Enable the Gmail API

1. Navigate to **APIs & Services > Library**
2. Search for **Gmail API**
3. Click **Gmail API** and then **Enable**

## 3. Configure the OAuth Consent Screen

1. Navigate to **APIs & Services > OAuth consent screen**
2. Select **External** user type and click **Create**
3. Fill in the required fields:
   - **App name**: `MaxBox`
   - **User support email**: your email
   - **Developer contact email**: your email
4. Click **Save and Continue**
5. On the **Scopes** page, click **Add or Remove Scopes** and add:
   - `openid`
   - `.../auth/userinfo.email` (or type: `email`)
   - `.../auth/userinfo.profile` (or type: `profile`)
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/gmail.modify`
   - `https://www.googleapis.com/auth/gmail.compose`
   - `https://www.googleapis.com/auth/gmail.labels`
6. Click **Save and Continue**
7. On the **Test users** page, add your Gmail address as a test user
8. Click **Save and Continue**, then **Back to Dashboard**

> **Note**: While the app is in "Testing" mode, only test users you add can authenticate. You can add up to 100 test users. Move to "Production" later for wider access (requires Google verification).

## 4. Create OAuth 2.0 Credentials

1. Navigate to **APIs & Services > Credentials**
2. Click **+ Create Credentials > OAuth client ID**
3. Select **Desktop app** as the application type
4. Name it `MaxBox Desktop`
5. Click **Create**
6. Note the **Client ID** and **Client Secret** — you will need these

> **Why Desktop app?** Google classifies Desktop app credentials as **non-confidential** — per the [OAuth 2.0 for Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app) documentation: *"Installed apps are distributed to individual devices, and it is assumed that these apps cannot keep secrets."* This means embedding the client_secret in the app bundle is the expected pattern. MaxBox uses a loopback redirect (`http://127.0.0.1:<port>`) which is the standard OAuth flow for Desktop apps. See also: [Google OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies).

## 5. Configure MaxBox with Your Credentials

MaxBox reads OAuth credentials from `Secrets.xcconfig`, which is injected into the app bundle at build time via Info.plist build variable substitution.

### Option A: Run the setup script (recommended)

```bash
./scripts/gcp-setup.sh
```

The script walks you through project creation, API enabling, consent screen, and writes `Secrets.xcconfig` automatically.

### Option B: Create Secrets.xcconfig manually

```bash
cp Secrets.xcconfig.template Secrets.xcconfig
```

Edit `Secrets.xcconfig` and fill in your credentials:

```
MAXBOX_GMAIL_CLIENT_ID = your-client-id.apps.googleusercontent.com
MAXBOX_GMAIL_CLIENT_SECRET = your-client-secret
```

> **Important**: `Secrets.xcconfig` is gitignored. Only the template is checked in. Since Desktop app credentials are non-confidential per Google policy, embedding them in the built binary is safe — but keeping the source file out of version control is still good hygiene.

## 6. First Run & Authentication

1. Build and run MaxBox:
   ```bash
   ./scripts/run.sh
   ```
   Or use `./scripts/build.sh` then open the app, or Cmd+R in Xcode.
2. The app opens with a 3-pane layout and "No Accounts" in the sidebar
3. Click **Add Account** in the sidebar
4. A browser window opens to Google's OAuth consent screen
5. Sign in with a test user account (added in step 3.7)
6. Grant the requested Gmail permissions
7. The browser redirects back to MaxBox and your account appears in the sidebar
8. Select a mailbox (Inbox, Starred, etc.) to view messages

## 7. Manual Testing Checklist

After authentication, verify each feature:

- [ ] **Sidebar**: All mailbox types listed (Inbox, Starred, Drafts, Sent, All Mail, Spam, Trash)
- [ ] **Account display**: Connected account shows name and email in sidebar
- [ ] **Message list**: Selecting a mailbox loads messages in the center pane
- [ ] **Message detail**: Clicking a message shows full content in the right pane
- [ ] **HTML rendering**: HTML emails render correctly with images and formatting
- [ ] **Compose**: Click the Compose button in the toolbar; send a test email
- [ ] **Unread filter**: Toggle the unread filter icon in the message list toolbar
- [ ] **Archive**: Select a message and click the Archive button in the toolbar
- [ ] **Trash**: Select a message and click the Trash button in the toolbar
- [ ] **Search**: Type a query in the search bar (upper-right) and press Enter
- [ ] **Multiple accounts**: Add a second Gmail account and switch between them
- [ ] **Disclosure groups**: With 2+ accounts, mailboxes show disclosure triangles
- [ ] **Remove account**: Right-click an account in the sidebar and remove it
- [ ] **Activity window**: Open via Window > Activity (Cmd+Option+0)

## 8. Troubleshooting

### "OAuth Client ID not configured"
`Secrets.xcconfig` is missing or has placeholder values. Run `./scripts/gcp-setup.sh` or copy from the template and fill in your credentials.

### "Access blocked: This app's request is invalid" (Error 400)
The redirect URI does not match. Ensure your OAuth client type is **Desktop app** (not Web application). Desktop apps use the loopback redirect flow (`http://127.0.0.1`), which does not require a pre-registered redirect URI.

### "Access Not Configured" (Error 403)
The Gmail API is not enabled for your GCP project. Go to **APIs & Services > Library** and enable it.

### Browser opens but never redirects back
MaxBox starts a local HTTP server on a random port for the OAuth callback. Ensure the app is not blocked from binding to localhost by a firewall or security tool. The `com.apple.security.network.server` entitlement is required.

### "This app is blocked" or consent screen issues
Your app is in Testing mode and the account is not a test user. Add the account under **OAuth consent screen > Test users**.

### Desktop app type not available in GCP Console
Make sure you have completed the OAuth consent screen configuration (step 3) first. The "Desktop app" option only appears after the consent screen is saved.

## 9. OAuth Scopes Reference

| Scope | Purpose |
|-------|---------|
| `gmail.readonly` | Read email messages and labels |
| `gmail.modify` | Modify messages (archive, trash, mark read/unread, label changes) |
| `gmail.compose` | Create and send new messages |
| `gmail.labels` | Read and manage mailbox labels |

## 10. Next Steps

Once manual testing confirms the app works end-to-end:

1. **Integration tests**: Add tests that exercise the real Gmail API with a dedicated test account
2. **Token persistence**: Store account state so users don't need to re-authenticate on every launch
3. **App icon**: Design and add a squircle-filling app icon for macOS Tahoe
4. **Notarization**: Sign and notarize the app for distribution outside the App Store
5. **Production OAuth**: Submit your app for Google OAuth verification to remove the "unverified app" warning
6. **Error handling**: Add retry logic and offline support for transient network errors
