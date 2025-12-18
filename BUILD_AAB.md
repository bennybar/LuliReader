# Building Android App Bundle (AAB) for Play Store

This guide explains how to build an AAB file for uploading to the Google Play Store.

## Prerequisites

1. **Java Development Kit (JDK)** - Version 11 or higher
2. **Android Studio** - Latest version recommended
3. **Flutter SDK** - Ensure you have the latest stable version

## Step 1: Generate a Keystore

If you don't already have a keystore file, generate one:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

You'll be prompted to enter:
- A password for the keystore
- Your name, organizational unit, organization, city, state, and country code
- A password for the key alias

**Important:** Keep this keystore file and passwords safe! You'll need them for all future updates.

## Step 2: Configure Signing

1. Copy the keystore file to the `android` directory:
   ```bash
   cp ~/upload-keystore.jks android/
   ```

2. Copy the key properties template:
   ```bash
   cd android
   cp key.properties.example key.properties
   ```

3. Edit `key.properties` and fill in your values:
   ```properties
   storePassword=your_keystore_password
   keyPassword=your_key_password
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```

## Step 3: Update Application ID (Important!)

Before building for production, update the application ID in `android/app/build.gradle.kts`:

```kotlin
applicationId = "com.yourcompany.luli_reader"  // Change from com.example.luli_reader2
```

**Important:** 
- The application ID must be unique and cannot be changed after publishing to Play Store
- Use reverse domain notation (e.g., `com.yourcompany.appname`)
- This should match your Play Store package name

## Step 4: Update Version Information

Update the version in `pubspec.yaml`:
```yaml
version: 1.1.41+10
```
- The first number (1.1.41) is the version name (shown to users)
- The number after + (10) is the version code (must increment for each release)

## Step 5: Build the AAB

Run the following command from the project root:

```bash
flutter build appbundle --release
```

The AAB file will be generated at:
```
build/app/outputs/bundle/release/app-release.aab
```

## Step 6: Verify the AAB

You can verify the AAB was built correctly:

```bash
bundletool build-apks --bundle=build/app/outputs/bundle/release/app-release.aab --output=app.apks --mode=universal
```

Or use Android Studio's built-in AAB analyzer.

## Step 7: Upload to Play Store

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app
3. Go to "Production" (or "Internal testing" / "Closed testing")
4. Click "Create new release"
5. Upload the `app-release.aab` file
6. Fill in release notes and submit for review

## Troubleshooting

### Build fails with signing errors
- Verify `key.properties` exists and has correct values
- Check that the keystore file path is correct
- Ensure passwords match what you used when creating the keystore

### Version code conflicts
- Each upload to Play Store must have a higher version code
- Increment the number after `+` in `pubspec.yaml`

### ProGuard/R8 issues
- Check `android/app/proguard-rules.pro` for any missing rules
- If you encounter runtime errors, you may need to add keep rules for specific classes

## Security Notes

- **Never commit** `key.properties` or `.jks` files to version control
- These files are already in `.gitignore`
- Store your keystore file and passwords in a secure location
- Consider using a password manager for the passwords

## Additional Resources

- [Flutter: Building and releasing an Android app](https://docs.flutter.dev/deployment/android)
- [Google Play: App bundles](https://developer.android.com/guide/app-bundle)
- [Android: Sign your app](https://developer.android.com/studio/publish/app-signing)

