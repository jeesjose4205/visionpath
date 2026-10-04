import 'package:flutter/material.dart';

import '../models/target_search.dart';

/// Minimal on-screen status for a Target Object Navigation session.
///
/// Deliberately just two lines — the target the user asked for and what is
/// happening to it right now — so the Navigation screen keeps its existing
/// layout and the voice guidance stays the primary channel.
class TargetStatusChip extends StatelessWidget {
  const TargetStatusChip({super.key, required this.state});

  final TargetSearchState state;

  @override
  Widget build(BuildContext context) {
    final String status = state.statusText;
    return Semantics(
      liveRegion: true,
      label: 'Target ${state.targetName}. $status',
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1424).withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF8FB6FF).withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.my_location_rounded,
              size: 16,
              color: Color(0xFF8FB6FF),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'TARGET  ${state.targetName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (status.isNotEmpty) ...[
                      const TextSpan(
                        text: '   ·   ',
                        style: TextStyle(color: Color(0xFF8FB6FF), fontSize: 12),
                      ),
                      TextSpan(
                        text: status,
                        style: const TextStyle(
                          color: Color(0xFF8FB6FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
