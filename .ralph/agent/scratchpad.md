# Scratchpad — Iteration 1

## Understanding
- MaxBox is a native macOS SwiftUI Gmail client (MVVM, macOS 14+, Swift 5.9)
- Repo already exists at pubino/maxbox (private) with remote configured
- Secrets.xcconfig has real OAuth creds — already gitignored but on disk
- No LICENSE or GitHub Pages currently exist
- No notarization script exists
- README exists but needs expansion for app + developer info

## Plan (8 tasks)
1. **Expand .gitignore** — add common macOS/Xcode/SPM patterns, xcresult, .env, logs, etc.
2. **Push to pubino/maxbox** — repo exists (private), just push current code
3. **GitHub Pages** — create docs/ or gh-pages branch with simple site
4. **Notarization script** — interactive zsh script, pull from Keychain, colorful output
5. **README.md** — expand with app description, developer info, screenshots placeholder
6. **LICENSE.md** — MIT, © Princeton University
7. **Security audit** — review OAuth handling, Keychain usage, secrets management, entitlements
8. **Data loss audit** — review message caching, drafts, token storage, error handling

## Completed (all 8 tasks)
1. Expanded .gitignore — added 45+ patterns, removed tracked lock files
2. Added LICENSE.md — MIT, © Princeton University
3. Added scripts/notarize.sh — interactive, colorful, Keychain-aware, uses "notary" profile
4. Expanded README.md — features, developer info, notarization docs
5. Created docs/index.html — dark-themed GitHub Pages site with feature cards
6. Pushed to pubino/maxbox — made public, enabled GitHub Pages at pubino.github.io/maxbox
7. Security audit — 3 critical, 5 high, 6 medium, 5 low, 10 good practices
8. Data loss audit — 3 critical, 5 high, 6 medium, 4 low, 8 good practices

All tasks complete. Objective fully satisfied.
