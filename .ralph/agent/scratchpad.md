# Scratchpad

## Objective Analysis (2026-03-23)

Six features to implement:

1. **Multiple concurrent compose windows via Cmd+N** - Currently `openWindow(id: "compose")` only opens one. Need to use `openWindow(value:)` with unique IDs to allow multiple.
2. **Cache building on account creation** - After adding an account via OAuth, kick off background message fetching for inbox/sent/drafts.
3. **Animated search icon → text input** - Replace SearchBar with a magnifying glass icon that expands into a text field with animation.
4. **Search arrow button** - Add an arrow/submit button next to the expanded search field.
5. **Double-click message → own window** - Open a message detail in a separate window with reply/reply-all/forward/archive/delete toolbar.
6. **Double-click draft → resume editing** - Open draft in a new compose window pre-filled with draft content.

### Architecture Notes

- MaxBoxApp.swift uses `WindowGroup(id: "compose") { ComposeView() }` currently
- For multiple compose windows, need `WindowGroup(id: "compose", for: ComposeContext.self)` with unique values
- For message detail windows, need a new `WindowGroup` with message context
- SearchBar.swift is a simple HStack with icon + TextField + clear button (39 lines)
- MessageListView has no double-click handler currently
- GmailAPIService.listMessages() supports pagination - good for cache building
- ComposeViewModel already supports pre-filling fields (reply/forward)

### Implementation Order

Start with the most foundational change: multiple compose windows (feature 1), since feature 6 depends on it.

## Iteration 1 - Completed

**Task:** Enable multiple concurrent compose windows via Cmd+N
**Approach:** Changed `Window("New Message", id: "compose")` → `WindowGroup("New Message", id: "compose", for: UUID.self)` and updated all `openWindow(id: "compose")` calls to pass `UUID()` as value. Each unique UUID opens a new independent window.
**Files changed:** MaxBoxApp.swift, ContentView.swift
**Verification:** Build succeeded, 189/189 tests pass.
**Remaining:** 4 tasks (cache-on-create, animated-search, message-window, draft-resume)

## Iteration 2 - Completed

**Task:** Build message cache on account creation
**Approach:** Added `buildInitialCaches(for:)` to MailboxViewModel. After `addAccount()` successfully adds a new account, it fires off a background `Task` that prefetches inbox, sent, and drafts (25 messages each via GmailAPIService) and persists results to disk cache via PersistenceService. Uses ActivityManager for progress visibility. Cancellable via `cacheBuildTask?.cancel()`, also cancelled on `removeAccount()`.
**Key design decisions:**
- Fetches per-account caches (SidebarSelection.account), not allAccounts — avoids invalidation complexity
- 25 messages per mailbox (not 50) — respectful of API quota on first load
- Fire-and-forget from addAccount — doesn't block the UI flow
- Only triggers for genuinely new accounts (not re-auth of existing)
**Files changed:** MailboxViewModel.swift, MailboxViewModelTests.swift
**Verification:** Build succeeded, 195/195 tests pass (6 new tests added).
**Remaining:** 3 tasks (animated-search, message-window, draft-resume)

## Iteration 3 - Completed

**Task:** Animated search icon that expands to text input with search arrow
**Approach:** Replaced the always-visible SearchBar with a collapsed magnifying glass icon button. On click, it expands with `easeInOut(duration: 0.25)` animation to reveal the full search field (magnifying glass icon + TextField + clear button + arrow submit button). Added `@State isExpanded` and `@FocusState isFocused` for state management. Collapses back on Escape (`onExitCommand`) or when focus is lost with empty query (`onChange(of: isFocused)`). Arrow button (`arrow.right.circle.fill`) triggers `onSearch()`.
**Files changed:** SearchBar.swift, SearchBarTests.swift
**Verification:** Build succeeded, 199/199 tests pass (4 new tests added).
**Remaining:** 2 tasks (message-window, draft-resume)

## Iteration 4 - Completed

**Task:** Double-click message to open in own window with action toolbar
**Approach:** Created `MessageWindowContext` (Codable, Hashable) with `messageId` + `accountId`. Added a new `WindowGroup("Message", id: "message", for: MessageWindowContext.self)` in `MaxBoxApp.swift`. Created `MessageWindowView` that wraps `MessageDetailView` with a toolbar containing reply, reply-all, forward, archive, and delete buttons. Archive/delete dismiss the window on success. Added `simultaneousGesture(TapGesture(count: 2))` on `MessageRowView` in `MessageListView` with `@Environment(\.openWindow)` to open message windows on double-click.
**Key design decisions:**
- `MessageWindowContext` passes both messageId and accountId so the window can independently resolve its access token
- Reply/reply-all/forward open compose windows (pre-fill not yet implemented in ComposeViewModel)
- Archive/delete are fully functional and dismiss the window on success
- Uses `simultaneousGesture` to not interfere with List selection behavior
**Files changed:** MessageWindowContext.swift (new), MessageWindowView.swift (new), MaxBoxApp.swift, MessageListView.swift, MessageWindowTests.swift (new)
**Verification:** Build succeeded, 206/206 tests pass (7 new tests added).
**Remaining:** 1 task (draft-resume)

## Iteration 5 - Completed

**Task:** Double-click draft to resume editing in new compose window
**Approach:** Created `DraftComposeContext` (Codable, Hashable) with `messageId` + `accountId`. Added `isDraft` computed property to `Message` (checks for "DRAFT" label). Added `getDraftId(accessToken:messageId:)` to `GmailAPIServiceProtocol` — calls `GET /drafts` and matches by message ID. Added `loadDraft(accessToken:messageId:)` to `ComposeViewModel` — fetches message content and resolves draft ID, populates compose fields without marking dirty. Modified `ComposeView` to accept optional `draftContext` — on appear, resolves token for the draft's account and loads draft data. Added `WindowGroup("Draft", id: "compose-draft", for: DraftComposeContext.self)` in `MaxBoxApp.swift`. Updated `MessageListView` double-click handler to branch: drafts open in compose-draft window, other messages open in message window.
**Key design decisions:**
- Uses `getDraftId` to resolve the Gmail draft resource ID so saves UPDATE the existing draft (not create new)
- `loadDraft` suppresses dirty tracking during field population
- If draft ID lookup fails, fields still load — draftId is nil and save will create new
- Draft compose uses same `ComposeView` with optional `draftContext` parameter — no UI duplication
**Files changed:** DraftComposeContext.swift (new), Message.swift, GmailAPIService.swift, ComposeViewModel.swift, ComposeView.swift, MaxBoxApp.swift, MessageListView.swift, Mocks.swift, DraftComposeTests.swift (new)
**Verification:** Build succeeded, 220/220 tests pass (14 new tests added).
**Remaining:** 0 tasks — all 6 features complete
