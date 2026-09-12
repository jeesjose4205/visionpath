import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

typedef OnFrameAvailable = void Function(CameraImage image);

/// CameraService manages camera lifecycle, initialization, and image streaming.
/// It handles rear camera selection and provides a throttled frame processing callback.
class CameraService with ChangeNotifier {
  CameraDescription? _camera;
  CameraController? _controller;
  bool _isInitializing = false;
  String? _errorMessage;
  bool _isImageStreamActive = false;

  // Frame throttling
  final int _targetFps = 5; // Process approximately 5 frames per second
  int _lastFrameTime = 0;

  // Frame processing callback (for navigation AI)
  OnFrameAvailable? _onFrameAvailable;

  CameraService();

  /// Get the list of available cameras
  Future<List<CameraDescription>> getAvailableCameras() async {
    try {
      return await availableCameras();
    } catch (e) {
      _errorMessage = 'Failed to get cameras: $e';
      notifyListeners();
      return [];
    }
  }

  /// Select the rear/back camera
  Future<bool> selectRearCamera() async {
    try {
      final cameras = await getAvailableCameras();
      if (cameras.isEmpty) {
        _errorMessage = 'No cameras available';
        notifyListeners();
        return false;
      }

      // Select rear camera (back-facing)
      _camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      return true;
    } catch (e) {
      _errorMessage = 'Failed to select rear camera: $e';
      notifyListeners();
      return false;
    }
  }

  /// Initialize the camera controller with appropriate settings
  /// for real-time AI processing
  Future<bool> initializeController() async {
    if (_isInitializing || _controller != null) {
      return _controller?.value.isInitialized ?? false;
    }

    if (_camera == null) {
      if (!await selectRearCamera()) {
        return false;
      }
    }

    _isInitializing = true;
    notifyListeners();

    try {
      _controller = CameraController(
        _camera!,
        ResolutionPreset.medium, // Balanced quality for AI processing
        enableAudio: false, // No audio needed for navigation
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // Start image stream after controller is ready
      if (_onFrameAvailable != null) {
        await _controller!.startImageStream(_processImageStream);
      }

      _isInitializing = false;
      _errorMessage = null;
      _isImageStreamActive = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isInitializing = false;
      _errorMessage = 'Failed to initialize camera: $e';
      _controller?.dispose();
      _controller = null;
      notifyListeners();
      return false;
    }
  }

  /// Process incoming camera frames with throttling
  void _processImageStream(CameraImage image) {
    final currentTime = DateTime.now().microsecondsSinceEpoch;

    // Throttle to approximately target FPS
    if (currentTime - _lastFrameTime > (1000000 / _targetFps)) {
      _lastFrameTime = currentTime;

      // Call the frame processing callback
      _onFrameAvailable?.call(image);
    }
  }

  /// Set the frame processing callback
  void setOnFrameAvailable(OnFrameAvailable callback) {
    _onFrameAvailable = callback;
  }

  /// Start image stream (called when navigation starts)
  Future<bool> startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      if (!await initializeController()) {
        return false;
      }
    }

    if (!_isImageStreamActive) {
      try {
        await _controller!.startImageStream(_processImageStream);
        _isImageStreamActive = true;
        notifyListeners();
        return true;
      } catch (e) {
        _errorMessage = 'Failed to start image stream: $e';
        notifyListeners();
        return false;
      }
    }

    return true;
  }

  /// Stop image stream (called when navigation stops)
  Future<bool> stopImageStream() async {
    if (_isImageStreamActive && _controller != null) {
      try {
        await _controller!.stopImageStream();
        _isImageStreamActive = false;
        notifyListeners();
        return true;
      } catch (e) {
        _errorMessage = 'Failed to stop image stream: $e';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  /// Get the CameraController
  CameraController? get controller => _controller;

  /// Check if camera is initialized
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Check if image stream is active
  bool get isImageStreamActive => _isImageStreamActive;

  /// Get any error message
  String? get errorMessage => _errorMessage;

  /// Check if camera is initializing
  bool get isInitializing => _isInitializing;

  /// Stop the image stream (synchronous, no async operations)
  void _stopImageStreamSync() {
    if (_isImageStreamActive && _controller != null) {
      _controller!.stopImageStream();
      _isImageStreamActive = false;
    }
  }

  /// Dispose the camera controller
  @override
  void dispose() {
    // Synchronously stop image stream (no async operations)
    _stopImageStreamSync();

    // Call super.dispose() immediately before any async cleanup
    super.dispose();

    // Cleanup remaining resources (async is OK here since UI won't update after disposal)
    _controller?.dispose();
    _controller = null;
    _camera = null;
    _errorMessage = null;
    _onFrameAvailable = null;
  }
}

