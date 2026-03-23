# Scratchpad

## Objective Analysis

Six features to implement:
1. Reply, Reply All, Forward buttons on main toolbar (active when message selected)
2. Wire those buttons to open compose with quoted message + populated headers
3. Click-to-select on message list rows
4. Privacy tab in Settings
5. Load Remote Images toggle (default disabled) in Privacy tab
6. Remote images banner in message body when toggle disabled

## Architecture Notes

- Main toolbar is in `ContentView.swift` (already has Compose, Archive, Trash, Search)
- Message selection tracked via `MessageListViewModel.selectedMessageId`
- `messageDetailVM.message` holds the full selected message
- Reply/Forward already exist as stubs in `MessageWindowView` but just open blank compose
- ComposeView currently accepts optional `DraftComposeContext` for drafts
- Need a new `ComposeContext` model for reply/reply-all/forward with original message data
- Need a new WindowGroup in MaxBoxApp for compose-reply windows
- Settings has one tab (Accounts); need to add Privacy tab
- HTMLContentView uses WKWebView; need to control remote image loading via CSS/JS or WKWebView config
- Message list uses `List(selection:)` + `.tag()` — should already handle click-to-select

## Task Breakdown

All tasks completed in single iteration:

1. **compose-context**: Created ComposeContext model (ComposeMode enum + struct) + new "compose-reply" WindowGroup + updated ComposeView to accept and populate from context
2. **toolbar-buttons**: Added Reply/Reply All/Forward to ContentView toolbar, disabled when no message selected, wired to open compose-reply with ComposeContext
3. **message-window-fix**: Updated MessageWindowView to build and pass ComposeContext instead of blank UUID
4. **click-select**: Added .contentShape(Rectangle()) to message rows for reliable hit testing
5. **privacy-tab**: Added Privacy tab to SettingsView with @AppStorage("loadRemoteImages") toggle, default false
6. **remote-images-banner**: Added banner to MessageDetailView when remote images present + blocking CSS in HTMLContentView

Build: passed. Tests: 238/238 passed. Commit: 66b0051.
