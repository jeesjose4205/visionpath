import 'package:flutter/material.dart';

/// Bounded card showing the recognized text.
///
/// The card keeps the exact size it has always had: short text lays out as-is
/// and long text is capped at the same number of lines as before. The overflow
/// is reached by scrolling inside the card rather than by truncating it with an
/// ellipsis, so the whole recognized text stays reachable without the screen
/// itself ever needing a scroll view.
class OcrResultCard extends StatelessWidget {
  /// Style of the recognized text body. Also used to measure a line box, so the
  /// scroll viewport can match the height the text always had.
  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: Color(0xFF2A3550),
  );

  final String text;
  final int charCount;
  final bool isReading;

  const OcrResultCard({
    super.key,
    required this.text,
    required this.charCount,
    required this.isReading,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFF5D9A8)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFB26A00), size: 21),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No text was found in this picture. Try scanning again.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A4A00)),
              ),
            ),
          ],
        ),
      );
    }

    final compact = MediaQuery.of(context).size.height < 700;

    // The height the text body already occupied: `maxLines` lines at fontSize 13
    // with height 1.4, i.e. exactly what a full-length ellipsized Text laid out
    // to before. Measured rather than assumed, so the card keeps its size on
    // any device/font.
    final TextPainter measurer = TextPainter(
      text: const TextSpan(text: 'Ag', style: _bodyStyle),
      textDirection: Directionality.of(context),
    )..layout();
    final double bodyMaxHeight = measurer.height * (compact ? 4 : 6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDCE4EF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isReading ? Icons.graphic_eq : Icons.article_outlined,
                size: 16,
                color: isReading
                    ? const Color(0xFF1769E0)
                    : const Color(0xFF718096),
              ),
              const SizedBox(width: 7),
              // The title yields space rather than letting the row overflow on
              // narrow phones; the character count is the part worth keeping.
              Expanded(
                child: Text(
                  'Recognized text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF15233D),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF5FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$charCount characters',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1769E0),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 12, color: Color(0xFFE8EDF5)),

          // Same rendered height as the previous `maxLines` + ellipsis text,
          // so the card itself is untouched in size. Only the tail of the text
          // is now reachable by scrolling.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bodyMaxHeight),
            child: SingleChildScrollView(
              child: Text(text, style: _bodyStyle),
            ),
          ),
        ],
      ),
    );
  }
}