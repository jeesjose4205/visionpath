# VisionPath AI - AI/ML Models and Inference

## 1. Machine Learning Models Overview

| Model | File | Type | Size (estimated) | Purpose | Status |
|-------|------|------|------------------|---------|--------|
| ArcFace | arcface_w600k_mbf.tflite | Face embedding | ~10-20 MB | Identity verification | Active |
| SCRFD | scrfd_640.tflite | Face detection | ~15-25 MB | Face localization | Active |
| MobileFaceNet | mobilefacenet.tflite | Face embedding | ~5-10 MB | Alternative embedding | Active |
| YOLO Currency | currency_notes_yolo.tflite | Object detection | ~5-10 MB | Currency detection | Active |
| YOLO Banknote | currency_banknote.tflite | Classifier | ~5-10 MB | Retired classifier | Inactive |
| YOLO Coin | currency_coin.tflite | Classifier | ~5-10 MB | Retired classifier | Inactive |
| Vosk | vosk-model-small-en-us-0.15 | Speech recognition | ~50-100 MB | Offline speech | Active |

## 2. Face Recognition Models

### 2.1 ArcFace (Primary Embedder)

**File:** `assets/ml/arcface_w600k_mbf.tflite`

**Architecture:** MobileFaceNet backbone with ArcFace loss

**Input:** 112x112 RGB face crop (aligned)

**Output:** 512-d L2-normalized embedding vector

**Training:** ArcFace margin-based loss on large-scale face dataset

**Usage:** 
- Face registration (embedding generation)
- Face recognition (cosine similarity matching)
- 12 samples per person for robustness

**Thresholds:**
- Matching threshold: 0.55 (default)
- Ambiguity margin: 0.06

**Implementation:**
```dart
// FaceEmbeddingService
final interp = await Interpreter.fromAsset(_modelAsset);
interp.allocateTensors();
// Input: [1, 112, 112, 3] RGB normalized [0, 1]
// Output: [1, 512] embedding (L2 normalized)
```

### 2.2 MobileFaceNet (Alternative)

**File:** `assets/ml/mobilefacenet.tflite`

**Architecture:** Lightweight face embedding network

**Input:** 112x112 RGB face crop (aligned)

**Output:** 128-d embedding vector

**Usage:**
- Fallback embedding model
- Configurable per registration
- Faster inference than ArcFace

### 2.3 SCRFD (Face Detector)

**File:** `assets/ml/scrfd_640.tflite`

**Architecture:** Sample and Computation Redistribution for Face Detection

**Input:** 640x640 RGBA image (normalized [-1, 1])

**Output:** Multiple feature maps (strides 8, 16, 32)
- Confidence scores
- Bounding box regressions
- 5 facial landmarks

**Features:**
- Multi-scale detection
- Landmark regression
- Efficient computation

**Thresholds:**
- Score threshold: 0.5
- NMS threshold: 0.4

**Implementation:**
```dart
// ScrfdFaceDetector
final interp = await Interpreter.fromAsset(_modelAsset);
// Input: [1, 640, 640, 3] normalized [-1, 1]
// Output: [1, N, 15] (xywh + confidence + 5 keypoints)
```

### 2.4 ML Kit Face Detection (Alternative)

**Library:** `google_mlkit_face_detection: ^0.15.1`

**Features:**
- Accurate mode enabled
- Landmarks enabled (5 points)
- Contours enabled (face outline)

**Output:**
- Bounding box
- 5 landmarks (eyes, nose, mouth corners)
- 1 face contour (dense outline)

**Usage:**
- Primary face detection for Familiar Faces
- Face alignment reference
- Geometric feature extraction

## 3. Object Detection Models

### 3.1 YOLO26n (Object Detection)

**Library:** `ultralytics_yolo: ^0.6.14`

**Architecture:** YOLOv10n (tiny variant)

**Input:** 640x640 RGB image (normalized [0, 1])

**Output:** [1, 84, 8400] tensor
- 84 classes (COCO dataset)
- 8400 anchor boxes
- Format: [x_center, y_center, width, height, class_scores...]

**Classes Supported:** 80 COCO classes including:
- Person
- Vehicle (car, truck, bus, motorcycle, bicycle)
- Furniture (chair, couch, bed, dining table)
- Animals (dog, cat, horse, sheep, cow)
- Electronics (laptop, cell phone)
- And more...

**Thresholds:**
- Confidence threshold: 0.40 (configurable)
- NMS threshold: 0.45 (default)

**Implementation:**
```dart
// ObjectDetectionService
_yolo = YOLO(modelPath: YOLO.defaultOfficialModel());
await _yolo!.loadModel();
// Run inference: _yolo!.predict()
```

### 3.2 Currency Detection (YOLO)

**File:** `assets/ml/currency_notes_yolo.tflite`

**Architecture:** Custom YOLOv10n for currency

**Input:** [1, 640, 640, 3] RGB normalized [0, 1]

**Output:** [1, 300, 6] tensor
- 300 detected objects
- Format: [x_min, y_min, x_max, y_max, confidence, class]

**Classes:**
- Banknote
- Coin

**Implementation:**
```dart
// CurrencyDetector
CurrencyDetector._fromAsset(_modelAsset);
// Input: [1, 640, 640, 3] normalized [0, 1]
// Output: [1, 300, 6] xyxy + conf + cls
```

## 4. OCR Model

### 4.1 ML Kit Text Recognition

**Library:** `google_mlkit_text_recognition: ^0.17.1`

**Features:**
- Latin script support
- Multiple text blocks
- Bounding boxes per block

**Input:** InputImage (camera frame or captured photo)

**Output:** RecognizedText with hierarchy:
- Text blocks
- Lines
- Elements (words/characters)

**Usage:**
- Real-time text reading
- OCR result extraction
- Text region visualization

**Implementation:**
```dart
// OcrService
final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
final recognized = await recognizer.processImage(inputImage);
// Output: RecognizedText with text blocks
```

## 5. Speech Recognition Model

### 5.1 Vosk Offline Speech Recognition

**Library:** `vosk_flutter` (vendored)

**Model:** vosk-model-small-en-us-0.15

**Location:** `assets/models/vosk-model-small-en-us-0.15.zip`

**Architecture:** DeepSpeech2-based speech recognition

**Input:** 16kHz mono audio stream

**Output:** Transcribed text (partial and final)

**Features:**
- Offline operation (no internet required)
- Partial transcriptions while speaking
- Final transcription on release

**Usage:**
- Press-and-hold voice assistant
- Voice commands
- Question answering

**Implementation:**
```dart
// SpeechService
final model = await plugin.createModel(modelPath);
_final recognizer = await plugin.createRecognizer(
  model: model,
  sampleRate: 16000,
);
// Output: Streaming text via onPartial/onResult
```

## 6. Inference Pipeline

### 6.1 Object Detection Pipeline

```
Camera Frame (YUV)
    ↓
YUV to RGB conversion
    ↓
Resize to 640x640 (bilinear)
    ↓
Normalize [0, 1]
    ↓
YOLO26n TFLite Inference
    ↓
Parse output tensor [1, 84, 8400]
    ↓
Apply confidence filter (0.40)
    ↓
Non-Maximum Suppression
    ↓
Extract bounding boxes, classes, confidence
    ↓
Enrich with position (LEFT/CENTER/RIGHT)
    ↓
Enrich with proximity (NEAR/MEDIUM/FAR)
    ↓
Path analysis
    ↓
Navigation decision + spoken message
```

### 6.2 Face Recognition Pipeline

```
Camera Frame (YUV)
    ↓
YUV to RGBA conversion
    ↓
SCRFD Face Detection
    ↓
Extract face crop + landmarks
    ↓
Align face to canonical positions (Umeyama)
    ↓
Crop to 112x112
    ↓
ArcFace TFLite Inference
    ↓
Extract 512-d embedding
    ↓
L2 normalization
    ↓
Compare with registered faces (cosine similarity)
    ↓
Match above threshold (0.95)
    ↓
Temporal confirmation (3 frames)
    ↓
Voice announcement with name
```

### 6.3 Currency Detection Pipeline

```
Camera Frame (YUV)
    ↓
YUV to RGBA conversion
    ↓
Resize to 640x640
    ↓
Normalize [0, 1]
    ↓
Currency YOLO Inference
    ↓
Parse output [1, 300, 6]
    ↓
Apply confidence filter
    ↓
Non-Maximum Suppression
    ↓
Classify: Banknote or Coin
    ↓
Stability verification (multiple frames)
    ↓
Voice announcement with currency type
```

## 7. Model Loading Strategy

### 7.1 Lazy Loading

```dart
// FaceEmbeddingService
Future<bool> ensureLoaded() async {
  if (_ready) return true;
  if (_loadStarted) return false;
  _loadStarted = true;
  try {
    final interp = await Interpreter.fromAsset(_modelAsset);
    interp.allocateTensors();
    _interpreter = interp;
    _ready = true;
    return true;
  } catch (e) {
    _loadError = '$e';
    _ready = false;
    return false;
  } finally {
    _loadStarted = false;
  }
}
```

### 7.2 App Initialization

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load the face-embedding model
  FaceEmbeddingService.instance.ensureLoaded();
  // Load persisted settings
  await SettingsService.instance.load();
  // Load emergency contacts
  await EmergencyContactService.instance.load();
  runApp(const VisionPathApp());
}
```

## 8. Inference Performance

### 8.1 Model Inference Times (approximate)

| Model | Input Size | Time (ms) | Device |
|-------|------------|-----------|--------|
| SCRFD | 640x640 | 50-100 | Modern Android |
| ArcFace | 112x112 | 20-40 | Modern Android |
| YOLO26n | 640x640 | 100-200 | Modern Android |
| Vosk | 16kHz audio | Real-time | Modern Android |
| ML Kit OCR | Varies | 50-150 | Modern Android |

### 8.2 Frame Sampling Rate

| Feature | Sampling Rate | Reason |
|---------|--------------|--------|
| Object Detection | 5 FPS | Balance accuracy and performance |
| Face Recognition | 5 FPS | Same as object detection |
| Depth Estimation | 5 FPS | Consistent with main pipeline |
| OCR Guidance | Continuous | Real-time feedback |

## 9. Model Files and Metadata

### 9.1 Model File Structure

```
assets/ml/
├── arcface_w600k_mbf.tflite       # Face embeddings (512-d)
├── scrfd_640.tflite               # Face detector (640x640)
├── mobilefacenet.tflite           # Alternative embedding
├── currency_notes_yolo.tflite     # Currency detector
├── currency_banknote.tflite       # Retired classifier
├── currency_coin.tflite           # Retired classifier
└── currency_notes_yolo_labels.txt # Class labels

assets/models/
└── vosk-model-small-en-us-0.15.zip # Speech recognition model
```

### 9.2 Model Validation

**Files checked at runtime:**
- Model exists in assets
- Model loads successfully
- Input/output shapes match expectations
- Tensor allocation succeeds

**Error handling:**
- Model load failure: Returns false, logs error
- Inference error: Returns empty results
- Missing model: Returns unavailable status

## 10. Model Updates and Maintenance

### 10.1 Adding New Models

1. Place model file in `assets/ml/`
2. Update `pubspec.yaml` if needed
3. Update model loading code
4. Add model metadata to service
5. Test inference

### 10.2 Model Versioning

- Models stored in `assets/ml/` with descriptive names
- No version tracking (file name is version identifier)
- Update by replacing file in assets

### 10.3 Model Dependencies

```yaml
# pubspec.yaml - No versioned dependencies
# Models are bundled as assets, not package dependencies
```

## 11. Inference Safety

### 11.1 Error Handling

```dart
// ObjectDetectionService
Future<List<DetectedObject>> detect(Uint8List imageBytes) async {
  if (!_isModelLoaded || _yolo == null) {
    return const [];  // Return empty on error
  }
  try {
    final results = await _yolo!.predict(imageBytes);
    return _parseResults(results);
  } catch (e) {
    return const [];  // Return empty on error
  }
}
```

### 11.2 Resource Cleanup

```dart
void dispose() {
  _interpreter?.close();
  _interpreter = null;
  _ready = false;
}
```

## 12. Privacy Considerations

### 12.1 On-Device Processing

- All models run locally
- No data leaves the device
- No cloud API calls
- No telemetry

### 12.2 Data Storage

- Face embeddings stored locally
- No facial images stored (only embeddings)
- No usage analytics
- No external logging

### 12.3 Security

- No API keys or credentials required
- No network access for AI features
- All processing local to device

## 13. Model Configuration

### 13.1 Confidence Thresholds

| Feature | Threshold | Configurable |
|---------|-----------|--------------|
| Object Detection | 0.40 | Yes (settings) |
| Face Detection (SCRFD) | 0.5 | No |
| Face Recognition | 0.95 | Yes (settings) |
| Currency Detection | Default | No |

### 13.2 NMS Thresholds

| Feature | Threshold | Configurable |
|---------|-----------|--------------|
| Object Detection | 0.45 | No (YOLO default) |
| Face Detection (SCRFD) | 0.4 | No |

## 14. Model Limitations

### 14.1 Accuracy

- Face recognition accuracy: ~95% on aligned faces
- Object detection: COCO dataset benchmark
- OCR: ML Kit accuracy on clear text
- Currency: Trained on limited dataset

### 14.2 Performance

- Real-time on modern devices
- May lag on low-end devices
- Battery impact from continuous camera use
- Memory usage: ~100-200 MB peak

### 14.3 Input Requirements

- Face recognition: Requires aligned faces
- Object detection: Optimal at 1-3 meters
- OCR: Requires clear, horizontal text
- Currency: Requires clear, well-lit notes/coins

## 15. Testing and Validation

### 15.1 Unit Tests

| Test File | Coverage |
|-----------|----------|
| scrfd_detector_test.dart | SCRFD inference |
| face_embedding_tensor_test.dart | ArcFace embeddings |
| currency_detector_test.dart | Currency detection |
| face_recognition_test.dart | Face matching |
| face_embedding_alignment_test.dart | Face alignment |

### 15.2 Integration Tests

| Test File | Coverage |
|-----------|----------|
| currency_recognition_service_test.dart | Full recognition pipeline |
| navigate_lifecycle_test.dart | Navigation flow |
| sos_service_test.dart | Emergency flow |

### 15.3 Manual Testing

- Face registration: Multiple poses
- Object detection: Various environments
- OCR: Clear and challenging text
- Currency: Different currencies and conditions

## 16. Model Updates Strategy

### 16.1 Version Management

- Model file name is version identifier
- Replace model file to update
- No version tracking in app

### 16.2 Compatibility

- TFLite models backward compatible
- No code changes for model updates
- Input/output shapes must match

### 16.3 Testing Updates

1. Test new model on sample data
2. Verify output format
3. Check accuracy on known cases
4. Test performance on target devices
