# MaxBox - macOS Gmail Client

## Understanding
Building a native macOS SwiftUI Gmail client with:
- 3-pane layout: folders | message list | message detail
- Gmail API integration (OAuth2)
- Mailbox management (Inbox, Starred, Drafts, Sent, All Mail, Spam, Trash)
- Compose, search, archive, trash, unread filter
- Must build, pass tests, and run waiting for auth

## Architecture Decisions
- **MVVM pattern** with SwiftUI + Combine/async-await
- **No heavy dependencies** - use URLSession for Gmail REST API, ASWebAuthenticationSession for OAuth
- **Keychain** for token storage
- **Swift Package Manager** via Xcode project
- Target macOS 14+ (Sonoma) for modern SwiftUI features

## Plan (task breakdown)
1. Project scaffold - Xcode project, App entry, basic 3-pane ContentView, models
2. Gmail API service layer - auth service, API client, keychain
3. ViewModels - MailboxVM, MessageListVM, MessageDetailVM, ComposeVM
4. UI Views - Sidebar, MessageList, MessageDetail, Compose, Search
5. Tests - Unit tests with mocks for services
6. Build verification & GCP setup guide

## Iteration 1
- Creating project scaffold with all source files (models, services, views, view models)
- This is a greenfield project so creating the full app structure in one go is appropriate
