import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/voice_command_controller.dart';
import 'listening_orb.dart';

/// The transparent listening surface shown while the user presses and holds the
/// navigation screen.
///
/// It sits above the camera view without replacing it: a translucent tint plus a
/// backdrop blur keeps the live navigation feed visible and readable behind the
/// animation, which matters because the user still needs to see where they are
/// walking while they speak.
///
/// The orb is [ListeningOrb], the same listening animation the rest of the app
/// already uses for its microphone surfaces.
class VoiceSearchOverlay extends StatelessWidget {
  const VoiceSearchOverlay({
    super.key,
    required this.controller,
  });

  final VoiceCommandController controller;

  @override
  Widget build(BuildContext context) {
    // The screen does not rebuild while a hold is in progress, so the overlay
    // listens to the controller itself. Without this the whole feature is
    // invisible: the states below would only be sampled on some unrelated
    // rebuild of the navigation screen.
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _buildOverlay(context),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final bool listening = controller.isListening;
    final String transcript = controller.transcript.trim();

    // Between holds the overlay is not built at all. The orb pulses forever, so
    // keeping it mounted would leave an animation running (and would stop
    // pumpAndSettle in widget tests) for something nobody can see.
    if (!controller.isActive) return const SizedBox.shrink();

    return AnimatedOpacity(
      // Fades in and out with the hold instead of popping.
      opacity: controller.isActive ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        // The hold is owned by the gesture that opened this, so the overlay
        // must never eat the release.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ColoredBox(
            color: const Color(0x66070B12),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.86, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (BuildContext context, double scale, Widget? child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListeningOrb(
                      size: 168,
                      listening: listening,
                      showMic: true,
                    ),
                    const SizedBox(height: 22),
                    _StatusLine(listening: listening),
                    // Showing the words back is the only visual confirmation a
                    // low-vision user gets that the right thing was heard.
                    if (transcript.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          transcript,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.listening});

  final bool listening;

  @override
  Widget build(BuildContext context) {
    final String label = listening
        ? 'Listening...'
        // Honest about why nothing is being captured yet: the app is still
        // finishing a sentence.
        : 'Getting ready...';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (listening) ...<Widget>[
          const MiniWaveform(active: true),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}