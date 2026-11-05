# Hush

A private, offline notes app for iPhone. No accounts, no analytics, no internet access.
Everything stays on your device.

## Install (with AltStore)

1. On your iPhone, open this repo's **Releases** page in Safari and download `Hush.ipa` from the **latest** release.
2. Open AltStore → **My Apps** → **+** → pick `Hush.ipa` (it's in Files → Downloads).
3. AltStore signs and installs it. It refreshes every 7 days like your other AltStore apps.

Every push to `main` or `hush-notes` rebuilds the app on GitHub Actions and updates the **latest** release.

## Status

- [x] Customizable sidebar (reorder, rename, hide, choose start screen)
- [x] Themes: light, dark, pure black, 12 accent colors + custom, 4 fonts, text size, compact lists
- [x] Passcode lock with Face ID, auto-lock timer, hide in app switcher
- [x] Notes: pins, colors, emoji icons, tags, search, sorting, checklists/bullets
- [ ] Tasks with reminder notifications, Calendar, Home dashboard
- [ ] Vault, Files, Drawings
- [ ] Journals, Contacts, Bookmarks
- [ ] Encrypted backup/restore, alternate app icons

## Build locally (optional, needs a Mac)

```sh
brew install xcodegen && xcodegen generate && open Hush.xcodeproj
```
