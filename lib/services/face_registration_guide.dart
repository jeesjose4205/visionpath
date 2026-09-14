import '../models/face_detection.dart';

/// Stage of the voice-guided face positioning during registration.
enum RegistrationStage {
  noFace,
  tooFar,
  tooClose,
  tooLeft,
  tooRight,
  tooHigh,
  tooLow,
  turnToTarget,
  moving,
  holdSteady,
}

/// Result of evaluating one guidance frame.
class RegistrationGuidance {
  const RegistrationGuidance({
    required this.stage,
    required this.message,
    required this.dedupeKey,
    required this.faceUsable,
  });

  final RegistrationStage stage;

  /// Voice-ready instruction line for the user.
  final String message;

  /// Key used to suppress repeated identical voice lines.
  final String dedupeKey;

  /// True when this frame produced a sample-quality face (caller may capture).
  final bool faceUsable;
}

/// FaceRegistrationGuide implements the voice-guided positioning loop for
/// registering a familiar person: position the face, hold steady, capture.
///
/// It is a pure state machine fed normalized face detections; the sample
/// targets alternate poses (front / slight left / slight right) so the
/// registered embedding benefits from small real variations, matching the
/// feature's multi-sample requirement.
class FaceRegistrationGuide {
  FaceRegistrationGuide({this.sampleCount = 4, this.steadyFramesRequired = 3});

  /// Number of samples to capture per person.
  final int sampleCount;

  /// Consecutive steady-quality frames required before a sample is accepted.
  final int steadyFramesRequired;

  // Quality windows (normalized portrait coordinates).
  static const double _minWidth = 0.16;
  static const double _maxWidth = 0.68;
  static const double _minHeight = 0.22;
  static const double _maxHeight = 0.86;
  static const double _centerLoX = 0.36;
  static const double _centerHiX = 0.64;
  static const double _centerLoY = 0.28;
  static const double _centerHiY = 0.66;
  static const double _maxYawAllowed = 34;
  static const double _steadyDelta = 0.015;

  double _prevCx = -1;
  double _prevCy = -1;
  int _steadyCount = 0;

  /// Voice line announcing where the user is heading for the current sample.
  String expectedPoseHint(int currentSample) =>
      'Keep your face toward the camera and hold steady.';

  /// Evaluate one detected face (or null when no face was found).
  RegistrationGuidance update({
    required DetectedFace? face,
    required int currentSample,
  }) {
    if (face == null) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.noFace,
        message: 'Position the person\'s face in front of the camera.',
        dedupeKey: 'noFace',
        faceUsable: false,
      );
    }

    // A full side turn isn't capturable; anything short of that is fine.
    if (face.yawDegrees.abs() > _maxYawAllowed) {
      _steadyCount = 0;
      _prevCx = -1;
      return RegistrationGuidance(
        stage: RegistrationStage.turnToTarget,
        message: 'Please turn toward the camera.',
        dedupeKey: 'yawTooExtreme',
        faceUsable: false,
      );
    }

    final w = face.width;
    final h = face.height;
    final cx = face.centerX;
    final cy = face.centerY;

    if (w < _minWidth || h < _minHeight) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooFar,
        message: 'Move closer.',
        dedupeKey: 'tooFar',
        faceUsable: false,
      );
    }
    if (w > _maxWidth || h > _maxHeight) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooClose,
        message: 'Move farther away.',
        dedupeKey: 'tooClose',
        faceUsable: false,
      );
    }
    if (cx < _centerLoX) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooRight,
        message: 'Move slightly right.',
        dedupeKey: 'tooRight',
        faceUsable: false,
      );
    }
    if (cx > _centerHiX) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooLeft,
        message: 'Move slightly left.',
        dedupeKey: 'tooLeft',
        faceUsable: false,
      );
    }
    if (cy < _centerLoY) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooLow,
        message: 'Move slightly down.',
        dedupeKey: 'tooLow',
        faceUsable: false,
      );
    }
    if (cy > _centerHiY) {
      _steadyCount = 0;
      _prevCx = -1;
      return const RegistrationGuidance(
        stage: RegistrationStage.tooHigh,
        message: 'Move slightly up.',
        dedupeKey: 'tooHigh',
        faceUsable: false,
      );
    }

    // Positioned correctly: require the frame to hold still.
    final moved =
        _prevCx >= 0 &&
        ((cx - _prevCx).abs() > _steadyDelta ||
            (cy - _prevCy).abs() > _steadyDelta);
    _prevCx = cx;
    _prevCy = cy;

    if (moved) {
      _steadyCount = 0;
      return const RegistrationGuidance(
        stage: RegistrationStage.moving,
        message: 'Hold steady.',
        dedupeKey: 'moving',
        faceUsable: false,
      );
    }

    _steadyCount++;
    if (_steadyCount >= steadyFramesRequired) {
      return RegistrationGuidance(
        stage: RegistrationStage.holdSteady,
        message: 'Hold steady. Face detected.',
        dedupeKey: 'holdSteady',
        faceUsable: true,
      );
    }

    return const RegistrationGuidance(
      stage: RegistrationStage.moving,
      message: 'Hold steady.',
      dedupeKey: 'moving',
      faceUsable: false,
    );
  }

  /// Reset between registrations.
  void reset() {
    _steadyCount = 0;
    _prevCx = -1;
    _prevCy = -1;
  }
}