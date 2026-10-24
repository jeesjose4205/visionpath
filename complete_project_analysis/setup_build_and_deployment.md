# VisionPath AI - Setup, Build, and Deployment

## 1. Prerequisites

### 1.1 Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Flutter SDK | ^3.13.3 | UI framework, build tooling |
| Dart SDK | ^3.13.3 | Programming language |
| Android Studio | Latest | IDE and Android SDK |
| JDK | 17+ | Java compilation |
| Android SDK | API 21+ | Android platform |
| Android NDK | Flutter default | Native code compilation |

### 1.2 Optional Software

| Software | Purpose |
|----------|---------|
| VS Code | Alternative IDE |
| IntelliJ IDEA | Alternative IDE |
| Git | Version control |
| uv/uvx | MCP server execution (if configured) |

---

## 2. Development Environment Setup

### 2.1 Flutter Setup

```bash
# Install Flutter SDK
# Download from: https://flutter.dev/docs/get-started/install

# Verify installation
flutter doctor

# Update Flutter
flutter upgrade
```

### 2.2 Android Setup

```bash
# Accept Android licenses
flutter doctor --android-licenses

# Verify Android setup
flutter doctor
```

### 2.3 Dependency Installation

```bash
# Install Flutter dependencies
flutter pub get

# Verify dependencies
flutter pub deps
```

---

## 3. Build Commands

### 3.1 Debug Build

```bash
# Build debug APK
flutter build apk --debug

# Build debug AAB
flutter build appbundle --debug

# Run on connected device
flutter run
```

### 3.2 Release Build

```bash
# Build release APK
flutter build apk --release

# Build release AAB
flutter build appbundle --release

# Build release bundle
flutter build appbundle --release --no-sound-null-safety
```

### 3.3 Platform-Specific Builds

```bash
# Android release APK (single APK)
flutter build apk --release --target-platform android-arm64

# Split APKs by ABI
flutter build apk --release --split-per-abi
```

---

## 4. Build Configuration

### 4.1 pubspec.yaml Dependencies

```yaml
dependencies:
  shared_preferences: ^2.5.3
  camera: ^0.12.0
  provider: ^6.1.2
  ultralytics_yolo: ^0.6.14
  flutter_tts: ^4.2.5
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  url_launcher: ^6.3.2
  google_mlkit_text_recognition: ^0.17.1
  google_mlkit_face_detection: ^0.15.1
  tflite_flutter: ^0.12.1
  package_info_plus: ^8.0.0
  vosk_flutter:
    path: third_party/vosk_flutter
  permission_handler: 10.2.0
  flutter_inappwebview: ^6.1.5
  vibration: ^3.2.1
```

### 4.2 Dependency Overrides

```yaml
dependency_overrides:
  permission_handler: 11.3.1
  flutter_inappwebview_android:
    path: third_party/flutter_inappwebview_android
```

**Reason:** AGP 9 compatibility issues with old permission_handler and flutter_inappwebview_android.

---

## 5. Gradle Configuration

### 5.1 android/app/build.gradle.kts

```kotlin
android {
    namespace = "com.example.visionpath"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.visionpath"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// TFLite conflict resolution
configurations.all {
    exclude(group = "com.google.ai.edge.litert", module = "litert-api")
}
```

---

## 6. Asset Packaging

### 6.1 Assets Configuration

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/ml/
    - assets/models/vosk-model-small-en-us-0.15.zip
```

### 6.2 Asset Files

| File | Size (estimated) | Purpose |
|------|-----------------|---------|
| assets/ml/ | ~100-200 MB | All TFLite models |
| assets/models/ | ~50-100 MB | Vosk speech model |

**Note:** Assets are bundled into APK and loaded at runtime.

---

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

### 7.2 Preloading on App Start

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FaceEmbeddingService.instance.ensureLoaded();
  await SettingsService.instance.load();
  await EmergencyContactService.instance.load();
  runApp(const VisionPathApp());
}
```

---

## 8. Release Configuration

### 8.1 Signing Configuration

```kotlin
// Default configuration uses debug signing
// For production, add release signing config
signingConfigs {
    release {
        keyAlias = 'keyAlias'
        keyPassword = 'keyPassword'
        storeFile = file('keystore.jks')
        storePassword = 'storePassword'
    }
}
```

### 8.2 ProGuard Rules

**Note:** No ProGuard rules file exists. The vendored flutter_inappwebview_android has been fixed to not reference the removed `proguard-android.txt`.

---

## 9. Deployment

### 9.1 Manual Deployment

```bash
# Build release APK
flutter build apk --release

# Install on device
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 9.2 Distribution

| Platform | Method | Status |
|----------|--------|--------|
| Google Play Store | AAB upload | Ready |
| Direct APK | APK file | Ready |
| Enterprise | APK file | Ready |

---

## 10. Build Variants

### 10.1 Debug

```bash
flutter build apk --debug
```

- Includes debug symbols
- Slower performance
- Enables DevTools
- For development/testing

### 10.2 Release

```bash
flutter build apk --release
```

- No debug symbols
- Optimized performance
- For production

### 10.3 Profile

```bash
flutter build apk --profile
```

- For performance profiling
- Includes some debug info

---

## 11. Troubleshooting

### 11.1 Common Build Issues

| Issue | Solution |
|-------|----------|
| Missing Android SDK | Run `flutter doctor --android-licenses` |
| Gradle version mismatch | Update Android Studio |
| Dependency conflicts | Check dependency_overrides in pubspec.yaml |
| TFLite conflicts | Verify exclude rules in build.gradle.kts |

### 11.2 Clean Build

```bash
# Clean build artifacts
flutter clean

# Reinstall dependencies
flutter pub get

# Rebuild
flutter build apk --release
```

---

## 12. Build Output Structure

```
build/
├── app/
│   └── outputs/
│       ├── flutter-apk/
│       │   ├── app-debug.apk
│       │   └── app-release.apk
│       ├── flutter-bundle/
│       └── app-bundle/
│           └── app-release.aab
├── dart-tool/
└── flutter_build/
```

---

## 13. Version Information

### 13.1 App Version

```yaml
# pubspec.yaml
version: 1.0.0+1
```

- Version code: 1
- Version name: 1.0.0

### 13.2 Platform Versions

| Component | Version |
|-----------|---------|
| Android minSdk | Flutter default (API 21+) |
| Android targetSdk | Flutter default |
| Android compileSdk | Flutter default |
| Java | 17 |
| Kotlin | JVM 17 |

---

## 14. Configuration Files

### 14.1 Required Files

| File | Purpose |
|------|---------|
| pubspec.yaml | Dependencies, assets, version |
| analysis_options.yaml | Dart analysis rules |
| android/app/build.gradle.kts | Android build config |
| android/app/src/main/AndroidManifest.xml | App manifest |
| android/gradle/wrapper/gradle-wrapper.properties | Gradle wrapper |

### 14.2 Optional Files

| File | Purpose |
|------|---------|
| flutter_01.log | Flutter execution log |
| .metadata | Flutter project metadata |

---

## 15. CI/CD Considerations

### 15.1 Not Configured

| Component | Status |
|-----------|--------|
| CI Pipeline | Not configured |
| Automated tests | Manual |
| Automated builds | Manual |

### 15.2 Recommendations

1. **GitHub Actions** for CI/CD
2. **Automated test execution**
3. **Automated APK/AAB builds**
4. **Code quality reporting**

---

## 16. Summary

VisionPath AI build setup includes:

- **Flutter SDK ^3.13.3** as core framework
- **Android API 21+** as minimum target
- **Java 17** and **Kotlin JVM 17**
- **Dependency overrides** for AGP 9 compatibility
- **Asset bundling** for TFLite models and Vosk model
- **Lazy loading** for ML models
- **Manual deployment** via APK or AAB

Build commands:
```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```
