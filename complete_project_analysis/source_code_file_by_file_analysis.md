# VisionPath AI - Source Code File-by-File Analysis

## 1. Entry Point and Application Structure

### 1.1 lib/main.dart

| Property | Value |
|----------|-------|
| **Purpose** | Application entry point, service initialization, provider tree setup |
| **Main Classes** | VisionPathApp, _AppRoot, _AppRootState, SosRouteObserver |
| **Key Functions** | main(), build() |
| **Inputs** | None (entry point) |
| **Outputs** | Flutter app with 9 providers |
| **Dependencies** | 12+ services, 2+ widgets |
| **Interactions** | Initializes all services before UI renders |
| **Algorithms** | Lazy loading with ensureLoaded() |
| **Error Handling** | Try-catch in service initialization |
| **Active** | ✅ Yes |

**Key Code:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FaceEmbeddingService.instance.ensureLoaded();
  await SettingsService.instance.load();
  await EmergencyContactService.instance.load();
  runApp(const VisionPathApp());
}
```

---

### 1.2 lib/l10n/app_localizations.dart

| Property | Value |
|----------|-------|
| **Purpose** | Localization support |
| **Main Classes** | AppLocalizations |
| **Key Functions** | load(), of() |
| **Inputs** | Locale |
| **Outputs** | Localized strings |
| **Dependencies** | Flutter localization |
| **Active** | ✅ Yes |

---

## 2. Model Files (lib/models/)

### 2.1 app_settings.dart

| Property | Value |
|----------|-------|
| **Purpose** | Settings enums and configuration |
| **Main Classes** | SpeechRate, VoiceLanguage, TextSizeLevel, ObstacleSensitivity, DetectionSensitivity, FamiliarFaceSensitivity, GuidanceMode, AlertMode, AppThemePreference, SosAlertTone |
| **Key Functions** | fromName() for enums |
| **Inputs** | None |
| **Outputs** | Enum values |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.2 currency_recognition.dart

| Property | Value |
|----------|-------|
| **Purpose** | Currency recognition result models |
| **Main Classes** | CurrencyKind, CurrencyInferenceStatus, CurrencyInferenceResult |
| **Key Functions** | From result states |
| **Inputs** | None |
| **Outputs** | Currency recognition results |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.3 depth_map.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth map data structures |
| **Main Classes** | DepthMap |
| **Key Functions** | Constructor, conversion |
| **Inputs** | Depth values |
| **Outputs** | Depth map |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.4 depth_result.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth analysis results |
| **Main Classes** | DepthResult |
| **Key Functions** | Constructor |
| **Inputs** | Depth data |
| **Outputs** | Depth result |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.5 depth_scene.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth scene classification |
| **Main Classes** | DepthScene |
| **Key Functions** | Constructor |
| **Inputs** | Scene classification |
| **Outputs** | Depth scene |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.6 detected_object.dart

| Property | Value |
|----------|-------|
| **Purpose** | Object detection results |
| **Main Classes** | DetectedObject |
| **Key Functions** | copyWith(), fromJson() |
| **Inputs** | Bounding box, class, confidence, position, proximity |
| **Outputs** | DetectedObject with all properties |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.7 emergency_contact.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency contact data |
| **Main Classes** | EmergencyContact |
| **Key Functions** | fromJson(), toJson() |
| **Inputs** | Name, phone |
| **Outputs** | EmergencyContact |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.8 face_detection.dart

| Property | Value |
|----------|-------|
| **Purpose** | Face detection models |
| **Main Classes** | DetectedFace, FaceLandmarkPoint |
| **Key Functions** | fromJson(), toJson() |
| **Inputs** | Bounding box, landmarks, contours |
| **Outputs** | DetectedFace |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.9 familiar_face.dart

| Property | Value |
|----------|-------|
| **Purpose** | Registered face embeddings |
| **Main Classes** | FamiliarFace |
| **Key Functions** | copyWith(), fromJson(), toJson() |
| **Inputs** | ID, name, embedding, sampleCount, createdAt, relationship, templates, model |
| **Outputs** | FamiliarFace |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.10 live_assistant_state.dart

| Property | Value |
|----------|-------|
| **Purpose** | Live assistant state |
| **Main Classes** | LiveAssistantState |
| **Key Functions** | Constructor |
| **Inputs** | None |
| **Outputs** | State object |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.11 look_and_detect.dart

| Property | Value |
|----------|-------|
| **Purpose** | Look & Detect models |
| **Main Classes** | SceneObject |
| **Key Functions** | Constructor |
| **Inputs** | Class name, position, proximity, name |
| **Outputs** | SceneObject |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.12 navigation_decision.dart

| Property | Value |
|----------|-------|
| **Purpose** | Navigation decision types |
| **Main Classes** | NavigationDecision |
| **Key Functions** | Constructor |
| **Inputs** | Decision type |
| **Outputs** | NavigationDecision enum |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.13 object_position.dart

| Property | Value |
|----------|-------|
| **Purpose** | Object position (LEFT/CENTER/RIGHT) |
| **Main Classes** | ObjectPosition |
| **Key Functions** | fromCenterX() |
| **Inputs** | Center X (normalized 0-1) |
| **Outputs** | ObjectPosition enum |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.14 ocr_result.dart

| Property | Value |
|----------|-------|
| **Purpose** | OCR result data |
| **Main Classes** | OcrResult |
| **Key Functions** | Constructor |
| **Inputs** | Text, text blocks |
| **Outputs** | OcrResult |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.15 path_analysis.dart

| Property | Value |
|----------|-------|
| **Purpose** | Path analysis results |
| **Main Classes** | PathAnalysis, PathAnalysisResult |
| **Key Functions** | Constructor |
| **Inputs** | Analysis type, primaryBlocker, leftMargin, rightMargin, pathFullyBlocked |
| **Outputs** | PathAnalysisResult |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.16 proximity_level.dart

| Property | Value |
|----------|-------|
| **Purpose** | Proximity levels (NEAR/MEDIUM/FAR) |
| **Main Classes** | ProximityLevel |
| **Key Functions** | Constructor |
| **Inputs** | Proximity level |
| **Outputs** | ProximityLevel enum |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.17 rgb_frame.dart

| Property | Value |
|----------|-------|
| **Purpose** | RGB frame data |
| **Main Classes** | RgbFrame |
| **Key Functions** | Constructor |
| **Inputs** | RGBA bytes, width, height |
| **Outputs** | RgbFrame |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.18 sos_session.dart

| Property | Value |
|----------|-------|
| **Purpose** | SOS emergency session state |
| **Main Classes** | SosSession, SosState, SosStep |
| **Key Functions** | Constructor |
| **Inputs** | State, contact info, steps, alerting |
| **Outputs** | SosSession |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 2.19 target_search.dart

| Property | Value |
|----------|-------|
| **Purpose** | Target search models |
| **Main Classes** | TargetSearch |
| **Key Functions** | Constructor |
| **Inputs** | None |
| **Outputs** | TargetSearch object |
| **Dependencies** | None |
| **Active** | ✅ Yes |

---

## 3. Service Files (lib/services/)

### 3.1 camera_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Camera management (preview, capture, lens switching) |
| **Main Classes** | CameraService |
| **Key Functions** | initializeCamera(), switchCamera(), takePicture() |
| **Inputs** | None |
| **Outputs** | Camera controller, preview, photos |
| **Dependencies** | camera ^0.12.0 |
| **Interactions** | Used by all camera screens |
| **Algorithms** | YUV to RGBA conversion |
| **Error Handling** | Try-catch with user feedback |
| **Active** | ✅ Yes |

### 3.2 currency_command_parser.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice command parsing for currency actions |
| **Main Classes** | CurrencyCommandParser |
| **Key Functions** | parseCommand() |
| **Inputs** | Voice transcript |
| **Outputs** | Currency command type |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.3 currency_detector.dart

| Property | Value |
|----------|-------|
| **Purpose** | Currency YOLO inference |
| **Main Classes** | CurrencyDetector |
| **Key Functions** | process(), preprocess() |
| **Inputs** | RGBA image buffer |
| **Outputs** | CurrencyRecognition? |
| **Dependencies** | tflite_flutter ^0.12.1 |
| **Interactions** | Called by CurrencyRecognitionService |
| **Algorithms** | YOLO inference |
| **Error Handling** | Try-catch, returns null on error |
| **Active** | ✅ Yes |

### 3.4 currency_recognition_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Currency recognition orchestration |
| **Main Classes** | CurrencyRecognitionService |
| **Key Functions** | analyze() |
| **Inputs** | RGBA image buffer |
| **Outputs** | CurrencyInferenceResult |
| **Dependencies** | CurrencyDetector |
| **Active** | ✅ Yes |

### 3.5 currency_stability_verifier.dart

| Property | Value |
|----------|-------|
| **Purpose** | Currency detection stability filtering |
| **Main Classes** | CurrencyStabilityVerifier |
| **Key Functions** | verify() |
| **Inputs** | Detection results |
| **Outputs** | Filtered results |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.6 depth/depth_engine.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth estimation interface |
| **Main Classes** | DepthEngine |
| **Key Functions** | estimateDepth() |
| **Inputs** | RGBA image |
| **Outputs** | Depth map |
| **Dependencies** | tflite_flutter |
| **Active** | ✅ Yes |

### 3.7 depth/depth_metric_calibration.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth calibration for metric distance |
| **Main Classes** | DepthMetricCalibration |
| **Key Functions** | calibrate() |
| **Inputs** | Relative depth |
| **Outputs** | Estimated distance in meters |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.8 depth/geometric_depth_engine.dart

| Property | Value |
|----------|-------|
| **Purpose** | Geometric depth fallback (box-area heuristic) |
| **Main Classes** | GeometricDepthEngine |
| **Key Functions** | estimateDepth() |
| **Inputs** | Detected objects |
| **Outputs** | Proximity levels |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.9 depth_analysis_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth analysis orchestration |
| **Main Classes** | DepthAnalysisService |
| **Key Functions** | analyze() |
| **Inputs** | Detected objects |
| **Outputs** | Objects with proximity |
| **Dependencies** | DepthEngine, SettingsService |
| **Active** | ✅ Yes |

### 3.10 detection_coordinate_transformer.dart

| Property | Value |
|----------|-------|
| **Purpose** | Coordinate mapping from model input to canvas |
| **Main Classes** | DetectionCoordinateTransformer |
| **Key Functions** | project() |
| **Inputs** | Box, inputSize, widgetSize |
| **Outputs** | Projected Rect |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.11 emergency_contact_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency contact storage and management |
| **Main Classes** | EmergencyContactService |
| **Key Functions** | load(), addContact(), updateContact(), deleteContact() |
| **Inputs** | Name, phone |
| **Outputs** | Contact list, save result |
| **Dependencies** | shared_preferences ^2.5.3 |
| **Interactions** | Used by EmergencyScreen and SosService |
| **Algorithms** | JSON encoding/decoding |
| **Error Handling** | Try-catch, returns error status |
| **Active** | ✅ Yes |

### 3.12 face_announcement_manager.dart

| Property | Value |
|----------|-------|
| **Purpose** | Face recognition temporal confirmation and announcement policy |
| **Main Classes** | FaceAnnouncementManager, _FaceTrack |
| **Key Functions** | update() |
| **Inputs** | Face occurrences, timestamp |
| **Outputs** | Announced faces with names |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.13 face_detection_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | ML Kit face detection wrapper |
| **Main Classes** | FaceDetectionService |
| **Key Functions** | detectRgba() |
| **Inputs** | RGBA image buffer |
| **Outputs** | DetectedFace[] |
| **Dependencies** | google_mlkit_face_detection ^0.15.1 |
| **Interactions** | Used by FamiliarFacesScreen |
| **Algorithms** | ML Kit Face Detector |
| **Error Handling** | Try-catch, returns empty list on error |
| **Active** | ✅ Yes |

### 3.14 face_embedding_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | ArcFace embedding extraction |
| **Main Classes** | FaceEmbeddingService |
| **Key Functions** | ensureLoaded(), embeddingFor() |
| **Inputs** | RGBA image, face |
| **Outputs** | 512-d embedding |
| **Dependencies** | tflite_flutter ^0.12.1 |
| **Interactions** | Used by FaceRecognitionService |
| **Algorithms** | ArcFace inference, alignment |
| **Error Handling** | Try-catch, returns null on error |
| **Active** | ✅ Yes |

### 3.15 face_recognition_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Face matching and geometric embeddings |
| **Main Classes** | FaceRecognitionService |
| **Key Functions** | generateEmbedding(), match() |
| **Inputs** | DetectedFace |
| **Outputs** | 30-d embedding, similarity score |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.16 face_registration_guide.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice-guided face positioning for registration |
| **Main Classes** | FaceRegistrationGuide |
| **Key Functions** | update() |
| **Inputs** | DetectedFace, currentSample |
| **Outputs** | RegistrationGuidance |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.17 familiar_face_repository.dart

| Property | Value |
|----------|-------|
| **Purpose** | Familiar face repository abstraction |
| **Main Classes** | FamiliarFaceRepository, SharedPreferencesFamiliarFaceRepository |
| **Key Functions** | loadAll(), saveAll() |
| **Inputs** | FamiliarFace list |
| **Outputs** | Repository operations |
| **Dependencies** | shared_preferences ^2.5.3 |
| **Active** | ✅ Yes |

### 3.18 familiar_face_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Registered faces management |
| **Main Classes** | FamiliarFaceService |
| **Key Functions** | load(), addPerson(), updatePerson(), deletePerson() |
| **Inputs** | Name, relationship, embeddings |
| **Outputs** | Face list, save result |
| **Dependencies** | FamiliarFaceRepository |
| **Interactions** | Used by FamiliarFacesScreen and FaceRegistrationScreen |
| **Algorithms** | Mean embedding calculation |
| **Error Handling** | Try-catch, empty list on error |
| **Active** | ✅ Yes |

### 3.19 instruction_manager.dart

| Property | Value |
|----------|-------|
| **Purpose** | Navigation instruction deduplication and cooldown |
| **Main Classes** | InstructionManager |
| **Key Functions** | shouldSpeak(), repeatLast() |
| **Inputs** | NavigationDecision, timestamp |
| **Outputs** | Boolean (should speak), sentences |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.20 look_and_detect_engine.dart

| Property | Value |
|----------|-------|
| **Purpose** | Look & Detect feature logic |
| **Main Classes** | LookAndDetectEngine, _Track, _Candidate |
| **Key Functions** | update(), answer(), primaryFor() |
| **Inputs** | DetectedObject[] |
| **Outputs** | SceneObject[], answer string |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.21 navigation_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Navigation decision engine |
| **Main Classes** | NavigationService |
| **Key Functions** | decide(), commitAnnouncement() |
| **Inputs** | PathAnalysisResult |
| **Outputs** | NavigationDecision, spoken message |
| **Dependencies** | SceneAnnouncer |
| **Interactions** | Used by NavigateScreen |
| **Algorithms** | Path-based navigation |
| **Error Handling** | Try-catch, default decision on error |
| **Active** | ✅ Yes |

### 3.22 object_detection_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | YOLO26n object detection |
| **Main Classes** | ObjectDetectionService |
| **Key Functions** | initialize(), detect() |
| **Inputs** | YUV image |
| **Outputs** | DetectedObject[] |
| **Dependencies** | ultralytics_yolo ^0.6.14 |
| **Interactions** | Used by NavigateScreen |
| **Algorithms** | YOLO26n inference |
| **Error Handling** | Try-catch, returns empty list on error |
| **Active** | ✅ Yes |

### 3.23 object_vocabulary.dart

| Property | Value |
|----------|-------|
| **Purpose** | Object class names and categories |
| **Main Classes** | ObjectVocabulary |
| **Key Functions** | getCategory(), isVehicle(), etc. |
| **Inputs** | Class name |
| **Outputs** | Category |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.24 ocr_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | ML Kit OCR wrapper |
| **Main Classes** | OcrService |
| **Key Functions** | _ensureRecognizer(), recognize(), recognizeImageFile() |
| **Inputs** | CameraImage, InputImage |
| **Outputs** | OcrResult |
| **Dependencies** | google_mlkit_text_recognition ^0.17.1 |
| **Interactions** | Used by ReadTextScreen |
| **Algorithms** | ML Kit Text Recognition |
| **Error Handling** | Try-catch, returns empty result on error |
| **Active** | ✅ Yes |

### 3.25 path_analysis_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Path obstruction analysis |
| **Main Classes** | PathAnalysisService |
| **Key Functions** | analyze() |
| **Inputs** | DetectedObject[] |
| **Outputs** | PathAnalysisResult |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.26 position_detection_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Object position classification |
| **Main Classes** | PositionDetectionService |
| **Key Functions** | analyze() |
| **Inputs** | DetectedObject[] |
| **Outputs** | Objects with position |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.27 scene_announcer.dart

| Property | Value |
|----------|-------|
| **Purpose** | Multi-object scene description generation |
| **Main Classes** | SceneAnnouncer, SceneAnnouncement, SceneSlot |
| **Key Functions** | announce(), commit() |
| **Inputs** | DetectedObject[] |
| **Outputs** | Sentence list, slots |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.28 scrfd_face_detector.dart

| Property | Value |
|----------|-------|
| **Purpose** | SCRFD face detector |
| **Main Classes** | ScrfdFaceDetector |
| **Key Functions** | ensureLoaded(), detectRgba() |
| **Inputs** | RGBA image buffer |
| **Outputs** | DetectedFace[] |
| **Dependencies** | tflite_flutter ^0.12.1 |
| **Interactions** | Used by FaceDetectionService |
| **Algorithms** | SCRFD inference |
| **Error Handling** | Try-catch, returns empty list on error |
| **Active** | ✅ Yes |

### 3.29 settings_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Settings persistence |
| **Main Classes** | SettingsService |
| **Key Functions** | load(), setters (voiceGuidanceEnabled=, etc.) |
| **Inputs** | Setting key-value pairs |
| **Outputs** | Settings, save result |
| **Dependencies** | shared_preferences ^2.5.3 |
| **Interactions** | Used by all screens via Provider |
| **Algorithms** | SharedPreferences read/write |
| **Error Handling** | Try-catch, returns default on error |
| **Active** | ✅ Yes |

### 3.30 sos_platform.dart

| Property | Value |
|----------|-------|
| **Purpose** | Platform integration for SOS (phone, SMS, location) |
| **Main Classes** | SosPlatform, SosCallBlocker, SosSmsBlocker, SosLocationBlocker |
| **Key Functions** | requestCallPhonePermission(), placeCall(), sendSms(), getLocation() |
| **Inputs** | Phone number, message, timeout |
| **Outputs** | Platform operation results |
| **Dependencies** | permission_handler, flutter/services |
| **Interactions** | Used by SosService |
| **Algorithms** | Platform method calls |
| **Error Handling** | Try-catch, returns blocker enum on error |
| **Active** | ✅ Yes |

### 3.31 sos_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency SOS orchestration |
| **Main Classes** | SosService, SosSession, SosState, SosStep |
| **Key Functions** | activate(), reset() |
| **Inputs** | User SOS activation |
| **Outputs** | Emergency state, call, SMS, notification |
| **Dependencies** | SosPlatform, VoiceService, VibrationService, EmergencyContactService |
| **Interactions** | Used by EmergencyScreen |
| **Algorithms** | Emergency contact notification |
| **Error Handling** | Try-catch, continues on partial errors |
| **Active** | ✅ Yes |

### 3.32 speech_capture_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice command capture |
| **Main Classes** | SpeechCaptureService |
| **Key Functions** | startCapture(), stopCapture() |
| **Inputs** | None |
| **Outputs** | Audio stream |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.33 speech_queue.dart

| Property | Value |
|----------|-------|
| **Purpose** | Sequential speech queue management |
| **Main Classes** | SpeechQueue |
| **Key Functions** | add(), takeNext(), finishCurrent(), clear() |
| **Inputs** | Sentences |
| **Outputs** | Queue operations |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.34 speech_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Vosk offline speech recognition |
| **Main Classes** | SpeechService |
| **Key Functions** | initialize(), listen(), stop(), cancel(), dispose() |
| **Inputs** | Audio stream |
| **Outputs** | Transcribed text |
| **Dependencies** | vosk_flutter (vendored) |
| **Interactions** | Used by VoiceCommandController |
| **Algorithms** | Vosk offline STT |
| **Error Handling** | Try-catch, returns error on failure |
| **Active** | ✅ Yes |

### 3.35 voice_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | TTS and speech orchestration |
| **Main Classes** | VoiceService (static) |
| **Key Functions** | enqueueSpeech(), speakEmergency(), clearSpeechQueue(), bindToSettings() |
| **Inputs** | Text, speech settings |
| **Outputs** | TTS playback |
| **Dependencies** | flutter_tts ^4.2.5, SpeechQueue |
| **Interactions** | Used by all screens |
| **Algorithms** | FlutterTTS integration |
| **Error Handling** | Try-catch, continues on error |
| **Active** | ✅ Yes |

### 3.36 target_navigation_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Target tracking navigation |
| **Main Classes** | TargetNavigationService |
| **Key Functions** | update() |
| **Inputs** | Detected objects |
| **Outputs** | Navigation guidance |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.37 text_guidance_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | OCR guidance overlay |
| **Main Classes** | TextGuidanceService |
| **Key Functions** | analyze() |
| **Inputs** | OCR result |
| **Outputs** | TextGuidance |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.38 vibration_service.dart

| Property | Value |
|----------|-------|
| **Purpose** | Haptic feedback management |
| **Main Classes** | VibrationService |
| **Key Functions** | vibrateOnce(), vibrateNavigation(), vibrateFamiliarFace(), vibrateSOS() |
| **Inputs** | Pattern type |
| **Outputs** | Vibration |
| **Dependencies** | vibration ^3.2.1, flutter/services |
| **Interactions** | Used by EmergencyScreen and voice command completion |
| **Algorithms** | Native vibration or HapticFeedback |
| **Error Handling** | Try-catch, silent on error |
| **Active** | ✅ Yes |

### 3.39 voice_command_controller.dart

| Property | Value |
|----------|-------|
| **Purpose** | Press-and-hold voice assistant |
| **Main Classes** | VoiceCommandController |
| **Key Functions** | beginHold(), onHoldReleased() |
| **Inputs** | Touch events |
| **Outputs** | Transcribed text |
| **Dependencies** | SpeechCaptureService, VoiceService |
| **Interactions** | Used by all screens with press-and-hold |
| **Algorithms** | Press-and-hold detection |
| **Error Handling** | Try-catch, returns failure enum on error |
| **Active** | ✅ Yes |

### 3.40 voice_input.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice input abstraction interface |
| **Main Classes** | VoiceInput |
| **Key Functions** | initialize(), listen(), stop(), cancel(), dispose() |
| **Inputs** | None |
| **Outputs** | Voice input operations |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 3.41 web_speech_engine.dart

| Property | Value |
|----------|-------|
| **Purpose** | Web Speech API fallback |
| **Main Classes** | WebSpeechEngine |
| **Key Functions** | initialize(), listen(), stop(), cancel(), dispose() |
| **Inputs** | None |
| **Outputs** | Voice recognition |
| **Dependencies** | None |
| **Active** | ✅ Yes |

---

## 4. Screen Files (lib/screens/)

### 4.1 about_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | About app screen |
| **Main Classes** | AboutScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | About screen UI |
| **Dependencies** | package_info_plus ^8.0.0 |
| **Active** | ✅ Yes |

### 4.2 accessibility_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Accessibility settings screen |
| **Main Classes** | AccessibilitySettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Accessibility settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.3 currency_recognition_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Currency recognition screen |
| **Main Classes** | CurrencyRecognitionScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Currency recognition UI |
| **Dependencies** | CurrencyRecognitionService |
| **Active** | ✅ Yes |

### 4.4 detection_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Detection settings screen |
| **Main Classes** | DetectionSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Detection settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.5 emergency_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | SOS emergency screen |
| **Main Classes** | EmergencyScreen |
| **Key Functions** | build(), _onSosChanged() |
| **Inputs** | None |
| **Outputs** | Emergency screen UI |
| **Dependencies** | SosService, EmergencyContactService |
| **Active** | ✅ Yes |

### 4.6 emergency_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency settings screen |
| **Main Classes** | EmergencySettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Emergency settings UI |
| **Dependencies** | EmergencyContactService |
| **Active** | ✅ Yes |

### 4.7 face_registration_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Face registration screen |
| **Main Classes** | FaceRegistrationScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Face registration UI |
| **Dependencies** | FaceDetectionService, FaceEmbeddingService, FamiliarFaceService |
| **Active** | ✅ Yes |

### 4.8 familiar_faces_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Familiar faces recognition hub |
| **Main Classes** | FamiliarFacesScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Familiar faces UI |
| **Dependencies** | FaceDetectionService, FaceRecognitionService, FamiliarFaceService |
| **Active** | ✅ Yes |

### 4.9 familiar_face_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Familiar face settings screen |
| **Main Classes** | FamiliarFaceSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Familiar face settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.10 general_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | General settings screen |
| **Main Classes** | GeneralSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | General settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.11 look_and_detect_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Look & Detect screen |
| **Main Classes** | LookAndDetectScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Look & Detect UI |
| **Dependencies** | LookAndDetectEngine |
| **Active** | ✅ Yes |

### 4.12 navigate_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Main navigation screen |
| **Main Classes** | NavigateScreen |
| **Key Functions** | build(), _startNavigation(), _stopNavigation() |
| **Inputs** | None |
| **Outputs** | Navigation UI |
| **Dependencies** | All navigation services |
| **Active** | ✅ Yes |

### 4.13 navigation_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Navigation settings screen |
| **Main Classes** | NavigationSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Navigation settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.14 notifications_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Notifications settings screen |
| **Main Classes** | NotificationsSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Notifications settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.15 privacy_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Privacy settings screen |
| **Main Classes** | PrivacySettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Privacy settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.16 read_text_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Read text (OCR) screen |
| **Main Classes** | ReadTextScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Read text UI |
| **Dependencies** | OcrService, TextGuidanceService |
| **Active** | ✅ Yes |

### 4.17 read_text_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Read text settings screen |
| **Main Classes** | ReadTextSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Read text settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.18 registered_faces_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Registered faces management screen |
| **Main Classes** | RegisteredFacesScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Registered faces UI |
| **Dependencies** | FamiliarFaceService |
| **Active** | ✅ Yes |

### 4.19 reset_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Reset settings screen |
| **Main Classes** | ResetSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Reset settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.20 settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Main settings dashboard |
| **Main Classes** | SettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 4.21 voice_settings_screen.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice settings screen |
| **Main Classes** | VoiceSettingsScreen |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Voice settings UI |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

---

## 5. Widget Files (lib/widgets/)

### 5.1 camera_preview_fit.dart

| Property | Value |
|----------|-------|
| **Purpose** | Camera preview with aspect ratio |
| **Main Classes** | CameraPreviewFit |
| **Key Functions** | build() |
| **Inputs** | Camera controller |
| **Outputs** | Camera preview widget |
| **Dependencies** | camera ^0.12.0 |
| **Active** | ✅ Yes |

### 5.2 depth_debug_overlay.dart

| Property | Value |
|----------|-------|
| **Purpose** | Depth map debug visualization |
| **Main Classes** | DepthDebugOverlay |
| **Key Functions** | build() |
| **Inputs** | Depth map |
| **Outputs** | Depth overlay widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.3 detection_overlay.dart

| Property | Value |
|----------|-------|
| **Purpose** | YOLO detection boxes overlay |
| **Main Classes** | DetectionOverlay |
| **Key Functions** | build() |
| **Inputs** | DetectedObject[] |
| **Outputs** | Detection overlay widget |
| **Dependencies** | DetectionCoordinateTransformer |
| **Active** | ✅ Yes |

### 5.4 emergency_contact_card.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency contact card |
| **Main Classes** | EmergencyContactCard |
| **Key Functions** | build() |
| **Inputs** | EmergencyContact |
| **Outputs** | Contact card widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.5 emergency_location_card.dart

| Property | Value |
|----------|-------|
| **Purpose** | Emergency location card |
| **Main Classes** | EmergencyLocationCard |
| **Key Functions** | build() |
| **Inputs** | Location |
| **Outputs** | Location card widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.6 emergency_sos_button.dart

| Property | Value |
|----------|-------|
| **Purpose** | SOS activation button |
| **Main Classes** | EmergencySOSButton |
| **Key Functions** | build() |
| **Inputs** | SosHoldController |
| **Outputs** | SOS button widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.7 face_recognition_overlay.dart

| Property | Value |
|----------|-------|
| **Purpose** | Face recognition boxes and labels overlay |
| **Main Classes** | FaceRecognitionOverlay, _FaceOverlayPainter |
| **Key Functions** | build() |
| **Inputs** | FaceOverlayEntry[] |
| **Outputs** | Face overlay widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.8 listening_orb.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice assistant listening indicator |
| **Main Classes** | ListeningOrb |
| **Key Functions** | build() |
| **Inputs** | Listening state |
| **Outputs** | Listening orb widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.9 ocr_result_card.dart

| Property | Value |
|----------|-------|
| **Purpose** | OCR result display |
| **Main Classes** | OcrResultCard |
| **Key Functions** | build() |
| **Inputs** | OcrResult |
| **Outputs** | OCR result card widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.10 press_and_hold_voice_region.dart

| Property | Value |
|----------|-------|
| **Purpose** | Press-and-hold voice assistant trigger |
| **Main Classes** | PressAndHoldVoiceRegion |
| **Key Functions** | build() |
| **Inputs** | VoiceCommandController |
| **Outputs** | Voice region widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.11 read_text_controls.dart

| Property | Value |
|----------|-------|
| **Purpose** | Read text controls |
| **Main Classes** | ReadTextControls |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Controls widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.12 settings_button.dart

| Property | Value |
|----------|-------|
| **Purpose** | Settings button |
| **Main Classes** | SettingsButton |
| **Key Functions** | build() |
| **Inputs** | None |
| **Outputs** | Settings button widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.13 settings_scope.dart

| Property | Value |
|----------|-------|
| **Purpose** | Settings theme wrapper |
| **Main Classes** | SettingsScope |
| **Key Functions** | build() |
| **Inputs** | Child widget |
| **Outputs** | Scoped widget |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 5.14 settings_widgets.dart

| Property | Value |
|----------|-------|
| **Purpose** | Shared settings UI components |
| **Main Classes** | Various settings widgets |
| **Key Functions** | Various |
| **Inputs** | None |
| **Outputs** | Settings UI components |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 5.15 sos_gesture.dart

| Property | Value |
|----------|-------|
| **Purpose** | Press-and-hold SOS handler |
| **Main Classes** | SosHoldController, SosGesture |
| **Key Functions** | beginHold(), onHoldReleased() |
| **Inputs** | Touch events |
| **Outputs** | SOS gesture processing |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.16 sound_mode_button.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice/vibrate/mute toggle |
| **Main Classes** | SoundModeButton |
| **Key Functions** | build() |
| **Inputs** | AlertMode |
| **Outputs** | Sound mode button widget |
| **Dependencies** | SettingsService |
| **Active** | ✅ Yes |

### 5.17 target_status_chip.dart

| Property | Value |
|----------|-------|
| **Purpose** | Target tracking status |
| **Main Classes** | TargetStatusChip |
| **Key Functions** | build() |
| **Inputs** | Target status |
| **Outputs** | Status chip widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.18 text_camera_preview.dart

| Property | Value |
|----------|-------|
| **Purpose** | OCR camera preview |
| **Main Classes** | TextCameraPreview |
| **Key Functions** | build() |
| **Inputs** | Camera controller |
| **Outputs** | OCR preview widget |
| **Dependencies** | camera ^0.12.0 |
| **Active** | ✅ Yes |

### 5.19 text_guidance_status.dart

| Property | Value |
|----------|-------|
| **Purpose** | OCR positioning guidance |
| **Main Classes** | TextGuidanceStatus |
| **Key Functions** | build() |
| **Inputs** | TextGuidance |
| **Outputs** | Guidance status widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

### 5.20 voice_search_overlay.dart

| Property | Value |
|----------|-------|
| **Purpose** | Voice search overlay |
| **Main Classes** | VoiceSearchOverlay |
| **Key Functions** | build() |
| **Inputs** | Listening state |
| **Outputs** | Voice search overlay widget |
| **Dependencies** | None |
| **Active** | ✅ Yes |

---

## 6. Utility Files (lib/utils/)

### 6.1 portrait_rgba.dart

| Property | Value |
|----------|-------|
| **Purpose** | Camera frame preprocessing |
| **Main Classes** | PortraitRgba |
| **Key Functions** | convertFrameToPortraitRgba() |
| **Inputs** | CameraImage |
| **Outputs** | RGBA buffer |
| **Dependencies** | None |
| **Active** | ✅ Yes |

---

## 7. Test Files (test/)

### 7.1 Summary

| Category | Count | Status |
|----------|-------|--------|
| Currency Tests | 5 | ✅ |
| Depth Tests | 1 | ✅ |
| Emergency Tests | 3 | ✅ |
| Face Tests | 6 | ✅ |
| Navigation Tests | 3 | ✅ |
| OCR Tests | 1 | ✅ |
| Settings Tests | 1 | ✅ |
| Voice Tests | 5 | ✅ |
| General Tests | 3 | ✅ |
| **Total** | **31** | ✅ |

### 7.2 Test Coverage

| File | Purpose |
|------|---------|
| currency_command_parser_test.dart | Voice command parsing |
| currency_detector_test.dart | Currency YOLO inference |
| currency_recognition_screen_test.dart | Currency screen UI |
| currency_recognition_service_test.dart | Full recognition pipeline |
| currency_stability_test.dart | Stability filtering |
| depth_analysis_test.dart | Depth estimation |
| emergency_screen_hold_test.dart | SOS hold gesture |
| emergency_sos_button_test.dart | SOS button UI |
| face_announcement_manager_test.dart | Face announcements |
| face_embedding_alignment_test.dart | Face alignment |
| face_embedding_tensor_test.dart | ArcFace inference |
| face_recognition_test.dart | Face matching |
| face_registry_test.dart | Face registration |
| home_screen_test.dart | Home screen |
| initial_state_currency_voice_test.dart | Voice initial state |
| navigate_lifecycle_test.dart | Navigation lifecycle |
| navigation_voice_suppression_test.dart | Voice suppression |
| ocr_result_card_test.dart | OCR UI |
| press_and_hold_voice_region_test.dart | Voice region |
| scene_announcer_test.dart | Scene announcements |
| scrfd_detector_test.dart | SCRFD detection |
| settings_integration_test.dart | Settings integration |
| sos_gesture_test.dart | SOS gesture |
| sos_service_test.dart | SOS service |
| speech_queue_test.dart | Speech queue |
| target_navigation_service_test.dart | Target navigation |
| vibration_service_test.dart | Vibration service |
| voice_command_controller_test.dart | Voice controller |
| voice_search_overlay_test.dart | Voice overlay |
| voice_service_channel_test.dart | TTS channel |
| widget_test.dart | Basic widget test |

---

## 8. Generated Files (excluded from analysis)

| File | Purpose |
|------|---------|
| .dart_tool/flutter_build/ | Flutter build artifacts |
| build/ | Flutter build output |
| android/.gradle/ | Gradle cache |
| android/.kotlin/sessions/ | Kotlin session history |
| android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java | Flutter plugin registration |
| android/app/src/main/java/com/example/visionpath/MainActivity.kt | Android entry point |
| android/app/src/main/kotlin/com/example/visionpath/MainActivity.kt | Android entry point |

---

## 9. File Summary

| Category | Count | Status |
|----------|-------|--------|
| Entry Point | 2 | ✅ |
| Models | 19 | ✅ |
| Services | 41 | ✅ |
| Screens | 21 | ✅ |
| Widgets | 20 | ✅ |
| Utilities | 1 | ✅ |
| Tests | 31 | ✅ |
| Generated | 8+ | ✅ |

**Total Source Files:** 133+ (excluding generated)
