# VisionPath AI - Backend, API, and Integrations

## 1. Backend Architecture Overview

**Status:** No backend infrastructure

VisionPath AI is designed as a **fully offline, client-only application**. All processing, storage, and AI inference occur on the device itself.

### 1.1 No Backend Design Decision

| Aspect | Approach | Rationale |
|--------|----------|-----------|
| Data Storage | Local (SharedPreferences) | Privacy, no server costs |
| AI Inference | On-device (TFLite) | Privacy, offline capability |
| API Calls | None | No external dependencies |
| Cloud Sync | None | No data leaves device |
| Authentication | None | No user accounts needed |

### 1.2 Privacy Benefits

- **Zero data transmission:** No camera frames, faces, or user data ever leave the device
- **No cloud storage:** All embeddings and contacts stored locally
- **No analytics:** No usage tracking or telemetry
- **No user accounts:** No account creation or password management

---

## 2. External Service Integrations

### 2.1 Android Platform Services

| Service | API | Purpose | Usage |
|---------|-----|---------|-------|
| CameraX/Camera2 | Camera API | Camera preview and frame capture | CameraService |
| TextToSpeech | TTS API | Speech synthesis | VoiceService |
| Location | LocationManager | GPS/network location | SosService (emergency) |
| Telephony | TelephonyManager | Phone calls | SosService (emergency) |
| SMS | SmsManager | SMS messaging | SosService (emergency) |
| Vibration | VibrationManager | Haptic feedback | VibrationService |
| Permissions | PackageManager | Runtime permissions | SosPlatform, CameraService |
| Storage | SharedPreferences | Settings persistence | SettingsService |

### 2.2 Flutter Plugin APIs

| Plugin | Purpose | Integration |
|--------|---------|-------------|
| camera | Camera preview and capture | CameraService |
| flutter_tts | Text-to-speech | VoiceService |
| tflite_flutter | TensorFlow Lite inference | All ML models |
| google_mlkit_face_detection | Face detection | FaceDetectionService |
| google_mlkit_text_recognition | OCR | OcrService |
| shared_preferences | Local storage | Settings, Contacts, Faces |
| permission_handler | Runtime permissions | SosPlatform |
| flutter_inappwebview | Web content (unused) | Not used |
| url_launcher | Open URLs/dialer | SosPlatform |
| vibration | Haptic feedback | VibrationService |
| flutter_inappwebview_android | WebView (unused) | Not used |
| vosk_flutter | Offline speech recognition | SpeechService |

### 2.3 ML Kit Integrations

#### 2.3.1 Face Detection

```dart
// ML Kit Face Detector
final detector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.accurate,
    enableLandmarks: true,
    enableContours: true,
  ),
);
final faces = await detector.processImage(inputImage);
```

#### 2.3.2 Text Recognition (OCR)

```dart
// ML Kit Text Recognizer
final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
final recognized = await recognizer.processImage(inputImage);
```

---

## 3. Third-Party Services and APIs

### 3.1 No External APIs Used

| Category | External API | Status |
|----------|--------------|--------|
| Cloud Storage | Firebase, AWS S3, etc. | Not used |
| AI/ML Backend | Google Vision, AWS Rekognition | Not used |
| Authentication | Firebase Auth, Auth0 | Not used |
| Analytics | Firebase Analytics, Google Analytics | Not used |
| Crash Reporting | Firebase Crashlytics | Not used |
| Push Notifications | FCM | Not used |

### 3.2 Local-Only Services

| Service | Data Location | Transmission |
|---------|---------------|--------------|
| Settings | SharedPreferences | None |
| Emergency Contacts | SharedPreferences | None |
| Familiar Faces | SharedPreferences | None |
| Face Embeddings | In-memory | None |
| Camera Frames | In-memory | None |

---

## 4. API Endpoints

**Status:** No API endpoints

The application has **zero external API endpoints**. All functionality is implemented locally.

---

## 5. External Dependencies

### 5.1 Flutter Plugins (No Server Components)

| Package | Purpose | Network Usage |
|---------|---------|---------------|
| camera | Camera preview | None |
| flutter_tts | Speech synthesis | None |
| tflite_flutter | TFLite inference | None |
| google_mlkit_face_detection | Face detection | None (local ML Kit) |
| google_mlkit_text_recognition | OCR | None (local ML Kit) |
| shared_preferences | Settings | None |
| permission_handler | Permissions | None |
| vosk_flutter | Speech recognition | None |

### 5.2 Platform-Specific APIs

| Platform | API | Network |
|----------|-----|---------|
| Android | CameraX/Camera2 | None |
| Android | TextToSpeech | None |
| Android | LocationManager | Optional (GPS, user-controlled) |
| Android | TelephonyManager | Optional (user-initiated) |
| Android | SmsManager | Optional (user-initiated) |

---

## 6. Network Permissions (Declared but Not Used)

### 6.1 AndroidManifest.xml

```xml
<!-- Permission declared but not actively used -->
<uses-permission android:name="android.permission.INTERNET" />
```

**Note:** The INTERNET permission is declared but not actively used by any feature. The app works without network connectivity.

### 6.2 Permission Usage

| Permission | Active Use | Purpose |
|------------|------------|---------|
| CAMERA | Yes | Camera preview |
| RECORD_AUDIO | Yes | Voice assistant |
| INTERNET | No (declared) | Not used |
| VIBRATE | Yes | Haptic feedback |
| CALL_PHONE | Yes (SOS) | Emergency calling |
| SEND_SMS | Yes (SOS) | Emergency SMS |
| ACCESS_FINE_LOCATION | Yes (SOS) | Emergency location |
| ACCESS_COARSE_LOCATION | Yes (SOS) | Emergency location |

---

## 7. Platform Integrations

### 7.1 Android Platform

#### 7.1.1 Activity Lifecycle

```kotlin
// MainActivity.kt
class MainActivity: FlutterActivity() {
    // Flutter embedding v2
}
```

#### 7.1.2 Permissions

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

#### 7.1.3 Intent Filters

```xml
<intent-filter>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
</intent-filter>
```

---

## 8. Communication Protocols

### 8.1 Flutter-to-Native Communication

| Channel | Purpose | Direction |
|---------|---------|-----------|
| Platform Channels | Camera preview | Bidirectional |
| Platform Channels | ML Kit | Bidirectional |
| Platform Channels | TTS | Bidirectional |
| Platform Channels | Permissions | Bidirectional |

### 8.2 Native-to-Flutter Communication

| Event | Purpose | Frequency |
|-------|---------|-----------|
| Frame callback | Camera preview | 30 FPS |
| Permission result | Permission grant | On demand |
| TTS completion | Speech finish | Per utterance |
| Speech result | Voice command | On release |

---

## 9. Integration Points Summary

| Component | Integration Type | Status |
|-----------|-----------------|--------|
| Camera | Android CameraX | Active |
| TTS | Android TextToSpeech | Active |
| Face Detection | ML Kit | Active |
| OCR | ML Kit | Active |
| Speech Recognition | Vosk (local) | Active |
| Settings | SharedPreferences | Active |
| Permissions | Runtime permissions | Active |
| SOS | Phone/SMS/Location | Active (conditional) |

---

## 10. No Backend Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     VisionPath AI (Client-Only)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         FLUTTER APP                                    │   │
│  │                                                                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ Navigate     │  │ Familiar     │  │ Read Text    │               │   │
│  │  │ Screen       │  │ Faces Screen │  │ Screen       │               │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ Currency     │  │ Emergency    │  │ Settings     │               │   │
│  │  │ Recognition  │  │ Screen       │  │ Screens      │               │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │   │
│  │                                                                        │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │                      SERVICES LAYER                           │   │   │
│  │  │ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │   │   │
│  │  │ │ Object       │  │ Face         │  │ OCR          │         │   │   │
│  │  │ │ Detection    │  │ Recognition  │  │ Service      │         │   │   │
│  │  │ └──────────────┘  └──────────────┘  └──────────────┘         │   │   │
│  │  │ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │   │   │
│  │  │ │ Depth        │  │ Path         │  │ Voice        │         │   │   │
│  │  │ │ Analysis     │  │ Analysis     │  │ Service      │         │   │   │
│  │  │ └──────────────┘  └──────────────┘  └──────────────┘         │   │   │
│  │  │ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │   │   │
│  │  │ │ SOS          │  │ Settings     │  │ Vibration    │         │   │   │
│  │  │ │ Service      │  │ Service      │  │ Service      │         │   │   │
│  │  │ └──────────────┘  └──────────────┘  └──────────────┘         │   │   │
│  │  └──────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │                      DATA LAYER                               │   │   │
│  │  │ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │   │   │
│  │  │ │ Settings     │  │ Familiar     │  │ Emergency    │         │   │   │
│  │  │ │ Storage      │  │ Face         │  │ Contacts     │         │   │   │
│  │  │ │ (SharedPreferences)│  │ Repository   │  │ Storage    │         │   │   │
│  │  │ └──────────────┘  └──────────────┘  └──────────────┘         │   │   │
│  │  └──────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      EXTERNAL DEVICES (NO NETWORK)                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ Camera       │  │ Microphone   │  │ Speaker      │               │   │
│  │  │ (Android)    │  │ (Android)    │  │ (Android)    │               │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         NO BACKEND                                      │   │
│  │  ● No API endpoints                                                     │   │
│  │  ● No cloud storage                                                     │   │
│  │  ● No server-side processing                                            │   │
│  │  ● No user accounts                                                     │   │
│  │  ● No analytics                                                         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 11. Integration Benefits

### 11.1 Privacy and Security

- **Zero data transmission:** All data stays on device
- **No API keys required:** No secrets to manage
- **No server costs:** Single-client architecture
- **No network dependency:** Works offline

### 11.2 Performance

- **Low latency:** No network round-trips
- **Reliability:** No network failures
- **Battery efficient:** No constant network polling

### 11.3 Simplicity

- **Single deployment:** One app file
- **No server maintenance:** No backend to update
- **No API versioning:** No compatibility issues

---

## 12. Conclusion

VisionPath AI is a **fully offline, client-only application** with:

- **Zero backend infrastructure**
- **Zero external API endpoints**
- **Zero cloud storage**
- **Zero user accounts**
- **Zero network dependencies for core features**

All AI inference, data processing, and storage occur locally on the device using:
- TensorFlow Lite models
- ML Kit (on-device)
- Vosk (offline speech recognition)
- Android platform services

This architecture prioritizes:
1. **Privacy:** No data leaves the device
2. **Reliability:** Works without internet
3. **Simplicity:** Single deployment unit
4. **Cost:** No server infrastructure
