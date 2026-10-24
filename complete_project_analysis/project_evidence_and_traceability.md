# VisionPath AI - Project Evidence and Traceability

## 1. Technical Claims Evidence Matrix

### 1.1 Core Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| YOLO26n object detection | `ObjectDetectionService` uses `YOLO` plugin | `lib/services/object_detection_service.dart` |
| SCRFD face detection | `ScrfdFaceDetector` loads `scrfd_640.tflite` | `lib/services/scrfd_face_detector.dart` |
| ArcFace embeddings (512-d) | `FaceEmbeddingService` loads `arcface_w600k_mbf.tflite` | `lib/services/face_embedding_service.dart` |
| ML Kit face detection | `FaceDetectionService` uses `FaceDetector` | `lib/services/face_detection_service.dart` |
| ML Kit OCR | `OcrService` uses `TextRecognizer` | `lib/services/ocr_service.dart` |
| Vosk speech recognition | `SpeechService` uses `vosk_flutter` | `lib/services/speech_service.dart` |
| SharedPreferences persistence | `SettingsService` uses `SharedPreferences` | `lib/services/settings_service.dart` |
| Emergency SOS | `SosService` uses `SosPlatform` for calls/SMS | `lib/services/sos_service.dart` |
| Voice guidance | `VoiceService` uses `FlutterTts` | `lib/services/voice_service.dart` |

### 1.2 Navigation Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| Object detection pipeline | 5 FPS sampling in `NavigateScreen` | `lib/screens/navigate_screen.dart` |
| Path analysis | `PathAnalysisService` analyzes central 28%-72% region | `lib/services/path_analysis_service.dart` |
| Navigation decisions | `NavigationService.decide()` returns FORWARD/LEFT/RIGHT/SLOW/STOP | `lib/services/navigation_service.dart` |
| Scene announcement | `SceneAnnouncer` generates sentences per object | `lib/services/scene_announcer.dart` |

### 1.3 Face Recognition Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| Face registration | `FaceRegistrationGuide` guides 12 samples | `lib/services/face_registration_guide.dart` |
| Face recognition | `FaceRecognitionService` matches embeddings | `lib/services/face_recognition_service.dart` |
| Temporal confirmation | `FaceAnnouncementManager` confirms 3 frames | `lib/services/face_announcement_manager.dart` |
| ArcFace model | `arcface_w600k_mbf.tflite` in `assets/ml/` | `assets/ml/arcface_w600k_mbf.tflite` |
| SCRFD model | `scrfd_640.tflite` in `assets/ml/` | `assets/ml/scrfd_640.tflite` |

### 1.4 Emergency Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| Press-and-hold SOS | `SosHoldController` with 5-second countdown | `lib/services/sos_gesture.dart` |
| Emergency contact storage | `EmergencyContactService` saves to SharedPreferences | `lib/services/emergency_contact_service.dart` |
| Location integration | `SosPlatform.getLocation()` uses LocationManager | `lib/services/sos_platform.dart` |

### 1.5 Voice Assistant Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| Press-and-hold voice assistant | `VoiceCommandController` with 350ms threshold | `lib/services/voice_command_controller.dart` |
| Vosk offline STT | `SpeechService` loads `vosk-model-small-en-us-0.15.zip` | `lib/services/speech_service.dart` |

### 1.6 Settings Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| 40+ settings | SettingsService has 40+ setting keys | `lib/services/settings_service.dart` |
| SharedPreferences persistence | `SettingsService.load()` reads from SharedPreferences | `lib/services/settings_service.dart` |
| Theme options | AppThemePreference enum: SYSTEM/LIGHT/DARK | `lib/models/app_settings.dart` |

### 1.7 Testing Features

| Claim | Evidence | File/Line |
|-------|----------|-----------|
| 31 test files | Test directory contains 31 test files | `test/` directory |

---

## 2. Data Flow Evidence

### 2.1 Object Detection Pipeline

| Step | Evidence | File/Line |
|------|----------|-----------|
| Camera frame capture | `CameraService` provides `CameraImage` | `lib/services/camera_service.dart` |
| YUV to RGB conversion | `convertFrameToPortraitRgba()` in `CameraService` | `lib/services/camera_service.dart` |
| YOLO inference | `_yolo!.predict(imageBytes)` | `lib/services/object_detection_service.dart` |
| Bounding box parsing | `_parseResults()` returns `DetectedObject[]` | `lib/services/object_detection_service.dart` |
| Position classification | `PositionDetectionService.analyze()` | `lib/services/position_detection_service.dart` |
| Depth estimation | `DepthAnalysisService.estimateProximity()` | `lib/services/depth_analysis_service.dart` |
| Path analysis | `PathAnalysisService.analyze()` | `lib/services/path_analysis_service.dart` |
| Navigation decision | `NavigationService.decide()` | `lib/services/navigation_service.dart` |

### 2.2 Face Recognition Pipeline

| Step | Evidence | File/Line |
|------|----------|-----------|
| Face detection | `FaceDetectionService.detectRgba()` or `ScrfdFaceDetector.detectRgba()` | `lib/services/face_detection_service.dart` |
| Face alignment | `embeddingFor()` in `FaceEmbeddingService` | `lib/services/face_embedding_service.dart` |
| ArcFace inference | `_interpreter!.run()` with `arcface_w600k_mbf.tflite` | `lib/services/face_embedding_service.dart` |
| Cosine similarity | `_match()` in `FaceRecognitionService` | `lib/services/face_recognition_service.dart` |
| Temporal confirmation | `update()` in `FaceAnnouncementManager` | `lib/services/face_announcement_manager.dart` |

---

## 3. Model File Evidence

### 3.1 Model Files

| Model | Evidence | File Path |
|-------|----------|-----------|
| ArcFace | `assets/ml/arcface_w600k_mbf.tflite` | `assets/ml/arcface_w600k_mbf.tflite` |
| SCRFD | `assets/ml/scrfd_640.tflite` | `assets/ml/scrfd_640.tflite` |
| MobileFaceNet | `assets/ml/mobilefacenet.tflite` | `assets/ml/mobilefacenet.tflite` |
| YOLO Currency | `assets/ml/currency_notes_yolo.tflite` | `assets/ml/currency_notes_yolo.tflite` |
| Vosk | `assets/models/vosk-model-small-en-us-0.15.zip` | `assets/models/vosk-model-small-en-us-0.15.zip` |

### 3.2 Model Loading

| Model | Loading Evidence |
|-------|------------------|
| ArcFace | `Interpreter.fromAsset('assets/ml/arcface_w600k_mbf.tflite')` - `FaceEmbeddingService` |
| SCRFD | `Interpreter.fromAsset('assets/ml/scrfd_640.tflite')` - `ScrfdFaceDetector` |
| Currency YOLO | `CurrencyDetector._fromAsset('assets/ml/currency_notes_yolo.tflite')` - `CurrencyDetector` |

---

## 4. Configuration Evidence

### 4.1 pubspec.yaml Dependencies

| Package | Version | Evidence |
|---------|---------|----------|
| camera | ^0.12.0 | `pubspec.yaml` |
| flutter_tts | ^4.2.5 | `pubspec.yaml` |
| tflite_flutter | ^0.12.1 | `pubspec.yaml` |
| shared_preferences | ^2.5.3 | `pubspec.yaml` |
| permission_handler | 10.2.0 | `pubspec.yaml` |
| provider | ^6.1.2 | `pubspec.yaml` |

### 4.2 Android Configuration

| Component | Evidence |
|-----------|----------|
| compileSdk | `compileSdk = flutter.compileSdkVersion` - `android/app/build.gradle.kts` |
| minSdk | `minSdk = flutter.minSdkVersion` - `android/app/build.gradle.kts` |
| Java version | `sourceCompatibility = JavaVersion.VERSION_17` - `android/app/build.gradle.kts` |
| Kotlin version | `jvmTarget = JVM_17` - `android/app/build.gradle.kts` |

---

## 5. Permission Evidence

### 5.1 AndroidManifest.xml Permissions

| Permission | Evidence | File |
|------------|----------|------|
| CAMERA | `<uses-permission android:name="android.permission.CAMERA" />` | `android/app/src/main/AndroidManifest.xml` |
| RECORD_AUDIO | `<uses-permission android:name="android.permission.RECORD_AUDIO" />` | `android/app/src/main/AndroidManifest.xml` |
| VIBRATE | `<uses-permission android:name="android.permission.VIBRATE" />` | `android/app/src/main/AndroidManifest.xml` |
| CALL_PHONE | `<uses-permission android:name="android.permission.CALL_PHONE" />` | `android/app/src/main/AndroidManifest.xml` |
| SEND_SMS | `<uses-permission android:name="android.permission.SEND_SMS" />` | `android/app/src/main/AndroidManifest.xml` |

### 5.2 Runtime Permissions

| Permission | Request Evidence |
|------------|------------------|
| CAMERA | `Permission.camera.request()` - `CameraService.initializeCamera()` |
| RECORD_AUDIO | `Permission.microphone.request()` - `SpeechCaptureService.startCapture()` |

---

## 6. Settings Evidence

### 6.1 Settings Keys

| Setting | Key Evidence |
|---------|--------------|
| voiceGuidance | `setting.voiceGuidance` |
| speechRate | `setting.speechRate` |
| voiceVolume | `setting.voiceVolume` |
| emergency_contacts | `emergency_contacts` |

---

## 7. Test Evidence

### 7.1 Test Files

| Test | Evidence | File |
|------|----------|------|
| SCRFD detection | `scrfd_detector_test.dart` | `test/scrfd_detector_test.dart` |
| ArcFace inference | `face_embedding_tensor_test.dart` | `test/face_embedding_tensor_test.dart` |
| Face matching | `face_recognition_test.dart` | `test/face_recognition_test.dart` |
| Currency detection | `currency_detector_test.dart` | `test/currency_detector_test.dart` |
| SOS service | `sos_service_test.dart` | `test/sos_service_test.dart` |

---

## 8. Data Flow Diagrams

### 8.1 Application Start Flow

```
main() [lib/main.dart:5]
    ↓
WidgetsFlutterBinding.ensureInitialized() [lib/main.dart:7]
    ↓
FaceEmbeddingService.instance.ensureLoaded() [lib/main.dart:10]
    ↓
SettingsService.instance.load() [lib/main.dart:13]
    ↓
EmergencyContactService.instance.load() [lib/main.dart:16]
    ↓
VoiceService.bindToSettings() [lib/main.dart:19]
    ↓
SosService.instance.attachNavigation() [lib/main.dart:22]
    ↓
runApp(VisionPathApp) [lib/main.dart:25]
```

### 8.2 Settings Persistence Flow

```
SettingsScreen [lib/screens/settings_screen.dart]
    ↓
SettingsService setter [lib/services/settings_service.dart]
    ↓
SharedPreferences.setBool()/setString() [lib/services/settings_service.dart]
    ↓
commit() [lib/services/settings_service.dart]
    ↓
SharedPreferences.xml [platform-specific]
```

---

## 9. Algorithm Evidence

### 9.1 Object Detection Algorithm

| Step | Evidence |
|------|----------|
| YOLO26n model | `YOLO26n` in `object_detection_service.dart:25` |
| Confidence threshold | `_confidenceThreshold = 0.40` - `object_detection_service.dart:28` |
| NMS | YOLO plugin handles NMS |

### 9.2 Face Recognition Algorithm

| Step | Evidence |
|------|----------|
| SCRFD detection | `scrfd_640.tflite` - `scrfd_face_detector.dart:18` |
| ArcFace embedding | `arcface_w600k_mbf.tflite` - `face_embedding_service.dart:18` |
| Similarity threshold | `0.95` - `face_recognition_service.dart:15` |

---

## 10. Platform Evidence

### 10.1 Android API

| Component | Evidence |
|-----------|----------|
| Camera | `CameraX` via `camera` plugin |
| TTS | `TextToSpeech` via `flutter_tts` plugin |
| Permissions | `android.permission.*` via `permission_handler` |

---

## 11. Evidence Summary Table

| Category | Claim | Evidence Level | File |
|----------|-------|----------------|------|
| Core Feature | YOLO26n detection | High | `lib/services/object_detection_service.dart` |
| Core Feature | SCRFD detection | High | `lib/services/scrfd_face_detector.dart` |
| Core Feature | ArcFace embeddings | High | `lib/services/face_embedding_service.dart` |
| Core Feature | ML Kit OCR | High | `lib/services/ocr_service.dart` |
| Core Feature | Vosk STT | High | `lib/services/speech_service.dart` |
| Navigation | Path analysis | High | `lib/services/path_analysis_service.dart` |
| Navigation | Navigation decisions | High | `lib/services/navigation_service.dart` |
| Face Recognition | Face registration | High | `lib/services/face_registration_guide.dart` |
| Face Recognition | Temporal confirmation | High | `lib/services/face_announcement_manager.dart` |
| Emergency | SOS activation | High | `lib/services/sos_service.dart` |
| Emergency | Contact storage | High | `lib/services/emergency_contact_service.dart` |
| Voice | Press-and-hold | High | `lib/services/voice_command_controller.dart` |
| Voice | Vosk STT | High | `lib/services/speech_service.dart` |
| Settings | 40+ settings | High | `lib/services/settings_service.dart` |
| Testing | 31 test files | High | `test/` |

---

## 12. Unverified Claims

| Claim | Evidence Level | Notes |
|-------|----------------|-------|
| Model accuracy | Medium | Accuracy not measured in code |
| Frame rate | Medium | Expected 5 FPS based on timer |
| Memory usage | Low | Not measured in code |
| Battery impact | Low | Not measured in code |

---

## 13. Conclusion

All major technical claims are **verified by source code evidence**:

- ✅ YOLO26n, SCRFD, ArcFace models - Model files and loading code verified
- ✅ ML Kit OCR, Face Detection - ML Kit integration verified
- ✅ Vosk speech recognition - Vosk integration verified
- ✅ Navigation pipeline - 5 FPS sampling, path analysis, decisions
- ✅ Face recognition - Registration, embedding, matching, confirmation
- ✅ Emergency SOS - Call, SMS, location, notification
- ✅ Settings persistence - SharedPreferences with 40+ keys
- ✅ Voice assistant - Press-and-hold, Vosk STT
- ✅ Testing - 31 test files covering core features

No unverified claims of external APIs, cloud services, or network communication.
