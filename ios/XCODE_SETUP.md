# Xcode Configuration Guide

## Required Configuration Steps

### 1. Open Project in Xcode
```bash
open ios/Runner.xcworkspace
```
**Important:** Always open `.xcworkspace`, not `.xcodeproj`

### 2. Configure Signing & Capabilities

1. **Select the Runner target** in the project navigator
2. **Go to "Signing & Capabilities" tab**
3. **Configure Team:**
   - Select your Apple Developer account under "Team"
   - This enables automatic signing

4. **Add Background Modes Capability:**
   - Click the "+ Capability" button
   - Search for and add "Background Modes"
   - Enable the following:
     - ✅ Background fetch
     - ✅ Background processing

### 3. Verify Bundle Identifier
- Bundle Identifier should be: `com.bennybar.luliReader2`
- This is already configured in the project

### 4. Set Minimum iOS Version
- Minimum deployment target: iOS 12.0 or higher (recommended: iOS 13.0+)
- Check in "General" tab → "Deployment Info"

### 5. Build Settings
- Ensure "Swift Language Version" is set appropriately (usually Swift 5)
- Verify "Enable Bitcode" is set to "No" (Flutter requirement)

## Testing Background Sync

### On Physical Device (Required)
Background sync **must be tested on a physical iOS device**. The iOS Simulator has limitations:
- Background tasks may not execute reliably
- Some background modes don't work in simulator

### Testing Steps:
1. Build and run on a physical device
2. Enable background sync in app settings
3. Put app in background
4. Wait for sync interval (minimum 15 minutes)
5. Check sync logs in app to verify background sync executed

### Debugging Background Tasks:
- Use Xcode's Console to view logs
- Look for `[BACKGROUND_SYNC]` log messages
- Check device logs: Window → Devices and Simulators → View Device Logs

## App Store Submission

Before submitting to App Store:
1. ✅ Verify background modes are enabled
2. ✅ Test background sync on physical device
3. ✅ Add app description explaining background sync usage
4. ✅ Ensure privacy policy mentions background data usage
5. ✅ Test with TestFlight before production release

