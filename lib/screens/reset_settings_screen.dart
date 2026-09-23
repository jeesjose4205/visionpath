import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Reset Settings: restores preferences to defaults via the existing
/// [SettingsService.resetToDefaults]. Never deletes familiar faces,
/// emergency contacts or history.
class ResetSettingsScreen extends StatelessWidget {
  const ResetSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Reset Settings',
      subtitle: 'Restore all preferences to their defaults.',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SettingsNote(
            'Resetting settings never deletes familiar faces, emergency '
            'contacts or your history. Only your preferences are restored.',
          ),
          SettingsCard(
            child: SettingsActionButton(
              label: 'Reset Settings',
              description:
                  'Restore all preferences to defaults. Does NOT delete '
                  'familiar faces, emergency contacts or history.',
              icon: Icons.restart_alt_rounded,
              destructive: true,
              onTap: () {
                HapticFeedback.selectionClick();
                _confirmReset(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Reset Settings',
            style: TextStyle(color: settingsRed, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Reset all preferences to their defaults? Your familiar faces, '
            'emergency contacts and history will not be deleted.',
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
                SettingsService.instance.resetToDefaults();
              },
              child: const Text('Reset Settings',
                  style: TextStyle(color: settingsRed)),
            ),
          ],
        );
      },
    );
  }
}