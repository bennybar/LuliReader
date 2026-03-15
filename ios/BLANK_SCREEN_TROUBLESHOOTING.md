# iOS Blank Screen Troubleshooting

## Fixed: Firebase Initialization

✅ **Fixed:** Firebase initialization now gracefully handles missing `GoogleService-Info.plist`

The app will now continue to run even if Firebase is not configured.

## Common Causes of Blank Screen

### 1. Missing GoogleService-Info.plist (FIXED)
- **Status:** ✅ Fixed - App now handles missing Firebase config gracefully
- **Solution:** App will run without Firebase, but analytics won't work

### 2. Check Console Logs
To see what's actually happening, check the device logs:

**In Xcode:**
- Window → Devices and Simulators
- Select your device
- Click "Open Console"
- Look for error messages

**Or via command line:**
```bash
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "Runner"'
```

### 3. Database Initialization Issues
If database fails to initialize, the app might show blank screen. Check logs for:
- `[DB_HELPER]` messages
- SQLite errors
- Permission errors

### 4. Provider Initialization
If Riverpod providers fail, check for:
- Provider errors in console
- Missing dependencies

### 5. Build Issues
Try a clean build:
```bash
flutter clean
cd ios && pod install && cd ..
flutter pub get
flutter run
```

## Quick Fixes to Try

### 1. Clean and Rebuild
```bash
flutter clean
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter pub get
flutter run
```

### 2. Check if App Actually Launches
- Look for the startup screen (should show "Luli Reader" with loading indicator)
- If completely blank, check console logs

### 3. Verify Firebase (Optional)
If you want Firebase to work:
- Download `GoogleService-Info.plist` from Firebase Console
- Place in `ios/Runner/`
- Rebuild app

### 4. Test Without Firebase
The app should now work without Firebase. Try running:
```bash
flutter run
```

## Debug Steps

1. **Check if app launches at all:**
   - Look for any UI elements
   - Check if startup screen appears

2. **Check console output:**
   - Look for Firebase errors (should be handled now)
   - Look for database errors
   - Look for provider errors

3. **Try debug mode:**
   ```bash
   flutter run --debug
   ```
   This shows more detailed error messages

4. **Check Xcode console:**
   - Open Xcode
   - Run app from Xcode
   - Check console for detailed errors

## Expected Behavior

After the fix:
- App should show startup screen with "Luli Reader" text and loading indicator
- Then navigate to either:
  - MainNavigation (if account exists)
  - AddAccountScreen (if no account)

If you still see a blank screen, check the console logs for specific errors.

