import 'package:flutter/material.dart';
import '../services/vibration_service.dart';

import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Notifications settings: reuses the existing notification preference from
/// [SettingsService] (same key, same state — nothing duplicated).
class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Notifications',
          subtitle:
              'Status notifications from VisionPath AI. Emergency alerts are '
              'not affected.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SettingsCard(
                child: SettingsToggle(
                  title: 'Notifications',
                  description:
                      'Allow VisionPath to post non-emergency status '
                      'notifications. VisionPath does not currently post any '
                      'notifications of its own, so this preference changes '
                      'nothing yet. The emergency SOS alert is separate and '
                      'always works.',
                  value: s.notificationsEnabled,
                  onChanged: (v) {
                    VibrationService.instance.selectionClick();
                    s.setNotificationsEnabled(v);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
