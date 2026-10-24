# VisionPath AI - Algorithms and Business Logic

## 1. Object Detection Algorithm

### 1.1 YOLO26n Inference Pipeline

**File:** `lib/services/object_detection_service.dart`

**Model:** Ultralytics YOLO26n (Tiny YOLO variant)

**Input:** Camera frame (RGBA, normalized [0,1])

**Output:** List of DetectedObject with bounding boxes, classes, confidence

```dart
// Algorithm Steps:
1. Convert CameraImage (YUV format) to RGBA
   - Extract Y, U, V planes from CameraImage
   - Apply color space transformation
   - Handle sensor rotation

2. Resize frame to model input size (640x640)
   - Bilinear interpolation
   - Preserve aspect ratio

3. Run YOLO26n inference
   - TFLite Interpreter.runForMultipleInputsOutputs()
   - Get output tensor: [1, 84, 8400] (84 classes, 8400 anchors)
   - Output format: [x_center, y_center, width, height, class_scores...]

4. Post-process detections
   - Apply sigmoid to confidence scores
   - Filter by confidence threshold (0.40)
   - Apply Non-Maximum Suppression (NMS)
   - Convert normalized coordinates to pixel coordinates

5. Enrich with position
   - Calculate center X
   - Classify as LEFT (0.0-0.28), CENTER (0.28-0.72), RIGHT (0.72-1.0)
```

**Key Constants:**
- Confidence threshold: 0.40
- NMS threshold: 0.45 (Yolo26n default)
- Input size: 640x640

---

## 2. Face Detection Algorithm

### 2.1 SCRFD Face Detection

**File:** `lib/services/scrfd_face_detector.dart`

**Model:** SCRFD (Sample and Computation Redistribution for Face Detection)

**Input:** 640x640 RGBA image

**Output:** List of DetectedFace with bounding boxes and 5 landmarks

```dart
// Algorithm Steps:
1. Preprocess image
   - Resize to 640x640 with bilinear interpolation
   - Normalize RGB to [-1, 1]

2. Run SCRFD inference
   - Three feature strides: 8, 16, 32
   - Per-anchor: confidence, bbox distances, 5 keypoints
   - Output: Multiple tensors (one per stride)

3. Decode detections
   - For each stride:
     * Extract anchor predictions
     * Apply bounding box regression
     * Calculate absolute coordinates
   - Combine results from all strides

4. Filter and NMS
   - Score threshold: 0.5
   - NMS threshold: 0.4
   - Keep top detections

5. Output format
   - DetectedFace with:
     * boundingBox (normalized)
     * 5 landmarks: left eye, right eye, nose, left mouth, right mouth
```

**Key Constants:**
- Input size: 640x640
- Score threshold: 0.5
- NMS threshold: 0.4
- Strides: [8, 16, 32]
- Anchors per position: 2

---

## 3. Face Recognition Algorithm

### 3.1 ArcFace Embedding Extraction

**File:** `lib/services/face_embedding_service.dart`

**Model:** ArcFace (arcface_w600k_mbf.tflite)

**Input:** 112x112 aligned face (RGB)

**Output:** 512-d L2-normalized embedding vector

```dart
// Algorithm Steps:
1. Get face landmarks from SCRFD or ML Kit
   - 5 keypoints: left eye, right eye, nose, left mouth, right mouth

2. Compute similarity transform (Umeyama)
   - Map landmarks to canonical ArcFace positions
   - Canonical positions:
     * Left eye: (38.2946, 51.6963)
     * Right eye: (73.5318, 51.5014)
     * Nose: (56.0252, 71.7366)
     * Left mouth: (41.5493, 92.3655)
     * Right mouth: (70.7299, 92.2041)

3. Warp face
   - Apply affine transform
   - Bilinear resampling
   - Output: 112x112 aligned face

4. Run ArcFace model
   - TFLite Interpreter
   - Input: [1, 112, 112, 3] RGB
   - Output: [1, 512] embedding

5. L2 normalization
   - Compute norm: sqrt(sum(x^2))
   - Normalize: x / norm

6. Output: 512-d unit vector
```

**Key Constants:**
- Input size: 112x112
- Output dimension: 512
- Default threshold: 0.55
- Ambiguity margin: 0.06

---

### 3.2 Geometric Face Recognition (Fallback)

**File:** `lib/services/face_recognition_service.dart`

**Algorithm:** Hand-crafted geometric features

**Input:** DetectedFace with landmarks

**Output:** 30-d geometric embedding + cosine similarity match

```dart
// Algorithm Steps:
1. Align face relative to eye midpoint
   - Calculate interocular distance (I)
   - Normalize all coordinates by I (scale invariance)

2. Extract 30 geometric features
   A. Position features (10):
      - Nose, mouth, ear positions relative to eye midpoint
   
   B. Distance features (10):
      - Mouth width, nose-to-chin, etc.
   
   C. Face shape features (6):
      - Cheek-to-cheek width, face box dimensions
   
   D. Vertical features (4):
      - Nose-to-lip, lip-to-chin heights

3. Whitening
   - Divide each feature by inter-person range
   - Face-shape dimensions have higher ranges

4. L2 normalization
   - Compute norm
   - Normalize: x / norm

5. Matching
   - Cosine similarity: dot(embedding, stored_embedding)
   - Threshold: 0.95
   - Below threshold = "unknown"
```

**Key Constants:**
- Feature dimensions: 30
- Default threshold: 0.95
- Ranges: Anthropometric ballparks

---

## 4. Depth Estimation Algorithm

### 4.1 Real Depth Estimation

**File:** `lib/services/depth/depth_engine.dart`

**Algorithm:** Monocular depth estimation via TFLite model

**Input:** Camera frame (upright portrait RGBA)

**Output:** Depth map (relative nearness 0.0-1.0)

```dart
// Algorithm Steps:
1. Preprocess frame
   - Resize to model input (typically 320x320 or 480x480)
   - Normalize [0, 1]

2. Run depth model
   - TFLite inference
   - Output: depth map (HxW)

3. Post-process depth
   - Apply sigmoid or exponential
   - Invert (smaller values = closer)
   - Normalize to [0, 1]

4. Sample object depths
   - For each detected object:
     * Extract bounding box region from depth map
     * Compute median or min depth
     * Map to ProximityLevel (NEAR/MEDIUM/FAR)

5. Temporal smoothing
   - Exponential moving average across frames
   - Configurable smoothing factor
```

### 4.2 Geometric Depth Fallback

**File:** `lib/services/depth/geometric_depth_engine.dart`

**Algorithm:** Box area heuristic

**Input:** Detected object bounding box

**Output:** Proximity level (NEAR/MEDIUM/FAR)

```dart
// Algorithm Steps:
1. Calculate object area
   - Area = width * height (normalized)

2. Apply sensitivity scaling
   - Low sensitivity: multiply by 1.25
   - Medium: multiply by 1.0
   - High: multiply by 0.8

3. Classify proximity
   - Very near: width > 0.70 OR height > 0.85
   - Very near: area >= 0.25
   - Near: area >= 0.12
   - Medium: area >= 0.05
   - Far: otherwise
```

---

## 5. Path Analysis Algorithm

**File:** `lib/services/path_analysis_service.dart`

**Algorithm:** Central walking region analysis

**Input:** List of detected objects with position and depth

**Output:** PathAnalysisResult (classification + primary blocker)

```dart
// Algorithm Steps:
1. Define walking region
   - Left edge: 28% of frame width
   - Right edge: 72% of frame width
   - Central band: 44% of frame width

2. Calculate margins
   - Find leftmost occupied edge
   - Find rightmost occupied edge
   - Left margin = leftmost edge position
   - Right margin = 1 - rightmost edge position

3. Select primary blocker
   - Filter objects: in walking region OR close proximity
   - If no filtered objects, use all objects
   - Sort by:
     a. Proximity (nearest first)
     b. Box area (larger first)
   - Pick first as primary blocker

4. Classify path
   - If no objects: CLEAR
   - If primary blocker in LEFT region: OBSTACLE_LEFT
   - If primary blocker in CENTER region: OBSTACLE_CENTER
   - If primary blocker in RIGHT region: OBSTACLE_RIGHT
```

**Key Constants:**
- Walking region: [0.28, 0.72]
- Distance thresholds: Configurable via proximity levels

---

## 6. Navigation Decision Algorithm

**File:** `lib/services/navigation_service.dart`

**Algorithm:** Path-based navigation guidance

**Input:** PathAnalysisResult

**Output:** NavigationDecision + spoken message

```dart
// Algorithm Steps:
1. Evaluate path obstruction
   - CLEAR: No objects in walking region
   - OBSTACLE_LEFT: Obstacle in left region
   - OBSTACLE_CENTER: Obstacle in center region
   - OBSTACLE_RIGHT: Obstacle in right region

2. Determine decision
   - CLEAR + safe margins: FORWARD
   - Obstacle left + right margin clear: RIGHT
   - Obstacle right + left margin clear: LEFT
   - Obstacle center or both margins blocked: SLOW
   - Very near obstacle: STOP

3. Generate spoken message
   - Safety decisions: "Stop. Person very close."
   - Other decisions: SceneAnnouncer to name all objects
   - Include distance for each object
   - Include position (ahead, to your left, etc.)

4. Apply cooldown
   - Check InstructionManager for cooldown
   - Skip if cooldown not elapsed and decision unchanged
```

**Navigation Decision Priority:**
1. STOP (most urgent)
2. SLOW (immediate danger)
3. FORWARD (safe path)
4. LEFT/RIGHT (lateral avoidance)

---

## 7. Voice Instruction Management

**File:** `lib/services/instruction_manager.dart`

**Algorithm:** Instruction deduplication and cooldown

**Input:** NavigationDecision, timestamp

**Output:** Boolean (should speak)

```dart
// Algorithm Steps:
1. Check decision change
   - Changed: true
   - Unchanged: false

2. Check escalation
   - Escalation = changed AND higher priority
   - Priority: STOP > SLOW > FORWARD > LEFT/RIGHT

3. Calculate gate duration
   - Escalation: 1.2 seconds (escalationMinimumGap)
   - Regular: max(repeatCooldown, guidanceModeInterval)

4. Check cooldown elapsed
   - No previous instruction: true
   - Time since last: >= gate duration

5. Check repeat enabled
   - If unchanged and repeatDisabled: false

6. Final decision
   - Speak = (changed OR (unchanged AND repeatEnabled)) AND cooldownElapsed
```

**Key Constants:**
- escalationMinimumGap: 1200ms
- default repeatCooldown: 3000ms
- guidanceMode intervals: 1.5s / 3s / 6s

---

## 8. Face Announcement Management

**File:** `lib/services/face_announcement_manager.dart`

**Algorithm:** Temporal confirmation and deduplication

**Input:** Face occurrences per frame

**Output:** Announced faces with names

```dart
// Algorithm Steps:
1. Expiration
   - Remove tracks older than trackExpiry (1600ms)

2. Track association
   - Match occurrences to existing tracks by center distance
   - Max association distance: 0.35 (normalized)

3. Update tracks
   - If new occurrence and no track: create new track
   - If existing track: update center, increment vote for identity

4. Confirmation
   - If votes >= confirmFrames (3): mark as confirmed
   - Store identity, name, similarity

5. Announcement check
   - Check announceCooldown (3000ms)
   - Skip if same identity + position + within cooldown
   - Skip if unknown announcements disabled

6. Output
   - Return list of announcements to speak
   - Limit maxAnnouncementsPerFrame (2)
```

**Key Constants:**
- confirmFrames: 3
- announceCooldown: 3000ms
- trackExpiry: 1600ms
- maxAnnouncementsPerFrame: 2
- max association distance: 0.35

---

## 9. Scene Announcement Algorithm

**File:** `lib/services/scene_announcer.dart`

**Algorithm:** Multi-object scene description generation

**Input:** List of detected objects with depth

**Output:** List of sentences, one per object

```dart
// Algorithm Steps:
1. Deduplicate overlapping detections
   - Group by class + position
   - Keep highest confidence

2. Assign slots
   - Create SceneSlot for each unique class+position
   - Store smoothed distance

3. Change detection
   - Compare with last announcement
   - Detect: new object, removed object, position change, distance change
   - Distance threshold: 0.3 meters

4. Ordering
   - Priority order:
     a. Path-blocking objects
     b. Collision risk
     c. Nearest objects
     d. Directly ahead
     e. Left/right

5. Sentence generation
   - For each changed object:
     * "Person detected, 2.4 meters ahead."
     * "Chair detected, 1.8 meters to your left."
   - Include distance only if available

6. Limit output
   - Maximum maxAnnouncedObjects (3) per frame
```

**Key Constants:**
- maxAnnouncedObjects: 3
- distanceChangeThreshold: 0.3
- smoothing factor: EMA weight

---

## 10. Speech Queue Algorithm

**File:** `lib/services/speech_queue.dart`

**Algorithm:** Sequential, duplicate-free speech ordering

**Input:** Sentences to queue

**Output:** Ordered queue with deduplication

```dart
// Algorithm Steps:
1. Add sentence
   - Trim whitespace
   - Check if blank: return false
   - Check if already waiting: return false
   - Check if currently speaking: return false
   - Add to end of pending list
   - Add to queued set

2. Take next sentence
   - Remove from front of pending
   - Remove from queued set
   - Set active sentence
   - Set speaking flag

3. Finish current
   - Clear active sentence
   - Clear speaking flag

4. Clear queue
   - Clear pending list
   - Clear queued set
   - Clear active sentence
   - Clear speaking flag
```

**Invariants:**
- No duplicate sentences in pending list
- Currently speaking sentence never in pending list
- Sentences leave only via takeNext() or clear()

---

## 11. Settings Persistence Algorithm

**File:** `lib/services/settings_service.dart`

**Algorithm:** SharedPreferences-based persistence

**Input:** Setting key-value pairs

**Output:** Persisted settings

```dart
// Algorithm Steps:
1. Load settings
   - Get SharedPreferences instance
   - Read each preference key
   - Parse values (bool, int, double, String)
   - Cache in memory

2. Save settings
   - Write to SharedPreferences
   - Notify listeners (ChangeNotifier)
   - Log change

3. Setting types
   - bool: voiceGuidanceEnabled, globalVoiceMuted, etc.
   - int: speechRate, announcementCooldown
   - double: voiceVolume
   - String: voiceLanguage, ocrLanguage, etc.
```

**Persistence Keys:**
- setting.voiceGuidance
- setting.globalVoiceMuted
- setting.speechRate
- setting.voiceVolume
- setting.voiceLanguage
- setting.announcementCooldown
- ... (40+ settings)

---

## 12. Emergency Contact Management

**File:** `lib/services/emergency_contact_service.dart`

**Algorithm:** JSON-based contact storage

**Input:** Contact name and phone

**Output:** Persisted contacts list

```dart
// Algorithm Steps:
1. Load contacts
   - Read from SharedPreferences key: "emergency_contacts"
   - Parse each JSON string
   - Convert to EmergencyContact objects
   - Limit: 5 contacts max

2. Add contact
   - Trim name and phone
   - Validate format
   - Check duplicates (by phone)
   - Check max limit
   - Serialize to JSON
   - Save to SharedPreferences

3. Update contact
   - Find by index
   - Validate new values
   - Check for duplicate phone (unless same contact)
   - Update and persist

4. Delete contact
   - Remove from list
   - Save remaining contacts
```

---

## 13. Voice Command Processing

**File:** `lib/services/voice_command_controller.dart`

**Algorithm:** Press-and-hold voice assistant

**Input:** Touch events (press, hold, release)

**Output:** Recognized transcript

```dart
// Algorithm Steps:
1. Press detection
   - Hold threshold: 350ms
   - Shorter press = tap (no voice)
   - Longer press = voice assistant

2. Microphone opening
   - Request microphone access
   - Start SpeechCaptureService
   - Begin partial transcription

3. Listening
   - Stream partial transcripts
   - Update UI with listening orb
   - Keep TTS quiet (voice muted)

4. Release
   - Stop microphone
   - Return final transcript
   - Call onCommand callback

5. Error handling
   - Permission denied: return VoiceCommandFailure.permissionDenied
   - No speech: return VoiceCommandFailure.nothingHeard
```

---

## 14. Currency Recognition Algorithm

**File:** `lib/services/currency_detector.dart`

**Algorithm:** YOLO-based currency detection

**Input:** Camera frame (640x640)

**Output:** Currency recognition result

```dart
// Algorithm Steps:
1. Preprocess image
   - Resize to 640x640
   - Normalize RGB to [0, 1]

2. Run YOLO model
   - Input: [1, 640, 640, 3]
   - Output: [1, 300, 6] (xyxy + conf + cls)

3. Post-process
   - Filter by confidence
   - Apply NMS
   - Extract class (note/coin)

4. Stability verification
   - Track across frames
   - Require multiple confirmations
   - Avoid flickering

5. Output
   - Recognized: confidence >= threshold
   - Uncertain: below threshold
   - Model unavailable: model not loaded
```

---

## 15. OCR Text Reading Algorithm

**File:** `lib/services/ocr_service.dart`

**Algorithm:** ML Kit Text Recognition

**Input:** Camera frame or captured image

**Output:** OCR result with text blocks

```dart
// Algorithm Steps:
1. Convert to InputImage
   - CameraImage: YUV to RGBA, rotate, create InputImage
   - Captured: Flutter image decoder, create InputImage

2. Run ML Kit OCR
   - TextRecognizer.processImage()
   - Return RecognizedText

3. Parse results
   - Extract text blocks
   - Extract text lines
   - Extract text elements

4. Format output
   - Extract full text
   - Extract bounding boxes
   - Return OcrResult

5. Guidance
   - Analyze text density
   - Guide user to position text
   - Trigger auto-capture when ready
```

---

## 16. Speech Recognition Algorithm

**File:** `lib/services/speech_service.dart`

**Algorithm:** Vosk offline speech recognition

**Input:** Microphone audio stream

**Output:** Transcribed text

```dart
// Algorithm Steps:
1. Initialize
   - Load Vosk model from assets
   - Create model and recognizer
   - Sample rate: 16000 Hz

2. Start listening
   - Initialize speech service
   - Open microphone stream
   - Begin streaming to Vosk

3. Process audio
   - Stream audio chunks to Vosk
   - Receive partial transcriptions
   - Receive final transcription

4. Output
   - onPartial: streaming text
   - onResult: final transcription
```

---

## 17. Text-to-Speech Algorithm

**File:** `lib/services/voice_service.dart`

**Algorithm:** FlutterTTS integration

**Input:** Text string

**Output:** Spoken audio

```dart
// Algorithm Steps:
1. Initialize TTS
   - FlutterTts.instance
   - Set language, rate, volume
   - Handle initialization

2. Queue speech
   - Add to SpeechQueue
   - Sequential playback

3. Interrupt
   - Flush queue
   - Speak emergency immediately

4. Playback
   - Speak text
   - Handle completion
   - Play next in queue
```

---

## 18. SOS Emergency Algorithm

**File:** `lib/services/sos_service.dart`

**Algorithm:** Emergency contact notification

**Input:** User SOS activation

**Output:** Call, SMS, and notification

```dart
// Algorithm Steps:
1. Activate
   - State: ACTIVATING
   - Play alert sound
   - Start vibration

2. Location
   - Request permissions
   - Get GPS/network fix
   - Format location URL

3. Call
   - Request CALL_PHONE permission
   - Dial primary contact

4. SMS
   - Request SEND_SMS permission
   - Send location to primary contact

5. Notification
   - Post ongoing notification
   - Show emergency status

6. Reset
   - Cancel all operations
   - Clear notification
   - State: INACTIVE
```
