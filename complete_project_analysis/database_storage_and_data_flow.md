# VisionPath AI - Database, Storage, and Data Flow

## 1. Storage Architecture Overview

VisionPath AI uses **SharedPreferences** as its sole persistent storage mechanism. This is a simple key-value store provided by Flutter for lightweight data persistence.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Storage Architecture                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         SHARED PREFERENCES                             │   │
│  │                        (Persistent Storage)                            │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                        KEYS                                    │   │   │
│  │  ├────────────────────────────────────────────────────────────────┤   │   │
│  │  │  setting.*              (Settings)                             │   │   │
│  │  │  emergency_contacts     (Emergency Contacts)                   │   │   │
│  │  │  familiar_faces         (Registered Faces)                     │   │   │
│  │  │  familiar_faces_v2      (V2 format)                            │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                        VALUES                                  │   │   │
│  │  ├────────────────────────────────────────────────────────────────┤   │   │
│  │  │  bool, int, double, String (Settings)                         │   │   │
│  │  │  List<String> (JSON contacts)                                 │   │   │
│  │  │  List<String> (JSON faces)                                    │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         IN-MEMORY STORAGE                              │   │
│  │                     (Runtime-only, volatile)                          │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    SETTINGS CACHE                              │   │   │
│  │  │  SettingsService.instance                                      │   │   │
│  │  │  - Voice guidance enabled                                     │   │   │
│  │  │  - Speech rate                                                │   │   │
│  │  │  - Volume, language, etc.                                     │   │   │
│  │  │  (Loaded from SharedPreferences on startup)                   │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                   EMERGENCY CONTACTS                           │   │   │
│  │  │  EmergencyContactService.instance                             │   │   │
│  │  │  - List of contacts (name, phone)                             │   │   │
│  │  │  (Loaded from SharedPreferences on startup)                   │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    FAMILIAR FACES                              │   │   │
│  │  │  FamiliarFaceService                                          │   │   │
│  │  │  - Registered people (name, embedding, relationship)          │   │   │
│  │  │  - 512-d embeddings (ArcFace)                                 │   │   │
│  │  │  - 30-d embeddings (geometric)                                │   │   │
│  │  │  (Loaded from SharedPreferences on startup)                   │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      TEMPORARY STORAGE                                 │   │
│  │                   (Frame-by-frame, volatile)                          │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    CAMERA FRAMES                               │   │   │
│  │  │  CameraImage / RGBA buffer                                    │   │   │
│  │  │  - YUV format (from camera)                                   │   │   │
│  │  │  - RGBA format (after conversion)                             │   │   │
│  │  │  - 5 FPS sampling                                             │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    DETECTION RESULTS                          │   │   │
│  │  │  DetectedObject[]                                             │   │   │
│  │  │  - Bounding boxes                                             │   │   │
│  │  │  - Classes, confidence                                        │   │   │
│  │  │  - Position, proximity                                        │   │   │
│  │  │  - Cleared each frame                                         │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. SharedPreferences Keys

### 2.1 Settings Keys

```dart
// SettingsService._k*
static const String _kVoiceGuidance = 'setting.voiceGuidance';
static const String _kGlobalVoiceMuted = 'setting.globalVoiceMuted';
static const String _kAlertMode = 'setting.alertMode';
static const String _kSpeechRate = 'setting.speechRate';
static const String _kVoiceVolume = 'setting.voiceVolume';
static const String _kVoiceLanguage = 'setting.voiceLanguage';
static const String _kRepeatInstruction = 'setting.repeatInstruction';
static const String _kAnnouncementCooldown = 'setting.announcementCooldown';
static const String _kLargeText = 'setting.largeText';
static const String _kHighContrast = 'setting.highContrast';
static const String _kLargeButtons = 'setting.largeButtons';
static const String _kHapticFeedback = 'setting.hapticFeedback';
static const String _kVoiceFirstMode = 'setting.voiceFirstMode';
static const String _kReduceAnimations = 'setting.reduceAnimations';
static const String _kNavVoice = 'setting.navVoice';
static const String _kObstacleSensitivity = 'setting.obstacleSensitivity';
static const String _kGuidanceMode = 'setting.guidanceMode';
static const String _kCloseObstacleWarnings = 'setting.closeObstacleWarnings';
static const String _kDepthAnalysis = 'setting.depthAnalysis';
static const String _kDepthDebugOverlay = 'setting.depthDebugOverlay';
static const String _kMetricDistance = 'setting.metricDistance';
static const String _kCameraHeight = 'setting.cameraHeight';
static const String _kCameraPitch = 'setting.cameraPitch';
static const String _kDetectionVoice = 'setting.detectionVoice';
static const String _kPeopleAnns = 'setting.peopleAnns';
static const String _kVehicleAnns = 'setting.vehicleAnns';
static const String _kAnimalAnns = 'setting.animalAnns';
static const String _kFurnitureAnns = 'setting.furnitureAnns';
static const String _kObstacleAnns = 'setting.obstacleAnns';
static const String _kDetectionSensitivity = 'setting.detectionSensitivity';
static const String _kReadAutoRead = 'setting.readAutoRead';
static const String _kTextPosGuidance = 'setting.textPosGuidance';
static const String _kOcrLanguage = 'setting.ocrLanguage';
static const String _kReadingSpeed = 'setting.readingSpeed';
static const String _kFacesEnabled = 'setting.facesEnabled';
static const String _kFaceVoice = 'setting.faceVoice';
static const String _kUnknownAnns = 'setting.unknownAnns';
static const String _kFaceSensitivity = 'setting.faceSensitivity';
static const String _kFaceCooldown = 'setting.faceCooldown';
static const String _kSosHoldDuration = 'setting.sosHoldDuration';
static const String _kSosAlertSoundEnabled = 'setting.sosAlertSoundEnabled';
static const String _kSosAlertTone = 'setting.sosAlertTone';
static const String _kAppLanguage = 'setting.appLanguage';
static const String _kTheme = 'setting.theme';
static const String _kNotifications = 'setting.notifications';
static const String _kClearHistory = 'app_history';
```

### 2.2 Emergency Contacts Key

```dart
static const String _contactsKey = 'emergency_contacts';
// Value: List<String> (JSON-encoded EmergencyContact objects)
```

### 2.3 Familiar Faces Key

```dart
// Note: Key not explicitly defined in code
// Uses SharedPreferences.getStringList() with JSON format
```

---

## 3. Data Flow

### 3.1 Settings Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Settings Data Flow                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  App Start                                                                   │
│       │                                                                        │
│       ▼                                                                        │
│  SettingsService.load()                                                      │
│       │                                                                        │
│       ├─→ SharedPreferences.getInstance()                                   │
│       │                                                                        │
│       ├─→ prefs.getBool('setting.voiceGuidance')                            │
│       ├─→ prefs.getInt('setting.speechRate')                                │
│       ├─→ prefs.getDouble('setting.voiceVolume')                            │
│       ├─→ prefs.getString('setting.voiceLanguage')                          │
│       └─→ ... (all settings)                                                │
│       │                                                                        │
│       ▼                                                                        │
│  In-Memory Cache                                                             │
│  SettingsService.instance                                                    │
│  - _voiceGuidanceEnabled                                                     │
│  - _speechRate                                                               │
│  - _voiceVolume                                                              │
│  - ...                                                                       │
│       │                                                                        │
│       ▼                                                                        │
│  UI Access (via Provider)                                                    │
│  - SettingsScreen reads from cache                                          │
│  - Widgets use Provider.of<SettingsService>()                               │
│       │                                                                        │
│       ▼                                                                        │
│  User Changes                                                                │
│       │                                                                        │
│       ▼                                                                        │
│  SettingsService setters                                                     │
│       │                                                                        │
│       ├─→ Update in-memory cache                                            │
│       ├─→ Call notifyListeners() (ChangeNotifier)                          │
│       ├─→ prefs.setBool('setting.key', value)                              │
│       └─→ prefs.commit()                                                    │
│       │                                                                        │
│       ▼                                                                        │
│  UI Updates                                                                  │
│  - ListenableBuilder rebuilds                                                │
│  - Live status updates                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Emergency Contacts Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Emergency Contacts Data Flow                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  App Start                                                                   │
│       │                                                                        │
│       ▼                                                                        │
│  EmergencyContactService.load()                                              │
│       │                                                                        │
│       ├─→ SharedPreferences.getInstance()                                   │
│       ├─→ prefs.getStringList('emergency_contacts')                         │
│       │                                                                        │
│       ├─→ For each raw string:                                              │
│       │    - jsonDecode(raw)                                                │
│       │    - EmergencyContact.fromJson(json)                               │
│       │                                                                        │
│       ▼                                                                        │
│  In-Memory Cache                                                             │
│  EmergencyContactService.instance                                            │
│  - List<EmergencyContact> _contacts                                         │
│       │                                                                        │
│       ▼                                                                        │
│  Emergency Screen Access                                                     │
│  - Display contact list                                                      │
│  - Show primary contact (index 0)                                           │
│       │                                                                        │
│       ▼                                                                        │
│  Add/Update/Delete Contact                                                   │
│       │                                                                        │
│       ▼                                                                        │
│  EmergencyContactService.addContact() / updateContact() / deleteContact()   │
│       │                                                                        │
│       ├─→ Update in-memory list                                             │
│       ├─→ Call notifyListeners()                                            │
│       ├─→ For each contact: jsonEncode(contact.toJson())                   │
│       ├─→ prefs.setStringList('emergency_contacts', jsonList)             │
│       └─→ prefs.commit()                                                    │
│       │                                                                        │
│       ▼                                                                        │
│  SOS Emergency Use                                                           │
│  - Access _contacts.first (primary)                                         │
│  - Extract phone number                                                      │
│  - Initiate call/SMS                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Familiar Faces Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Familiar Faces Data Flow                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  App Start                                                                   │
│       │                                                                        │
│       ▼                                                                        │
│  FamiliarFaceService.load()                                                  │
│       │                                                                        │
│       ├─→ SharedPreferences.getInstance()                                   │
│       ├─→ prefs.getStringList('familiar_faces')                            │
│       │                                                                        │
│       ├─→ For each raw string:                                              │
│       │    - jsonDecode(raw)                                                │
│       │    - FamiliarFace.fromJson(json)                                   │
│       │    - Extract embedding (List<double>)                              │
│       │    - Extract templates (List<List<double>>)                        │
│       │                                                                        │
│       ▼                                                                        │
│  In-Memory Cache                                                             │
│  FamiliarFaceService._people                                                │
│  - List<FamiliarFace> people                                                │
│       │                                                                        │
│       ▼                                                                        │
│  Face Recognition Screen Access                                              │
│  - Load embeddings into memory                                              │
│       │                                                                        │
│       ▼                                                                        │
│  Face Registration (Add New Person)                                         │
│       │                                                                        │
│       ▼                                                                        │
│  FaceRegistrationScreen                                                      │
│       │                                                                        │
│       ├─→ Capture 12 face samples                                          │
│       ├─→ Generate embeddings (ArcFace or geometric)                       │
│       │                                                                        │
│       ▼                                                                        │
│  FamiliarFaceService.addPerson()                                            │
│       │                                                                        │
│       ├─→ Calculate mean embedding from samples                            │
│       ├─→ Create FamiliarFace object                                       │
│       │    - id: DateTime.now().millisecondsSinceEpoch.toString()          │
│       │    - name: user-provided                                          │
│       │    - embedding: mean of samples                                   │
│       │    - sampleCount: 12                                              │
│       │    - model: 'arcface' or 'geometric'                             │
│       │                                                                        │
│       ▼                                                                        │
│  Save to SharedPreferences                                                   │
│       │                                                                        │
│       ├─→ For each person: jsonEncode(face.toJson())                      │
│       ├─→ prefs.setStringList('familiar_faces', jsonList)                │
│       ├─→ _people.add(newFace) (in-memory)                                │
│       ├─→ notifyListeners()                                                │
│       └─→ Print debug info                                                 │
│       │                                                                        │
│       ▼                                                                        │
│  Face Recognition (Recognition)                                             │
│       │                                                                        │
│       ▼                                                                        │
│  FaceEmbeddingService.embeddingFor(face, rgba)                             │
│       │                                                                        │
│       ├─→ Extract 512-d embedding from ArcFace model                      │
│       │                                                                        │
│       ▼                                                                        │
│  FaceRecognitionService.match(embedding)                                   │
│       │                                                                        │
│       ├─→ For each registered face:                                       │
│       │    - cosine_similarity(stored_embedding, new_embedding)          │
│       │    - Track highest similarity                                    │
│       │                                                                        │
│       ▼                                                                        │
│  Match above threshold (0.95)?                                              │
│       │                                                                        │
│       ├─ YES → Announce name                                               │
│       └─ NO → Announce "unknown" (opt-in)                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Data Models

### 4.1 Settings Data Model

```dart
// AppSettings.dart
class SettingsService with ChangeNotifier {
  bool _voiceGuidanceEnabled;
  bool _globalVoiceMuted;
  AlertMode _alertMode;
  double _voiceVolume;
  int _announcementCooldownSeconds;
  SpeechRate _speechRate;
  VoiceLanguage _voiceLanguage;
  // ... 40+ settings
}
```

### 4.2 Emergency Contact Data Model

```dart
// EmergencyContact.dart
class EmergencyContact {
  final String name;
  final String phone;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: (json['name'] as String?)?.trim() ?? '',
      phone: (json['phone'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}
```

### 4.3 Familiar Face Data Model

```dart
// FamiliarFace.dart
class FamiliarFace {
  final String id;
  final String name;
  final String? relationship;
  final List<double> embedding;  // 512-d ArcFace or 30-d geometric
  final int sampleCount;
  final int createdAt;
  final List<List<double>>? templates;
  final String? model;

  factory FamiliarFace.fromJson(Map<String, dynamic> json) {
    final embedding = (json['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
    final templatesRaw = json['templates'] as List?;
    final templates = templatesRaw?.map((t) => (t as List).map((e) => (e as num).toDouble()).toList()).toList() ?? <List<double>>[];
    final model = json['model'] as String?;
    return FamiliarFace(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String?,
      embedding: embedding,
      sampleCount: json['sampleCount'] as int,
      createdAt: json['createdAt'] as int,
      templates: templates.isEmpty ? [embedding] : templates,
      model: model,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'embedding': embedding,
      'sampleCount': sampleCount,
      'createdAt': createdAt,
      'templates': templates,
      'model': model,
    };
  }
}
```

---

## 5. Data Persistence Patterns

### 5.1 Load Pattern

```dart
Future<void> load() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList(_contactsKey) ?? const [];
  _contacts
    ..clear()
    ..addAll(raw.map(_decodeEntry).whereType<EmergencyContact>());
  _loaded = true;
  notifyListeners();
}
```

### 5.2 Save Pattern

```dart
Future<void> _persist() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _contactsKey,
    _contacts.map((c) => jsonEncode(c.toJson())).toList(),
  );
}
```

### 5.3 Update Pattern

```dart
Future<ContactSaveResult> addContact(String name, String phone) async {
  // Validation...
  _contacts.add(EmergencyContact(name: trimmedName, phone: trimmedPhone));
  await _persist();  // Save to SharedPreferences
  notifyListeners();
  return ContactSaveResult.success;
}
```

---

## 6. Data Volume and Growth

### 6.1 Settings

| Setting Type | Storage Size | Growth Rate |
|--------------|--------------|-------------|
| Settings | ~40 bytes each | Constant |
| Total Settings | ~1-2 KB | Never grows |

### 6.2 Emergency Contacts

| Contact | Storage Size | Growth Rate |
|---------|--------------|-------------|
| Per Contact | ~50 bytes | Max 5 contacts |
| Total | Max ~250 bytes | Constant (5 max) |

### 6.3 Familiar Faces

| Face | Storage Size | Growth Rate |
|------|--------------|-------------|
| ArcFace (512-d) | ~4 KB | Variable |
| Geometric (30-d) | ~250 bytes | Variable |
| Templates | ~4 KB (12 samples) | Variable |
| Per Person | ~8-12 KB | Variable |

**Estimates:**
- 5 faces with ArcFace: ~60 KB
- 10 faces with ArcFace: ~120 KB
- 50 faces with ArcFace: ~600 KB

---

## 7. Data Recovery and Backup

### 7.1 No Automatic Backup

- SharedPreferences data persists across app updates
- No automatic cloud backup
- No export/import functionality

### 7.2 User Data Loss Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| App uninstall | All data lost | Cannot recover |
| Device reset | All data lost | Cannot recover |
| Settings change | Settings reset | Manual reconfiguration |
| Contact update | Contact updated | Manual change |

---

## 8. Data Flow Summary

| Component | Storage Type | Data Size | Growth | Persistence |
|-----------|-------------|-----------|--------|-------------|
| Settings | SharedPreferences | ~1-2 KB | None | Permanent |
| Emergency Contacts | SharedPreferences | Max ~250 bytes | 5 max | Permanent |
| Familiar Faces | SharedPreferences | ~8-12 KB per face | Variable | Permanent |
| Camera Frames | In-memory | ~1-5 MB/frame | 5 FPS | Temporary |
| Detection Results | In-memory | ~1 KB/frame | 5 FPS | Temporary |
| Face Embeddings | In-memory | ~2 KB/frame | 5 FPS | Temporary |

---

## 9. Data Security

### 9.1 Storage Security

| Aspect | Status |
|--------|--------|
| Encryption | No (SharedPreferences is not encrypted) |
| Access Control | System-level (app sandbox) |
| Backup | Manual only |
| Transfer | None (local only) |

### 9.2 Sensitive Data

| Data | Storage | Security Notes |
|------|---------|----------------|
| Face embeddings | SharedPreferences | L2-normalized vectors, cannot reconstruct face |
| Contact phone numbers | SharedPreferences | Plaintext, but in app sandbox |
| User settings | SharedPreferences | Plaintext, but in app sandbox |

**Note:** SharedPreferences is not encrypted. For sensitive data like face embeddings, the vectors are L2-normalized and cannot reconstruct the original face image.

---

## 10. Data Flow Diagram: Full Application

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Full Application Data Flow                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SHARED PREFERENCES (Persistent)                      │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  setting.*                    (40+ keys)                      │   │   │
│  │  │  emergency_contacts           (JSON array)                   │   │   │
│  │  │  familiar_faces               (JSON array)                   │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│       │                                                                        │
│       ▼                                                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    IN-MEMORY CACHE (Runtime)                           │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  SettingsService.instance                                     │   │   │
│  │  │  - 40+ settings (bool, int, double, String)                 │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  EmergencyContactService.instance                            │   │   │
│  │  │  - List<EmergencyContact> (name, phone)                     │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  FamiliarFaceService                                         │   │   │
│  │  │  - List<FamiliarFace> (name, embedding, relationship)       │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│       │                                                                        │
│       ▼                                                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    CAMERA PROCESSING PIPELINE                         │   │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  CameraImage (YUV)                                           │   │   │
│  │  │  - 30 FPS from camera                                        │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │       │                                                                        │
│  │       ▼                                                                        │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  RGBA Frame (640x640)                                        │   │   │
│  │  │  - 5 FPS sampled                                             │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  │       │                                                                        │
│  │       ├─→ ObjectDetectionService → DetectedObject[]                    │   │
│  │       ├─→ FaceDetectionService → DetectedFace[]                        │   │
│  │       ├─→ DepthAnalysisService → Proximity[]                          │   │
│  │       └─→ PathAnalysisService → PathAnalysisResult                    │   │
│  │       │                                                                        │
│  │       ▼                                                                        │
│  │  ┌────────────────────────────────────────────────────────────────┐   │   │
│  │  │  TEMPORARY RESULTS (cleared each frame)                      │   │   │
│  │  │  - DetectedObject[] (with position, proximity)              │   │   │
│  │  │  - DetectedFace[] (with landmarks)                          │   │   │
│  │  │  - PathAnalysisResult                                       │   │   │
│  │  └────────────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 11. Conclusion

VisionPath AI uses a **lightweight, client-only storage architecture**:

- **SharedPreferences** for all persistent data (settings, contacts, faces)
- **In-memory** for runtime data (camera frames, detections)
- **No database** (no SQLite, no Hive, no Moor)
- **No cloud storage** (no Firebase, no S3)
- **No backend** (no API endpoints)

This design prioritizes:
1. **Privacy:** No data leaves the device
2. **Simplicity:** Single storage mechanism
3. **Performance:** No database queries
4. **Offline:** Works without internet

The storage is sufficient for the app's needs but has limitations:
- No data backup/restore
- No sync across devices
- No data analytics
- No user accounts
