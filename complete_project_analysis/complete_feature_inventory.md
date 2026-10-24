# VisionPath AI - Complete Feature Inventory

## 1. Feature Categories Overview

| Category | Features | Status |
|----------|----------|--------|
| Navigation & Object Detection | 3 features | Implemented |
| Face Recognition | 4 features | Implemented |
| Text Reading | 2 features | Implemented |
| Currency Recognition | 4 features | Implemented |
| Emergency | 2 features | Implemented |
| Voice Assistant | 2 features | Implemented |
| Settings | 15+ settings | Implemented |
| Accessibility | 6 settings | Implemented |

---

## 2. Navigation & Object Detection Features

### 2.1 Real-Time Object Detection

**Entry Point:** `NavigateScreen`

**Description:** Uses YOLO26n model via ultralytics_yolo plugin to detect and classify objects in real-time camera frames.

**Components:**
- `ObjectDetectionService` - YOLO26n model wrapper
- `DetectedObject` model - Detection results with position
- `PositionDetectionService` - LEFT/CENTER/RIGHT classification
- `DepthAnalysisService` - Proximity estimation
- `PathAnalysisService` - Path obstruction analysis
- `NavigationService` - Navigation decision engine
- `InstructionManager` - Voice instruction deduplication
- `SceneAnnouncer` - Multi-object scene descriptions

**Features:**
- Detects 80+ COCO classes (people, vehicles, furniture, etc.)
- Object position classification (LEFT, CENTER, RIGHT)
- Depth-based proximity estimation (NEAR, MEDIUM, FAR)
- Path analysis (CLEAR, OBSTACLE_LEFT, OBSTACLE_CENTER, OBSTACLE_RIGHT)
- Navigation decisions (FORWARD, LEFT, RIGHT, SLOW, STOP)
- Voice guidance with configurable frequency

**Status:** Implemented and tested

**Key Files:**
- `lib/services/object_detection_service.dart`
- `lib/services/position_detection_service.dart`
- `lib/services/depth_analysis_service.dart`
- `lib/services/path_analysis_service.dart`
- `lib/services/navigation_service.dart`
- `lib/services/instruction_manager.dart`
- `lib/services/scene_announcer.dart`

### 2.2 Path Analysis

**Entry Point:** `PathAnalysisService`

**Description:** Analyzes detected objects to determine if the walking path is obstructed.

**Features:**
- Central walking region detection (28%-72% of frame width)
- Object proximity classification based on depth
- Path obstruction classification
- Left/right margin calculation

**Status:** Implemented

**Key Files:**
- `lib/services/path_analysis_service.dart`
- `lib/models/path_analysis.dart`

### 2.3 Depth Estimation

**Entry Point:** `DepthAnalysisService`

**Description:** Estimates relative and calibrated absolute depth for detected objects.

**Features:**
- Real depth estimation via depth engine
- Geometric fallback when depth unavailable
- Relative depth mapping (0.0-1.0)
- Calibrated absolute distance estimation
- Temporal smoothing

**Status:** Implemented

**Key Files:**
- `lib/services/depth_analysis_service.dart`
- `lib/services/depth/depth_engine.dart`
- `lib/services/depth/geometric_depth_engine.dart`
- `lib/services/depth/depth_metric_calibration.dart`

---

## 3. Face Recognition Features

### 3.1 Familiar Face Registration

**Entry Point:** `FaceRegistrationScreen`

**Description:** Registers new people by capturing multiple face samples with voice guidance.

**Features:**
- Voice-guided positioning (move closer/farther/turn)
- 12-sample capture sequence
- Front/left/right pose alternation
- Automatic sample quality validation
- Geometric or ArcFace embedding generation
- Local storage via SharedPreferences

**Status:** Implemented and tested

**Key Files:**
- `lib/services/face_registration_guide.dart`
- `lib/services/familiar_face_service.dart`
- `lib/services/familiar_face_repository.dart`
- `lib/screens/face_registration_screen.dart`
- `lib/services/face_embedding_service.dart`

### 3.2 Face Detection

**Entry Point:** `FaceDetectionService`

**Description:** Detects faces using ML Kit with high accuracy mode.

**Features:**
- ML Kit Face Detector
- Accurate mode with landmarks and contours
- 5 landmarks (eyes, nose, mouth corners)
- Dense face contours for shape features
- Normalized coordinate output

**Status:** Implemented

**Key Files:**
- `lib/services/face_detection_service.dart`
- `lib/models/face_detection.dart`

### 3.3 Face Recognition (Familiar Face Matching)

**Entry Point:** `FamiliarFacesScreen`

**Description:** Recognizes registered familiar faces from camera frames.

**Features:**
- SCRFD face detection (TensorFlow Lite)
- ArcFace embedding extraction (512-d)
- Cosine similarity matching
- Temporal confirmation (3-frame average)
- Voice announcements with name and position
- Unknown face option (opt-in)

**Status:** Implemented and tested

**Key Files:**
- `lib/services/scrfd_face_detector.dart`
- `lib/services/face_embedding_service.dart`
- `lib/services/face_recognition_service.dart`
- `lib/services/face_announcement_manager.dart`
- `lib/screens/familiar_faces_screen.dart`
- `lib/models/familiar_face.dart`

### 3.4 Face Registration with MobileFaceNet

**Entry Point:** Alternative embedding path

**Description:** Uses MobileFaceNet as an alternative embedding model.

**Features:**
- Alternative to ArcFace (30-d geometric embeddings)
- Configurable per registration
- Local model storage

**Status:** Implemented

**Key Files:**
- `lib/models/familiar_face.dart`
- `lib/services/familiar_face_service.dart`

---

## 4. Text Reading Features

### 4.1 Real-Time Text Reading (OCR)

**Entry Point:** `ReadTextScreen`

**Description:** Reads text from camera frames using ML Kit OCR with voice guidance.

**Features:**
- ML Kit Text Recognition
- Latin script support
- Real-time text box detection
- Voice-guided positioning
- Auto-capture with voice command
- Manual capture button
- Sequential text reading with TTS

**Status:** Implemented and tested

**Key Files:**
- `lib/services/ocr_service.dart`
- `lib/services/text_guidance_service.dart`
- `lib/screens/read_text_screen.dart`

### 4.2 Text Guidance Overlay

**Entry Point:** `TextGuidanceService`

**Description:** Provides voice guidance for positioning camera over text.

**Features:**
- Voice instructions for text positioning
- Visual feedback overlay
- Automatic capture readiness
- Text region bounding boxes

**Status:** Implemented

**Key Files:**
- `lib/services/text_guidance_service.dart`
- `lib/widgets/text_guidance_status.dart`

---

## 5. Currency Recognition Features

### 5.1 Currency Note Recognition

**Entry Point:** `CurrencyRecognitionScreen`

**Description:** Identifies currency notes using YOLO model.

**Features:**
- YOLOv10n currency detector
- Input: [1,640,640,3] float32 RGB normalized
- Output: [1,300,6] xyxy+conf+cls
- Optional label file support

**Status:** Implemented

**Key Files:**
- `lib/services/currency_detector.dart`
- `lib/services/currency_recognition_service.dart`
- `lib/services/currency_stability_verifier.dart`
- `lib/screens/currency_recognition_screen.dart`

### 5.2 Voice Command Currency Recognition

**Entry Point:** `CurrencyCommandParser`

**Description:** Voice command parsing for currency-related actions.

**Features:**
- Voice command parsing
- Currency note/coin detection triggers
- Automatic screen navigation

**Status:** Implemented

**Key Files:**
- `lib/services/currency_command_parser.dart`

### 5.3 Currency Stability Verification

**Entry Point:** `CurrencyStabilityVerifier`

**Description:** Filters currency detection results to avoid flickering.

**Features:**
- Temporal filtering
- Stability threshold
- Result deduplication

**Status:** Implemented

**Key Files:**
- `lib/services/currency_stability_verifier.dart`

### 5.4 Currency Recognition Results

**Entry Point:** `CurrencyRecognitionResult`

**Description:** Currency recognition outcome classification.

**Features:**
- Recognized/uncertain/modelUnavailable states
- Confidence scores
- Failure reason reporting

**Status:** Implemented

**Key Files:**
- `lib/models/currency_recognition.dart`

---

## 6. Emergency Features

### 6.1 SOS Emergency System

**Entry Point:** `EmergencyScreen`

**Description:** Press-and-hold SOS with countdown and emergency actions.

**Features:**
- Press-and-hold activation (configurable duration)
- Countdown with voice cues
- Alert sound
- Call primary contact
- SMS with location to primary contact
- Location fix attempt (GPS/network)
- Notification center integration
- App-wide persistence (survives navigation)

**Status:** Implemented and tested

**Key Files:**
- `lib/services/sos_service.dart`
- `lib/services/sos_platform.dart`
- `lib/services/sos_gesture.dart`
- `lib/screens/emergency_screen.dart`
- `lib/models/sos_session.dart`

### 6.2 Emergency Contact Management

**Entry Point:** `EmergencySettingsScreen`

**Description:** Add, edit, and manage emergency contacts.

**Features:**
- Add up to 5 emergency contacts
- Edit contact name and phone
- Delete contacts
- Duplicate prevention
- Validation

**Status:** Implemented

**Key Files:**
- `lib/services/emergency_contact_service.dart`
- `lib/models/emergency_contact.dart`

---

## 7. Voice Assistant Features

### 7.1 Press-and-Hold Voice Assistant

**Entry Point:** `VoiceCommandController`

**Description:** Hold screen to speak questions, voice assistant responds.

**Features:**
- Press-and-hold (350ms threshold)
- Vosk offline speech recognition
- Partial transcription while speaking
- Final transcription on release
- Environment speech filtering
- Voice feedback on error

**Status:** Implemented

**Key Files:**
- `lib/services/voice_command_controller.dart`
- `lib/services/speech_service.dart`
- `lib/services/speech_capture_service.dart`

### 7.2 Voice Input Abstraction

**Entry Point:** `VoiceInput` interface

**Description:** Unified interface for speech recognition engines.

**Features:**
- Google Speech (Web Speech API fallback)
- Vosk (offline)
- Runtime switching
- Error handling

**Status:** Implemented

**Key Files:**
- `lib/services/voice_input.dart`
- `lib/services/web_speech_engine.dart`

---

## 8. Settings Features

### 8.1 Voice & Audio Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Voice Guidance | SettingsScreen | ON | Enable/disable navigation voice guidance |
| Global Voice Muted | SettingsScreen | OFF | Mute all speech output |
| Alert Mode | SettingsScreen | Sound | Sound/Vibration/Mute mode |
| Speech Rate | SettingsScreen | Normal | TTS rate (slow/normal/fast) |
| Voice Volume | SettingsScreen | 1.0 | TTS volume (0.0-1.0) |
| Voice Language | SettingsScreen | System Default | TTS language (US/UK/System) |
| Repeat Instruction | SettingsScreen | ON | Repeat last instruction |
| Announcement Cooldown | SettingsScreen | 3s | Minimum time between instructions |

### 8.2 Navigation Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Obstacle Sensitivity | SettingsScreen | Medium | Depth estimation sensitivity |
| Guidance Mode | SettingsScreen | Balanced | Navigation frequency (balanced/more frequent/minimal) |
| Close Obstacle Warnings | SettingsScreen | ON | Enable close obstacle alerts |
| Depth Analysis | SettingsScreen | ON | Enable depth estimation |
| Depth Debug Overlay | SettingsScreen | OFF | Visual depth map debug |
| Metric Distance | SettingsScreen | ON | Use metric system |

### 8.3 Detection Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Detection Voice | SettingsScreen | ON | Voice announcements |
| People Announcements | SettingsScreen | ON | Announce people detected |
| Vehicle Announcements | SettingsScreen | ON | Announce vehicles |
| Animal Announcements | SettingsScreen | ON | Announce animals |
| Furniture Announcements | SettingsScreen | ON | Announce furniture |
| Obstacle Announcements | SettingsScreen | ON | Announce obstacles |
| Detection Sensitivity | SettingsScreen | Balanced | YOLO confidence threshold |

### 8.4 Read Text Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Auto Read | SettingsScreen | OFF | Auto-capture text |
| Text Position Guidance | SettingsScreen | ON | Positioning voice guidance |
| OCR Language | SettingsScreen | Latin | Recognition script |
| Reading Speed | SettingsScreen | Normal | TTS speed for reading |

### 8.5 Familiar Face Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Faces Enabled | SettingsScreen | ON | Enable face recognition |
| Face Voice | SettingsScreen | ON | Voice announcements |
| Unknown Announcements | SettingsScreen | OFF | Announce unknown faces |
| Face Sensitivity | SettingsScreen | Balanced | Matching threshold |
| Face Cooldown | SettingsScreen | 3s | Re-announcement delay |

### 8.6 Emergency Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| SOS Hold Duration | SettingsScreen | 5s | Hold time for SOS activation |
| SOS Alert Sound | SettingsScreen | ON | Enable alert tone |
| SOS Alert Tone | SettingsScreen | Emergency | Tone selection |

### 8.7 Accessibility Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Large Text | SettingsScreen | OFF | Increase text size |
| High Contrast | SettingsScreen | OFF | High contrast theme |
| Large Buttons | SettingsScreen | OFF | Larger UI buttons |
| Haptic Feedback | SettingsScreen | ON | Vibration feedback |
| Voice First Mode | SettingsScreen | OFF | Voice-only navigation |
| Reduce Animations | SettingsScreen | OFF | Disable animations |

### 8.8 General Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| App Language | SettingsScreen | System Default | UI language |
| Theme | SettingsScreen | System | Light/Dark/System theme |
| Notifications | SettingsScreen | ON | Enable notifications |

### 8.9 Privacy Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Clear History | SettingsScreen | N/A | Clear app history |

### 8.10 Reset Settings

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Reset To Defaults | SettingsScreen | Button | Reset all settings |

---

## 9. Accessibility Features

### 9.1 Voice-First Design

| Feature | Description |
|---------|-------------|
| Voice Guidance | All navigation uses voice commands |
| Voice Assistant | Press-and-hold for questions |
| Screen Reader Support | Full TalkBack compatibility |

### 9.2 Visual Accessibility

| Feature | Description |
|---------|-------------|
| Large Text | Scalable text sizes |
| High Contrast | Enhanced color contrast |
| Large Buttons | Larger touch targets |
| Reduce Animations | Reduced motion support |

### 9.3 Audio Accessibility

| Feature | Description |
|---------|-------------|
| Volume Control | Per-user volume preferences |
| Speech Rate | Adjustable TTS speed |
| Multiple Languages | US/UK English support |

### 9.4 Haptic Accessibility

| Feature | Description |
|---------|-------------|
| Haptic Feedback | Vibration for interactions |
| SOS Vibration | Continuous vibration during SOS |

---

## 10. Utility Features

### 10.1 Speech Queue

**Entry Point:** `SpeechQueue`

**Description:** Sequential, duplicate-free speech queue.

**Features:**
- Strict one-at-a-time speaking
- Duplicate detection
- Automatic ordering

**Status:** Implemented

**Key Files:**
- `lib/services/speech_queue.dart`

### 10.2 Settings Service

**Entry Point:** `SettingsService`

**Description:** Centralized settings persistence.

**Features:**
- SharedPreferences-based persistence
- Change notification (ChangeNotifier)
- settings_service.dart

**Status:** Implemented

**Key Files:**
- `lib/services/settings_service.dart`
- `lib/models/app_settings.dart`

### 10.3 Vibration Service

**Entry Point:** `VibrationService`

**Description:** Haptic feedback management.

**Features:**
- Native vibration plugin
- Flutter HapticFeedback fallback
- Pattern-based pulses
- Accessibility-aware

**Status:** Implemented

**Key Files:**
- `lib/services/vibration_service.dart`

### 10.4 Camera Service

**Entry Point:** `CameraService`

**Description:** Shared camera controller.

**Features:**
- Single camera instance
- Front/rear lens switching
- Camera lifecycle management
- Camera preview widget

**Status:** Implemented

**Key Files:**
- `lib/services/camera_service.dart`

---

## 11. Unimplemented/Planned Features

| Feature | Status | Notes |
|---------|--------|-------|
| iOS Support | Not implemented | iOS platform directories empty |
| Web Support | Not implemented | Web platform directory empty |
| Cloud Sync | Not implemented | No backend infrastructure |
| Social Sharing | Not implemented | No social media integration |
| Wearable Support | Not implemented | No smart glasses integration |

---

## 12. Feature Status Summary

| Feature Category | Status | Implementation |
|-----------------|--------|----------------|
| Navigation & Object Detection | Implemented | 100% |
| Face Recognition | Implemented | 100% |
| Text Reading | Implemented | 100% |
| Currency Recognition | Implemented | 100% |
| Emergency | Implemented | 100% |
| Voice Assistant | Implemented | 100% |
| Settings | Implemented | 100% |
| Accessibility | Implemented | 100% |
| Tests | Implemented | 31 test files |
