import 'package:flutter/material.dart';

import '../models/depth_scene.dart';

/// Debug visualization of the running depth analysis, drawn over the camera
/// preview. Enabled only through the "Depth Debug Overlay" setting.
///
/// Shows the three walking regions (LEFT / CENTER / RIGHT) tinted by their
/// blocking level, with the block level, open fraction and nearest relative
/// depth, plus a small summary line. All numbers are RELATIVE depth — never
/// meters.
class DepthDebugOverlay extends StatelessWidget {
  const DepthDebugOverlay({super.key, required this.scene});

  final DepthScene scene;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DepthDebugPainter(scene: scene),
      ),
    );
  }
}

class _DepthDebugPainter extends CustomPainter {
  _DepthDebugPainter({required this.scene});

  final DepthScene scene;

  Color _tint(DepthBlockLevel level) {
    switch (level) {
      case DepthBlockLevel.open:
        return const Color(0xFF198754);
      case DepthBlockLevel.partiallyBlocked:
        return const Color(0xFFFFB020);
      case DepthBlockLevel.blocked:
        return const Color(0xFFD92D20);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bandPaint = Paint()..style = PaintingStyle.stroke;
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final TextStyle labelStyle = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );

    const double top = 0.50;
    const double bottom = 0.90;

    for (final PathRegionAssessment region in scene.regions) {
      final (double from, double to) = switch (region.region) {
        PathRegion.left => (0.0, 1.0 / 3.0),
        PathRegion.center => (1.0 / 3.0, 2.0 / 3.0),
        PathRegion.right => (2.0 / 3.0, 1.0),
      };
      final Color color = _tint(region.blockLevel);

      final Rect band = Rect.fromLTRB(
        size.width * from,
        size.height * top,
        size.width * to,
        size.height * bottom,
      );
      fillPaint.color = color.withValues(alpha: 0.14);
      canvas.drawRect(band, fillPaint);
      bandPaint
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 2.0;
      canvas.drawRect(band, bandPaint);

      final String label =
          '${region.region.name.toUpperCase()} ${region.blockLevel.name.toUpperCase()}\n'
          'open ${(region.openRatio * 100).round()}%  '
          'near ${region.nearestDepth.toStringAsFixed(2)}';
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * (to - from));
      tp.paint(
        canvas,
        Offset(size.width * from + 6, size.height * top + 6),
      );
    }

    final String summary = scene.usedFallback
        ? 'DEPTH FALLBACK'
        : 'DEPTH ${scene.engineType.name.toUpperCase()} '
            'conf ${(scene.overallConfidence * 100).round()}%';
    final TextPainter summaryTp = TextPainter(
      text: TextSpan(
        text: summary,
        style: labelStyle.copyWith(color: const Color(0xFF0B1424)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect chip = Rect.fromLTWH(
      size.width - summaryTp.width - 20,
      8,
      summaryTp.width + 12,
      summaryTp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(10)),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    summaryTp.paint(
      canvas,
      Offset(chip.left + 6, chip.top + 3),
    );
  }

  @override
  bool shouldRepaint(_DepthDebugPainter oldDelegate) =>
      oldDelegate.scene != scene;
}