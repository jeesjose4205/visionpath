import 'package:flutter/material.dart';

import '../models/sos_session.dart';

/// Live location status for an SOS session.
///
/// Replaces the old card that hard-coded "no live location tracking": while SOS
/// runs this reports what the GPS step actually produced, including when the
/// position could not be obtained. It never invents coordinates.
class EmergencyLocationCard extends StatelessWidget {
  const EmergencyLocationCard({
    super.key,
    required this.session,
    this.height = 56,
  });

  /// The running session to report on.
  final SosSession session;

  final double height;

  @override
  Widget build(BuildContext context) {
    final SosStep step = session.locationStep;

    final (IconData icon, Color iconBg, Color iconFg) = switch (step) {
      SosStep.locationFound => (
          Icons.location_on_rounded,
          const Color(0xFFE4F8EF),
          const Color(0xFF15805A),
        ),
      SosStep.locationUnavailable => (
          Icons.location_off_rounded,
          const Color(0xFFFFF4E0),
          const Color(0xFFE65100),
        ),
      SosStep.locating => (
          Icons.my_location_rounded,
          const Color(0xFFEAF2FE),
          const Color(0xFF1769E0),
        ),
      _ => (
          Icons.location_off_rounded,
          const Color(0xFFFFF4E0),
          const Color(0xFFE65100),
        ),
    };

    final (String title, String detail) = switch (step) {
      SosStep.locationFound => (
          'Location shared',
          session.location?.coordinates ?? 'Fix obtained.',
        ),
      SosStep.locationUnavailable => (
          'Location unavailable',
          session.locationBlockerMessage ?? 'Your position was not available.',
        ),
      SosStep.locating => ('Locating…', 'Getting your current position.'),
      _ => ('Location status', 'Not requested yet.'),
    };

    final (Color badgeBg, Color badgeFg, String badge) = switch (step) {
      SosStep.locationFound => (
          const Color(0xFFE4F8EF),
          const Color(0xFF15805A),
          'SHARED',
        ),
      SosStep.locationUnavailable => (
          const Color(0xFFFFEEE8),
          const Color(0xFFC62828),
          'UNAVAILABLE',
        ),
      SosStep.locating => (
          const Color(0xFFEAF2FE),
          const Color(0xFF1769E0),
          'BUSY',
        ),
      _ => (
          const Color(0xFFF1F5F9),
          const Color(0xFF718096),
          'IDLE',
        ),
    };

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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconBg,
              ),
              child: Icon(icon, color: iconFg, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF15233D),
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: badgeFg,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}