# SalesTracker App Crash Fix - Android 13+ Compatibility

## Problem Summary
The app was crashing when users clicked "Track Journey" on newer Android devices (Android 13+). The system was showing:
- "SalesTracker keeps stopping"
- "SalesTracker is crashing frequently"
- Device care notification about frequent crashes

## Root Causes Identified

### 1. **Missing Critical Permissions for Android 13+ (API 33+)**
   - `FOREGROUND_SERVICE_LOCATION` - Required for location-based foreground services
   - `POST_NOTIFICATIONS` - Required to show any notifications on Android 13+

### 2. **Missing Foreground Service Type Declaration**
   - Android 14+ requires explicit `foregroundServiceType="location"` in AndroidManifest.xml
   - Without this, the app crashes when trying to start the background service

### 3. **Insufficient Permission Handling**
   - App wasn't explicitly requesting notification permission at runtime
   - Background service configuration missing the location service type

### 4. **SDK Version Configuration**
   - minSdk needed to be explicitly set to 21 for background service support
   - targetSdk needed to be set to 34 for Android 14 compatibility

## Changes Made

### 1. AndroidManifest.xml
**Added Permissions:**
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**Added Service Declaration:**
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:exported="false"
    android:foregroundServiceType="location" />
```

### 2. build.gradle.kts
**Updated SDK Versions:**
```kotlin
minSdk = 21  // Required for background services
targetSdk = 34  // Android 14 support
```

### 3. background_service.dart
**Added:**
- Error handling wrapper for service initialization
- `foregroundServiceTypes: [AndroidForegroundType.location]` configuration
- Try-catch block to prevent crashes during initialization

### 4. trip_tracking_screen.dart
**Added:**
- Explicit notification permission request for Android 13+
- Better error handling for permission denials
- Debug logging for permission status

## Testing Recommendations

1. **Test on Android 13+ devices** (API 33+)
2. **Test on Android 14+ devices** (API 34+)
3. **Verify permissions are requested:**
   - Location permission
   - Background location permission
   - Notification permission
4. **Test the "Track Journey" flow:**
   - Start a trip
   - Verify foreground notification appears
   - Verify location tracking works
   - Close and reopen app to verify persistence

## What Users Will See Now

1. When clicking "Track Journey", they will be prompted for:
   - Location permission (if not already granted)
   - Background location permission
   - Notification permission (on Android 13+)

2. Once permissions are granted:
   - Foreground notification will appear showing trip progress
   - Location tracking will work smoothly
   - No more crashes

## Important Notes

- **Users must grant all permissions** for the app to work properly
- If users deny notification permission, the foreground service may still work but won't show notifications
- The app now properly declares its use of location-based foreground services
- All changes are backward compatible with older Android versions

## Next Steps

1. **Clean and rebuild the app:**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. **Test on a physical device** running Android 13 or higher

3. **Monitor crash reports** after deployment to ensure the fix is effective

## Files Modified

1. `android/app/src/main/AndroidManifest.xml`
2. `android/app/build.gradle.kts`
3. `lib/services/background_service.dart`
4. `lib/screens/trip_tracking_screen.dart`
