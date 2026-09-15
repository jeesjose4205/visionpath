import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Privacy & Data: permissions information, face-data transparency, clear
/// history and delete-face-data management. Destructive actions always ask
/// for confirmation first.
class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Privacy & Data',
          subtitle:
              'What VisionPath uses, what stays on your device, and how '
              'you can control it.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Permissions'),
              SettingsCard(
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.photo_camera_outlined,
                      title: 'Camera',
                      description:
                          'Required for Object Detection, Navigation, '
                          'Read Text and Familiar Faces. Awarded by the '
                          'system; VisionPath never bypasses Android '
                          'permissions.',
                    ),
                    _divider(),
                    _InfoRow(
                      icon: Icons.mic_none_outlined,
                      title: 'Microphone',
                      description:
                          'Used only where voice input is available. '
                          'VisionPath does not record or store audio.',
                    ),
                    _divider(),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      description:
                          'Camera-based navigation does not request '
                          'location. Location is only used when a feature '
                          'actually requires it.',
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Familiar Face Data'),
              SettingsCard(
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.face_retouching_natural_outlined,
                      title: 'Face embeddings stay local',
                      description:
                          'Registered faces are stored on this device as '
                          'non-reversible embeddings. They are never sent '
                          'to a server.',
                    ),
                    _divider(),
                    SettingsLink(
                      title: 'Delete Familiar Face Data',
                      description:
                          'Manage and delete registered face information.',
                      icon: Icons.delete_outline_rounded,
                      accent: settingsRed,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _showFaceDataDialog(context);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('History'),
              SettingsCard(
                child: SettingsActionButton(
                  label: 'Clear History',
                  description:
                      'Remove stored scan and recognition history.',
                  icon: Icons.delete_sweep_outlined,
                  destructive: true,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _confirmClearHistory(context, s);
                  },
                ),
              ),
              const SettingsSectionTitle('Privacy'),
              SettingsCard(
                child: _InfoRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Privacy information',
                  description:
                      'VisionPath AI processes camera frames, OCR data and '
                      'face information entirely on device where possible. '
                      'Nothing is sent to external servers.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFaceDataDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Manage face data',
            style: TextStyle(color: settingsInk, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'To delete a registered face or change who is known, open '
            'Familiar Faces and use the delete option on each person. '
            'Your settings will not be affected.',
            style: TextStyle(color: settingsInk, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close',
                  style: TextStyle(color: settingsBlue)),
            ),
          ],
        );
      },
    );
  }

  void _confirmClearHistory(BuildContext context, SettingsService s) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Clear History',
            style: TextStyle(color: settingsRed, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Are you sure you want to clear your history? This removes '
            'scan and recognition history. Your settings, familiar faces '
            'and emergency contacts stay untouched.',
            style: TextStyle(color: settingsInk, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: settingsSubtext)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                s.clearHistory();
              },
              child: const Text('Clear History',
                  style: TextStyle(color: settingsRed)),
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: settingsGreen, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: settingsInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: settingsSubtext,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);