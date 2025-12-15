# Luli Reader

A beautiful RSS reader for Flutter with full article download functionality, inspired by ReadYou.

## Features

- ✅ **Local Account Support** - No cloud sync needed, everything stored locally
- ✅ **Full Article Download** - Automatically downloads and parses full article content using readability algorithm
- ✅ **RSS Feed Subscription** - Subscribe to any RSS feed
- ✅ **Material 3 Design** - Beautiful Material You interface
- ✅ **Dark Mode** - Full dark mode support
- ✅ **Article Management** - Mark as read, star articles, read later
- ✅ **Feed Organization** - Organize feeds into groups
- ✅ **Offline Reading** - Download articles for offline reading

## Getting Started

### Prerequisites

- Flutter SDK 3.9.2 or higher
- Dart 3.9.2 or higher

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── models/          # Data models (Article, Feed, Group, Account)
├── database/        # Database layer (DAOs and helpers)
├── services/        # Business logic (RSS parsing, readability, sync)
├── screens/         # UI screens
├── providers/       # Riverpod providers for state management
└── theme/           # App theme configuration
```

## Key Features Implementation

### Full Article Download

The app uses a custom readability implementation to extract clean article content from web pages. When you open an article, it automatically downloads the full content from the source URL and parses it to remove ads, navigation, and other clutter.

### RSS Parsing

Uses the `rss` package to parse RSS and Atom feeds. Supports:
- RSS 2.0
- Atom feeds
- Media enclosures
- Custom namespaces

### Database

Uses SQLite (via sqflite) for local storage:
- Articles
- Feeds
- Groups
- Accounts

## Dependencies

- `sqflite` - Local SQLite database
- `http` - HTTP client for fetching feeds and articles
- `rss` - RSS feed parsing
- `html` - HTML parsing and manipulation
- `flutter_riverpod` - State management
- `cached_network_image` - Image caching
- `url_launcher` - Opening links in browser
- And more...

## License

This project is open source and available for use.
