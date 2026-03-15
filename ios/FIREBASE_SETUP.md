# Firebase iOS Setup Guide

## Required Steps

1. **Download GoogleService-Info.plist**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select your project (or create one if needed)
   - Click on the iOS app icon (or "Add app" if no iOS app exists)
   - Enter your bundle identifier: `com.bennybar.luliReader2`
   - Download the `GoogleService-Info.plist` file

2. **Add GoogleService-Info.plist to Project**
   - Place the downloaded `GoogleService-Info.plist` file in: `ios/Runner/`
   - Make sure it's added to the Xcode project (it should be automatically detected)

3. **Verify in Xcode**
   - Open `ios/Runner.xcworkspace` in Xcode
   - Check that `GoogleService-Info.plist` appears in the Runner folder
   - Ensure it's included in the target membership

## Notes

- The bundle identifier must match: `com.bennybar.luliReader2`
- Firebase Analytics will work once this file is added
- The app will crash on launch if Firebase is initialized without this file

