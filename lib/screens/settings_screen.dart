import 'package:flutter/material.dart';

import '../widgets/settings_widgets.dart';
import 'accessibility_settings_screen.dart';
import 'detection_settings_screen.dart';
import 'emergency_settings_screen.dart';
import 'familiar_face_settings_screen.dart';
import 'general_settings_screen.dart';
import 'navigation_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'read_text_settings_screen.dart';
import 'voice_settings_screen.dart';

/// SettingsScreen is the category launcher for VisionPath AI configuration.
///
/// Each row opens its dedicated settings screen. The Home screen feature
/// cards are intentionally NOT duplicated here — this is purely
/// "how the app behaves", the Home screen remains "what the user wants to do".
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBg,
      appBar: AppBar(
        backgroundColor: settingsBg,
        foregroundColor: settingsInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: settingsInk,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Personalize how VisionPath AI sees and speaks. '
                'Choose a category below.',
                style: TextStyle(
                  color: settingsSubtext,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            _CategoryTile(
              icon: Icons.volume_up_outlined,
              accent: settingsBlue,
              title: 'Voice & Audio',
              description: 'Speech rate, volume, language and guidance',
              screen: const VoiceSettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.accessibility_new_outlined,
              accent: settingsGreen,
              title: 'Accessibility',
              description: 'Text size, contrast, haptics, voice-first mode',
              screen: const AccessibilitySettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.explore_outlined,
              accent: settingsInk,
              title: 'Navigation',
              description: 'Camera-based movement guidance',
              screen: const NavigationSettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.center_focus_strong_outlined,
              accent: settingsBlue,
              title: 'Detection',
              description: 'Object announcements and sensitivity',
              screen: const DetectionSettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.menu_book_outlined,
              accent: settingsGreen,
              title: 'Read Text',
              description: 'OCR reading and positioning guidance',
              screen: const ReadTextSettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.face_retouching_natural_outlined,
              accent: settingsBlue,
              title: 'Familiar Faces',
              description: 'Recognition, announcements and management',
              screen: const FamiliarFaceSettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.emergency_outlined,
              accent: settingsRed,
              title: 'Emergency',
              description: 'Contacts and SOS behaviour',
              screen: const EmergencySettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.lock_outline_rounded,
              accent: settingsInk,
              title: 'Privacy & Data',
              description: 'Permissions, face data and history',
              screen: const PrivacySettingsScreen(),
            ),
            _CategoryTile(
              icon: Icons.settings_outlined,
              accent: settingsBlue,
              title: 'General',
              description: 'Theme, language and app information',
              screen: const GeneralSettingsScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.screen,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => screen),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: settingsBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: settingsInk,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          color: settingsSubtext,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: settingsSubtext),
              ],
            ),
          ),
        ),
      ),
    );
  }
}