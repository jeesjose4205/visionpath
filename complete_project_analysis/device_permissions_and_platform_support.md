# VisionPath AI - Device Permissions and Platform Support

## 1. Platform Support Summary

| Platform | Status | Implementation |
|----------|--------|----------------|
| Android | ✅ Active | Full implementation |
| iOS | ❌ Not implemented | Empty platform directory |
| Web | ❌ Not implemented | Empty platform directory |
| Linux | ❌ Not implemented | Empty platform directory |
| macOS | ❌ Not implemented | Empty platform directory |
| Windows | ❌ Not implemented | Empty platform directory |

---

## 2. Android Platform Support

### 2.1 Android Manifest Permissions

**File:** `android/app/src/main/AndroidManifest.xml`

```xml
<!-- Camera permission for visual navigation -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- Microphone permission for voice assistant -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- Internet permission (declared but not actively used) -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- Vibration for haptic feedback -->
<uses-permission android:name="android.permission.VIBRATE" />

<!-- Emergency SOS permissions -->
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### 2.2 Permission Types

| Permission | Type | Usage | Status |
|------------|------|-------|--------|
| CAMERA | Dangerous | Camera preview | Active |
| RECORD_AUDIO | Dangerous | Voice assistant | Active |
| VIBRATE | Normal | Haptic feedback | Active |
| CALL_PHONE | Dangerous | Emergency calling | Active (SOS) |
| SEND_SMS | Dangerous | Emergency SMS | Active (SOS) |
| ACCESS_FINE_LOCATION | Dangerous | Emergency GPS | Active (SOS) |
| ACCESS_COARSE_LOCATION | Dangerous | Emergency network | Active (SOS) |
| INTERNET | Normal | Not used | Declared only |

### 2.3 Runtime Permission Requests

**File:** `lib/services/sos_platform.dart`

```dart
// SOS Platform handles all dangerous permissions
class SosPlatform {
  Future<bool> requestCallPhonePermission() async {
    final status = await Permission.callPhone.request();
    return status.isGranted;
  }

  Future<bool> requestSendSmsPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> requestFineLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }
}
```

### 2.4 Camera Permissions

**File:** `lib/services/camera_service.dart`

```dart
Future<void> initializeCamera() async {
  // Request camera permission
  final status = await Permission.camera.request();
  if (!status.isGranted) {
    throw Exception('Camera permission denied');
  }
  
  // Initialize camera
  _camera = CameraDescription(...);
}
```

---

## 3. Device Features and Requirements

### 3.1 Required Hardware Features

| Feature | Requirement | Description |
|---------|-------------|-------------|
| Camera | Required | Main input source for all features |
| Microphone | Required | Voice assistant, speech recognition |
| Speaker | Required | TTS voice feedback |
| Vibration | Optional | Haptic feedback |

### 3.2 Optional Hardware Features

| Feature | Requirement | Description |
|---------|-------------|-------------|
| GPS | Optional | Emergency location only |
| Network | Optional | Not required for core features |

### 3.3 Android Manifest Features

```xml
<!-- GPS/network fixes are optional: SOS still calls and texts without one. -->
<uses-feature android:name="android.hardware.location.gps" android:required="false" />
```

---

## 4. Platform-Specific Implementations

### 4.1 Camera Implementation

| Component | Android Implementation |
|-----------|------------------------|
| Camera API | CameraX / Camera2 |
| Preview | SurfaceView / TextureView |
| Frame Capture | ImageReader |
| Rotation Handling | Sensor orientation matrix |

### 4.2 TTS Implementation

| Component | Android Implementation |
|-----------|------------------------|
| API | TextToSpeech |
| Languages | Multiple languages supported |
| Rate | 0.05x to 5.0x |
| Pitch | configurable |

### 4.3 Permissions Implementation

| Component | Android Implementation |
|-----------|------------------------|
| Permissions | android.permission.* |
| Request | Activity.requestPermissions() |
| Result | Activity.onRequestPermissionsResult() |

### 4.4 SOS Platform Implementation

| Action | Android Implementation |
|--------|------------------------|
| Call | Intent.ACTION_CALL |
| SMS | SmsManager.sendTextMessage() |
| Location | LocationManager.getLastKnownLocation() |
| Notification | NotificationManager.notify() |

---

## 5. Permission Handling Flow

### 5.1 Camera Permission Flow

```
App Start
    │
    ▼
Initialize Camera
    │
    ├─→ Permission.camera.request()
    │    │
    │    ├─ GRANTED → Continue
    │    └─ DENIED → Show error
    │
    ▼
Camera Ready
```

### 5.2 Emergency Permission Flow

```
User activates SOS
    │
    ▼
Check required permissions
    │
    ├─ CALL_PHONE → Request if not granted
    ├─ SEND_SMS → Request if not granted
    └─ ACCESS_FINE_LOCATION → Request if not granted
    │
    ▼
Execute emergency actions (concurrent)
    ├─ Play alert sound (no permission)
    ├─ Get location (if granted)
    ├─ Place call (if granted)
    └─ Send SMS (if granted)
```

### 5.3 Permission Request UI

**File:** `lib/services/sos_platform.dart`

```dart
SosCallBlocker? getCallBlocker() {
  if (!Permission.callPhone.isGranted) {
    return SosCallBlocker.callPhonePermission;
  }
  // Check for dialer app...
  return null;
}
```

---

## 6. Permission Error Handling

### 6.1 Camera Permission Denied

**Error:** "Camera permission denied"  
**Recovery:** User must enable in Settings  
**UI Feedback:** Error message, no camera preview

### 6.2 Microphone Permission Denied

**Error:** "Microphone permission denied"  
**Recovery:** User must enable in Settings  
**UI Feedback:** Voice assistant unavailable

### 6.3 Emergency Permission Denied

**Blocker:** Permission not granted  
**Recovery:** User must grant in Settings  
**UI Feedback:** SOS limited functionality

---

## 7. Platform Capabilities

### 7.1 Android Capabilities

| Capability | Status | Notes |
|------------|--------|-------|
| Camera preview | ✅ | CameraX API |
| Camera capture | ✅ | TakePicture |
| Camera switch | ✅ | Front/rear lens |
| Face detection | ✅ | ML Kit |
| OCR | ✅ | ML Kit |
| TTS | ✅ | TextToSpeech |
| STT (online) | ✅ | Web Speech API |
| STT (offline) | ✅ | Vosk |
| Vibration | ✅ | Vibration plugin |
| Permissions | ✅ | permission_handler |
| Location | ✅ | LocationManager |
| Phone calls | ✅ | TelephonyManager |
| SMS | ✅ | SmsManager |
| Notifications | ✅ | NotificationManager |

### 7.2 Supported Android Versions

| API Level | Version | Status |
|-----------|---------|--------|
| 21+ | Android 5.0 | Supported (minSdk) |
| 33+ | Android 13 | Tested |
| Future | Android 14+ | Should work |

---

## 8. Permissions Summary

### 8.1 Required Permissions (Core Features)

| Permission | Used By | Feature |
|------------|---------|---------|
| CAMERA | CameraService | All camera features |
| RECORD_AUDIO | VoiceService | Voice assistant |

### 8.2 Conditional Permissions (Emergency Only)

| Permission | Used By | Feature |
|------------|---------|---------|
| CALL_PHONE | SosPlatform | SOS calling |
| SEND_SMS | SosPlatform | SOS SMS |
| ACCESS_FINE_LOCATION | SosPlatform | SOS GPS |
| ACCESS_COARSE_LOCATION | SosPlatform | SOS network location |

### 8.3 Optional Permissions

| Permission | Used By | Feature |
|------------|---------|---------|
| VIBRATE | VibrationService | Haptic feedback |
| INTERNET | None | Not used |

---

## 9. Platform Limitations

### 9.1 Android Limitations

| Limitation | Impact |
|------------|--------|
| Android 5.0+ only | Excludes older devices |
| Camera permissions required | Cannot run without permission |
| Microphone required for assistant | Voice features blocked without permission |

### 9.2 No iOS Support

- iOS directory empty
- No iOS-specific code
- No TestFlight or App Store submission prepared

### 9.3 No Web Support

- Web directory empty
- No browser-based deployment possible
- No PWA support

---

## 10. Platform Configuration

### 10.1 Android Configuration

**File:** `android/app/build.gradle.kts`

```kotlin
android {
    namespace = "com.example.visionpath"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.visionpath"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

### 10.2 Gradle Configuration

```kotlin
// TFLite conflict resolution
configurations.all {
    exclude(group = "com.google.ai.edge.litert", module = "litert-api")
}

flutter {
    source = "../.."
}
```

---

## 11. Conclusion

VisionPath AI is **Android-only** with:

- **Active Android implementation** (CameraX, ML Kit, TextToSpeech)
- **No iOS, Web, or desktop support** (empty platform directories)
- **Runtime permission handling** for all dangerous permissions
- **Conditional emergency permissions** (only requested when SOS activated)

The app requires:
1. Android device with camera
2. Android 5.0+ (API 21+)
3. Camera permission for core features
4. Microphone permission for voice features
