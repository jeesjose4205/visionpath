import 'package:flutter/material.dart';

class ReadTextScreen extends StatefulWidget {
  const ReadTextScreen({super.key});

  @override
  State<ReadTextScreen> createState() => _ReadTextScreenState();
}

class _ReadTextScreenState extends State<ReadTextScreen> {
  bool isReading = false;

  void _scanText() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Camera activated. Position the text inside the frame.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _readText() {
    setState(() {
      isReading = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reading detected text...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _pauseReading() {
    setState(() {
      isReading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reading paused'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool compact = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 20,
            vertical: compact ? 8 : 12,
          ),
          child: Column(
            children: [
              // ─────────────────────────────────────────
              // HEADER
              // ─────────────────────────────────────────
              SizedBox(
                height: compact ? 50 : 56,
                child: Row(
                  children: [
                    _HeaderButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Back',
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),

                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Read Text',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF15233D),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Scan and listen to text',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _HeaderButton(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              SizedBox(height: compact ? 10 : 14),

              // ─────────────────────────────────────────
              // TITLE
              // ─────────────────────────────────────────
              const Text(
                'Capture & Listen',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF15233D),
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'Point your camera at text to read it aloud',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF718096),
                ),
              ),

              SizedBox(height: compact ? 12 : 16),

              // ─────────────────────────────────────────
              // CAMERA PREVIEW
              // ─────────────────────────────────────────
              Expanded(
                flex: 6,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EEF5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFD8E0EA),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Camera placeholder
                      const Center(
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 58,
                          color: Color(0xFF8793A5),
                        ),
                      ),

                      // Scanning frame
                      Center(
                        child: Container(
                          width: compact ? 210 : 250,
                          height: compact ? 130 : 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF1769E0),
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                      // Top status
                      Positioned(
                        top: 14,
                        left: 14,
                        right: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.document_scanner_outlined,
                                size: 17,
                                color: Color(0xFF1769E0),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Position text inside the frame',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF15233D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: compact ? 10 : 14),

              // ─────────────────────────────────────────
              // INFORMATION
              // ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF5FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.volume_up_outlined,
                      color: Color(0xFF1769E0),
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Detected text will be converted to speech.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF40516B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: compact ? 10 : 14),

              // ─────────────────────────────────────────
              // SCAN BUTTON
              // ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: compact ? 56 : 62,
                child: ElevatedButton(
                  onPressed: _scanText,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1769E0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.document_scanner_outlined,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'SCAN TEXT',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: compact ? 8 : 10),

              // ─────────────────────────────────────────
              // READ / PAUSE
              // ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.volume_up_outlined,
                      title: 'Read',
                      onTap: _readText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.pause_rounded,
                      title: 'Pause',
                      onTap: _pauseReading,
                    ),
                  ),
                ],
              ),

              SizedBox(height: compact ? 8 : 10),

              // ─────────────────────────────────────────
              // VOICE HINT
              // ─────────────────────────────────────────
              SizedBox(
                height: compact ? 32 : 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic_none_rounded,
                      size: 17,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tap to speak for hands-free control',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// HEADER BUTTON
// ═══════════════════════════════════════════════════════

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 27,
              color: const Color(0xFF15233D),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ACTION BUTTON
// ═══════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 21,
        ),
        label: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1769E0),
          backgroundColor: Colors.white,
          side: const BorderSide(
            color: Color(0xFFDCE4EF),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}