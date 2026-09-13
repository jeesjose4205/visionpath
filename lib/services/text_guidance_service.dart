import 'dart:math';
import 'dart:ui';

/// Position of the text relative to the frame, used to pick the next spoken
/// instruction.
enum GuidanceDirection { closer, farther, left, right, up, down }

/// Output of one guidance analysis pass.
class TextGuidance {
  final GuidancePhase phase;
  final GuidanceDirection? direction;

  /// Normalized portrait union of all text-block regions; null when no text
  /// was found in the frame.
  final Rect? region;
  final int blockCount;
  final double coverage;

  const TextGuidance({
    required this.phase,
    this.direction,
    this.region,
    required this.blockCount,
    required this.coverage,
  });

  bool get hasText => region != null && blockCount > 0;
}

/// High-level voice-guidance phase for the positioning assistant.
enum GuidancePhase { searching, moving, holding, ready }

/// Pure Dart text-positioning assistant (no detection here).
///
/// The caller feeds real ML Kit text-block regions (normalized 0..1 portrait)
/// and this service decides, with simple framing rules, whether the text is
/// centered, too close, too far, or stable enough to capture. All thresholds
/// are first-pass constants that can be tuned after device testing — they are
/// deliberately isolated here.
class TextGuidanceService {
  // Framing thresholds, in normalized portrait coordinates.
  static const double _minWidth = 0.30; // below -> text is far away
  static const double _maxWidth = 0.88; // above -> text fills the frame
  static const double _leftEdge = 0.36;
  static const double _rightEdge = 0.64;
  static const double _topEdge = 0.26;
  static const double _bottomEdge = 0.72;

  // Consecutive framed frames required before declaring READY.
  static const int _holdFramesForReady = 5;

  int _holdCount = 0;
  String? _lastSpokenKey;
  Rect? _prevRegion;

  /// Analyze normalized block regions and return the guidance for the frame.
  TextGuidance analyze(List<Rect> regions) {
    final valid = regions
        .where((r) => r.width > 0.001 && r.height > 0.001)
        .toList();

    if (valid.isEmpty) {
      _holdCount = 0;
      _prevRegion = null;
      return const TextGuidance(
        phase: GuidancePhase.searching,
        blockCount: 0,
        coverage: 0,
      );
    }

    var left = 1.0, top = 1.0, right = 0.0, bottom = 0.0;
    for (final r in valid) {
      left = min(left, r.left.clamp(0.0, 1.0));
      top = min(top, r.top.clamp(0.0, 1.0));
      right = max(right, r.right.clamp(0.0, 1.0));
      bottom = max(bottom, r.bottom.clamp(0.0, 1.0));
    }
    // Time-smooth the union region so the live overlay and the centering
    // decisions do not jitter frame-to-frame.
    final rect = _smoothRegion(Rect.fromLTRB(left, top, right, bottom));
    final width = rect.width;
    final status = _moving(
      direction: _pickDirection(rect),
      rect: rect,
      blockCount: valid.length,
    );

    if (status.direction != null) {
      _holdCount = 0;
      return status;
    }

    // Text is centered and reasonably sized: accumulate holding frames.
    _holdCount++;
    final phase = _holdCount >= _holdFramesForReady
        ? GuidancePhase.ready
        : GuidancePhase.holding;
    return TextGuidance(
      phase: phase,
      region: rect,
      blockCount: valid.length,
      coverage: width * rect.height,
    );
  }

  GuidanceDirection? _pickDirection(Rect rect) {
    final width = rect.width;
    final cx = rect.center.dx;
    final cy = rect.center.dy;

    if (width < _minWidth) return GuidanceDirection.closer;
    if (width > _maxWidth) return GuidanceDirection.farther;
    if (cx < _leftEdge) return GuidanceDirection.left;
    if (cx > _rightEdge) return GuidanceDirection.right;
    if (cy < _topEdge) return GuidanceDirection.up;
    if (cy > _bottomEdge) return GuidanceDirection.down;
    return null;
  }

  TextGuidance _moving({
    required GuidanceDirection? direction,
    required Rect rect,
    required int blockCount,
  }) {
    return TextGuidance(
      phase: GuidancePhase.moving,
      direction: direction,
      region: rect,
      blockCount: blockCount,
      coverage: rect.width * rect.height,
    );
  }

  /// Time-smooth the region toward its previous value to damp frame-to-frame
  /// jitter of both the overlay and the centering decisions.
  Rect _smoothRegion(Rect current) {
    final Rect? prev = _prevRegion;
    if (prev == null) {
      _prevRegion = current;
      return current;
    }
    const double s = 0.55;
    final double cx = prev.center.dx * (1 - s) + current.center.dx * s;
    final double cy = prev.center.dy * (1 - s) + current.center.dy * s;
    final double w = prev.width * (1 - s) + current.width * s;
    final double h = prev.height * (1 - s) + current.height * s;
    final Rect smoothed =
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    _prevRegion = smoothed;
    return smoothed;
  }

  /// The voice line to speak for [guidance], or null when the instruction has
  /// not changed since the last announcement (prevents repeat spam).
  String? voiceLineFor(TextGuidance guidance) {
    final String key;
    final String line;

    switch (guidance.phase) {
      case GuidancePhase.searching:
        key = 'searching';
        line = 'No text found. Slowly scan the area.';
        break;
      case GuidancePhase.moving:
        switch (guidance.direction!) {
          case GuidanceDirection.closer:
            key = 'closer';
            line = 'Move closer to the text.';
            break;
          case GuidanceDirection.farther:
            key = 'farther';
            line = 'Move back a little.';
            break;
          case GuidanceDirection.left:
            key = 'left';
            line = 'Move the phone a little to the left.';
            break;
          case GuidanceDirection.right:
            key = 'right';
            line = 'Move the phone a little to the right.';
            break;
          case GuidanceDirection.up:
            key = 'up';
            line = 'Move the phone up.';
            break;
          case GuidanceDirection.down:
            key = 'down';
            line = 'Move the phone down.';
            break;
        }
        break;
      case GuidancePhase.holding:
        key = 'holding';
        line = 'Hold steady.';
        break;
      case GuidancePhase.ready:
        key = 'ready';
        line = 'Ready. Text is perfectly framed.';
        break;
    }

    if (_lastSpokenKey == key) return null;
    _lastSpokenKey = key;
    return line;
  }

  /// Human label used by the status pill.
  String detailFor(TextGuidance guidance) {
    switch (guidance.phase) {
      case GuidancePhase.searching:
        return 'No text found. Slowly scan the area.';
      case GuidancePhase.moving:
        switch (guidance.direction!) {
          case GuidanceDirection.closer:
            return 'Move closer to the text';
          case GuidanceDirection.farther:
            return 'Move back a little';
          case GuidanceDirection.left:
            return 'Move the phone left';
          case GuidanceDirection.right:
            return 'Move the phone right';
          case GuidanceDirection.up:
            return 'Move the phone up';
          case GuidanceDirection.down:
            return 'Move the phone down';
        }
      case GuidancePhase.holding:
        return 'Keep the phone still';
      case GuidancePhase.ready:
        return 'Text is perfectly framed';
    }
  }

  /// Reset the hold counter, region history and the last spoken instruction,
  /// e.g. at the start of a new scan.
  void reset() {
    _holdCount = 0;
    _lastSpokenKey = null;
    _prevRegion = null;
  }
}