import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/detected_object.dart';

/// DetectionOverlay draws bounding boxes and labels on the camera preview.
class DetectionOverlay extends StatelessWidget {
  /// The camera preview size
  final Size previewSize;

  /// Size of the upright-frame the normalized [DetectedObject] boxes are
  /// relative to, in DISPLAY space (matches what the preview shows; see
  /// [camera_preview_fit.dart]'s displayPreviewSize). When null, falls back to
  /// the rotated [previewSize].
  final Size? inputSize;

  /// Detected objects to draw
  final List<DetectedObject> results;

  /// Show the confidence percentage on the label (default true).
  final bool showConfidence;

  /// Append the horizontal position (LEFT / CENTER / RIGHT) to the label.
  final bool showPosition;

  /// Create a DetectionOverlay
  const DetectionOverlay({
    required this.previewSize,
    this.inputSize,
    required this.results,
    this.showConfidence = true,
    this.showPosition = false,
  });

  @override
  Widget build(BuildContext context) {
    print('DetectionOverlay.build: Results count: ${results.length}');

    if (results.isEmpty) {
      print('DetectionOverlay.build: No results - returning SizedBox.shrink');
      return const SizedBox.shrink();
    }

    print('DetectionOverlay.build: Creating _DetectionPainter with ${results.length} results');

    return CustomPaint(
      painter: _DetectionPainter(
        previewSize: previewSize,
        inputSize: inputSize,
        results: results,
        showConfidence: showConfidence,
        showPosition: showPosition,
      ),
    );
  }
}

/// Painter that draws detection bounding boxes and labels.
class _DetectionPainter extends CustomPainter {
  final Size previewSize;
  final Size? inputSize;
  final List<DetectedObject> results;
  final bool showConfidence;
  final bool showPosition;

  _DetectionPainter({
    required this.previewSize,
    this.inputSize,
    required this.results,
    this.showConfidence = true,
    this.showPosition = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('DetectionOverlay._DetectionPainter.paint: Size=$size, Results count=${results.length}');

    if (results.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF1769E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final style = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    // Normalized boxes are relative to the upright detection frame, whose
    // display size is [sourceSize] (see camera_preview_fit.dart). The overlay
    // canvas covers the same area as the preview widget, which fills that area
    // with a uniform cover fit: both axes scaled by the same factor and the
    // overflow cropped symmetrically. Applying the same scale + offset here
    // keeps every box glued to the visible video geometry.
    final Size sourceSize = inputSize ?? Size(previewSize.height, previewSize.width);

    print('DetectionOverlay._DetectionPainter.paint: PREVIEW_WIDTH=$size.width');
    print('DetectionOverlay._DetectionPainter.paint: PREVIEW_HEIGHT=${size.height}');

    final double scale = math.max(
      size.width / sourceSize.width,
      size.height / sourceSize.height,
    );
    final double fittedWidth = sourceSize.width * scale;
    final double fittedHeight = sourceSize.height * scale;
    final double offsetX = (size.width - fittedWidth) / 2;
    final double offsetY = (size.height - fittedHeight) / 2;

    print('DetectionOverlay._DetectionPainter.paint: SCALE=$scale');
    print('DetectionOverlay._DetectionPainter.paint: OFFSET_X=$offsetX');
    print('DetectionOverlay._DetectionPainter.paint: OFFSET_Y=$offsetY');

    for (final result in results) {
      final box = result.boundingBox;

      final rawLeft = box.left;
      final rawTop = box.top;
      final rawRight = box.right;
      final rawBottom = box.bottom;

      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_LEFT=$rawLeft');
      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_TOP=$rawTop');
      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_RIGHT=$rawRight');
      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_BOTTOM=$rawBottom');
      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_WIDTH=${rawRight - rawLeft}');
      print('DetectionOverlay._DetectionPainter.paint: RAW_BOX_HEIGHT=${rawBottom - rawTop}');

      final left = offsetX + box.left * fittedWidth;
      final top = offsetY + box.top * fittedHeight;
      final right = offsetX + box.right * fittedWidth;
      final bottom = offsetY + box.bottom * fittedHeight;

      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_LEFT=$left');
      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_TOP=$top');
      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_RIGHT=$right');
      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_BOTTOM=$bottom');
      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_WIDTH=${right - left}');
      print('DetectionOverlay._DetectionPainter.paint: DISPLAY_BOX_HEIGHT=${bottom - top}');

      // Draw bounding box
      canvas.drawRect(
        Rect.fromLTWH(left, top, right - left, bottom - top),
        paint,
      );

      // Draw label below bounding box (not above)
      final String posLabel = showPosition && result.position != null
          ? '   ${result.position!.label}'
          : '';
      final String confLabel =
          showConfidence ? ' ${(_formatConfidence(result.confidence))}' : '';
      final label = '${result.displayName}$posLabel$confLabel';

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: style),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      final labelWidth = textPainter.width + 12;
      final labelHeight = textPainter.height + 8;

      // Draw label background BELOW the bounding box
      canvas.drawRect(
        Rect.fromLTWH(left, bottom + 2, labelWidth, labelHeight),
        Paint()..color = const Color(0xFF1769E0),
      );

      // Draw label text
      textPainter.paint(
        canvas,
        Offset(left + 6, bottom + 6),
      );
    }
  }

  /// Format confidence as percentage
  String _formatConfidence(double confidence) {
    return '${(confidence * 100).toInt()}%';
  }

  @override
  bool shouldRepaint(_DetectionPainter oldDelegate) {
    print('DetectionOverlay._DetectionPainter.shouldRepaint: ${oldDelegate.results != results}');
    return oldDelegate.results != results || oldDelegate.inputSize != inputSize;
  }
}