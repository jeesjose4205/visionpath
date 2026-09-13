import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:camera/camera.dart';

import '../models/detected_object.dart';

/// ObjectDetectionService wraps the ultralytics_yolo plugin for YOLO26n inference.
/// It manages model loading, inference on CameraImage frames, and result processing.
class ObjectDetectionService with ChangeNotifier {
  YOLO? _yolo;
  bool _isInitializing = false;
  bool _isModelLoaded = false;
  String? _errorMessage;
  List<DetectedObject> _currentObjects = [];
  double _confidenceThreshold = 0.40;

  ObjectDetectionService();

  /// Confidence threshold for accepting detections (0.0-1.0).
  double get confidenceThreshold => _confidenceThreshold;

  /// Update the confidence threshold. Valid range 0.0-1.0.
  set confidenceThreshold(double value) {
    _confidenceThreshold = value.clamp(0.0, 1.0);
  }

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  /// Check if model is initializing
  bool get isInitializing => _isInitializing;

  /// Get any error message
  String? get errorMessage => _errorMessage;

  /// Get current detected objects (with position info)
  List<DetectedObject> get currentResults => _currentObjects;

  /// Load the YOLO26n model
  Future<bool> initialize() async {
    if (_isModelLoaded) return true;

    if (_isInitializing) {
      // Wait for initialization to complete
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isModelLoaded;
    }

    _isInitializing = true;

    try {
      // Load official YOLO26n model
      final modelId = YOLO.defaultOfficialModel() ?? 'yolo26n';
      print('YOLO_MODEL_ID: $modelId');
      _yolo = YOLO(modelPath: modelId);
      await _yolo!.loadModel();

      _isModelLoaded = true;
      _errorMessage = null;
      _isInitializing = false;
      print('YOLO_MODEL_INITIALIZED');
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _isModelLoaded = false;
      _errorMessage = 'Failed to load model: $e';
      _isInitializing = false;
      print('YOLO_MODEL_INIT_FAILED: $e');
      notifyListeners();
      return false;
    }
  }

  /// Run inference on image bytes
  Future<List<DetectedObject>> detect(Uint8List imageBytes) async {
    print('YOLO_INFERENCE_START');

    if (!_isModelLoaded || _yolo == null) {
      print('YOLO_MODEL_NOT_LOADED');
      return [];
    }

    try {
      print('YOLO_PREDICT_START');
      final results = await _yolo!.predict(
        imageBytes,
        confidenceThreshold: _confidenceThreshold,
      );

      print('YOLO_PREDICT_RETURNED');
      print('YOLO_RESULT_TYPE: ${results.runtimeType}; keys=${results.keys.toList()}');

      final objects = <DetectedObject>[];

      if (results.containsKey('detections')) {
        final detections = results['detections'];
        if (detections is List) {
          print('YOLO_RESULT_COUNT: ${detections.length}');
          for (int i = 0; i < detections.length; i++) {
            final d = detections[i];
            if (d is Map<String, dynamic>) {
              final className = d['className'] as String? ?? 'unknown';
              final confidence = (d['confidence'] as num?)?.toDouble() ?? 0.0;

              Rect normalizedRect = Rect.zero;
              final normBox = d['normalizedBox'];
              if (normBox is Map<String, dynamic>) {
                normalizedRect = Rect.fromLTRB(
                  (normBox['left'] as num?)?.toDouble() ?? 0.0,
                  (normBox['top'] as num?)?.toDouble() ?? 0.0,
                  (normBox['right'] as num?)?.toDouble() ?? 0.0,
                  (normBox['bottom'] as num?)?.toDouble() ?? 0.0,
                );
              }

              print('DETECTED_CLASS: $className');
              print('DETECTED_CONFIDENCE: ${(confidence * 100).toInt()}%');
              print('DETECTED_NORMALIZED_BOX: $normalizedRect');

              objects.add(DetectedObject(
                className: className,
                confidence: confidence,
                boundingBox: normalizedRect,
              ));
              print('OBJECT_MODEL_CREATED: $className');
            } else {
              print('YOLO_DETECTION_UNEXPECTED_TYPE: ${d.runtimeType}');
            }
          }
        } else {
          print('YOLO_DETECTIONS_UNEXPECTED_TYPE: ${detections.runtimeType}');
        }
      } else {
        print('YOLO_RESULT_KEYS_NO_DETECTIONS: ${results.keys.toList()}');
      }

      print('OVERLAY_OBJECT_COUNT: ${objects.length}');

      _currentObjects = objects;
      notifyListeners();

      return _currentObjects;
    } catch (e, stack) {
      print('YOLO_INFERENCE_ERROR: $e');
      print('YOLO_INFERENCE_STACK: $stack');
      return [];
    }
  }

  /// Run inference on CameraImage
  Future<List<DetectedObject>> detectCameraImage(
    CameraImage image, {
    int inputRotationQuarterTurns = 0,
  }) async {
    print('INFERENCE_START');
    print('INFERENCE_IMAGE_SIZE: ${image.width}x${image.height}');
    print('FRAME_INPUT_ROTATION_QUARTER_TURNS: $inputRotationQuarterTurns');

    final bytes = await _convertCameraImageToBytes(
      image,
      inputRotationQuarterTurns: inputRotationQuarterTurns,
    );
    if (bytes == null) {
      print('INFERENCE_CONVERSION_FAILED');
      return [];
    }

    print('INFERENCE_BYTES_SIZE: ${bytes.length}');

    final results = await detect(bytes);
    print('INFERENCE_RESULTS_COUNT: ${results.length}');
    return results;
  }

  /// Convert CameraImage to decodable model input bytes.
  ///
  /// The ultralytics_yolo native side decodes the bytes with
  /// BitmapFactory.decodeByteArray, which only accepts encoded images
  /// (JPEG/PNG/WebP/BMP). Raw RGB is not decodable and caused predict() to
  /// fail silently. The frame is therefore encoded as PNG before inference.
  Future<Uint8List?> _convertCameraImageToBytes(
    CameraImage image, {
    int inputRotationQuarterTurns = 0,
  }) async {
    if (image.format.group != ImageFormatGroup.yuv420) {
      print('YUV_FORMAT_UNEXPECTED: ${image.format.group}');
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    // Convert YUV to RGB
    final width = image.width;
    final height = image.height;
    final rgbBytes = Uint8List(width * height * 3);

    int rgbIndex = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yValue = yPlane.bytes[y * yPlane.bytesPerRow + x];
        final int uvX = x ~/ 2;
        final int uvY = y ~/ 2;

        final int uValue = uPlane.bytes[uvY * uPlane.bytesPerRow + uvX] - 128;
        final int vValue = vPlane.bytes[uvY * vPlane.bytesPerRow + uvX] - 128;

        final int r = (yValue + 1.370705 * vValue).toInt().clamp(0, 255);
        final int g = (yValue - 0.337633 * uValue - 0.698001 * vValue).toInt().clamp(0, 255);
        final int b = (yValue + 1.732446 * uValue).toInt().clamp(0, 255);

        rgbBytes[rgbIndex++] = r;
        rgbBytes[rgbIndex++] = g;
        rgbBytes[rgbIndex++] = b;
      }
    }

    int rgbWidth = width;
    int rgbHeight = height;
    Uint8List rgb = rgbBytes;
    final int turns = inputRotationQuarterTurns % 4;

    // Rotate the RGB frame so the model input matches the upright preview
    // orientation. Quarter turns are clockwise. Documented transform:
    //   source: CameraImage WxH in sensor coordinates (landscape on Android
    //           rear cameras, sensorOrientation=90 -> 1 quarter turn CW)
    //   rotation: turns * 90deg clockwise
    //   result: portrait frame with dimensions swapped when turns is odd.
    if (turns != 0) {
      rgb = _rotateRgbCw(rgbBytes, width, height, turns);
      if (turns % 2 == 1) {
        rgbWidth = height;
        rgbHeight = width;
      }
      print('YOLO_ROTATED_INPUT_SIZE: ${rgbWidth}x$rgbHeight');
    }

    // Pad RGB -> RGBA so the frame can be handed to the engine as a pixels
    // buffer, then encode PNG for the native BitmapFactory decoder.
    final Uint8List rgba = Uint8List(rgbWidth * rgbHeight * 4);
    for (int i = 0, j = 0; i < rgb.length; i += 3, j += 4) {
      rgba[j] = rgb[i];
      rgba[j + 1] = rgb[i + 1];
      rgba[j + 2] = rgb[i + 2];
      rgba[j + 3] = 255;
    }

    final Completer<ui.Image> completer = Completer<ui.Image>();
    try {
      ui.decodeImageFromPixels(
        rgba,
        rgbWidth,
        rgbHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
    } catch (e) {
      print('YOLO_ENCODE_DECODE_FAILED: $e');
      return null;
    }

    final ui.Image uiImage = await completer.future;
    final ByteData? pngData =
        await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();

    if (pngData == null) {
      print('YOLO_ENCODE_FAILED: null png data');
      return null;
    }
    return pngData.buffer.asUint8List();
  }

  /// Rotates a row-major RGB byte buffer [quarterTurns] times clockwise.
  ///
  /// A single 90-degree clockwise rotation maps (x, y) -> (height - 1 - y, x)
  /// and swaps the buffer dimensions. The number of turns is applied
  /// cumulatively onto the buffer produced by the previous turn.
  Uint8List _rotateRgbCw(
    Uint8List rgb,
    int width,
    int height,
    int quarterTurns,
  ) {
    var bytes = rgb;
    var w = width;
    var h = height;

    for (var turn = 0; turn < quarterTurns % 4; turn++) {
      final inWidth = w;
      final inHeight = h;
      final rotated = Uint8List(inWidth * inHeight * 3);

      for (var y = 0; y < inHeight; y++) {
        for (var x = 0; x < inWidth; x++) {
          final src = (y * inWidth + x) * 3;

          final dx = inHeight - 1 - y;
          final dy = x;
          final dst = (dy * inHeight + dx) * 3;

          rotated[dst] = bytes[src];
          rotated[dst + 1] = bytes[src + 1];
          rotated[dst + 2] = bytes[src + 2];
        }
      }

      w = inHeight;
      h = inWidth;
      bytes = rotated;
    }

    return bytes;
  }

  /// Clear current results
  void clearResults() {
    _currentObjects.clear();
    notifyListeners();
  }

  /// Stop inference (clears current results)
  void stop() {
    clearResults();
  }

  /// Dispose resources
  @override
  void dispose() {
    _currentObjects.clear();
    _yolo = null;
    _isModelLoaded = false;
    _errorMessage = null;
    super.dispose();
  }
}
