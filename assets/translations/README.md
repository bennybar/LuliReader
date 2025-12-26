# Translations

This directory contains translation files for the Luli Reader app.

## Supported Languages

- English (en)
- Arabic (ar)
- Hebrew (he)
- German (de)
- French (fr)
- Russian (ru)
- Chinese (zh)

## Usage in Code

To use translations in your code, import easy_localization and use the `.tr()` extension:

```dart
import 'package:easy_localization/easy_localization.dart';

// Simple translation
Text('settings'.tr())

// Translation with parameters
Text('keep_read_items_days'.tr(namedArgs: {'days': days}))
```

## Changing Language

To change the app language programmatically:

```dart
context.setLocale(Locale('ar')); // Change to Arabic
context.setLocale(Locale('he')); // Change to Hebrew
// etc.
```

## Adding New Translations

1. Add the key to all language files in this directory
2. Add the translation for each language
3. Use the key in your code with `.tr()`


