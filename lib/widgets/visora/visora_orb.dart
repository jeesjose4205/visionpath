import 'package:flutter/material.dart';

/// Visora's visual identity: a glowing blue→purple orb.
///
/// Rendered by [AnimationController]s so it is fully GPU-friendly and only
/// animates while mounted. The orb supports the core assistant states and
/// swaps its inner content (waveform-pulse vs mic icon) without leaving the
/// shared visual language.
class VisoraOrb extends StatefulWidget {
  const VisoraOrb({
    super.key,
    this.size = 148,
    this.listening = false,
    this.showMic = false,
    this.error = false,
    this.micIcon = Icons.mic_rounded,
  });

  final double size;
  final bool listening;
  final bool showMic;
  final bool error;
  final IconData micIcon;

  @override
  State<VisoraOrb> createState() => _VisoraOrbState();
}

class _VisoraOrbState extends State<VisoraOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _pulse = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glowOpacity = 0.25 + (0.15 * _fade.value);
        return Opacity(
          opacity: widget.error ? 0.85 : 1.0,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4C8DFF).withValues(alpha: glowOpacity),
                  blurRadius: size * 0.45,
                  spreadRadius: size * 0.08,
                ),
                BoxShadow(
                  color: const Color(0xFF7C5BFF).withValues(
                    alpha: glowOpacity * 0.7,
                  ),
                  blurRadius: size * 0.28,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glass gradient sphere.
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFF9FC6FF),
                        Color(0xFF4C8DFF),
                        Color(0xFF5B4FD8),
                        Color(0xFF2D2B6B),
                      ],
                      stops: [0.0, 0.45, 0.75, 1.0],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                ),
                // Outer listening ripple.
                if (widget.listening)
                  _RippleRing(size: size, controller: _controller),
                // Inner waveform whistle (idle whisper + speak energy).
                _InnerPulse(
                  size: size,
                  fade: _fade.value,
                  pulse: _pulse.value,
                ),
                // Center content.
                Transform.scale(
                  scale: _pulse.value,
                  child: Icon(
                    widget.error
                        ? Icons.error_outline_rounded
                        : widget.showMic
                            ? widget.micIcon
                            : Icons.graphic_eq_rounded,
                    color: widget.error
                        ? const Color(0xFFFFD9D9)
                        : Colors.white.withValues(alpha: 0.95),
                    size: widget.showMic ? size * 0.26 : size * 0.34,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Expanding concentric rings displayed while Visora listens.
class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.size, required this.controller});

  final double size;
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(0.0),
              _ring(0.33),
              _ring(0.66),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double offset) {
    final t = ((controller.value + offset) % 1.0);
    final radius = 0.35 + (t * 0.75);
    final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.45;
    return Container(
      width: size * radius,
      height: size * radius,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF8FB6FF).withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}

/// Slow breathing gradient pulse inside the sphere.
class _InnerPulse extends StatelessWidget {
  const _InnerPulse({
    required this.size,
    required this.fade,
    required this.pulse,
  });

  final double size;
  final double fade;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * pulse,
      height: size * pulse,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.18 * fade),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// A small horizontal equalizer icon used next to the Visora label.
class VisoraMiniWaveform extends StatefulWidget {
  const VisoraMiniWaveform({super.key, this.active = true});

  final bool active;

  @override
  State<VisoraMiniWaveform> createState() => _VisoraMiniWaveformState();
}

class _VisoraMiniWaveformState extends State<VisoraMiniWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant VisoraMiniWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    }
    if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(
            4,
            (i) {
              final phase = (_controller.value + i * 0.25) % 1.0;
              final height = widget.active
                  ? 4 + (10 * (0.5 - (phase - 0.5).abs()) * 2).clamp(2.0, 12.0)
                  : 4.0;
              return Container(
                width: 3,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4C8DFF).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          ),
        );
      },
    );
  }
}