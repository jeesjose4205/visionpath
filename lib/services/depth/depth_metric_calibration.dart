import 'dart:math' as math;

/// Calibrated conversion from the geometric engine's RELATIVE nearness
/// (0..1, higher = closer) to an ESTIMATED METRIC distance in meters.
///
/// The geometric engine is a monocular prior, not a rangefinder, so there is
/// no way to derive meters from its output alone. This class supplies the
/// missing physical context through a ground-plane-style projection:
///
///   1. Invert the engine's relative-nearness curve back to a "row fraction"
///      below the horizon (see [GeometricDepthEngine._rowNearness]).
///   2. Treat that row as an angle below the optical axis using the camera's
///      vertical field of view.
///   3. Convert the depression angle to ground distance via
///      `distance = height / tan(pitch + angle)`.
///
/// The result is a monotonic, physically-consistent estimate whose absolute
/// scale is set by three user-tunable parameters:
///   - [cameraHeightMeters]  how high the phone is held,
///   - [downwardPitchDegrees] how far the phone is tilted toward the floor,
///   - [verticalFovDegrees]  the camera's vertical field of view.
///
/// This is an ESTIMATE, never a precise measurement. Values beyond
/// [maxDistanceMeters] are rejected so "far" never reads as a confident
/// meter value.
class DepthMetricCalibration {
  final double cameraHeightMeters;
  final double downwardPitchDegrees;
  final double verticalFovDegrees;

  const DepthMetricCalibration({
    this.cameraHeightMeters = 1.5,
    this.downwardPitchDegrees = 20,
    this.verticalFovDegrees = 50,
  });

  /// Constants must mirror [GeometricDepthEngine]: horizon row, boost cap and
  /// the relative-nearness curve exponent.
  static const double _kHorizon = 0.40;
  static const double _kBoostCap = 0.92;
  static const double _kCurve = 1.6;

  /// Distances beyond this are treated as "out of range" and rejected rather
  /// than displayed as implausible meter values.
  static const double maxDistanceMeters = 12.0;

  double get _pitchRad => downwardPitchDegrees * math.pi / 180.0;

  /// Estimated ground distance (meters) for a relative nearness value, or
  /// null when the value is invalid or maps beyond [maxDistanceMeters].
  double? metersFromRelative(double relativeDepth) {
    if (relativeDepth.isNaN || relativeDepth.isInfinite) return null;
    final double v = relativeDepth.clamp(0.0, _kBoostCap);

    // Invert nearness curve -> row fraction below the horizon (0..1).
    final double t = math.pow(v / _kBoostCap, 1.0 / _kCurve).toDouble();
    final double row = _kHorizon + t * (1.0 - _kHorizon);

    // Depression angle of that row below the camera's optical axis.
    final double beta = math.atan(
      (row - 0.5) * 2.0 * math.tan((verticalFovDegrees * math.pi / 180.0) / 2.0),
    );
    final double angle = _pitchRad + beta;
    if (angle <= 0.01) return null;

    final double meters = cameraHeightMeters / math.tan(angle);
    if (meters > maxDistanceMeters) return null;
    if (meters <= 0.05) return null;
    return meters;
  }
}