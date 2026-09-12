import 'dart:async';

import 'package:flutter/material.dart';

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  bool _isNavigating = false;
  bool _voiceGuidance = true;

  String _navigationStatus = 'Ready to navigate';
  String _instruction = 'Press START NAVIGATION';
  String _detectedObject = 'No obstacle detected';
  String _direction = 'FORWARD';

  Timer? _demoTimer;
  int _demoStep = 0;

  @override
  void dispose() {
    _demoTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------
  // START NAVIGATION
  // ------------------------------------------------------------

  void _startNavigation() {
    setState(() {
      _isNavigating = true;
      _navigationStatus = 'Analyzing path';
      _instruction = 'Path clear. Move forward.';
      _detectedObject = 'No obstacle detected';
      _direction = 'FORWARD';
      _demoStep = 0;
    });

    _startDemoNavigation();
  }

  // ------------------------------------------------------------
  // DEMO NAVIGATION
  // ------------------------------------------------------------
  //
  // This currently simulates AI navigation decisions.
  // Later this will be replaced with:
  //
  // Camera → AI Detection → Path Analysis → Decision
  //
  // ------------------------------------------------------------

  void _startDemoNavigation() {
    _demoTimer?.cancel();

    _demoTimer = Timer.periodic(
      const Duration(seconds: 4),
      (timer) {
        if (!_isNavigating || !mounted) {
          timer.cancel();
          return;
        }

        _demoStep++;

        switch (_demoStep % 5) {
          case 1:
            _updateNavigation(
              status: 'Path clear',
              instruction: 'Path clear. Move forward.',
              object: 'No obstacle detected',
              direction: 'FORWARD',
            );
            break;

          case 2:
            _updateNavigation(
              status: 'Obstacle detected',
              instruction: 'Obstacle ahead. Move slightly left.',
              object: 'Obstacle • Center',
              direction: 'LEFT',
            );
            break;

          case 3:
            _updateNavigation(
              status: 'Path changing',
              instruction: 'Continue forward.',
              object: 'Path clear on left',
              direction: 'FORWARD',
            );
            break;

          case 4:
            _updateNavigation(
              status: 'Object detected',
              instruction: 'Person ahead. Slow down.',
              object: 'Person • Center',
              direction: 'SLOW',
            );
            break;

          case 0:
            _updateNavigation(
              status: 'Path clear',
              instruction: 'Path clear. Continue forward.',
              object: 'No obstacle detected',
              direction: 'FORWARD',
            );
            break;
        }
      },
    );
  }

  void _updateNavigation({
    required String status,
    required String instruction,
    required String object,
    required String direction,
  }) {
    if (!mounted) return;

    setState(() {
      _navigationStatus = status;
      _instruction = instruction;
      _detectedObject = object;
      _direction = direction;
    });

    // Later:
    // _speakInstruction(instruction);
  }

  // ------------------------------------------------------------
  // STOP NAVIGATION
  // ------------------------------------------------------------

  void _stopNavigation() {
    _demoTimer?.cancel();

    setState(() {
      _isNavigating = false;
      _navigationStatus = 'Navigation stopped';
      _instruction = 'Press START NAVIGATION';
      _detectedObject = 'No obstacle detected';
      _direction = 'FORWARD';
    });
  }

  // ------------------------------------------------------------
  // REPEAT INSTRUCTION
  // ------------------------------------------------------------

  void _repeatInstruction() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_instruction),
        duration: const Duration(seconds: 2),
      ),
    );

    // Later:
    // _speakInstruction(_instruction);
  }

  // ------------------------------------------------------------
  // VOICE GUIDANCE
  // ------------------------------------------------------------

  void _toggleVoiceGuidance() {
    setState(() {
      _voiceGuidance = !_voiceGuidance;
    });
  }

  // ------------------------------------------------------------
  // SETTINGS
  // ------------------------------------------------------------

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              24,
              20,
              24,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Navigation Settings',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Voice Guidance',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Speak navigation instructions',
                  ),
                  value: _voiceGuidance,
                  onChanged: (value) {
                    setState(() {
                      _voiceGuidance = value;
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final bool compact = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(compact),

            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  8,
                  compact ? 14 : 18,
                  compact ? 10 : 16,
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildCameraPreview(),
                    ),

                    SizedBox(height: compact ? 8 : 12),

                    _buildStatusCard(compact),

                    SizedBox(height: compact ? 8 : 12),

                    _buildInstructionCard(compact),

                    SizedBox(height: compact ? 8 : 12),

                    _buildBottomControls(compact),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        compact ? 8 : 14,
        compact ? 12 : 18,
        4,
      ),
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.arrow_back,
            onTap: () {
              if (_isNavigating) {
                _stopNavigation();
              }

              Navigator.pop(context);
            },
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Navigate',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF182230),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Camera-based path assistance',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),

          _HeaderButton(
            icon: Icons.settings_outlined,
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CAMERA PREVIEW
  // ------------------------------------------------------------

  Widget _buildCameraPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF20252B),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            // --------------------------------------------------
            // CAMERA PLACEHOLDER
            // --------------------------------------------------
            //
            // Later this container will be replaced with:
            //
            // CameraPreview(_cameraController)
            //
            // --------------------------------------------------

            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam_outlined,
                    color: Colors.white70,
                    size: 58,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Camera Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'AI navigation view',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // SCAN FRAME
            // --------------------------------------------------

            Positioned.fill(
              child: CustomPaint(
                painter: _NavigationFramePainter(),
              ),
            ),

            // --------------------------------------------------
            // AI STATUS
            // --------------------------------------------------

            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isNavigating
                            ? Colors.greenAccent
                            : Colors.white54,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _isNavigating
                          ? 'AI ANALYZING'
                          : 'CAMERA READY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --------------------------------------------------
            // DETECTED OBJECT
            // --------------------------------------------------

            if (_isNavigating)
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.60),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _detectedObject,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // STATUS CARD
  // ------------------------------------------------------------

  Widget _buildStatusCard(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 10 : 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE4E7EC),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              color: _isNavigating
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _isNavigating
                  ? Icons.radar
                  : Icons.navigation_outlined,
              color: _isNavigating
                  ? const Color(0xFF198754)
                  : const Color(0xFF475467),
              size: compact ? 21 : 24,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _navigationStatus,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF182230),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isNavigating
                      ? 'Monitoring your path'
                      : 'Ready to analyze your surroundings',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // INSTRUCTION CARD
  // ------------------------------------------------------------

  Widget _buildInstructionCard(bool compact) {
    IconData directionIcon;

    switch (_direction) {
      case 'LEFT':
        directionIcon = Icons.arrow_back;
        break;

      case 'RIGHT':
        directionIcon = Icons.arrow_forward;
        break;

      case 'SLOW':
        directionIcon = Icons.slow_motion_video;
        break;

      case 'STOP':
        directionIcon = Icons.stop_circle_outlined;
        break;

      default:
        directionIcon = Icons.arrow_upward;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        compact ? 14 : 18,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD9E5FF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 50,
            height: compact ? 44 : 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              directionIcon,
              color: const Color(0xFF175CD3),
              size: compact ? 24 : 27,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isNavigating
                      ? 'NEXT ACTION'
                      : 'NAVIGATION INSTRUCTION',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF667085),
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF182230),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BOTTOM CONTROLS
  // ------------------------------------------------------------

  Widget _buildBottomControls(bool compact) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SmallControlButton(
                icon: Icons.volume_up_outlined,
                label: _voiceGuidance
                    ? 'Voice ON'
                    : 'Voice OFF',
                onTap: _toggleVoiceGuidance,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: _SmallControlButton(
                icon: Icons.replay,
                label: 'Repeat',
                onTap: _isNavigating
                    ? _repeatInstruction
                    : null,
              ),
            ),
          ],
        ),

        SizedBox(height: compact ? 8 : 10),

        SizedBox(
          width: double.infinity,
          height: compact ? 48 : 54,
          child: ElevatedButton.icon(
            onPressed: _isNavigating
                ? _stopNavigation
                : _startNavigation,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isNavigating
                  ? const Color(0xFFD92D20)
                  : const Color(0xFF175CD3),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              _isNavigating
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow_rounded,
              size: 25,
            ),
            label: Text(
              _isNavigating
                  ? 'STOP NAVIGATION'
                  : 'START NAVIGATION',
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// HEADER BUTTON
// ============================================================

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: const Color(0xFFE4E7EC),
            ),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF344054),
            size: 21,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SMALL CONTROL BUTTON
// ============================================================

class _SmallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SmallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled
              ? const Color(0xFF344054)
              : const Color(0xFF98A2B3),
          side: BorderSide(
            color: enabled
                ? const Color(0xFFD0D5DD)
                : const Color(0xFFE4E7EC),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        icon: Icon(
          icon,
          size: 19,
        ),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// NAVIGATION FRAME PAINTER
// ============================================================

class _NavigationFramePainter extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final double left = size.width * 0.12;
    final double right = size.width * 0.88;
    final double top = size.height * 0.18;
    final double bottom = size.height * 0.82;

    const double corner = 28;

    // Top-left
    canvas.drawLine(
      Offset(left, top),
      Offset(left + corner, top),
      paint,
    );

    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + corner),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(right, top),
      Offset(right - corner, top),
      paint,
    );

    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + corner),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + corner, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(left, bottom),
      Offset(left, bottom - corner),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right - corner, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}