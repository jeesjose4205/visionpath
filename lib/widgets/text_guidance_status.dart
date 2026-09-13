import 'package:flutter/material.dart';

/// Voice-guidance status pill shown above the camera area.
class TextGuidanceStatus extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String detail;

  const TextGuidanceStatus({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 700;
    return Semantics(
      label: '$label. $detail',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFDCE4EF)),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 30 : 34,
              height: compact ? 30 : 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF15233D),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}