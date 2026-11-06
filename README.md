# Hush

A private, offline notes app for iPhone. No accounts, no analytics, no internet access.
Everything stays on your device.

## Install (with AltStore)

1. On your iPhone, open this repo's **Releases** page in Safari and download `Hush.ipa` from the **latest** release.
2. Open AltStore → **My Apps** → **+** → pick `Hush.ipa` (it's in Files → Downloads).
3. AltStore signs and installs it. It refreshes every 7 days like your other AltStore apps.

Every push to `main` or `hush-notes` rebuilds the app on GitHub Actions and updates the **latest** release.

## Features

- **Spaces**: Personal, Work, or any you add — switch at the top of the menu; each shows only its own items
- **Habits**: daily or chosen weekdays, multiple times per day, streaks, 30-day rate, month heat map, optional reminders
- **Trash**: deleted items are kept 30 days and can be restored
- **Home**: a dashboard you arrange yourself (quick add, today, next 7 days, pinned, recent, journal streak, stats)
- **All**: one searchable timeline of everything, filterable by type
- **Notes**: live Markdown styling, tappable checklists, `[[note links]]` with backlinks, nested folders, tags (and Untagged), pins, colors, emoji icons, version history, Zen mode, 25+ built-in templates (incl. homelab), your own templates, photos/files/scans/voice memos attached, export as Markdown, PDF or text
- **Tasks**: due dates and times, reminders, priorities, repeats, subtasks, lists
- **Calendar**: month and agenda views of events, tasks and journal entries; event alerts
- **Journals**: mood, streaks, monthly grouping, optional daily reminder
- **Drawings**: PencilKit canvas with pens, markers, eraser and ruler
- **Vault**: separate passcode or Face ID; secure notes, logins (password generator, 60 s clipboard) and photos; AES-256 encrypted
- **Files**: import from Files or Photos, scan documents (searchable text recognized on-device), record voice memos; encrypted at rest, Quick Look preview
- **Contacts**: private address book with call/message/email buttons and birthday reminders
- **Bookmarks**: links with tags and favorites, never fetched in the background
- **Connected calendars**: show Apple Calendar, Outlook, Google and other iPhone calendar accounts live in Calendar and Home; add or edit those events with Apple's editor
- **Import from iPhone**: Contacts, Reminders (as tasks), calendar events, and .txt/.md (notes), .vcf (contacts) and .ics (events) files
- **Customization**: sidebar order, names and visibility, start screen, Home blocks, 4 themes, 12 accents plus custom, 4 fonts, 6 text sizes, compact lists, 6 app icons, week start, reminder defaults
- **Privacy**: no network, no accounts, no analytics; app lock with Face ID and auto-lock; app-switcher cover; notification text hiding; data excluded from iCloud backup
- **Export**: notes (.md), journal (.md), tasks and habits (.csv), calendar (.ics), contacts (.vcf), bookmarks (.html)
- **Siri & Shortcuts**: “Add a task in Hush”, “Take a note in Hush”, “Log a habit in Hush”, “Journal in Hush”
- **Widgets**: Today, interactive Habits, Quick Add (hidden while App Lock is on unless allowed)
- **Backup**: one password-encrypted `.hushbackup` file; restore merges without deleting

## Good to know

- Widgets need AltStore to register one extra App ID (free accounts get 10 per week).

- **Outlook:** add your Outlook account in iPhone Settings → Apps → Calendar → Calendar Accounts, then turn it on in Hush → Settings → Connected Calendars. iOS does the syncing; Hush still never connects to the internet.

- Your data never leaves the phone, so **make backups** (Settings → Backup & Restore). Deleting the app deletes your data.
- Vault and Files are encrypted with a key kept in the iPhone Keychain. If you re-sign Hush with a *different* Apple ID in AltStore, that key can become unreachable. Back up first.

## Build locally (optional, needs a Mac)

```sh
brew install xcodegen && xcodegen generate && open Hush.xcodeproj
```
