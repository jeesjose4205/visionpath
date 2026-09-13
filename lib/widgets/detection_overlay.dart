import 'package:flutter/material.dart';

import '../models/detected_object.dart';

/// DetectionOverlay draws bounding boxes and labels on the camera preview.
class DetectionOverlay extends StatelessWidget {
  /// The camera preview size
  final Size previewSize;

  /// Detected objects to draw
  final List<DetectedObject> results;

  /// Create a DetectionOverlay
  const DetectionOverlay({
    required this.previewSize,
    required this.results,
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
        results: results,
      ),
    );
  }
}

/// Painter that draws detection bounding boxes and labels.
class _DetectionPainter extends CustomPainter {
  final Size previewSize;
  final List<DetectedObject> results;

  _DetectionPainter({
    required this.previewSize,
    required this.results,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('DetectionOverlay._DetectionPainter.paint: Size=$size, Results count=${results.length}');

    if (results.isEmpty) return;

    print('DetectionOverlay._DetectionPainter.paint: Drawing ${results.length} bounding boxes');

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

    for (final result in results) {
      print('DetectionOverlay._DetectionPainter.paint: Drawing result: ${result.displayName} (${result.confidence * 100}%)');

      final box = result.boundingBox;

      print('DetectionOverlay._DetectionPainter.paint: Normalized box: ${box}');

      // TEMPORARY simple mapping for debugging: scale the normalized YOLO box
      // directly by the canvas size. Coordinate transformation is intentionally
      // not applied until detections are proven on-device.
      final left = box.left * size.width;
      final top = box.top * size.height;
      final right = box.right * size.width;
      final bottom = box.bottom * size.height;

      print('DetectionOverlay._DetectionPainter.paint: Pixel coordinates: left=$left, top=$top, right=$right, bottom=$bottom');

      // Draw bounding box
      canvas.drawRect(
        Rect.fromLTWH(left, top, right - left, bottom - top),
        paint,
      );

      // Get horizontal position from DetectedObject (for potential future use)

      // Draw label below bounding box (not above)
      final label = '${result.displayName} ${(_formatConfidence(result.confidence))}';

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
    return oldDelegate.results != results;
  }
}