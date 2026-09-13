import 'dart:ui';

/// A recognized text block with its region expressed in normalized
/// portrait coordinates (0..1 on both axes). The origin is the top-left of
/// the upright portrait frame, which matches the camera preview.
class OcrTextBlock {
  final Rect region;
  final String text;

  const OcrTextBlock({required this.region, required this.text});
}

/// Structured result of a text-recognition pass.
class OcrResult {
  final String text;
  final List<OcrTextBlock> blocks;

  /// Dimensions of the upright portrait source image (pixels), or -1 when the
  /// source dimensions are unknown. Used to align normalized regions with the
  /// displayed snapshot.
  final int imageWidth;
  final int imageHeight;

  const OcrResult({
    required this.text,
    required this.blocks,
    this.imageWidth = -1,
    this.imageHeight = -1,
  });

  const OcrResult.empty()
      : text = '',
        blocks = const [],
        imageWidth = -1,
        imageHeight = -1;

  bool get hasText => text.trim().isNotEmpty;

  int get charCount => text.length;

  double get aspectRatio =>
      imageWidth > 0 && imageHeight > 0 ? imageWidth / imageHeight : 1;
}