# VisionPath AI - Screens, Navigation, and UI Structure

## 1. Application Screens

### 1.1 Main Navigation Screen

**File:** `lib/screens/navigate_screen.dart`

**Purpose:** Primary navigation and object detection interface.

**Key Features:**
- Live camera preview with object detection overlay
- Navigation guidance voice announcements
- Carousels: Settings, Currency Recognition, Read Text, Familiar Faces
- Press-and-hold voice assistant
- Emergency SOS button
- Sound mode toggle (speaker/vibrate/mute)
- Start/Stop navigation control

**State Machine:**
- Idle → Starting → Camera Ready → Analyzing → Clear/Obstacle/Danger/Stopped

**Navigation Destinations:**
- Settings (`SettingsScreen`)
- Currency Recognition (`CurrencyRecognitionScreen`)
- Read Text (`ReadTextScreen`)
- Familiar Faces (`FamiliarFacesScreen`)

### 1.2 Familiar Faces Screen

**File:** `lib/screens/familiar_faces_screen.dart`

**Purpose:** Face recognition hub for registering and recognizing familiar people.

**Key Features:**
- Recognize registered faces via camera
- Voice announcement of recognized faces
- Navigation to Registration screen
- Settings configuration
- Unknown face announcements (opt-in)

**Navigation Destinations:**
- Face Registration (`FaceRegistrationScreen`)
- Settings (`SettingsScreen`)

### 1.3 Face Registration Screen

**File:** `lib/services/face_registration_screen.dart`

**Purpose:** Register new familiar people via multi-sample capture.

**Key Features:**
- Voice-guided positioning
- 12-sample capture sequence (front/left/right poses)
- Face quality validation
- Automatic pose guidance
- Geometric or ArcFace embedding generation

**Navigation Destinations:**
- Familiar Faces (back button)

### 1.4 Read Text Screen

**File:** `lib/screens/read_text_screen.dart`

**Purpose:** Text reading assistant with OCR and voice guidance.

**Key Features:**
- Live OCR on camera frames
- Voice-guided positioning
- Auto-capture with voice command
- Manual capture button
- Sequential text reading with TTS
- Text region visualization

**Navigation Destinations:**
- Settings (`SettingsScreen`)
- Currency Recognition (`CurrencyRecognitionScreen`)

### 1.5 Currency Recognition Screen

**File:** `lib/screens/currency_recognition_screen.dart`

**Purpose:** Currency note and coin identification.

**Key Features:**
- YOLO-based currency detection
- Real-time note detection
- Optional coin detection
- Detection confidence display
- Voice feedback

**Navigation Destinations:**
- Settings (`SettingsScreen`)
- Navigate (back button)

### 1.6 Emergency Screen

**File:** `lib/screens/emergency_screen.dart`

**Purpose:** SOS emergency assistance with call and SMS.

**Key Features:**
- Press-and-hold activation (5-second default)
- Countdown with voice cues
- Alert sound
- Call primary contact
- SMS with location
- Notification integration
- Session persistence across navigation

**Navigation Destinations:**
- Back to previous screen (SOS persists)

### 1.7 Settings Screen

**File:** `lib/screens/settings_screen.dart`

**Purpose:** Main settings dashboard.

**Key Features:**
- Grouped settings by category
- Live status indicators
- Chevron navigation to sub-screens
- Sound mode toggle (top-right)

**Navigation Destinations:**
- General Settings (`GeneralSettingsScreen`)
- Voice Settings (`VoiceSettingsScreen`)
- Navigation Settings (`NavigationSettingsScreen`)
- Detection Settings (`DetectionSettingsScreen`)
- Read Text Settings (`ReadTextSettingsScreen`)
- Familiar Face Settings (`FamiliarFaceSettingsScreen`)
- Emergency Settings (`EmergencySettingsScreen`)
- Accessibility Settings (`AccessibilitySettingsScreen`)
- Privacy Settings (`PrivacySettingsScreen`)
- Notifications Settings (`NotificationsSettingsScreen`)
- About (`AboutScreen`)
- Reset Settings (`ResetSettingsScreen`)

### 1.8 Sub-Screens (Settings)

| Screen | File | Purpose |
|--------|------|---------|
| GeneralSettingsScreen | `lib/screens/general_settings_screen.dart` | App language, theme |
| VoiceSettingsScreen | `lib/screens/voice_settings_screen.dart` | Voice & audio settings |
| NavigationSettingsScreen | `lib/screens/navigation_settings_screen.dart` | Navigation preferences |
| DetectionSettingsScreen | `lib/screens/detection_settings_screen.dart` | Object detection settings |
| ReadTextSettingsScreen | `lib/screens/read_text_settings_screen.dart` | OCR settings |
| FamiliarFaceSettingsScreen | `lib/screens/familiar_face_settings_screen.dart` | Face recognition settings |
| EmergencySettingsScreen | `lib/screens/emergency_settings_screen.dart` | SOS settings |
| AccessibilitySettingsScreen | `lib/screens/accessibility_settings_screen.dart` | Accessibility settings |
| PrivacySettingsScreen | `lib/screens/privacy_settings_screen.dart` | Privacy controls |
| NotificationsSettingsScreen | `lib/screens/notifications_settings_screen.dart` | Notification settings |
| AboutScreen | `lib/screens/about_screen.dart` | App information |
| ResetSettingsScreen | `lib/screens/reset_settings_screen.dart` | Reset to defaults |

### 1.9 Registered Faces Screen

**File:** `lib/screens/registered_faces_screen.dart`

**Purpose:** View and manage registered familiar faces.

**Key Features:**
- List of registered people
- Edit name and relationship
- Delete contacts
- Face thumbnail preview

**Navigation Destinations:**
- Familiar Faces (back button)

---

## 2. Navigation Architecture

### 2.1 Navigation Service

**File:** `lib/services/navigation_service.dart`

**Purpose:** App-wide navigation service singleton.

**Features:**
- Shared instance (SOS needs app-wide access)
- Navigation decision engine
- Instruction generation
- Voice announcement management

### 2.2 Route Observer

**File:** `_AppRoot` (main.dart)

**Purpose:** SOS route tracking.

**Features:**
- Track SOS screen presence
- Prevent duplicate SOS instances
- Route transitions

### 2.3 Navigation Destinations

| Source | Destination | Purpose |
|--------|-------------|---------|
| NavigateScreen | SettingsScreen | Configuration |
| NavigateScreen | CurrencyRecognitionScreen | Currency detection |
| NavigateScreen | ReadTextScreen | Text reading |
| NavigateScreen | FamiliarFacesScreen | Face recognition |
| NavigateScreen | EmergencyScreen | SOS |
| NavigateScreen (settings) | All sub-settings | Detailed settings |
| FamiliarFacesScreen | FaceRegistrationScreen | Register new face |
| FamiliarFacesScreen | RegisteredFacesScreen | Manage registered faces |
| RegisteredFacesScreen | FaceRegistrationScreen | Register new face |
| Any Screen | EmergencyScreen | SOS activation |

---

## 3. UI Components (Widgets)

### 3.1 Camera Preview Widgets

| Widget | File | Purpose |
|--------|------|---------|
| CameraPreviewFit | `lib/widgets/camera_preview_fit.dart` | Aspect-ratio camera preview |
| TextCameraPreview | `lib/widgets/text_camera_preview.dart` | OCR camera preview |
| VoiceSearchOverlay | `lib/widgets/voice_search_overlay.dart` | Voice command overlay |
| PressAndHoldVoiceRegion | `lib/widgets/press_and_hold_voice_region.dart` | Voice assistant trigger |

### 3.2 Detection Overlays

| Widget | File | Purpose |
|--------|------|---------|
| DetectionOverlay | `lib/widgets/detection_overlay.dart` | YOLO detection boxes |
| FaceRecognitionOverlay | `lib/widgets/face_recognition_overlay.dart` | Face detection + name labels |
| TargetStatusChip | `lib/widgets/target_status_chip.dart` | Target tracking status |
| DepthDebugOverlay | `lib/widgets/depth_debug_overlay.dart` | Depth map visualization |

### 3.3 Text Reading Widgets

| Widget | File | Purpose |
|--------|------|---------|
| ReadTextControls | `lib/widgets/read_text_controls.dart` | OCR controls |
| OCRResultCard | `lib/widgets/ocr_result_card.dart` | OCR result display |
| TextGuidanceStatus | `lib/widgets/text_guidance_status.dart` | Positioning guidance |

### 3.4 Emergency Widgets

| Widget | File | Purpose |
|--------|------|---------|
| EmergencySOSButton | `lib/widgets/emergency_sos_button.dart` | SOS activation button |
| SosGesture | `lib/widgets/sos_gesture.dart` | Press-and-hold SOS handler |
| EmergencyContactCard | `lib/widgets/emergency_contact_card.dart` | Contact display |
| EmergencyLocationCard | `lib/widgets/emergency_location_card.dart` | Location display |

### 3.5 Settings Widgets

| Widget | File | Purpose |
|--------|------|---------|
| SettingsButton | `lib/widgets/settings_button.dart` | Settings navigation |
| SettingsScope | `lib/widgets/settings_scope.dart` | Settings theme wrapper |
| SettingsWidgets | `lib/widgets/settings_widgets.dart` | Shared settings UI |
| SoundModeButton | `lib/widgets/sound_mode_button.dart` | Voice/vibrate/mute toggle |

### 3.6 Utility Widgets

| Widget | File | Purpose |
|--------|------|---------|
| ListeningOrb | `lib/widgets/listening_orb.dart` | Listening indicator |
| OCRResultCard | `lib/widgets/ocr_result_card.dart` | OCR results |

---

## 4. UI Themes and Styling

### 4.1 Theme Configuration

**File:** `lib/services/settings_service.dart`

| Theme | Description |
|-------|-------------|
| System | Follow system theme |
| Light | Always light mode |
| Dark | Always dark mode |

### 4.2 High Contrast Mode

**Feature:** Enhanced color contrast for low vision users.

**Implementation:** Dynamic theme generation.

### 4.3 Text Scaling

**Feature:** Large text support (standard/large/extra large).

**Implementation:** MediaQuery text scale factor.

### 4.4 Button Scaling

**Feature:** Large buttons for motor accessibility.

**Implementation:** ButtonTheme scaling.

---

## 5. Screen Lifecycle

### 5.1 Navigation Screen Lifecycle

1. **Build** - Initialize services, prepare camera
2. **Start Navigation** - Camera preview + inference loop
3. **Stop Navigation** - Clean up camera, stop inference
4. **Dispose** - Release resources

### 5.2 Face Recognition Lifecycle

1. **Build** - Load face embeddings
2. **Recognition** - Start camera, run recognition loop
3. **Stop** - Stop recognition, keep camera live
4. **Dispose** - Release resources

### 5.3 Settings Screen Lifecycle

1. **Build** - Load settings from SharedPreferences
2. **Listen** - Subscribe to settings changes
3. **Update** - UI updates on setting changes
4. **Dispose** - Unsubscribe from settings

---

## 6. Accessibility Features

### 6.1 Screen Reader Support

- Full TalkBack compatibility
- Proper semantic labels
- Focus order management
- Live region announcements

### 6.2 Voice-First Navigation

- No screen requires visual inspection
- All interactions可通过语音完成
- Visual elements have audio descriptions

### 6.3 Motor Accessibility

- Large touch targets
- Press-and-hold alternatives
- Keyboard navigation support

---

## 7. Navigation Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        App Start                            │
│                         main.dart                           │
└─────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────┐
│                     VisionPathApp                           │
│              MultiProvider + _AppRoot                       │
└─────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      NavigateScreen                         │
│              Main entry point after launch                  │
└─────────────────────────────────────────────────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
┌────────────────┐         ┌──────────────────────┐     ┌─────────────────┐
│ Settings       │         │ Currency Recognition │     │ Read Text       │
│ Screen         │         │ Screen               │     │ Screen          │
└────────────────┘         └──────────────────────┘     └─────────────────┘
         │                            │                            │
         │                            │                            │
         ▼                            ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Familiar Faces Screen                    │
│                    (Face Recognition)                       │
└─────────────────────────────────────────────────────────────┘
                                      │
                   ┌──────────────────┼──────────────────┐
                   │                  │                  │
                   ▼                  ▼                  ▼
         ┌────────────────┐  ┌─────────────────┐ ┌────────────────┐
         │ Register Face  │  │ Registered      │ │ Emergency      │
         │ Screen         │  │ Faces Screen    │ │ Screen         │
         └────────────────┘  └─────────────────┘ └────────────────┘
                                      │                  │
                                      ▼                  ▼
                            ┌─────────────────┐  ┌──────────────┐
                            │ All Settings    │  │ All Settings │
                            └─────────────────┘  └──────────────┘
```

---

## 8. Screen Entry Points

| Screen | Entry Method | Purpose |
|--------|--------------|---------|
| NavigateScreen | App launch | Main navigation interface |
| FamiliarFacesScreen | NavigateScreen carousel | Face recognition hub |
| FaceRegistrationScreen | FamiliarFacesScreen | Register new face |
| RegisteredFacesScreen | FamiliarFacesScreen | Manage registered faces |
| ReadTextScreen | NavigateScreen carousel | Text reading |
| CurrencyRecognitionScreen | NavigateScreen carousel | Currency detection |
| EmergencyScreen | NavigateScreen button | SOS emergency |
| SettingsScreen | NavigateScreen button | Main settings |
| Sub-Settings | SettingsScreen | Detailed settings |

---

## 9. State Management

### 9.1 Provider Hierarchy

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider<CameraService>.value(value: CameraService()),
    ChangeNotifierProvider<ObjectDetectionService>.value(...),
    Provider<PositionDetectionService>.value(...),
    Provider<DepthAnalysisService>.value(...),
    Provider<PathAnalysisService>.value(...),
    ChangeNotifierProvider<NavigationService>.value(...),
    ChangeNotifierProvider<FamiliarFaceService>(...),
    ChangeNotifierProvider<SettingsService>.value(...),
    ChangeNotifierProvider<SosService>.value(...),
  ],
  child: _AppRoot(),
)
```

### 9.2 Change Notifiers

| Service | Purpose |
|---------|---------|
| CameraService | Camera state |
| ObjectDetectionService | Detection results |
| NavigationService | Navigation decisions |
| FamiliarFaceService | Registered faces |
| SettingsService | Settings persistence |
| SosService | Emergency state |

---

## 10. UI Patterns

### 10.1 Carousel Navigation

**NavigateScreen uses a carousel** for quick access to other screens:
- Settings
- Currency Recognition
- Read Text
- Familiar Faces

### 10.2 Title Card Pattern

**NavigateScreen and FamiliarFacesScreen** use title cards:
- Covers camera preview when idle
- Slides away when user presses start
- Returns on stop

### 10.3 Press-and-Hold Pattern

**Emergency SOS and Voice Assistant** use press-and-hold:
- 5-second countdown for SOS
- 350ms threshold for voice assistant
- Countdown feedback

---

## 11. Accessibility UI Features

| Feature | Description |
|---------|-------------|
| Text Size Scaling | User-configurable text scale |
| High Contrast | Enhanced color contrast |
| Large Buttons | Larger touch targets |
| Voice Feedback | All actions have audio feedback |
| Haptic Feedback | Vibration for interactions |
