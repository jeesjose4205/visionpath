import 'package:flutter/material.dart';

/// Bounded, non-scrolling preview of the recognized text.
///
/// The full text is always available to TTS; the visual panel shows a fixed
/// number of lines so the screen never needs a scroll view.
class OcrResultCard extends StatelessWidget {
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
              Text(
                'Recognized text',
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF15233D),
                ),
              ),
              const Spacer(),
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
          Text(
            text,
            maxLines: compact ? 4 : 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF2A3550),
            ),
          ),
        ],
      ),
    );
  }
}