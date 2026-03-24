Address and mitigate all issues in the following risk report.  Generate a new report at the conclusion.

# MaxBox Data Loss Risk Audit

**Date:** 2026-03-23
**Scope:** All persistence, authentication, caching, compose, and destructive-action code paths.

---

## CRITICAL RISKS (Likely Data Loss)

### C1. Version mismatch silently deletes all account data
**File:** `MaxBox/Services/PersistenceService.swift` (lines 96-101)

If `VersionedStore.currentVersion` is ever incremented, existing account data is **permanently deleted without warning**. No migration path exists. Keychain tokens become orphaned.

**Fix:** Add migration logic. At minimum: if version < current, attempt migration; if version > current, preserve file and return empty.

### C2. Corrupt JSON silently deletes data files
**File:** `MaxBox/Services/PersistenceService.swift` (lines 194-206)

Any JSON decoding failure — partial write from crash, disk corruption, or Codable schema change — causes the file to be **permanently deleted**. No backup, no logging.

**Fix:** Create a `.bak` copy before deleting corrupt files. Log the error for diagnostics.

### C3. No local draft fallback when API is unreachable
**File:** `MaxBox/ViewModels/ComposeViewModel.swift` (lines 63-93)

Draft saving is remote-only (Gmail API). If network is down, token expired, or API errors, auto-save silently fails. User sees stale `draftSavedAt` timestamp. App crash or window close loses all compose content.

**Fix:** Add local draft storage in Application Support as fallback. Flush compose state to disk periodically.

---

## HIGH RISKS (Possible Data Loss)

### H1. No confirmation for Trash or Archive
**Files:** `MaxBox/Views/ContentView.swift` (lines 103-125), `MaxBox/Views/MessageWindowView.swift` (lines 71-95)

Single-click trash/archive with no confirmation dialog and no undo mechanism. Gmail preserves trashed messages for 30 days server-side, but the local UI provides no recovery path.

**Fix:** Add confirmation dialog or implement undo toast with label re-application.

### H2. Token refresh failure locks user out
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 105-133)

If refresh token is revoked (password change, app revocation), the account appears authenticated but all API operations silently fail. No automatic re-authentication prompt.

**Fix:** Detect `invalid_grant` errors and prompt user to re-authenticate the affected account.

### H3. Silent persistence failures everywhere
**Files:** `MaxBox/ViewModels/MailboxViewModel.swift` (lines 274-280), `MaxBox/ViewModels/MessageListViewModel.swift` (line 667)

All persistence writes use `try?`, silently swallowing disk-full, permission, or encoding errors. User unknowingly loses state changes.

**Fix:** Surface errors to user. A banner like "Could not save — disk may be full" is better than silent failure.

### H4. 30-second auto-save gap
**File:** `MaxBox/ViewModels/ComposeViewModel.swift` (line 23)

Auto-save interval is 30 seconds. Combined with C3 (silent failure), the actual loss window could be the entire compose session if previous saves also failed.

**Fix:** Reduce interval and/or add local-first saving.

### H5. Stale token in compose after ~1 hour
**File:** `MaxBox/Views/ComposeView.swift` (lines 120-140)

Access token is resolved once at window open. After ~1 hour (token expiry), auto-save calls fail silently. User believes drafts are being saved.

**Fix:** Refresh token inside `saveDraft()` and `send()` rather than using captured token.

---

## MEDIUM RISKS (Edge Case Data Loss)

### M1. Race condition in cache writes during rapid mailbox switching
**File:** `MaxBox/ViewModels/MessageListViewModel.swift` (lines 59-120)

Rapid switching may cause overlapping writes to the wrong selection's cache entry. No permanent data loss since Gmail is source of truth, but can cause UI confusion.

### M2. BCC field lost when reopening drafts
**File:** `MaxBox/ViewModels/ComposeViewModel.swift` (lines 104-121)

Gmail API does not return BCC headers in fetched messages. BCC recipients silently disappear when reopening a draft.

### M3. Ghost drafts from failed discard
**File:** `MaxBox/ViewModels/ComposeViewModel.swift` (lines 95-101)

If delete API call fails, `draftId` is set to nil locally but draft persists in Gmail. User believes draft is discarded.

### M4. Keychain save has delete-before-add gap
**File:** `MaxBox/Services/KeychainService.swift` (lines 27-43)

A crash between `SecItemDelete` and `SecItemAdd` would lose the token. Extremely small window.

### M5. Reply/Forward opens blank compose window
**File:** `MaxBox/Views/MessageWindowView.swift` (lines 59-69)

Reply, Reply All, and Forward all open blank compose windows with no pre-filled context. User must manually reconstruct reply context.

### M6. No backup or export mechanism
All data lives in `~/Library/Application Support/MaxBox/` with no iCloud sync or export.

---

## LOW RISKS (Theoretical Data Loss)

- **L1.** `VersionedStore.currentVersion` shared across all types — version bump for one type forces all to be treated as incompatible
- **L2.** Atomic writes assume temp directory is on same volume (standard macOS behavior)
- **L3.** Timer-based auto-save may be delayed during modal dialogs
- **L4.** In-memory cache dictionary is unbounded — extreme multi-account usage could trigger memory pressure kill

---

## Good Practices

| Practice | Details |
|----------|---------|
| Tokens in Keychain only | `PersistableAccount` excludes sensitive tokens from disk |
| Atomic file writes | `.atomic` option prevents partial write corruption |
| Window close interceptor | Confirmation dialog on compose window close with unsaved content |
| Account removal confirmation | Alert shown before removing an account |
| Cache cleanup on removal | Per-account cache files cleaned up properly |
| Differential sync | Fetches only new messages, preserves existing data |
| Suppress dirty flag | Prevents false dirty state during programmatic updates |
| Idempotent Keychain delete | `errSecItemNotFound` treated as success |

---

## Top Recommendations

1. **Add migration logic** instead of deleting files on version mismatch
2. **Add local draft storage** as fallback when Gmail API is unreachable
3. **Back up corrupt files** before deleting in `readJSON`
4. **Add confirmation dialogs** for trash/archive, or implement undo
5. **Refresh access tokens** in compose auto-save, not just at window open
6. **Surface persistence errors** to the user instead of `try?` everywhere

---

## Priority Summary

| Severity | Count | Key Theme |
|----------|-------|-------------|
| CRITICAL | 3 | Version mismatch destroys data; corrupt JSON destroys data; no local draft fallback |
| HIGH | 5 | No trash/archive confirmation; token lockout; silent persistence failures; auto-save gaps; stale tokens |
| MEDIUM | 6 | Cache races; BCC loss; ghost drafts; Keychain gap; blank replies; no backups |
| LOW | 4 | Shared versioning; atomic edge case; timer delays; unbounded cache |
| GOOD | 8 | Strong baseline with room for improvement |
