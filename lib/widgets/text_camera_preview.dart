import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live camera feed with a light overlay that shows where recognized text sits
/// (helpful for partially sighted users; voice guidance is the primary input).
class TextCameraPreview extends StatelessWidget {
  final CameraController? controller;
  final bool initialized;
  final String? errorMessage;

  /// Normalized (0..1 portrait) region of the recognized text, when found.
  final Rect? textRegion;
  final int blockCount;

  /// Scanning-frame corners drawn while actively positioning text.
  final bool showFrame;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusColor;

  const TextCameraPreview({
    super.key,
    required this.controller,
    required this.initialized,
    this.errorMessage,
    this.textRegion,
    this.blockCount = 0,
    this.showFrame = true,
    this.statusLabel = 'SCANNING',
    this.statusIcon = Icons.document_scanner_outlined,
    this.statusColor = const Color(0xFF1769E0),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF20252B),
          borderRadius: BorderRadius.circular(22),
        ),
        child: !initialized || controller == null
            ? _buildLoading(context)
            : _buildPreview(context),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF64B5F6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            errorMessage ?? 'Starting camera...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller!),
        if (textRegion != null)
          CustomPaint(
            painter: _TextRegionPainter(
              region: textRegion!,
              blockCount: blockCount,
            ),
          ),
        if (showFrame)
          const Positioned.fill(
            child: CustomPaint(painter: _UprightFramePainter()),
          ),
        Positioned(
          top: 14,
          left: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 15, color: statusColor),
                const SizedBox(width: 7),
                Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws a soft translucent panel over the recognized text region plus a
/// highlight border.
class _TextRegionPainter extends CustomPainter {
  final Rect region;
  final int blockCount;

  _TextRegionPainter({required this.region, required this.blockCount});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x331769E0)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF4FC3F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Block count chip anchored under the top-left corner of the region.
    final labelPainter = TextPainter(
      text: TextSpan(
        text: blockCount > 1 ? '$blockCount text blocks' : '1 text block',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(rect.left.clamp(0, size.width - labelPainter.width),
          (rect.top - 20).clamp(4.0, size.height - labelPainter.height - 4)),
    );
  }

  @override
  bool shouldRepaint(_TextRegionPainter oldDelegate) =>
      oldDelegate.region != region || oldDelegate.blockCount != blockCount;
}

/// Corner brackets that indicate the "safe" upright framing area.
class _UprightFramePainter extends CustomPainter {
  const _UprightFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final margin = size.width * 0.12;
    final inset = size.height * 0.06;
    final left = margin;
    final top = inset;
    final right = size.width - margin;
    final bottom = size.height - inset;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final corner = 24.0;
    final path = Path()
      ..moveTo(left, top + corner)
      ..lineTo(left, top)
      ..lineTo(left + corner, top)
      ..moveTo(right - corner, top)
      ..lineTo(right, top)
      ..lineTo(right, top + corner)
      ..moveTo(right, bottom - corner)
      ..lineTo(right, bottom)
      ..lineTo(right - corner, bottom)
      ..moveTo(left + corner, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, bottom - corner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_UprightFramePainter oldDelegate) => false;
}