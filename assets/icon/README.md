# App Icon Assets

This directory contains the app icon files for Luli Reader.

## Required Files:

1. **app_icon.png** - Base icon (1024x1024px) - Used for iOS and fallback
2. **app_icon_foreground.png** - Foreground icon for Android adaptive icon (1024x1024px)
   - Should have transparent background
   - Icon should be centered
   - Recommended: Book/RSS feed icon in brand color
3. **app_icon_foreground_dark.png** - Dark mode foreground icon (1024x1024px)
   - Same design but optimized for dark backgrounds
   - May use lighter colors or white

## Icon Design Suggestions:

- **Light Mode**: Use a book or RSS feed symbol in a vibrant color (e.g., blue, purple, or green)
- **Dark Mode**: Use the same icon but in white or a lighter color that contrasts well with dark backgrounds
- **Style**: Modern, minimalist, Material Design 3 compatible
- **Symbol**: Could be:
  - An open book with an RSS feed symbol
  - A stylized "L" for Luli
  - A document/article icon with feed waves

## Generating Icons:

After adding the icon files, run:
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

This will generate all required icon sizes for Android and iOS automatically.

