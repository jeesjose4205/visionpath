import 'dart:typed_data';

/// A decoded, upright RGB frame (row-major, 3 bytes per pixel).
///
/// This is the SAME orientation the YOLO bounding boxes are normalized
/// against: the camera sensor frame after applying the sensor rotation.
/// Depth analysis consumes this exact frame so depth cells and boxes share
/// one consistent coordinate system.
class RgbFrame {
  final Uint8List rgb;

  /// Width in pixels of the upright frame.
  final int width;

  /// Height in pixels of the upright frame.
  final int height;

  const RgbFrame({
    required this.rgb,
    required this.width,
    required this.height,
  });

  /// Expected number of bytes (width * height * 3).
  int get length => width * height * 3;

  /// True when the buffer does not match its declared dimensions.
  bool get isEmpty =>
      width <= 0 ||
      height <= 0 ||
      rgb.length < length;
}