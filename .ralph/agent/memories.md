# Memories

## Patterns

### mem-1774024477-3178
> Gmail OAuth credentials read from env vars MAXBOX_GMAIL_CLIENT_ID and MAXBOX_GMAIL_CLIENT_SECRET. Redirect URI: com.maxbox.MaxBox:/oauth2callback. Scopes: gmail.readonly, gmail.modify, gmail.compose, gmail.labels.
<!-- tags: auth, gmail, oauth | created: 2026-03-20 -->

## Decisions

## Fixes

## Context

### mem-1774024475-94cf
> MaxBox uses MVVM with SwiftUI. Models: Account, Mailbox (MailboxType enum), Message. Services: AuthenticationService (OAuth2 via ASWebAuthenticationSession), GmailAPIService (REST), KeychainService. ViewModels: MailboxVM, MessageListVM, MessageDetailVM, ComposeVM. xcodegen with project.yml generates MaxBox.xcodeproj. macOS 14+ target, Swift 5.9.
<!-- tags: architecture, swift, swiftui | created: 2026-03-20 -->
