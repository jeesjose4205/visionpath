# VisionPath AI - Glossary of Technical Terms

## 1. Core Concepts

| Term | Definition |
|------|------------|
| **VisionPath AI** | An AI-powered accessibility application for visually impaired users that provides environmental awareness through camera-based object detection, face recognition, text reading, and emergency assistance. |
| **Flutter** | UI framework for building cross-platform applications using Dart. |
| **TFLite (TensorFlow Lite)** | Lightweight TensorFlow implementation for on-device inference. |
| **YOLO (You Only Look Once)** | Real-time object detection algorithm that processes entire image in single pass. |
| **OCR (Optical Character Recognition)** | Technology that extracts text from images. |
| **STT (Speech-to-Text)** | Technology that converts spoken language to text. |
| **TTS (Text-to-Speech)** | Technology that converts text to spoken audio. |
| **TTS** | Text-to-Speech |
| **ML Kit** | Google's on-device machine learning SDK for mobile. |
| **Vosk** | Open-source offline speech recognition engine. |

## 2. Face Recognition Terms

| Term | Definition |
|------|------------|
| **Face Embedding** | Numerical vector representation of facial features (512-d for ArcFace). |
| **Cosine Similarity** | Metric to measure similarity between two vectors (face embeddings). |
| **ArcFace** | Deep learning-based face recognition model using angular margin loss. |
| **SCRFD** | Sample and Computation Redistribution for Face Detection - efficient face detector. |
| **MobileFaceNet** | Lightweight face embedding network for mobile devices. |
| **Face Detection** | Process of locating faces in an image. |
| **Face Recognition** | Process of identifying known faces by comparing embeddings. |
| **Face Registration** | Process of capturing face samples and storing embeddings for later recognition. |
| **Temporal Confirmation** | Technique of confirming face recognition over multiple frames to reduce errors. |
| **Landmarks** | Key facial points (eyes, nose, mouth corners) used for alignment. |

## 3. Object Detection Terms

| Term | Definition |
|------|------------|
| **YOLO26n** | Tiny variant of YOLOv26 object detection model. |
| **Bounding Box** | Rectangle enclosing detected object (x_min, y_min, x_max, y_max). |
| **Confidence Score** | Model's certainty that detection is correct (0-1). |
| **Non-Maximum Suppression (NMS)** | Algorithm to remove duplicate overlapping detections. |
| **Class** | Object category (person, car, chair, etc.). |
| **COCO Dataset** | Common Objects in Context dataset - 80 classes. |

## 4. Navigation Terms

| Term | Definition |
|------|------------|
| **Path Analysis** | Process of determining if walking path is obstructed. |
| **Proximity Level** | Classification of object distance (NEAR, MEDIUM, FAR). |
| **Navigation Decision** | Action recommendation (FORWARD, LEFT, RIGHT, SLOW, STOP). |
| **Depth Estimation** | Process of estimating object distance from camera. |
| **Geometric Depth** | Fallback depth estimation using bounding box size. |
| **Monocular Depth** | Depth estimation from single camera (monocular). |

## 5. Voice Terms

| Term | Definition |
|------|------------|
| **Voice Guidance** | Audio instructions provided to user during navigation. |
| **Press-and-Hold** | Interaction pattern where holding screen triggers voice assistant. |
| **Vosk** | Open-source offline speech recognition engine. |
| **Partial Transcription** | Streaming text while user is still speaking. |
| **Final Transcription** | Complete text after user releases. |
| **TTS Engine** | Software that synthesizes speech from text. |

## 6. Emergency Terms

| Term | Definition |
|------|------------|
| **SOS (Save Our Souls)** | Emergency distress signal system. |
| **Emergency Contact** | Pre-saved contact for emergency notifications. |
| **Location Fix** | Process of determining GPS coordinates. |
| **Call Phone** | Direct phone call without opening dialer. |
| **SMS** | Short Message Service - text messaging. |

## 7. Settings Terms

| Term | Definition |
|------|------------|
| **SharedPreferences** | Simple key-value storage for app settings. |
| **High Contrast** | Enhanced color contrast for low vision users. |
| **Large Text** | Increased text size for better readability. |
| **Haptic Feedback** | Vibration for touch interactions. |
| **Guidance Mode** | Frequency of navigation voice instructions. |
| **Obstacle Sensitivity** | Depth estimation sensitivity adjustment. |

## 8. Currency Terms

| Term | Definition |
|------|------------|
| **Currency Recognition** | Process of identifying money (banknotes and coins). |
| **YOLO Currency** | Custom YOLO model trained for currency detection. |

## 9. Technical Terms

| Term | Definition |
|------|------------|
| **YUV to RGB** | Color space conversion from YUV to Red-Green-Blue. |
| **RGBA** | Red-Green-Blue-Alpha color format with transparency. |
| **TensorFlow Lite** | Lightweight TensorFlow for mobile and embedded. |
| **Flutter TTS** | Flutter plugin for text-to-speech. |
| **Permission Handler** | Flutter plugin for runtime permissions. |
| **ChangeNotifier** | Flutter state management class for reactive updates. |
| **Provider** | Flutter package for dependency injection and state management. |
| **Android Manifest** | Android app configuration file. |
| **AGP (Android Gradle Plugin)** | Build tool for Android projects. |

## 10. Depth Terms

| Term | Definition |
|------|------------|
| **Depth Map** | 2D array where each value represents distance to camera. |
| **Relative Depth** | Depth values normalized to 0-1 range. |
| **Absolute Depth** | Depth values in meters or feet. |
| **Depth Calibration** | Process of converting relative depth to metric units. |
| **Metric Calibration** | Calibration for real-world distance measurement. |

## 11. UI Terms

| Term | Definition |
|------|------------|
| **Title Card** | Overlay covering camera preview until user action. |
| **Carousel** | Horizontal swipe navigation between screens. |
| **Speech Queue** | Sequential queue for speech utterances. |
| **Deduplication** | Preventing repeated voice instructions. |
| **Cooldown** | Minimum time between repeated instructions. |

## 12. Architecture Terms

| Term | Definition |
|------|------------|
| **Provider Pattern** | Flutter state management using dependency injection. |
| **Singleton** | Single instance of a class (NavigationService, SosService). |
| **Lazy Loading** | Loading resources only when needed. |
| **On-Device Inference** | Running ML models on the device without cloud. |
| **Client-Only** | Application that doesn't require backend server. |

## 13. Model Terms

| Term | Definition |
|------|------------|
| **Input Tensor** | Model input data shape (e.g., [1, 112, 112, 3]). |
| **Output Tensor** | Model output data shape (e.g., [1, 512]). |
| **NHWC** | Data format: [Batch, Height, Width, Channels]. |
| **L2 Normalization** | Scaling vector to unit length for cosine similarity. |
| **Margin Loss** | Loss function in face recognition for better separation. |
| **Anchor** | Predefined boxes in YOLO for object prediction. |
| **Stride** | Feature map reduction factor in YOLO. |

## 14. Service Terms

| Term | Definition |
|------|------------|
| **Service** | Business logic class in Flutter (often ChangeNotifier). |
| **Repository** | Data access abstraction layer. |
| **Engine** | Core processing component (LookAndDetectEngine, DepthEngine). |

## 15. Testing Terms

| Term | Definition |
|------|------------|
| **Unit Test** | Test for single function or class. |
| **Widget Test** | Test for UI component. |
| **Integration Test** | Test for multiple components working together. |
| **Mock** | Fake object for testing dependencies. |

## 16. Performance Terms

| Term | Definition |
|------|------------|
| **Frame Rate** | Frames per second (FPS) for camera processing. |
| **5 FPS Sampling** | Processing every 5th frame to reduce CPU. |
| **Latency** | Delay between input and output. |
| **Memory Usage** | RAM consumption by application. |
| **Battery Impact** | Power consumption by feature. |

## 17. Security Terms

| Term | Definition |
|------|------------|
| **SharedPreferences** | Unencrypted local storage (security note). |
| **Runtime Permission** | Permission granted by user at runtime. |
| **App Sandbox** | Android isolation of app data. |
| **On-Device Processing** | No data leaves the device. |

## 18. Platform Terms

| Term | Definition |
|------|------------|
| **Android SDK** | Software development kit for Android. |
| **CameraX** | Android camera library. |
| **TextToSpeech** | Android API for speech synthesis. |
| **LocationManager** | Android API for GPS location. |
| **SmsManager** | Android API for SMS messaging. |

## 19. Data Terms

| Term | Definition |
|------|------------|
| **JSON** | JavaScript Object Notation - data format. |
| **Embedding** | Numerical representation of features. |
| **Vector** | Ordered list of numbers (e.g., 512-d embedding). |
| **Cosine Similarity** | Measure of angle between two vectors. |

## 20. Abbreviations

| Abbreviation | Meaning |
|--------------|---------|
| AI | Artificial Intelligence |
| ML | Machine Learning |
| OCR | Optical Character Recognition |
| STT | Speech-to-Text |
| TTS | Text-to-Speech |
| API | Application Programming Interface |
| GUI | Graphical User Interface |
| GPS | Global Positioning System |
| SMS | Short Message Service |
| NMS | Non-Maximum Suppression |
| YOLO | You Only Look Once |
| TFLite | TensorFlow Lite |
| ML Kit | Machine Learning Kit |
| API | Application Programming Interface |
| UI | User Interface |
| UX | User Experience |
| GPU | Graphics Processing Unit |
| CPU | Central Processing Unit |
| RAM | Random Access Memory |
