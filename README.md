# Luli Reader

Luli Reader is a Flutter rewrite of the excellent [ReadYou](https://github.com/Ashinch/ReadYou), tailored with extra reliability, offline-first behavior, and UI polish for heavy RSS users.

[![Get it on Google Play](https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png)](https://play.google.com/store/apps/details?id=com.bennybar.luli_reader2&hl=en)

📱 **[Download on Google Play](https://play.google.com/store/apps/details?id=com.bennybar.luli_reader2&hl=en)**

## Highlights

- Background sync built on Workmanager with selectable intervals (15/30/60/120 min), Wi‑Fi/charging constraints, and a sync log viewer.
- Full-article offline mode using a strengthened readability parser (cleaner content, deduped images, trimmed whitespace/extra breaks).
- RTL-aware UI across lists and reader (direction detection per item, aligned links, trimmed leading spaces).
- Reader controls: adjustable font scale, content padding, and persistent theme choice (System/Light/Dark).
- Feed and folder management: add/move feeds between folders, OPML import/export, “resync all” to clear and re-sync.
- Swipe actions tuned for unread/star filters with safe dismissal behavior.
- Floating glass-style bottom navigation with padding so content stays visible.
- Supports FreshRSS servers.

## Tech Stack

- Flutter + Material 3
- Riverpod for state management
- sqflite for local storage
- Workmanager for background jobs (Android)
- Custom readability pipeline with `html` parsing

## Getting Started

Prerequisites: Flutter SDK 3.9.2+ and Dart 3.9.2+.

```bash
flutter pub get
flutter run
```


## Notable Improvements over ReadYou

- More reliable background sync with interval selection and constraint toggles.
- Full-content fetch with aggressive cleanup (fewer boilerplate blocks, fewer duplicate images).
- Offline-first: articles cached locally for reading without connectivity.
- Rich settings: theme mode, reader font scale/padding, resync all, sync interval, sync log.
- Better RTL handling in both lists and the reader.

## License

MIT.
