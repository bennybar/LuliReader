# iOS Deployment Checklist

## ✅ Completed Setup Steps

- [x] iOS project structure created
- [x] Info.plist configured with background modes (fetch, processing)
- [x] BGTaskSchedulerPermittedIdentifiers added
- [x] pubspec.yaml updated for iOS icons
- [x] Bundle identifier configured: `com.bennybar.luliReader2`

## ⚠️ Manual Steps Required

### 1. Firebase iOS Configuration
- [ ] Download `GoogleService-Info.plist` from Firebase Console
- [ ] Place file in `ios/Runner/` directory
- [ ] See `ios/FIREBASE_SETUP.md` for detailed instructions

### 2. Xcode Configuration
- [ ] Open `ios/Runner.xcworkspace` in Xcode
- [ ] Configure signing with your Apple Developer account
- [ ] Add Background Modes capability (fetch, processing)
- [ ] Set minimum iOS deployment target (recommended: iOS 13.0+)
- [ ] See `ios/XCODE_SETUP.md` for detailed instructions

### 3. App Icons
- [ ] Run `flutter pub run flutter_launcher_icons` to generate iOS icons
- [ ] Verify icons appear correctly in Xcode

### 4. Testing
- [ ] Build and run on physical iOS device (simulator has limitations)
- [ ] Test background sync functionality
- [ ] Verify Firebase Analytics works
- [ ] Test all app features on iOS

### 5. App Store Preparation
- [ ] Create App Store Connect listing
- [ ] Prepare screenshots for iOS
- [ ] Write app description
- [ ] Set up privacy policy URL
- [ ] Configure in-app purchases (if any)
- [ ] Submit for review

## Background Sync Notes

- **Minimum interval:** iOS requires minimum 15 minutes between background tasks
- **Testing:** Must test on physical device (simulator limitations)
- **Task identifier:** `com.bennybar.luliReader2.background_sync_task`
- **WorkManager:** Uses BGTaskScheduler on iOS automatically

## Known Limitations

- Background sync on iOS is less reliable than Android
- iOS may delay or skip background tasks based on system conditions
- User must open app periodically for iOS to schedule background tasks
- Background processing requires app to have been used recently

## Troubleshooting

### Background sync not working?
1. Ensure app has been opened recently (within last few days)
2. Check device battery is not low
3. Verify Background Modes capability is enabled in Xcode
4. Check device logs for `[BACKGROUND_SYNC]` messages
5. Test on physical device, not simulator

### Firebase not working?
1. Verify `GoogleService-Info.plist` is in `ios/Runner/`
2. Check bundle identifier matches Firebase project
3. Ensure file is added to Xcode target

### Build errors?
1. Run `flutter clean`
2. Run `flutter pub get`
3. Open Xcode and clean build folder (Cmd+Shift+K)
4. Try building again

