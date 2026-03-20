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

## Iteration 1 - DONE
- Created full project scaffold: 27 files, MVVM architecture
- App builds successfully with zero warnings on Xcode 26.3 / Swift 6.2.4
- All models, services, ViewModels, and Views created
- Git repo initialized, initial commit made
- Next: UI views+ViewModels are already created in scaffold, so next tasks are tests (task-1774024188-78e2) and build verification (task-1774024192-0c60)

## Iteration 2 - DONE
- Closed ui:views task (already completed in scaffold)
- Created 7 test files with 74 unit tests covering all models and ViewModels
- Mock services: MockAuthenticationService, MockGmailAPIService, MockKeychainService
- Test coverage: Account, Mailbox, MailboxType, Message, MessageListResponse, all 4 ViewModels
- Fixed test target to auto-generate Info.plist (GENERATE_INFOPLIST_FILE: YES)
- All 74 tests pass, build succeeds
- Committed: 63d2de4
- Next: Build verification & GCP setup guide (task-1774024192-0c60) is now unblocked

## Iteration 3 - DONE
- Added OAuth URL scheme (com.maxbox.MaxBox) to Info.plist for callback handling
- Created GCP_SETUP.md: step-by-step guide for GCP project, OAuth consent screen, credentials, and manual testing checklist
- Created zsh-compatible scripts: build.sh, run.sh, test.sh
- Verified: build succeeds, 74/74 tests pass, app launches with 3-pane layout waiting for auth
- Committed: d872171
- ALL TASKS COMPLETE: Project is at the defined stopping point — builds, tests pass, runs waiting for auth
