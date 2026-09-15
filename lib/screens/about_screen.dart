import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/settings_widgets.dart';

/// About VisionPath AI: vision, features, technology and the real installed
/// version from the build.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (e) {
      print('ABOUT_VERSION_FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionLine = _version.isEmpty
        ? 'Version 1.0.0 (build 1)'
        : 'Version $_version (build $_buildNumber)';
    return SettingsScaffold(
      title: 'About',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0E2A47), Color(0xFF123A63)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.route_outlined,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'VisionPath AI',
              style: TextStyle(
                color: settingsInk,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'SEE BEYOND TOGETHER',
              style: TextStyle(
                color: settingsBlue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SettingsCard(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI-powered assistance for people with visual '
                  'impairment, using the camera, computer vision, OCR, '
                  'face recognition, navigation assistance, emergency '
                  'assistance and voice interaction to help you '
                  'understand and interact with your surroundings.',
                  style: TextStyle(
                    color: settingsInk,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SettingsSectionTitle('Main Features'),
          const SettingsCard(
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.visibility_outlined,
                  label: 'Look & Detect — identify objects around you.',
                ),
                _FeatureRow(
                  icon: Icons.menu_book_outlined,
                  label: 'Read Text — camera OCR read aloud.',
                ),
                _FeatureRow(
                  icon: Icons.explore_outlined,
                  label: 'Navigate — camera-based movement guidance.',
                ),
                _FeatureRow(
                  icon: Icons.face_retouching_natural_outlined,
                  label: 'Familiar Faces — recognize people by name.',
                ),
                _FeatureRow(
                  icon: Icons.emergency_outlined,
                  label: 'Emergency — quick, reliable SOS.',
                ),
                _FeatureRow(
                  icon: Icons.mic_outlined,
                  label: 'Voice Assistant — speak to act.',
                ),
              ],
            ),
          ),
          const SettingsSectionTitle('Technology'),
          const SettingsCard(
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.memory_outlined,
                  label: 'On-device AI: YOLO object detection, ML Kit face '
                      'detection and MobileFaceNet face recognition.',
                ),
                _FeatureRow(
                  icon: Icons.shield_outlined,
                  label: 'All data stays local to this device.',
                ),
                _FeatureRow(
                  icon: Icons.smartphone_outlined,
                  label: 'Built with Flutter for Android.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              versionLine,
              style: const TextStyle(
                color: settingsSubtext,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: settingsBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: settingsInk,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}