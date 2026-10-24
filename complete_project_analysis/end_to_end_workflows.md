# VisionPath AI - End-to-End Workflows

## 1. Application Launch Workflow

```
User taps VisionPath AI icon
    │
    ▼
Android launches MainActivity
    │
    ▼
main() function executes
    │
    ├─ WidgetsFlutterBinding.ensureInitialized()
    │
    ├─ FaceEmbeddingService.instance.ensureLoaded()
    │  ├─ Loads arcface_w600k_mbf.tflite
    │  ├─ Allocates tensors
    │  └─ Sets _ready = true
    │
    ├─ SettingsService.instance.load()
    │  ├─ SharedPreferences.getInstance()
    │  ├─ Loads all 40+ settings
    │  └─ Caches in memory
    │
    ├─ EmergencyContactService.instance.load()
    │  ├─ Loads emergency contacts
    │  └─ Caches in memory
    │
    ├─ VoiceService.bindToSettings()
    │  └─ Binds TTS to voice settings
    │
    └─ SosService.instance.attachNavigation()
       └─ Links SOS to NavigationService
    │
    ▼
VisionPathApp widget builds
    │
    ├─ MultiProvider (9 providers)
    │  ├─ CameraService
    │  ├─ ObjectDetectionService
    │  ├─ PositionDetectionService
    │  ├─ DepthAnalysisService
    │  ├─ PathAnalysisService
    │  ├─ NavigationService
    │  ├─ FamiliarFaceService
    │  ├─ SettingsService
    │  └─ SosService
    │
    └─ _AppRoot (navigator + SOS route observer)
    │
    ▼
NavigateScreen displays
    ├─ Title card covers camera
    ├─ Voice guidance: "Welcome to VisionPath AI"
    ├─ Settings, Currency, Read Text, Familiar Faces buttons
    └─ Ready for user interaction
```

---

## 2. Object Detection Navigation Workflow

```
User presses START NAVIGATION
    │
    ▼
_NavigateScreenState._startNavigation()
    │
    ├─ setState(() => _navState = _NavState.starting)
    ├─ _cameraService = CameraService()
    ├─ _cameraService!.initializeCamera()
    │  ├─ Permission.camera.request()
    │  ├─ CameraController.initialize()
    │  └─ Start camera preview
    │
    ├─ _voiceGuidance = SettingsService.instance.voiceGuidanceEnabled
    ├─ _pumpTimer = Timer.periodic(200ms, _pumpFrame)
    └─ notifyListeners()
    │
    ▼
Camera preview starts (30 FPS)
    │
    ▼
_pumpFrame() (5 FPS sampling)
    │
    ├─ _cameraImage = _latestFrame
    │
    ├─ CameraService.convertFrameToPortraitRgba()
    │  ├─ YUV to RGB conversion
    │  ├─ Apply rotation
    │  └─ Output RGBA buffer
    │
    ├─ ObjectDetectionService.detect(rgbFrame)
    │  ├─ Resize to 640x640
    │  ├─ Run YOLO26n inference
    │  ├─ Parse output [1, 84, 8400]
    │  ├─ Filter by confidence (0.40)
    │  ├─ Apply NMS
    │  └─ Return DetectedObject[]
    │
    ├─ PositionDetectionService.analyze()
    │  └─ Classify LEFT/CENTER/RIGHT
    │
    ├─ DepthAnalysisService.analyze()
    │  └─ Estimate proximity (NEAR/MEDIUM/FAR)
    │
    ├─ PathAnalysisService.analyze()
    │  ├─ Analyze central walking region (28%-72%)
    │  ├─ Identify primary blocker
    │  └─ Return PathAnalysisResult
    │
    ├─ NavigationService.decide(pathResult)
    │  ├─ Evaluate path obstruction
    │  ├─ Determine decision (FORWARD/LEFT/RIGHT/SLOW/STOP)
    │  └─ Generate spoken message
    │
    ├─ InstructionManager.shouldSpeak(decision)
    │  ├─ Check cooldown (3 seconds default)
    │  └─ Return true if should speak
    │
    ├─ VoiceService.enqueueSpeech(message)
    │  └─ Add to SpeechQueue
    │
    └─ UI updates with results
    │
    ▼
Voice output
    │
    ├─ SpeechQueue takes next sentence
    ├─ VoiceService.speak(sentence)
    └─ TTS playback
```

---

## 3. Face Recognition Workflow

```
User opens Familiar Faces screen
    │
    ▼
_FamiliarFacesScreenState.initState()
    │
    ├─ _faceService = Provider.of<FamiliarFaceService>(context)
    ├─ _faceService.load()
    │  ├─ Load registered faces from SharedPreferences
    │  └─ Cache in memory
    │
    └─ _showTitleCard = true
    │
    ▼
User presses RECOGNIZE
    │
    ▼
_startRecognizing()
    │
    ├─ _recognizing = true
    ├─ _showTitleCard = false
    ├─ _pumpTimer = Timer.periodic(200ms, _pumpFrame)
    └─ notifyListeners()
    │
    ▼
Camera preview starts (5 FPS)
    │
    ▼
_pumpFrame()
    │
    ├─ CameraImage to RGBA
    │
    ├─ FaceDetectionService.detectRgba()
    │  ├─ ML Kit Face Detection
    │  ├─ Return DetectedFace[]
    │  └─ Extract landmarks (5 points)
    │
    ├─ ScrfdFaceDetector.detectRgba() [alternative path]
    │  ├─ Load scrfd_640.tflite
    │  ├─ Run SCRFD inference
    │  └─ Return DetectedFace[]
    │
    ├─ For each face:
    │  │
    │  ├─ FaceEmbeddingService.embeddingFor()
    │  │  ├─ Crop and align face (112x112)
    │  │  ├─ Run ArcFace model
    │  │  ├─ Extract 512-d embedding
    │  │  └─ L2 normalize
    │  │
    │  ├─ FaceRecognitionService.match()
    │  │  ├─ Compare with registered faces
    │  │  ├─ Calculate cosine similarity
    │  │  └─ Match if > 0.95
    │  │
    │  └─ FaceOccurrence(identity, similarity)
    │
    ├─ FaceAnnouncementManager.update(occurrences)
    │  ├─ Track faces across frames
    │  ├─ Temporal confirmation (3 frames)
    │  └─ Return confirmed face + name
    │
    └─ UI updates with face overlays
    │
    ▼
Voice announcement
    │
    ├─ "John detected, 2.4 meters ahead."
    └─ TTS playback
```

---

## 4. Face Registration Workflow

```
User presses ADD NEW PERSON
    │
    ▼
FaceRegistrationScreen displays
    │
    ├─ Step 1: Enter name and relationship
    ├─ Form validation
    └─ User presses CONTINUE
    │
    ▼
User presses START CAPTURE
    │
    ▼
Camera starts (front lens)
    │
    ▼
Voice-guided positioning loop
    │
    ├─ FaceDetectionService.detectRgba()
    │
    ├─ FaceRegistrationGuide.update(face)
    │  ├─ Check face size (0.16-0.68 width)
    │  ├─ Check face position (center 0.36-0.64 X)
    │  ├─ Check yaw (max 34 degrees)
    │  └─ Return guidance (too far, too close, turn, etc.)
    │
    └─ Voice feedback: "Move closer" / "Turn toward camera"
    │
    ▼
User holds steady (2 consecutive frames)
    │
    ├─ Capture sample
    │  ├─ Extract face crop
    │  ├─ Generate embedding (ArcFace)
    │  └─ Store in _samples list
    │
    ├─ Update sample count
    │
    └─ Voice: "Sample captured. Hold steady."
    │
    ▼
Repeat 12 times (alternating front/left/right)
    │
    ├─ Front sample (4 times)
    ├─ Left sample (4 times)
    └─ Right sample (4 times)
    │
    ▼
All samples captured
    │
    ▼
AddPerson button pressed
    │
    ▼
FamiliarFaceService.addPerson()
    │
    ├─ Calculate mean embedding from 12 samples
    │
    ├─ Create FamiliarFace object
    │  ├─ id: DateTime.now().millisecondsSinceEpoch.toString()
    │  ├─ name: user-provided
    │  ├─ embedding: mean of 512-d vectors
    │  ├─ sampleCount: 12
    │  └─ model: 'arcface'
    │
    ├─ _people.add(newFace)
    │
    ├─ _persist() → SharedPreferences
    │  └─ JSON encode and save
    │
    ├─ notifyListeners()
    │
    └─ Print debug: "FAMILIAR_FACE_ADDED: John samples=12"
    │
    ▼
Back to Familiar Faces screen
```

---

## 5. Read Text Workflow

```
User presses READ TEXT
    │
    ▼
ReadTextScreen displays
    │
    ├─ OcrService initialized
    ├─ TextGuidanceService initialized
    └─ _phase = searching
    │
    ▼
User holds press-and-hold voice region
    │
    ├─ VoiceCommandController.beginHold()
    │  ├─ _speech.clearSpeechQueue()
    │  └─ _listening = true
    │
    ├─ SpeechCaptureService.startCapture()
    │  ├─ _audioPlugin.initMicrophone()
    │  └─ Start recording
    │
    ├─ onPartial callback (streaming text)
    └─ onResult callback (final transcript)
    │
    ▼
Voice command: "Read text"
    │
    ▼
_voiceCommand.onCommand()
    │
    ├─ _phase = capturing
    ├─ _cameraService.takePicture()
    │  └─ Capture photo to file
    │
    ├─ OcrService.recognizeImageFile()
    │  ├─ Load image as InputImage
    │  ├─ ML Kit TextRecognizer.processImage()
    │  ├─ Parse RecognizedText
    │  └─ Return OcrResult
    │
    ├─ _phase = result
    └─ Display OCR result
    │
    ▼
User presses READ ALOUD
    │
    ├─ _voiceEnabled = true
    ├─ _reading = true
    └─ _startReading()
    │
    ▼
Sequential text reading
    │
    ├─ Split text into sentences
    ├─ For each sentence:
    │  ├─ VoiceService.speak(sentence)
    │  ├─ Wait for completion
    │  └─ Next sentence
    │
    └─ _reading = false
```

---

## 6. Currency Recognition Workflow

```
User presses CURRENCY RECOGNITION
    │
    ▼
CurrencyRecognitionScreen displays
    │
    ├─ Camera preview starts
    ├─ CurrencyDetector loaded
    └─ _latestResult = CurrencyInferenceResult.modelUnavailable()
    │
    ▼
Currency detection loop (5 FPS)
    │
    ├─ CameraImage to RGBA
    │
    ├─ CurrencyDetector.process()
    │  ├─ Resize to 640x640
    │  ├─ Run YOLO currency model
    │  ├─ Parse output [1, 300, 6]
    │  ├─ Filter by confidence
    │  └─ Return CurrencyRecognition?
    │
    ├─ CurrencyStabilityVerifier.verify()
    │  ├─ Check previous results (2 frames)
    │  └─ Require stable detection
    │
    └─ Update UI with result
    │
    ▼
Voice feedback (if enabled)
    │
    ├─ "Dollar bill detected."
    └─ TTS playback
```

---

## 7. Emergency SOS Workflow

```
User presses-and-holds SOS button
    │
    ▼
SosHoldController.beginHold()
    │
    ├─ _holding = true
    ├─ _countdown = 5 (configurable)
    └─ Start timer (1 second ticks)
    │
    ▼
Countdown loop
    │
    ├─ Voice cue: "Release to cancel"
    ├─ _hold.tick()
    └─ Countdown decreases (5 → 4 → 3 → 2 → 1)
    │
    ▼
Countdown reaches 0
    │
    ▼
_onActivated()
    │
    ├─ SosService.instance.activate()
    │  ├─ State: ACTIVATING
    │  ├─ Play alert sound
    │  └─ Start vibration pattern
    │  │
    │  ├─ Get primary contact
    │  │  └─ _contacts.contacts.first
    │  │
    │  ├─ Get location (concurrent)
    │  │  ├─ Permission.location.request()
    │  │  ├─ LocationManager.getLastKnownLocation()
    │  │  └─ Format: "https://maps.google.com/?q=lat,lon"
    │  │
    │  ├─ Place call (concurrent)
    │  │  ├─ Permission.callPhone.request()
    │  │  ├─ Intent.ACTION_CALL
    │  │  └─ tel:+1234567890
    │  │
    │  └─ Send SMS (concurrent)
    │     ├─ Permission.sms.request()
    │     ├─ SmsManager.sendTextMessage()
    │     └─ Location URL in message
    │
    └─ State: ACTIVE
    │
    ▼
Emergency notification posted
    │
    └─ NotificationManager.notify()
    │
    ▼
User sees emergency status
    │
    ▼
User presses STOP SOS
    │
    ▼
SosService.instance.reset()
    │
    ├─ Cancel timer
    ├─ Stop alert sound
    ├─ Stop vibration
    ├─ Clear notification
    └─ State: INACTIVE
```

---

## 8. Settings Workflow

```
User presses SETTINGS
    │
    ▼
SettingsScreen displays
    │
    ├─ Grouped settings by category
    ├─ Read from SettingsService
    └─ Show live status
    │
    ▼
User changes setting
    │
    ▼
SettingsService setter
    │
    ├─ Update in-memory value
    ├─ notifyListeners()
    ├─ SharedPreferences.setBool()
    └─ Commit to disk
    │
    ▼
UI rebuilds (ListenableBuilder)
    │
    └─ Update status indicator
```

---

## 9. Voice Assistant Workflow

```
User holds screen (350ms threshold)
    │
    ▼
VoiceCommandController.beginHold()
    │
    ├─ _holding = true
    ├─ _listening = false
    └─ _transcript = ''
    │
    ▼
Hold duration >= 350ms
    │
    ▼
Open microphone
    │
    ├─ _speech.clearSpeechQueue()
    ├─ SpeechCaptureService.startCapture()
    └─ _listening = true
    │
    ▼
User speaks question
    │
    ├─ onPartial callback (streaming)
    │  └─ _transcript += partial
    │
    └─ Vosk recognition
    │
    ▼
User releases screen
    │
    ▼
_onHoldReleased()
    │
    ├─ SpeechCaptureService.stopCapture()
    ├─ _listening = false
    ├─ _holding = false
    └─ _transcript = final text
    │
    ▼
onCommand(transcript)
    │
    ├─ LookAndDetectEngine.answer(transcript)
    │  ├─ Parse question
    │  ├─ Search scene for object
    │  └─ Generate answer
    │
    └─ VoiceService.speak(answer)
    │
    ▼
TTS playback
```

---

## 10. Navigation Screen Carousel Workflow

```
User taps settings button
    │
    ▼
Navigator.push(SettingsScreen)
    │
    ├─ NavigateScreen paused
    ├─ SettingsScreen displayed
    └─ SettingsService listened
    │
    ▼
User changes settings
    │
    ▼
SettingsService.notifyListeners()
    │
    ▼
SettingsScreen rebuilds
    │
    ▼
User presses BACK
    │
    ▼
Navigator.pop()
    │
    ▼
NavigateScreen resumes
    │
    ├─ _voiceGuidance updates
    └─ Navigation resumes
```

---

## 11. Data Persistence Workflow

```
Settings changed
    │
    ▼
SettingsService setter
    │
    ├─ Update in-memory cache
    ├─ notifyListeners() → UI updates
    ├─ SharedPreferences.setBool() / setString()
    └─ SharedPreferences.commit()
    │
    ▼
Data stored in SharedPreferences
    │
    └─ XML file: com.example.visionpath SharedPreferences.xml
    │
    ▼
App restart
    │
    ▼
SettingsService.load()
    │
    ├─ SharedPreferences.getInstance()
    ├─ prefs.getBool('setting.key')
    └─ Cache in memory
```

---

## 12. Face Recognition Data Flow

```
Face registration
    │
    ├─ Camera: FaceImage (112x112)
    ├─ ArcFace: 512-d embedding (L2 normalized)
    ├─ SharedPreferences: JSON array
    └─ Cache: FamiliarFaceService._people
    │
    ▼
Face recognition
    │
    ├─ Camera: FaceImage (112x112)
    ├─ ArcFace: 512-d embedding
    ├─ Comparison: Cosine similarity
    └─ Match: > 0.95 threshold
    │
    ▼
Result: Identity + Name
```

---

## 13. Summary

VisionPath AI has **9 key workflows**:

1. **Application Launch** (10+ services initialized)
2. **Object Detection Navigation** (5 FPS pipeline)
3. **Face Recognition** (SCRFD + ArcFace)
4. **Face Registration** (12 samples, voice-guided)
5. **Read Text** (OCR + TTS)
6. **Currency Recognition** (YOLO currency model)
7. **Emergency SOS** (5-second countdown)
8. **Settings** (SharedPreferences persistence)
9. **Voice Assistant** (Vosk offline STT)

All workflows:
- Run on main thread
- Use 5 FPS sampling
- Include error handling
- Provide voice feedback
- Persist state in SharedPreferences
