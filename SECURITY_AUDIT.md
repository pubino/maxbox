# MaxBox Security Audit

**Date:** 2026-03-23
**Scope:** OAuth flow, keychain usage, API calls, HTML rendering, entitlements, secrets management, local persistence, error handling, network security, input validation

---

## CRITICAL (Must Fix)

### C1. No PKCE in OAuth flow
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 146-171)

The OAuth authorization request does not include `code_challenge` or `code_challenge_method`. Without PKCE, the authorization code is vulnerable to interception by another local process. Google requires PKCE for native/desktop OAuth apps.

**Fix:** Generate a cryptographically random `code_verifier` (43-128 chars, URL-safe), compute SHA256 `code_challenge`, include both in the auth request, send `code_verifier` in token exchange.

### C2. No OAuth `state` parameter for CSRF protection
**File:** `MaxBox/Services/AuthenticationService.swift` (line 154)

The authorization URL does not include a `state` parameter, making the callback vulnerable to CSRF. An attacker could craft a redirect binding an attacker-controlled account.

**Fix:** Generate a random `state` nonce before auth request, validate it matches on callback.

### C3. Credential rotation advisory
**File:** `Secrets.xcconfig`

Verify that real OAuth credentials were never committed to git history. If they were, rotate immediately via GCP Console and purge from history with `git filter-repo`.

---

## HIGH (Should Fix)

### H1. HTML email rendered without sanitization or CSP
**File:** `MaxBox/Views/HTMLContentView.swift` (lines 27-72)

Raw HTML email body is injected into WKWebView with JavaScript enabled and no Content-Security-Policy. Malicious emails can execute scripts, load tracking pixels, or embed phishing forms.

**Fix:**
1. Disable JavaScript: `config.defaultWebpagePreferences.allowsContentJavaScript = false`
2. Add CSP: `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data: cid:;">`
3. Block network loads via `WKContentRuleList`

### H2. Keychain items lack explicit access control
**File:** `MaxBox/Services/KeychainService.swift` (lines 30-35)

No `kSecAttrAccessible` or `kSecAttrAccessControl` is set on saved items.

**Fix:** Set `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to prevent backup migration.

### H3. Token refresh response not validated for HTTP status
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 119-133)

The HTTP response object is discarded (`let (data, _) = ...`). Non-200 responses may produce confusing decode errors.

**Fix:** Check `httpResponse.statusCode == 200` before decoding (as done in `exchangeCodeForTokens`).

### H4. OAuth form parameters not URL-encoded
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 120-121, 183-184)

Token exchange parameters are concatenated without URL-encoding. Special characters in values could corrupt the request.

**Fix:** Use `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` or `URLComponents`.

### H5. Loopback server race condition (mitigated by PKCE)
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 250-292)

Combined with `SO_REUSEADDR`, a local attacker could race to intercept the OAuth callback. Implementing PKCE (C1) fully mitigates this.

---

## MEDIUM (Consider Fixing)

### M1. Sensitive data in error messages
**File:** `MaxBox/Services/AuthenticationService.swift` (lines 190-198)

Raw HTTP response bodies (possibly containing partial tokens) are included in error messages shown to the user.

**Fix:** Log details privately with `os.Logger` at `.debug` level; show sanitized messages in UI.

### M2. Message IDs interpolated into URL paths without validation
**File:** `MaxBox/Services/GmailAPIService.swift` (multiple lines)

Force-unwrapped `URL(string:)!` with user-derived IDs could crash or allow path traversal.

**Fix:** Use `URLComponents` with proper path construction; guard against nil URLs.

### M3. Email message bodies cached unencrypted to disk
**File:** `MaxBox/Services/PersistenceService.swift` (lines 126-129)

Full message bodies written as plaintext JSON to `~/Library/Application Support/MaxBox/cache/`.

**Fix:** Use encrypted writes or store cache encryption key in Keychain.

### M4. No email address validation on compose
**File:** `MaxBox/ViewModels/ComposeViewModel.swift` (lines 29-32)

No validation that To/Cc/Bcc contain valid email addresses. No `\r\n` stripping.

### M5. MIME header injection in `buildRawMessage`
**File:** `MaxBox/Services/GmailAPIService.swift` (lines 218-236)

User-provided To/Subject values interpolated directly into MIME headers without sanitizing CR/LF.

**Fix:** Strip `\r` and `\n` from all header field values.

### M6. No certificate pinning
Both services use `URLSession.shared` with default TLS. A compromised CA could MITM traffic.

---

## LOW (Nice to Have)

- **L1.** Loopback server has no timeout — can hang forever if user abandons auth
- **L2.** Token expiry buffer is zero — should subtract 60 seconds for clock skew
- **L3.** `SidebarSelection.cacheKey` used in file paths without sanitization
- **L4.** `SO_REUSEADDR` allows port racing (mitigated by PKCE)
- **L5.** Preferences stored in plaintext UserDefaults (acceptable for current non-sensitive data)

---

## Good Practices

| Practice | Details |
|----------|---------|
| Token/persistence separation | `PersistableAccount` excludes tokens; only Keychain stores credentials |
| App Sandbox enabled | Only `network.client` and `network.server` entitlements |
| HTTPS hardcoded | All OAuth and Gmail API URLs use `https://` |
| 127.0.0.1 binding | Loopback server correctly avoids `INADDR_ANY` |
| HTML error escaping | OAuth callback error page escapes `&` and `<` |
| Atomic file writes | `PersistenceService` uses `.atomic` write option |
| Protocol-based DI | All services use protocols enabling mock-based testing |
| External links in browser | WKWebView delegate opens links in default browser |
| Minimal OAuth scopes | Only necessary Gmail scopes requested |
| Versioned persistence | `VersionedStore` wrapper supports future migration |

---

## Priority Summary

| Severity | Count | Key Actions |
|----------|-------|-------------|
| CRITICAL | 3 | Implement PKCE, add OAuth state parameter, verify credential history |
| HIGH | 5 | Disable WKWebView JS + add CSP, Keychain access control, validate HTTP status, URL-encode params |
| MEDIUM | 6 | Sanitize errors, validate URLs, encrypt cache, validate emails, prevent MIME injection, cert pinning |
| LOW | 5 | Timeout, token buffer, path sanitization, SO_REUSEADDR, UserDefaults |
| GOOD | 10 | Strong baseline security posture |
