import 'package:flutter/material.dart';

/// Real-time audio waveform for the Visora listening state.
///
/// Bar heights are driven by a sliding [energy] (0..1) supplied by the session
/// as partial transcript activity arrives, so the bars move in reaction to the
/// user's voice rather than looping a static animation.
class VisoraWaveform extends StatefulWidget {
  const VisoraWaveform({
    super.key,
    required this.energy,
    this.barCount = 42,
    this.height = 64,
    this.color = const Color(0xFF7C5BFF),
  });

  /// 0..1 current voice energy.
  final double energy;

  final int barCount;

  final double height;

  final Color color;

  @override
  State<VisoraWaveform> createState() => _VisoraWaveformState();
}

class _VisoraWaveformState extends State<VisoraWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final n = widget.barCount;
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(
              n,
              (i) {
                final t = (_controller.value + (i * 0.61803) % 1.0) % 1.0;
                // Idle micro-motion always present; scaled by voice energy.
                final idle = 0.12 + 0.16 * (0.5 - (t - 0.5).abs()) * 2;
                final level = idle + (widget.energy * (0.85 - idle * 0.5));
                final heightFactor = 0.25 + (level.clamp(0.0, 1.0) * 0.75);
                final center = widget.height / 2;
                return Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 1.6),
                  height: widget.height * heightFactor,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.color.withValues(alpha: 0.55),
                        widget.color,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  // Smooth vertical centering via padding to animate naturally.
                  transform: Matrix4.translationValues(
                    0,
                    center - (widget.height * heightFactor) / 2,
                    0,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}