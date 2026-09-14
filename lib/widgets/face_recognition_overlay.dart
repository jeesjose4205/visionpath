import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as p;

/// A face to draw on the live preview.
class FaceOverlayEntry {
  const FaceOverlayEntry({
    required this.box,
    required this.label,
    required this.color,
    this.subtitle,
  });

  /// Normalized bounding box (0..1, upright portrait).
  final Rect box;
  final String label;
  final Color color;
  final String? subtitle;
}

/// Live face boxes + name labels drawn over the camera preview.
///
/// Mirrors DetectionOverlay: normalized boxes are scaled directly by the
/// canvas size and a label chip is drawn under each box.
class FaceRecognitionOverlay extends StatelessWidget {
  const FaceRecognitionOverlay({
    super.key,
    this.entries = const [],
  });

  final List<FaceOverlayEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _FaceOverlayPainter(entries)),
    );
  }
}

class _FaceOverlayPainter extends CustomPainter {
  const _FaceOverlayPainter(this.entries);

  final List<FaceOverlayEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      final box = entry.box;
      final left = box.left * size.width;
      final top = box.top * size.height;
      final right = box.right * size.width;
      final bottom = box.bottom * size.height;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final paint = Paint()
        ..color = entry.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(rect, paint);

      final label = entry.subtitle == null
          ? entry.label
          : '${entry.label} ${entry.subtitle}';
      final tp = _labelPainter(label, entry.color);
      final textW = tp.width + 14;
      final textH = tp.height + 10;
      final chipLeft = (left - 2).clamp(0.0, size.width - textW);
      final chipBottom = (top - 4).clamp(0.0, size.height - textH);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(chipLeft, chipBottom, textW, textH),
          const Radius.circular(7),
        ),
        Paint()..color = entry.color.withValues(alpha: 0.92),
      );
      tp.paint(
        canvas,
        Offset(chipLeft + 7, chipBottom + 5),
      );
    }
  }

  p.TextPainter _labelPainter(String label, Color color) {
    return p.TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter oldDelegate) =>
      oldDelegate.entries != entries;
}