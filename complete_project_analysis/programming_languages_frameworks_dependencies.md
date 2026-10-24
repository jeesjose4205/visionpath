# VisionPath AI - Programming Languages, Frameworks, and Dependencies

## 1. Programming Languages

| Language | Usage | Version |
|----------|-------|---------|
| Dart | Main application code, services, models, widgets | ^3.13.3 (Dart SDK) |
| Kotlin | Android platform code (MainActivity) | JVM 17 |
| Java | Generated Flutter plugin registrant | Not specified |
| XML | Android manifest, styles, layouts | Not specified |

## 2. Core Frameworks

### 2.1 Flutter SDK

| Component | Version | Purpose |
|-----------|---------|---------|
| Flutter SDK | SDK included | UI framework, widget system |
| Material Design | Built-in | UI components and theming |
| Cupertino Icons | ^1.0.8 | iOS-style icons |

### 2.2 State Management

| Library | Version | Usage |
|---------|---------|-------|
| provider | ^6.1.2 | State management via ChangeNotifier |

## 3. Dependencies Analysis

### 3.1 Camera and Media

| Package | Version | Purpose | Status |
|---------|---------|---------|--------|
| camera | ^0.12.0 | Camera preview, frame capture | Active |
| vibration | ^3.2.1 | Haptic feedback | Active |
| flutter_tts | ^4.2.5 | Text-to-speech synthesis | Active |

### 3.2 Machine Learning and AI

| Package | Version | Purpose | Status |
|---------|---------|---------|--------|
| tflite_flutter | ^0.12.1 | TensorFlow Lite inference | Active |
| ultralytics_yolo | ^0.6.14 | YOLO object detection | Active |
| google_mlkit_face_detection | ^0.15.1 | ML Kit face detection | Active |
| google_mlkit_text_recognition | ^0.17.1 | ML Kit OCR | Active |
| vosk_flutter | path: third_party | Offline speech recognition | Active |

### 3.3 Data Storage and Preferences

| Package | Version | Purpose | Status |
|---------|---------|---------|--------|
| shared_preferences | ^2.5.3 | Local settings storage | Active |
| package_info_plus | ^8.0.0 | App version info | Active |

### 3.4 Platform Integration

| Package | Version | Purpose | Status |
|---------|---------|---------|--------|
| permission_handler | 10.2.0 (override: 11.3.1) | Runtime permissions | Active |
| flutter_inappwebview | ^6.1.5 | Web view (usage unknown) | Active |
| url_launcher | ^6.3.2 | Open URLs, dialer | Active |

### 3.5 Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_test | SDK | Unit and widget tests |
| flutter_lints | ^6.0.0 | Linting rules |

## 4. Dependency Overrides

The project uses two dependency overrides to resolve AGP 9 compatibility issues:

| Original Package | Override Version | Reason |
|-----------------|------------------|--------|
| permission_handler | 11.3.1 | Original (10.2.0) uses removed Flutter v1 embedding APIs |
| flutter_inappwebview_android | path: third_party | Calls removed proguard file |

## 5. Third-Party Vendoring

### 5.1 flutter_inappwebview_android

| Location | Purpose |
|----------|---------|
| third_party/flutter_inappwebview_android | Vendored fix for AGP 9 compatibility |

### 5.2 vosk_flutter

| Location | Purpose |
|----------|---------|
| third_party/vosk_flutter | Vendored Vosk Flutter plugin |

## 6. Platform-Specific Versions

### 6.1 Android

| Component | Version |
|-----------|---------|
| compileSdk | Flutter default |
| minSdk | Flutter default |
| targetSdk | Flutter default |
| ndkVersion | Flutter default |
| Java Version | 17 |
| Kotlin JVM Target | 17 |
| AGP (Android Gradle Plugin) | 9.x |

### 6.2 Dart/Flutter

| Component | Version |
|-----------|---------|
| Dart SDK | ^3.13.3 |
| Flutter | SDK included |
| Android API | 21+ (minSdk) |

## 7. Package Usage Summary

### 7.1 High-Impact Packages

| Package | Usage |
|---------|-------|
| camera | CameraService, all camera screens |
| tflite_flutter | FaceEmbeddingService, ScrfdFaceDetector, CurrencyDetector |
| ultralytics_yolo | ObjectDetectionService |
| google_mlkit_face_detection | FaceDetectionService |
| google_mlkit_text_recognition | OcrService |
| flutter_tts | VoiceService, SpeechService |
| shared_preferences | SettingsService, EmergencyContactService, FamiliarFaceRepository |
| permission_handler | SosPlatform, CameraService |
| vosk_flutter | SpeechService |

### 7.2 Medium-Impact Packages

| Package | Usage |
|---------|-------|
| vibration | VibrationService |
| package_info_plus | Settings, About screen |
| flutter_inappwebview | Unused/unknown |
| url_launcher | SosPlatform (dialer) |

### 7.3 Low-Impact Packages

| Package | Usage |
|---------|-------|
| cupertino_icons | UI icon support |
| flutter_lints | Analysis options |

## 8. ML Model Dependencies

The project uses TensorFlow Lite models loaded via tflite_flutter:

| Model | File | Size (estimated) | Purpose |
|-------|------|-----------------|---------|
| ArcFace | arcface_w600k_mbf.tflite | ~10-20 MB | Face embeddings |
| SCRFD | scrfd_640.tflite | ~15-25 MB | Face detection |
| MobileFaceNet | mobilefacenet.tflite | ~5-10 MB | Face embeddings |
| YOLO Currency | currency_notes_yolo.tflite | ~5-10 MB | Currency detection |
| YOLO Banknote | currency_banknote.tflite | ~5-10 MB | Retired classifier |
| YOLO Coin | currency_coin.tflite | ~5-10 MB | Retired classifier |

## 9. Speech Recognition Dependencies

| Service | Model | Location | Size (estimated) |
|---------|-------|----------|------------------|
| Vosk | vosk-model-small-en-us-0.15 | assets/models/ | ~50-100 MB |

## 10. Version Compatibility Notes

### 10.1 Critical Compatibility Layers

| Layer | Components | Status |
|-------|-----------|--------|
| Flutter SDK | 3.13.3+ | Verified |
| Android Gradle Plugin | 9.x | Verified with overrides |
| TensorFlow Lite | 1.4.0 / 2.1.5 | Resolved via config |
| ML Kit | Latest stable | Verified |
| Vosk Flutter | Vendored | Verified |

### 10.2 Known Compatibility Fixes

1. **permission_handler override**: Fixes Flutter v1 embedding API usage
2. **flutter_inappwebview_android override**: Fixes missing proguard file reference
3. **TensorFlow Lite conflict**: Excludes litert-api to avoid duplicate classes

## 11. Dependency Resolution Strategy

### 11.1 Build-Time Resolution

1. Flutter resolves all dependencies from pubspec.yaml
2. Dependency overrides replace specified packages
3. Gradle applies exclude rules for TensorFlow Lite conflict
4. Flutter tooling generates platform embedder code

### 11.2 Runtime Dependencies

| Component | Runtime Dependency |
|-----------|-------------------|
| Camera | camera plugin native implementation |
| TFLite | TensorFlow Lite native library |
| ML Kit | Google Play Services (optional) |
| Vosk | Native C++ runtime |
| TTS | Android TextToSpeech API |
| Permissions | Android Permission System |

## 12. Future Dependency Considerations

### 12.1 Potential Updates

| Package | Current | Consideration |
|---------|---------|---------------|
| camera | ^0.12.0 | Check for newer stable versions |
| flutter_tts | ^4.2.5 | Check for API changes |
| tflite_flutter | ^0.12.1 | Monitor for breaking changes |

### 12.2 Potential Replacements

| Current | Alternative | Rationale |
|---------|-------------|-----------|
| ultralytics_yolo | direct TFLite | More control, fewer dependencies |
| flutter_inappwebview | Remove if unused | Reduces attack surface |
