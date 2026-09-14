import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Callback that receives every dispatched camera frame.
typedef OnFrameAvailable = void Function(CameraImage image);

/// CameraService manages the single CameraController used for preview,
/// image streaming, and inference.
///
/// Orientation pipeline (documented):
/// 1. CameraImage is delivered in sensor coordinates. On Android rear cameras
///    the evidence is landscape (1280x720) while the preview/widget is
///    portrait.
/// 2. The plugin auto-rotates the CameraPreview widget so it is upright in
///    portrait. We do NOT apply a blind Transform.rotate.
/// 3. [imageRotationQuarterTurns] reports the clockwise quarter-turns needed to
///    rotate a captured frame to match the upright portrait preview; the
///    inference service applies that rotation to the model input so detection
///    coordinates share the preview's orientation.
class CameraService with ChangeNotifier {
  CameraDescription? _camera;
  CameraController? _controller;
  bool _isInitializing = false;
  String? _errorMessage;
  bool _isImageStreamActive = false;

  // Frame throttling (~5 FPS sampling for inference)
  final int _targetFps = 5;
  int _lastFrameTime = 0;
  int _framesReceived = 0;
  int _framesDispatched = 0;

  // Frame processing callback (for navigation AI)
  OnFrameAvailable? _onFrameAvailable;

  // Latest CameraImage for inference
  CameraImage? _latestImage;

  // Watchdog to detect a started-but-silent image stream.
  Timer? _streamWatchdog;

  // True while an async stop is in flight. Guards the start/stop race: a
  // screen that calls startImageStream() right after another screen disposed
  // must wait for the outstanding stop to finish instead of reading the stale
  // "active" flag and never actually starting the stream.
  bool _stopInFlight = false;

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

      // Prefer the back-facing camera, fall back to the first available.
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

  /// Initialize the single CameraController. The image stream is NOT started
  /// here; call [startImageStream] after setting the frame callback so the
  /// callback-linkage can never be missed.
  Future<bool> initializeController() async {
    print('CAMERA_INIT_START');

    if (_controller != null && _controller!.value.isInitialized) {
      print('CAMERA_INIT_ALREADY_INITIALIZED');
      return true;
    }

    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _controller?.value.isInitialized ?? false;
    }

    if (_camera == null && !await selectRearCamera()) {
      _errorMessage = 'No rear camera available.';
      notifyListeners();
      return false;
    }

    _isInitializing = true;
    notifyListeners();

    try {
      _controller = CameraController(
        _camera!,
        ResolutionPreset.medium, // Balanced quality for AI processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // YUV required by converter
      );

      await _controller!.initialize();
      print('CAMERA_INIT_SUCCESS');
      print('CAMERA_SENSOR_ORIENTATION: ${_controller!.description.sensorOrientation}');
      print('CAMERA_PREVIEW_SIZE: ${_controller!.value.previewSize}');
      print('CAMERA_IMAGE_ROTATION_QUARTER_TURNS: $imageRotationQuarterTurns');

      _isInitializing = false;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      print('CAMERA_INIT_FAILED: $e');
      _isInitializing = false;
      _errorMessage = 'Failed to initialize camera: $e';
      _controller?.dispose();
      _controller = null;
      notifyListeners();
      return false;
    }
  }

  /// The image-stream callback installed on the CameraController.
  ///
  /// IMPORTANT: The body is fully guarded. camera 0.12.1 subscribes to the
  /// frame stream without an error handler; any exception escaping here
  /// silently kills the stream and frames stop arriving forever.
  void _processImageStream(CameraImage image) {
    try {
      print('CAMERA_CONTROLLER_FRAME_RECEIVED');
      print('FRAME_PROCESSOR_ENTERED');

      _framesReceived++;
      print('FRAME_CALLBACK_RECEIVED');
      print('FRAME_WIDTH: ${image.width}');
      print('FRAME_HEIGHT: ${image.height}');
      print('FRAME_FORMAT: ${image.format.group}');

      // Always keep the latest frame, throttled or not, so inference never
      // sees a stale/null frame while the camera is producing.
      _latestImage = image;

      final int now = DateTime.now().microsecondsSinceEpoch;

      if (now - _lastFrameTime > (1000000 / _targetFps)) {
        _lastFrameTime = now;
        _framesDispatched++;

        print('FRAME_CALLBACK_DISPATCH: framesReceived=$_framesReceived');
        _onFrameAvailable?.call(image);
      } else {
        print('FRAME_CALLBACK_THROTTLED');
      }
    } catch (e, stack) {
      // Never let errors escape the stream callback.
      print('FRAME_CALLBACK_ERROR: $e');
      print('FRAME_CALLBACK_ERROR_STACK: $stack');
    }
  }

  /// Number of camera frames delivered since stream start.
  int get framesReceived => _framesReceived;

  /// Number of frames dispatched to the navigation callback (post-throttle).
  int get framesDispatched => _framesDispatched;

  /// Get the latest CameraImage for inference.
  CameraImage? get latestImage => _latestImage;

  /// Number of 90-degree clockwise quarter-turns required to orient a captured
  /// frame upright in portrait for this camera. Source => transformation:
  /// sensor orientation (90 on most rear cameras) => rotation in inference.
  int get imageRotationQuarterTurns {
    final int sensorOrientation =
        _controller?.description.sensorOrientation ?? 90;
    return ((sensorOrientation % 360) / 90).round() % 4;
  }

  /// Set the frame processing callback.
  void setOnFrameAvailable(OnFrameAvailable callback) {
    _onFrameAvailable = callback;
  }

  /// Start the image stream. Safe to call multiple times; only acts when the
  /// stream is not already active.
  Future<bool> startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      final bool ok = await initializeController();
      if (!ok) return false;
    }

    // A previous screen may have fired an async stopImageStream() that is
    // still draining. Wait for it so the platform stream is not silently
    // killed by a concurrent stop right after this start returns.
    while (_stopInFlight) {
      await Future.delayed(const Duration(milliseconds: 25));
    }

    // Keep our bookkeeping in sync with the camera package state.
    if (_controller!.value.isStreamingImages) {
      _isImageStreamActive = true;
      print('CAMERA_STREAM_ALREADY_ACTIVE');
      _armWatchdog();
      return true;
    }

    try {
      print('CAMERA_STREAM_START');
      await _controller!.startImageStream(_processImageStream);
      _isImageStreamActive = true;
      print('CAMERA_STREAM_STARTED');
      _armWatchdog();
      notifyListeners();
      return true;
    } catch (e) {
      print('CAMERA_STREAM_START_FAILED: $e');
      _errorMessage = 'Failed to start image stream: $e';
      _isImageStreamActive = false;
      notifyListeners();
      return false;
    }
  }

  /// Stop the image stream. Safe to call multiple times.
  Future<bool> stopImageStream() async {
    _streamWatchdog?.cancel();
    _streamWatchdog = null;

    if (_controller == null || !_controller!.value.isInitialized) {
      _isImageStreamActive = false;
      _stopInFlight = false;
      return true;
    }

    // Clear the active flag immediately so a concurrent startImageStream()
    // cannot short-circuit on the stale flag while this stop is in flight.
    _isImageStreamActive = false;
    _stopInFlight = true;

    // Only invoke the platform stop when the stream is actually streaming.
    if (_controller!.value.isStreamingImages) {
      try {
        print('CAMERA_STREAM_STOP');
        await _controller!.stopImageStream();
        print('CAMERA_STREAM_STOPPED');
        notifyListeners();
        return true;
      } catch (e) {
        print('CAMERA_STREAM_STOP_FAILED: $e');
        notifyListeners();
        return false;
      } finally {
        _stopInFlight = false;
      }
    }

    _stopInFlight = false;
    return true;
  }

  /// Watchdog: if a stream is active but no frames arrive within 3 seconds,
  /// log it loudly so the "latestCameraImage stays null" case is diagnosable.
  void _armWatchdog() {
    _streamWatchdog?.cancel();
    _streamWatchdog = Timer(const Duration(seconds: 3), () {
      if (_isImageStreamActive && _framesReceived == 0) {
        print('CAMERA_STREAM_NO_FRAMES: 0 frames received in 3s after start.');
        _errorMessage = 'Camera is streaming but no frames were received.';
        notifyListeners();
      } else if (_isImageStreamActive) {
        print('CAMERA_STREAM_HEARTBEAT: frames=${_framesReceived} dispatched=${_framesDispatched}');
      }
    });
  }

  /// Get the CameraController for the preview widget.
  CameraController? get controller => _controller;

  /// Check if camera is initialized.
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Check if image stream is active.
  bool get isImageStreamActive => _isImageStreamActive;

  /// Get any error message.
  String? get errorMessage => _errorMessage;

  /// Check if camera is initializing.
  bool get isInitializing => _isInitializing;

  /// Stop the image stream synchronously (used during teardown).
  void _stopImageStreamSync() {
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    if (_isImageStreamActive && _controller != null) {
      // Fire-and-forget; the stream may already be stopped.
      unawaited(_controller!.stopImageStream().catchError((dynamic _) {}));
      _isImageStreamActive = false;
    }
  }

  /// Dispose camera resources.
  @override
  void dispose() {
    _stopImageStreamSync();
    _controller?.dispose();
    _controller = null;
    _camera = null;
    _errorMessage = null;
    _onFrameAvailable = null;
    _latestImage = null;
    super.dispose();
  }
}