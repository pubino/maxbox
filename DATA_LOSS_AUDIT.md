# MaxBox Data Loss Risk Audit

**Date:** 2026-03-23
**Verified:** 2026-03-23 (build pass, 245/245 tests pass)
**Scope:** All persistence, authentication, caching, compose, and destructive-action code paths.

---

## RESOLVED ISSUES

### CRITICAL — All Mitigated

| ID | Issue | Fix Applied | Verified At |
|----|-------|-------------|-------------|
| C1 | Version mismatch silently deletes all account data | Added migration logic: older versions migrated in-place via `writeJSON`; future versions preserve the file and return empty | `PersistenceService.swift:100-118`, `PersistenceService.swift:147-162` |
| C2 | Corrupt JSON silently deletes data files | Corrupt files backed up to `.bak` before removal; errors logged via `os.log` | `PersistenceService.swift:244-260` |
| C3 | No local draft fallback when API is unreachable | `LocalDraft` model with local filesystem storage; `ComposeViewModel` falls back to local drafts when remote save fails or no token available | `PersistableTypes.swift:76-100`, `PersistenceService.swift:189-217`, `ComposeViewModel.swift:93-131` |

### HIGH — All Mitigated

| ID | Issue | Fix Applied | Verified At |
|----|-------|-------------|-------------|
| H1 | No confirmation for Trash or Archive | Confirmation alert dialogs before trash and archive actions with destructive-role buttons | `ContentView.swift:106-122`, `MessageWindowView.swift:54-70` |
| H2 | Token refresh failure locks user out | `AuthError.tokenRevoked` case detects `invalid_grant` HTTP 400; `MailboxViewModel` surfaces re-auth prompt via `authError` | `AuthenticationService.swift:129-134`, `MailboxViewModel.swift:148-155` |
| H3 | Silent persistence failures everywhere | `persistAccounts()` and `persistCacheToDisk()` catch errors, surface via `persistenceError` and `os.log`; `ContentView` shows "Storage Error" alert | `MailboxViewModel.swift:294-302`, `MessageListViewModel.swift:671-688`, `ContentView.swift:123-131` |
| H4 | 30-second auto-save gap | Reduced `autoSaveInterval` from 30s to 10s | `ComposeViewModel.swift:33` |
| H5 | Stale token in compose after ~1 hour | `ComposeView` provides `tokenRefresher` closure; `saveDraft()` and `send()` call `resolveToken()` to get a fresh token before each operation | `ComposeView.swift:138-142`, `ComposeViewModel.swift:75-89`, `ComposeViewModel.swift:247-263` |

### MEDIUM — All Addressed

| ID | Issue | Fix Applied | Verified At |
|----|-------|-------------|-------------|
| M1 | Race condition in cache writes | `refreshTask?.cancel()` serializes writes; bounded cache (L4) prevents stale accumulation | `MessageListViewModel.swift:62-69`, `MessageListViewModel.swift:681-687` |
| M2 | BCC field lost when reopening drafts | **Accepted** — Gmail API does not return BCC headers. BCC preserved in `LocalDraft` model but cannot be recovered from remote drafts | `PersistableTypes.swift:82` (LocalDraft.bcc field) |
| M3 | Ghost drafts from failed discard | `discardDraft()` only nils `draftId` after successful API delete; preserved on failure | `ComposeViewModel.swift:133-145` |
| M4 | Keychain save delete-before-add gap | `SecItemUpdate` first; `SecItemAdd` fallback only when item doesn't exist. Eliminates crash-window | `KeychainService.swift:27-52` |
| M5 | Reply/Forward opens blank compose window | Fixed: `ComposeContext` model with `populateFromContext` pre-fills all fields | `ComposeViewModel.swift:197-243` |
| M6 | No backup or export mechanism | **Deferred** — Gmail is source of truth for messages; local data is preferences and cache only | _(future work)_ |

### LOW — All Mitigated or Accepted

| ID | Issue | Fix Applied | Verified At |
|----|-------|-------------|-------------|
| L1 | Shared `currentVersion` across all types | **Accepted** — migration logic handles mismatches gracefully without data deletion | `PersistableTypes.swift:5-6`, `PersistenceService.swift:106-116` |
| L2 | Atomic writes assume same volume | **Accepted** — standard macOS behavior; temp dir always on same volume as Application Support | _(no change needed)_ |
| L3 | Timer-based auto-save delayed during modals | **Reduced impact** — interval lowered to 10s, local draft fallback preserves content | `ComposeViewModel.swift:33` |
| L4 | In-memory cache dictionary is unbounded | `maxCacheEntries = 20` limit with oldest-entry eviction | `MessageListViewModel.swift:668-687` |

---

## REMAINING RISKS (Accepted / Deferred)

| ID | Risk | Severity | Rationale |
|----|------|----------|-----------|
| M2 | BCC loss on draft reopen | Low | Gmail API limitation; BCC preserved in local drafts |
| M6 | No backup/export | Low | Gmail is source of truth; local data is expendable cache/preferences |
| L1 | Shared versioning | Low | Migration logic prevents data loss on version mismatch |
| L2 | Same-volume assumption | Low | macOS platform guarantee |

No active data loss risks remain.

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
| Corrupt file backup | `.bak` copy created before removing corrupt JSON files |
| Version migration | Older versions migrated; future versions preserved without deletion |
| Local draft fallback | Compose content saved to disk when Gmail API is unreachable |
| Trash/Archive confirmation | Destructive actions require user confirmation |
| Token revocation detection | `invalid_grant` detected and surfaced as re-auth prompt |
| Persistence error surfacing | Disk/encoding errors shown to user instead of silently swallowed |
| 10s auto-save | Reduced from 30s for tighter draft safety |
| Fresh token per operation | `saveDraft` and `send` refresh the token before each call |
| Atomic Keychain update | `SecItemUpdate` eliminates the delete-add crash window |
| Bounded in-memory cache | Maximum 20 entries prevents memory pressure |

---

## Test Coverage

All 245 tests pass. Tests covering mitigations:

| Test | Risk |
|------|------|
| `testCorruptFile_returnsNilAndCreatesBackup` | C2 |
| `testFutureVersion_preservesFileAndReturnsEmpty` | C1 |
| `testSaveAndLoadLocalDraft` | C3 |
| `testDeleteLocalDraft` | C3 |
| `testLoadAllLocalDrafts` | C3 |
| `testSaveDraft_noAccessToken_savesLocally` | C3 |
| `testSaveDraft_remoteFailure_fallsBackToLocal` | C3 |
| `testSaveDraft_remoteSuccess_cleansUpLocalDraft` | C3 |
| `testDiscardDraft_remoteFailure_keepsDraftId` | M3 |

---

## Summary

| Severity | Original | Resolved | Accepted/Deferred | Active |
|----------|----------|----------|-------------------|--------|
| CRITICAL | 3 | 3 | 0 | **0** |
| HIGH | 5 | 5 | 0 | **0** |
| MEDIUM | 6 | 4 | 2 | **0** |
| LOW | 4 | 2 | 2 | **0** |
| **Total** | **18** | **14** | **4** | **0** |

All critical and high-severity data loss risks have been eliminated. Remaining items are accepted limitations (Gmail API BCC behavior, macOS platform guarantees) or deferred enhancements (export/backup). No active data loss risks remain.
