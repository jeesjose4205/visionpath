import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import 'about_screen.dart';
import 'accessibility_settings_screen.dart';
import 'detection_settings_screen.dart';
import 'emergency_settings_screen.dart';
import 'familiar_face_settings_screen.dart';
import 'general_settings_screen.dart';
import 'navigation_settings_screen.dart';
import 'notifications_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'read_text_settings_screen.dart';
import 'reset_settings_screen.dart';
import 'voice_settings_screen.dart';

/// SettingsScreen is the launcher for VisionPath AI configuration.
///
/// A standard, professional grouped-list dashboard: iOS/Android-style
/// sections where every setting is a row with a leading icon, a title, an
/// optional subtitle, a live status read from [SettingsService] and a
/// chevron on the right. Only this dashboard is restyled — every target
/// screen, the [SettingsService] and its persisted preferences remain
/// untouched.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------------------
            // HEADER — only the page title + subtitle. No back icon,
            // no branding, no gear, no additional controls.
            // ----------------------------------------------------------
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: Color(0xFF15233D),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Customize your experience',
                    style: TextStyle(
                      color: Color(0xFF5A6B8C),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ----------------------------------------------------------
            // GROUPED LIST — three standard sections. Status values are
            // live: the list rebuilds whenever SettingsService notifies.
            // ----------------------------------------------------------
            Expanded(
              child: ListenableBuilder(
                listenable: SettingsService.instance,
                builder: (context, _) {
                  final s = SettingsService.instance;
                  return ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _GroupSection(
                        title: 'Voice & Interaction',
                        rows: [
                          _SettingRow(
                            icon: Icons.volume_up_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Voice & Audio',
                            subtitle: 'Speech, volume and language',
                            semanticLabel: 'Voice and Audio settings',
                            status: s.voiceGuidanceEnabled ? 'On' : 'Off',
                            target: VoiceSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.accessibility_new_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Accessibility',
                            subtitle: 'Display, haptics and controls',
                            semanticLabel: 'Accessibility settings',
                            status: s.voiceFirstMode ? 'On' : 'Off',
                            target: AccessibilitySettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.explore_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Navigation',
                            subtitle: 'Guidance preferences',
                            semanticLabel: 'Navigation settings',
                            status: s.navigationVoiceEnabled ? 'On' : 'Off',
                            target: NavigationSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.center_focus_strong_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Detection',
                            subtitle: 'Object detection settings',
                            semanticLabel: 'Detection settings',
                            status: s.detectionVoiceEnabled ? 'On' : 'Off',
                            target: DetectionSettingsScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _GroupSection(
                        title: 'Vision & Assistance',
                        rows: [
                          _SettingRow(
                            icon: Icons.menu_book_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Read Text',
                            subtitle: 'OCR and reading preferences',
                            semanticLabel: 'Read Text settings',
                            status: s.readTextAutoRead ? 'Auto' : 'Manual',
                            target: ReadTextSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.face_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Familiar Faces',
                            subtitle: 'Recognition settings',
                            semanticLabel: 'Familiar Faces settings',
                            status: s.familiarFacesEnabled ? 'On' : 'Off',
                            target: FamiliarFaceSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.emergency_rounded,
                            accent: const Color(0xFFD02020),
                            bubble: const Color(0xFFFFEBEB),
                            title: 'Emergency',
                            subtitle: 'Contacts and alerts',
                            semanticLabel: 'Emergency settings',
                            target: EmergencySettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.lock_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Privacy & Data',
                            subtitle: 'Permissions and data',
                            semanticLabel: 'Privacy and Data settings',
                            target: PrivacySettingsScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _GroupSection(
                        title: 'System',
                        rows: [
                          _SettingRow(
                            icon: Icons.settings_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'General',
                            subtitle: 'App preferences',
                            semanticLabel: 'General settings',
                            target: GeneralSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.notifications_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'Notifications',
                            subtitle: 'Alerts and reminders',
                            semanticLabel: 'Notifications settings',
                            status: s.notificationsEnabled ? 'On' : 'Off',
                            target: NotificationsSettingsScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.info_rounded,
                            accent: const Color(0xFF1459C7),
                            bubble: const Color(0xFFE7F0FF),
                            title: 'About',
                            subtitle: 'Version and information',
                            semanticLabel: 'About',
                            target: AboutScreen(),
                          ),
                          _SettingRow(
                            icon: Icons.restart_alt_rounded,
                            accent: const Color(0xFFD02020),
                            bubble: const Color(0xFFFFEBEB),
                            title: 'Reset Settings',
                            subtitle: 'Restore default settings',
                            semanticLabel: 'Reset Settings',
                            target: ResetSettingsScreen(),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A standard grouped section: a small uppercase header over a white rounded
/// container whose rows are separated by thin dividers.
class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.title, required this.rows});

  final String title;
  final List<_SettingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF6B7A96),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    endIndent: 0,
                    color: Color(0xFFEEF1F6),
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single grouped-list setting row: leading icon, title (+ optional
/// subtitle), optional live status, and a chevron on the right. The whole
/// row is the touch target.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.accent,
    required this.bubble,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.target,
    this.status,
  });

  final IconData icon;
  final Color accent;
  final Color bubble;
  final String title;
  final String subtitle;
  final String? status;
  final String semanticLabel;
  final Widget target;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => target),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bubble,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF15233D),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF74829C),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                Text(
                  status!,
                  style: const TextStyle(
                    color: Color(0xFF74829C),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  color: const Color(0xFFA8B4C8),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}