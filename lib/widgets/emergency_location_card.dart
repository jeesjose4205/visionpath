import 'package:flutter/material.dart';

/// A polished, honest location status card.
///
/// This version of the app does not include GPS/network location tracking, so
/// the card reports "Unavailable" instead of fabricating coordinates.
class EmergencyLocationCard extends StatelessWidget {
  const EmergencyLocationCard({
    super.key,
    this.height = 56,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE3E8EF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A1A2333),
              blurRadius: 9,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFF4E0),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: Color(0xFFE65100),
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF15233D),
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'No live location tracking',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEE8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Color(0xFFC62828), size: 7),
                  SizedBox(width: 5),
                  Text(
                    'OFF',
                    style: TextStyle(
                      color: Color(0xFFC62828),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
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