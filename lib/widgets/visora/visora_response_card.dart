import 'package:flutter/material.dart';

import '../../models/visora_message.dart';
import 'visora_orb.dart';

/// A conversation bubble in the Visora transcript.
///
/// User messages align right in a blue pill; Visora answers render as cards
/// with her mini identity (waveform glyph + "Visora" label) and a
/// speaker/play toggle that speaks (or stops) the stored answer.
class VisoraResponseCard extends StatelessWidget {
  const VisoraResponseCard({
    super.key,
    required this.message,
    this.onSpeak,
    this.onStop,
    this.speaking = false,
  });

  final VisoraMessage message;

  /// Play the assistant message aloud.
  final VoidCallback? onSpeak;

  /// Stop the assistant message playback.
  final VoidCallback? onStop;

  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1769E0), Color(0xFF4C8DFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        constraints: const BoxConstraints(maxWidth: 330),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E8EF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF15233D).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const VisoraMiniWaveform(),
                const SizedBox(width: 7),
                const Text(
                  'Visora',
                  style: TextStyle(
                    color: Color(0xFF4C8DFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: speaking ? 'Stop speaking' : 'Play response',
                  child: GestureDetector(
                    onTap: speaking ? onStop : onSpeak,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF4FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        speaking
                            ? Icons.stop_circle_rounded
                            : Icons.volume_up_rounded,
                        color: speaking
                            ? const Color(0xFFD92D20)
                            : const Color(0xFF175CD3),
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.text,
              style: TextStyle(
                color: message.isError
                    ? const Color(0xFFB42318)
                    : const Color(0xFF182230),
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}