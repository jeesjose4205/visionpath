# VisionPath AI - Complete Repository Structure

## 1. Root Directory Structure

```
c:\Users\Jees\Desktop\visionpath\
├── .dart_tool/                    # Flutter build artifacts (auto-generated)
├── .git/                          # Git version control
├── .idea/                         # IntelliJ/Android Studio IDE configuration
├── android/                       # Android platform-specific code
├── ios/                           # iOS platform support (empty/unused)
├── web/                           # Web platform support (empty/unused)
├── linux/                         # Linux platform support (empty/unused)
├── macos/                         # macOS platform support (empty/unused)
├── windows/                       # Windows platform support (empty/unused)
├── assets/                        # Application assets (images, models, data)
├── lib/                           # Dart source code (main application code)
├── test/                          # Unit and widget tests
├── build/                         # Flutter build output (auto-generated)
├── third_party/                   # vendored third-party Flutter plugins
├── .flutter-plugins-dependencies  # Flutter plugin dependencies
├── .gitignore                     # Git ignore rules
├── .metadata                      # Flutter project metadata
├── analysis_options.yaml          # Dart analysis options
├── pubspec.yaml                   # Flutter/Dart dependencies
├── pubspec.lock                   # Locked dependency versions
├── README.md                      # Project README
├── flutter_01.log                 # Flutter execution log
├── calibration_image_sample_data_20x128x128x3_float32.npy  # Model calibration data
└── visionpath.iml                 # IntelliJ module file
```

## 2. Android Platform Structure

```
android/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/io/flutter/plugins/GeneratedPluginRegistrant.java
│   │   │   ├── java/com/example/visionpath/MainActivity.kt
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── kotlin/com/example/visionpath/MainActivity.kt
│   │   │   └── res/                 # Android resources
│   │   │       ├── drawable/        # Launch background images
│   │   │       ├── drawable-v21/
│   │   │       ├── mipmap-*/        # App launcher icons (various densities)
│   │   │       ├── values/          # Styles and themes
│   │   │       └── values-night/    # Dark theme variants
│   │   └── debug/
│   │       └── AndroidManifest.xml  # Debug configuration
│   └── build.gradle.kts             # Android build configuration (AGP 9.1)
├── .gradle/                         # Gradle cache (auto-generated)
└── .kotlin/sessions/                # Kotlin session history
```

## 3. Assets Structure

```
assets/
├── ml/                              # Machine learning model files
│   ├── arcface_w600k_mbf.tflite     # ArcFace face embedding model (512-d)
│   ├── scrfd_640.tflite             # SCRFD face detector (TensorFlow Lite)
│   ├── mobilefacenet.tflite         # MobileFaceNet embedding model
│   ├── currency_notes_yolo.tflite   # YOLO currency note detector
│   ├── currency_banknote.tflite     # Retired currency classifier
│   ├── currency_coin.tflite         # Retired currency classifier
│   └── currency_notes_yolo_labels.txt  # Currency class labels
├── models/
│   └── vosk-model-small-en-us-0.15.zip  # Offline speech recognition model
└── (various)                        # Currency recognition expects files dropped here
```

## 4. Source Code Structure (lib/)

```
lib/
├── main.dart                        # Application entry point
├── l10n/
│   └── app_localizations.dart       # Localization support
├── models/                          # Data models and DTOs
│   ├── app_settings.dart            # Settings enums and configuration
│   ├── currency_recognition.dart    # Currency recognition result models
│   ├── depth_map.dart               # Depth map data structures
│   ├── depth_result.dart            # Depth analysis results
│   ├── depth_scene.dart             # Depth scene classification
│   ├── detected_object.dart         # Object detection results
│   ├── emergency_contact.dart       # Emergency contact data
│   ├── face_detection.dart          # Face detection models
│   ├── familiar_face.dart           # Registered face embeddings
│   ├── live_assistant_state.dart    # Live assistant state
│   ├── look_and_detect.dart         # Look & Detect models
│   ├── navigation_decision.dart     # Navigation decision types
│   ├── object_position.dart         # Object position (LEFT/CENTER/RIGHT)
│   ├── ocr_result.dart              # OCR result data
│   ├── path_analysis.dart           # Path analysis results
│   ├── proximity_level.dart         # Proximity levels (NEAR/MEDIUM/FAR)
│   ├── rgb_frame.dart               # RGB frame data
│   ├── sos_session.dart             # SOS emergency session state
│   └── target_search.dart           # Target search models
├── services/                        # Business logic and AI services
│   ├── camera_service.dart          # Camera management
│   ├── currency_command_parser.dart # Currency voice commands
│   ├── currency_detector.dart       # Currency YOLO inference
│   ├── currency_recognition_service.dart  # Currency recognition
│   ├── currency_stability_verifier.dart  # Currency result filtering
│   ├── depth/
│   │   ├── depth_engine.dart        # Depth estimation interface
│   │   ├── depth_metric_calibration.dart  # Depth calibration
│   │   └── geometric_depth_engine.dart  # Geometric depth fallback
│   ├── depth_analysis_service.dart  # Depth analysis orchestration
│   ├── detection_coordinate_transformer.dart  # Coordinate mapping
│   ├── emergency_contact_service.dart  # Emergency contact storage
│   ├── face_announcement_manager.dart  # Face recognition announcements
│   ├── face_detection_service.dart  # ML Kit face detection wrapper
│   ├── face_embedding_service.dart  # ArcFace embeddings
│   ├── face_recognition_service.dart  # Face matching and embeddings
│   ├── face_registration_guide.dart  # Registration guidance
│   ├── familiar_face_repository.dart  # Face storage abstraction
│   ├── familiar_face_service.dart   # Face registration and lookup
│   ├── instruction_manager.dart     # Navigation instruction deduplication
│   ├── look_and_detect_engine.dart  # Look & Detect logic
│   ├── navigation_service.dart      # Navigation decision engine
│   ├── object_detection_service.dart  # YOLO object detection
│   ├── object_vocabulary.dart       # Object class names
│   ├── ocr_service.dart             # ML Kit OCR wrapper
│   ├── path_analysis_service.dart   # Path obstruction analysis
│   ├── position_detection_service.dart  # Object position detection
│   ├── scene_announcer.dart         # Multi-object scene descriptions
│   ├── scrfd_face_detector.dart     # SCRFD face detector
│   ├── settings_service.dart        # Settings persistence
│   ├── sos_platform.dart            # Platform integration for SOS
│   ├── sos_service.dart             # SOS emergency orchestration
│   ├── speech_capture_service.dart  # Voice command capture
│   ├── speech_queue.dart            # Speech queue management
│   ├── speech_service.dart          # Vosk offline speech recognition
│   ├── voice_service.dart           # TTS and speech orchestration
│   ├── target_navigation_service.dart  # Target tracking
│   ├── text_guidance_service.dart   # OCR guidance overlay
│   ├── vibration_service.dart       # Haptic feedback
│   ├── voice_command_controller.dart  # Press-and-hold voice assistant
│   ├── voice_input.dart             # Voice input abstraction
│   └── web_speech_engine.dart       # Web Speech API fallback
├── screens/                         # Application screens
│   ├── about_screen.dart
│   ├── accessibility_settings_screen.dart
│   ├── currency_recognition_screen.dart
│   ├── detection_settings_screen.dart
│   ├── emergency_screen.dart
│   ├── emergency_settings_screen.dart
│   ├── face_registration_screen.dart
│   ├── familiar_faces_screen.dart
│   ├── familiar_face_settings_screen.dart
│   ├── general_settings_screen.dart
│   ├── look_and_detect_screen.dart
│   ├── navigate_screen.dart         # Main navigation screen
│   ├── navigation_settings_screen.dart
│   ├── notifications_settings_screen.dart
│   ├── privacy_settings_screen.dart
│   ├── read_text_screen.dart
│   ├── read_text_settings_screen.dart
│   ├── registered_faces_screen.dart
│   ├── reset_settings_screen.dart
│   ├── settings_screen.dart
│   └── voice_settings_screen.dart
├── utils/                           # Utility functions
│   └── portrait_rgba.dart           # Camera frame preprocessing
└── widgets/                         # Reusable UI components
    ├── camera_preview_fit.dart
    ├── depth_debug_overlay.dart
    ├── detection_overlay.dart
    ├── emergency_contact_card.dart
    ├── emergency_location_card.dart
    ├── emergency_sos_button.dart
    ├── face_recognition_overlay.dart
    ├── listening_orb.dart
    ├── ocr_result_card.dart
    ├── press_and_hold_voice_region.dart
    ├── read_text_controls.dart
    ├── settings_button.dart
    ├── settings_scope.dart
    ├── settings_widgets.dart
    ├── sos_gesture.dart
    ├── sound_mode_button.dart
    ├── target_status_chip.dart
    ├── text_camera_preview.dart
    ├── text_guidance_status.dart
    └── voice_search_overlay.dart
```

## 5. Test Structure (test/)

```
test/
├── currency_command_parser_test.dart
├── currency_detector_test.dart
├── currency_recognition_screen_test.dart
├── currency_recognition_service_test.dart
├── currency_stability_test.dart
├── depth_analysis_test.dart
├── emergency_screen_hold_test.dart
├── emergency_sos_button_test.dart
├── face_announcement_manager_test.dart
├── face_embedding_alignment_test.dart
├── face_embedding_tensor_test.dart
├── face_recognition_test.dart
├── face_registry_test.dart
├── home_screen_test.dart
├── initial_state_currency_voice_test.dart
├── navigate_lifecycle_test.dart
├── navigation_voice_suppression_test.dart
├── ocr_result_card_test.dart
├── press_and_hold_voice_region_test.dart
├── scene_announcer_test.dart
├── scrfd_detector_test.dart
├── settings_integration_test.dart
├── sos_gesture_test.dart
├── sos_service_test.dart
├── speech_queue_test.dart
├── target_navigation_service_test.dart
├── vibration_service_test.dart
├── voice_command_controller_test.dart
├── voice_search_overlay_test.dart
├── voice_service_channel_test.dart
└── widget_test.dart
```

## 6. Third-Party Dependencies (third_party/)

```
third_party/
├── flutter_inappwebview_android/  # Vendored fix for AGP 9 compatibility
└── vosk_flutter/                  # Vendored Vosk Flutter plugin
```

## 7. Documentation Files

```
complete_project_analysis/         # This analysis output directory
├── project_identity_and_overview.md
├── complete_repository_structure.md (this file)
├── programming_languages_frameworks_dependencies.md
├── complete_feature_inventory.md
├── screens_navigation_and_ui.md
├── system_architecture_and_diagrams.md
├── algorithms_and_business_logic.md
├── ai_ml_models_and_inference.md
├── backend_api_and_integrations.md
├── database_storage_and_data_flow.md
├── device_permissions_and_platform_support.md
├── security_privacy_and_reliability.md
├── testing_and_quality_analysis.md
├── setup_build_and_deployment.md
├── performance_limitations_and_future_work.md
├── end_to_end_workflows.md
├── source_code_file_by_file_analysis.md
├── project_evidence_and_traceability.md
├── glossary_of_technical_terms.md
└── unresolved_questions_and_verification_checklist.md
```

## 8. Generated Files

```
.dart_tool/                         # Flutter build artifacts
build/                              # Flutter build output
android/.gradle/                    # Gradle cache
android/.kotlin/                    # Kotlin compilation data
android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
android/app/src/main/java/com/example/visionpath/MainActivity.kt
android/app/src/main/kotlin/com/example/visionpath/MainActivity.kt
android/app/build/                  # Android build output
android/app/src/main/java/com/example/visionpath/BuildConfig.java
```

## 9. Configuration Files

| File | Purpose |
|------|---------|
| `pubspec.yaml` | Dart/Flutter dependencies and assets |
| `pubspec.lock` | Locked dependency versions |
| `analysis_options.yaml` | Dart code analysis rules |
| `.gitignore` | Git ignore patterns |
| `.metadata` | Flutter project metadata |
| `android/app/build.gradle.kts` | Android build configuration |
| `android/app/src/main/AndroidManifest.xml` | Android app manifest |
| `lib/l10n/app_localizations.dart` | Localization configuration |

## 10. Key Directories Summary

| Directory | Content | Purpose |
|-----------|---------|---------|
| `lib/` | Dart source | Main application logic |
| `android/app/src/main/` | Android code | Platform-specific Android implementation |
| `assets/ml/` | TFLite models | On-device ML models |
| `assets/models/` | Vosk model | Offline speech recognition |
| `test/` | Test files | Unit and widget tests |
| `lib/services/` | Services | Business logic and AI inference |
| `lib/screens/` | Screens | UI screens |
| `lib/widgets/` | Widgets | Reusable UI components |
| `lib/models/` | Models | Data structures |
