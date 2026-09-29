import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/visora_state.dart';
import '../../services/visora/visora_config.dart';
import '../../services/visora/visora_session.dart';
import '../../screens/visora_settings_screen.dart';
import 'visora_microphone_button.dart';
import 'visora_orb.dart';
import 'visora_response_card.dart';
import 'visora_suggestions.dart';
import 'visora_waveform.dart';

/// Full-height Visora assistant opening as an overlay on top of the current
/// VisionPath screen.
///
/// Activation sequence (wake word or card tap):
///  1. the existing screen dims via a dark translucent overlay,
///  2. the blue "AI" of the heading expands into "Visora" (typed + cursor),
///  3. a soft glow pulse acknowledges the wake word,
///  4. the glassy panel slides up with Visora's orb, then greeting + list.
class VisoraOverlay extends StatefulWidget {
  const VisoraOverlay({
    super.key,
    this.autoListen = false,
  });

  /// When true (wake-word activation) listening starts after the greeting.
  final bool autoListen;

  /// Push the Visora assistant as an overlay above the current screen.
  static Future<void> show(BuildContext context, {bool autoListen = false}) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => VisoraOverlay(autoListen: autoListen),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<VisoraOverlay> createState() => _VisoraOverlayState();
}

class _VisoraOverlayState extends State<VisoraOverlay>
    with TickerProviderStateMixin {
  final VisoraSession _session = VisoraSession.instance;
  Timer? _greetingTimer;

  /// Typing animation: characters revealed one at a time.
  late final AnimationController _typeController;
  final int _typeChars = 6; // "Visora"
  int _typedCount = 0;

  /// Cursor blink.
  late final AnimationController _cursorController;
  late final AnimationController _glowController;
  late final AnimationController _panelController;

  bool _introDone = false;
  bool _cursorVisible = true;
  bool _showCursor = false;

  @override
  void initState() {
    super.initState();
    _session.open();
    _typeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..addListener(_typeListener);
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _introDone = true;
            _showCursor = false;
            _cursorVisible = false;
          });
          _session.speakGreeting();
          _greetingTimer = Timer(const Duration(milliseconds: 2200), () {
            if (!mounted || _session.state != VisoraState.idle) return;
            if (widget.autoListen) {
              unawaited(_session.startListening());
            }
          });
        }
      });

    _runIntro();
  }

  void _typeListener() {
    final count = ((_typeController.value * _typeChars).round());
    if (count != _typedCount) {
      setState(() => _typedCount = count);
    }
  }

  Future<void> _runIntro() async {
    _showCursor = true;
    setState(() {});
    _typeController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _cursorController.repeat(reverse: true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _showCursor = false;
      _cursorVisible = false;
    });
    _glowController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    _panelController.forward();
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    _typeController.dispose();
    _cursorController.dispose();
    _glowController.dispose();
    _panelController.dispose();
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dim + typing heading layer (behind the panel).
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _introDone ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: _HeadingTypingLayer(
                  typedCount: _typedCount,
                  showCursor: _showCursor && _cursorVisible,
                  cursorController: _cursorController,
                  glow: _glowController,
                ),
              ),
            ),
          ),

          // Glass assistant panel.
          Positioned.fill(
            child: AnimatedSlide(
              offset: Offset(0, _introDone ? 0 : 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              child: _assistantPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD).withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(30),
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15233D).withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Visora',
            child: GestureDetector(
              onTap: _close,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF344054),
                  size: 22,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Visora',
                  style: TextStyle(
                    color: Color(0xFF15233D),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    color: const Color(0xFF718096).withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Visora settings',
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const VisoraSettingsScreen(),
                ),
              ),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: Color(0xFF344054),
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final state = _session.state;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: switch (state) {
        VisoraState.closed || VisoraState.activating => const SizedBox.shrink(),
        VisoraState.listening =>
          _ListeningBody(
            session: _session,
            onStop: () => unawaited(_session.stopListening()),
          ),
        VisoraState.processing => _ThinkingBody(
            session: _session,
          ),
        VisoraState.speaking => _SpeakingBody(
            session: _session,
            onStopAnswer: () => _session.stopSpeaking(),
          ),
        VisoraState.stopped => _StoppedBody(
            onResume: () => unawaited(_session.startListening()),
          ),
        VisoraState.error => _ErrorBody(
            session: _session,
            onRetry: () => unawaited(_session.startListening()),
          ),
        VisoraState.idle => _IdleBody(
            session: _session,
            onAsk: (text) => unawaited(_session.handleUserMessage(text)),
            onListen: () => unawaited(_session.startListening()),
          ),
      },
    );
  }

  Widget _buildFooter() {
    final speakState = _session.state == VisoraState.listening ||
        _session.state == VisoraState.processing ||
        _session.state == VisoraState.speaking ||
        _session.state == VisoraState.stopped;
    if (speakState) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: VisoraStopButton(
          onTap: () => unawaited(_session.interrupt()),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: VisoraMicrophoneButton(
        onTap: () => unawaited(_session.startListening()),
      ),
    );
  }

  void _close() {
    Navigator.of(context).pop();
  }
}

// ------------------------------------------------------------------
// TYPING HEADING LAYER
// ------------------------------------------------------------------

class _HeadingTypingLayer extends StatelessWidget {
  const _HeadingTypingLayer({
    required this.typedCount,
    required this.showCursor,
    required this.cursorController,
    required this.glow,
  });

  final int typedCount;
  final bool showCursor;
  final AnimationController cursorController;
  final AnimationController glow;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    const word = 'Visora';
    const prefix = 'VisionPath ';
    final revealed = word.substring(0, typedCount.clamp(0, word.length));
    final glowAlpha = (glow.value * 0.5);

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([glow, cursorController]),
            builder: (context, _) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1424).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4C8DFF).withValues(
                        alpha: glowAlpha,
                      ),
                      blurRadius: 30 + glow.value * 40,
                      spreadRadius: glow.value * 8,
                    ),
                  ],
                ),
                child: RichText(
                  text: TextSpan(
                    style: baseStyle.copyWith(color: const Color(0xFF182230)),
                    children: [
                      TextSpan(
                        text: prefix,
                        style: const TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: revealed,
                        style: const TextStyle(
                          color: Color(0xFF8FB6FF),
                          shadows: [
                            Shadow(
                              color: Color(0xFF4C8DFF),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ),
                      if (showCursor && revealed.isNotEmpty)
                        TextSpan(
                          text: '|',
                          style: TextStyle(
                            color: Colors.white.withValues(
                              alpha:
                                  0.4 + (cursorController.value * 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// IDLE
// ------------------------------------------------------------------

class _IdleBody extends StatelessWidget {
  const _IdleBody({
    required this.session,
    required this.onAsk,
    required this.onListen,
  });

  final VisoraSession session;
  final ValueChanged<String> onAsk;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 4),
        const Center(child: VisoraOrb(size: 120)),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: ListenableBuilder(
              listenable: VisoraConfig.instance,
              builder: (context, _) {
                final cfg = VisoraConfig.instance;
                final String label;
                final Color color;
                if (cfg.hasBackend && cfg.connectionVerified) {
                  label = 'Online';
                  color = const Color(0xFF175CD3);
                } else if (cfg.hasBackend) {
                  label = 'Ready';
                  color = const Color(0xFF74849E);
                } else {
                  label = 'Offline';
                  color = const Color(0xFF98A2B3);
                }
                return Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Column(
            children: [
              const Text(
                'Visora',
                style: TextStyle(
                  color: Color(0xFF15233D),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your AI Assistant',
                style: TextStyle(
                  color: const Color(0xFF718096).withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            session.hasBackend
                ? 'Hello! I am Visora, your AI assistant. Ask me anything.'
                : 'Hello! I am Visora, your AI assistant.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 14.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            session.hasBackend
                ? 'Ask me anything — from general questions to everyday help.'
                : 'Connect a backend in Visora settings for full AI answers.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 14),
        VisoraSuggestions(onSelected: onAsk),
      ],
    );
  }
}

// ------------------------------------------------------------------
// LISTENING
// ------------------------------------------------------------------

class _ListeningBody extends StatelessWidget {
  const _ListeningBody({
    required this.session,
    required this.onStop,
  });

  final VisoraSession session;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.center,
          children: [
            const SizedBox(width: 200, height: 200),
            VisoraOrb(
              size: 136,
              listening: true,
              showMic: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          session.partialText.isEmpty ? 'Listening...' : session.partialText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF15233D),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          'Speak naturally',
          style: TextStyle(
            color: const Color(0xFF718096).withValues(alpha: 0.9),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: VisoraWaveform(energy: session.voiceEnergy),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// THINKING
// ------------------------------------------------------------------

class _ThinkingBody extends StatefulWidget {
  const _ThinkingBody({required this.session});

  final VisoraSession session;

  @override
  State<_ThinkingBody> createState() => _ThinkingBodyState();
}

class _ThinkingBodyState extends State<_ThinkingBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _step;

  @override
  void initState() {
    super.initState();
    _step = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
  }

  @override
  void dispose() {
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Understanding your request',
      'Finding relevant information',
      'Generating response',
    ];
    return Column(
      children: [
        const SizedBox(height: 24),
        const VisoraOrb(size: 110),
        const SizedBox(height: 18),
        const Text(
          'Thinking...',
          style: TextStyle(
            color: Color(0xFF15233D),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Just a moment',
          style: TextStyle(
            color: const Color(0xFF718096).withValues(alpha: 0.9),
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _step,
          builder: (context, _) {
            final t = _step.value;
            return Column(
              children: [
                for (var i = 0; i < steps.length; i++) _stepRow(steps[i], i, t),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _stepRow(String label, int index, double t) {
    final phase = ((t * 3) - index).clamp(0.0, 1.0);
    final done = phase >= 0.95;
    final active = phase > 0 && !done;
    final icon = done
        ? Icons.check_circle_rounded
        : active
            ? Icons.sync_rounded
            : Icons.radio_button_unchecked_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: done
                ? const Color(0xFF1E8E3E)
                : active
                    ? const Color(0xFF1769E0)
                    : const Color(0xFFA8B4C8),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: done || active
                  ? const Color(0xFF344054)
                  : const Color(0xFFA8B4C8),
              fontSize: 14,
              fontWeight: done || active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// SPEAKING
// ------------------------------------------------------------------

class _SpeakingBody extends StatelessWidget {
  const _SpeakingBody({
    required this.session,
    required this.onStopAnswer,
  });

  final VisoraSession session;
  final VoidCallback onStopAnswer;

  @override
  Widget build(BuildContext context) {
    // The most recent assistant message gets an active speaker toggle; the
    // session speaks only the latest answer.
    var lastAssistant = -1;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      if (!session.messages[i].isUser) {
        lastAssistant = i;
        break;
      }
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Visora is speaking',
            style: TextStyle(
              color: const Color(0xFF718096).withValues(alpha: 0.95),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < session.messages.length; i++)
          VisoraResponseCard(
            message: session.messages[i],
            speaking: i == lastAssistant,
            onSpeak:
                i == lastAssistant ? () => session.replayAnswer() : null,
            onStop: onStopAnswer,
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// STOPPED / ERROR
// ------------------------------------------------------------------

class _StoppedBody extends StatelessWidget {
  const _StoppedBody({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const VisoraOrb(size: 100),
        const SizedBox(height: 18),
        const Text(
          'Listening stopped',
          style: TextStyle(
            color: Color(0xFF15233D),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap below to speak again',
          style: TextStyle(
            color: const Color(0xFF718096).withValues(alpha: 0.9),
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.session, required this.onRetry});

  final VisoraSession session;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final micPermission = session.lastError.toLowerCase().contains('microphone') ||
        session.lastError.toLowerCase().contains('permission');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const VisoraOrb(size: 100, error: true, showMic: true),
        const SizedBox(height: 18),
        Text(
          micPermission
              ? 'Microphone access is needed to talk with Visora.'
              : session.lastError.isEmpty
                  ? 'Something went wrong.'
                  : session.lastError,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF15233D),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          micPermission ? 'Enable it in your phone settings.' : 'Please try again.',
          style: TextStyle(
            color: const Color(0xFF718096).withValues(alpha: 0.9),
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1769E0), Color(0xFF7C5BFF)],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Try again',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}