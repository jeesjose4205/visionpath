import 'package:flutter/material.dart';

/// The large rounded "Tap to speak" pill at the bottom of the assistant.
class VisoraMicrophoneButton extends StatefulWidget {
  const VisoraMicrophoneButton({
    super.key,
    required this.onTap,
    this.enabled = true,
  });

  final VoidCallback onTap;

  final bool enabled;

  @override
  State<VisoraMicrophoneButton> createState() => _VisoraMicrophoneButtonState();
}

class _VisoraMicrophoneButtonState extends State<VisoraMicrophoneButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _handleDown() {
    if (!widget.enabled) return;
    _press.forward();
  }

  void _handleUp() {
    if (!_press.isAnimating) _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tap to speak',
      child: GestureDetector(
        onTapDown: (_) => _handleDown(),
        onTapUp: (_) {
          _handleUp();
          if (widget.enabled) widget.onTap();
        },
        onTapCancel: _handleUp,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final scale = 1 - (_press.value * 0.04);
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1769E0),
                  Color(0xFF7C5BFF),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1769E0).withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                SizedBox(width: 10),
                Text(
                  'Tap to speak',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact "Tap to stop" control shown in listening/thinking states.
class VisoraStopButton extends StatelessWidget {
  const VisoraStopButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tap to stop',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD9E5FF)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle_rounded, color: Color(0xFFD92D20), size: 20),
              SizedBox(width: 7),
              Text(
                'Tap to stop',
                style: TextStyle(
                  color: Color(0xFF15233D),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}