# Building IPA for Configurator 2

## The Error
"App cannot be installed because its integrity couldn't be verified with Configurator 2"

This error occurs when the IPA file is not properly signed for distribution via Configurator 2.

## Solution: Build with Ad Hoc Distribution

Configurator 2 requires an **Ad Hoc** or **Enterprise** distribution profile. Here's how to build correctly:

### Method 1: Using Flutter Command Line (Recommended)

**1. Register Device UDIDs in Apple Developer Portal:**
   - Go to [Apple Developer Portal](https://developer.apple.com/account/resources/devices/list)
   - Add all device UDIDs that will install the app
   - Get UDID from device: Settings → General → About → Identifier (or use Xcode → Window → Devices)

**2. Create Ad Hoc Provisioning Profile:**
   - Go to [Provisioning Profiles](https://developer.apple.com/account/resources/profiles/list)
   - Create new profile → Ad Hoc
   - Select your App ID: `com.bennybar.luliReader2`
   - Select all devices you want to install on
   - Download and install the profile (or let Xcode manage it automatically)

**3. Build IPA with Ad Hoc Export Method:**
   ```bash
   flutter build ipa --export-method=ad-hoc
   ```

   The IPA will be at: `build/ios/ipa/luli_reader2.ipa`

**4. Install via Configurator 2:**
   - Open Configurator 2
   - Connect your iOS device
   - Drag and drop the IPA file
   - The app should install successfully

### Method 2: Using Xcode

**1. Open in Xcode:**
   ```bash
   open ios/Runner.xcworkspace
   ```

**2. Configure Signing:**
   - Select Runner target
   - Go to "Signing & Capabilities"
   - Ensure "Automatically manage signing" is enabled
   - Select your Team: `57L2ULXB7Z`
   - Xcode will automatically create/select provisioning profile

**3. Archive:**
   - Product → Destination → Any iOS Device
   - Product → Archive
   - Wait for archive to complete

**4. Export for Ad Hoc:**
   - In Organizer window, select your archive
   - Click "Distribute App"
   - Select "Ad Hoc"
   - Select devices (or use automatic)
   - Export the IPA

**5. Install via Configurator 2:**
   - Use the exported IPA file

## Alternative: Enterprise Distribution

If you have an Enterprise Developer account:

```bash
flutter build ipa --export-method=enterprise
```

This doesn't require device registration but requires Enterprise account.

## Troubleshooting

### Issue: "No valid provisioning profile found"
**Solution:**
- Ensure device UDID is registered in Apple Developer Portal
- Create/update Ad Hoc provisioning profile with device included
- In Xcode, ensure "Automatically manage signing" is enabled

### Issue: "Code signing failed"
**Solution:**
- Verify DEVELOPMENT_TEAM is set correctly in Xcode
- Check that your Apple Developer account has valid certificates
- Try cleaning build: `flutter clean && flutter pub get`

### Issue: "App still won't install"
**Solution:**
- Verify the device UDID is in the provisioning profile
- Try building directly from Xcode (Product → Archive → Distribute)
- Check device logs in Xcode (Window → Devices and Simulators → View Device Logs)

## Quick Reference

```bash
# Build for Ad Hoc (Configurator 2)
flutter build ipa --export-method=ad-hoc

# Build for Enterprise
flutter build ipa --export-method=enterprise

# Build for App Store (not for Configurator 2)
flutter build ipa --export-method=app-store

# Build with specific version
flutter build ipa --export-method=ad-hoc --build-name=1.1.80 --build-number=23
```

## Important Notes

- **Ad Hoc builds** can only be installed on devices registered in the provisioning profile
- **Maximum 100 devices** per Ad Hoc profile (free Apple Developer account)
- **Enterprise builds** don't have device limits but require Enterprise account
- **App Store builds** cannot be installed via Configurator 2

## Current Configuration

- **Bundle ID:** `com.bennybar.luliReader2`
- **Team ID:** `57L2ULXB7Z`
- **Code Signing:** Automatic
- **Minimum iOS:** 14.0

