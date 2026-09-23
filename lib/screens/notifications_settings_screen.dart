import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          subtitle: 'Status notifications from VisionPath AI.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SettingsCard(
                child: SettingsToggle(
                  title: 'Notifications',
                  description:
                      'Allow VisionPath to show status notifications.',
                  value: s.notificationsEnabled,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
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