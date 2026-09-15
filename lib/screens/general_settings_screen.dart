import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'about_screen.dart';

/// General settings: app language, theme, notifications, reset-to-defaults
/// and a link to the About screen.
///
/// Reset Settings only restores preferences — it never deletes familiar
/// faces, emergency contacts or history.
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'General',
          subtitle: 'App-wide preferences and information.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Language'),
              SettingsCard(
                child: SettingsChoice(
                  title: 'App Language',
                  selected: _languageLabel(s.appLanguage),
                  description:
                      'Language of the app interface where supported.',
                  choices: const [
                    (label: 'English', value: 'en'),
                  ],
                  onSelected: (v) => s.setAppLanguage(v),
                ),
              ),
              const SettingsSectionTitle('Appearance'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Theme',
                      selected: _themeLabel(s.theme),
                      description:
                          'VisionPath keeps its visual identity in every '
                          'theme.',
                      choices: const [
                        (label: 'System Default', value: 'system'),
                        (label: 'Light', value: 'light'),
                        (label: 'Dark', value: 'dark'),
                      ],
                      onSelected: (v) => s.setTheme(
                        AppThemePreference.values.firstWhere((e) => e.name == v),
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Notifications'),
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
              const SettingsSectionTitle('Manage'),
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
                    _confirmReset(context, s);
                  },
                ),
              ),
              const SettingsSectionTitle('About'),
              SettingsCard(
                child: SettingsLink(
                  title: 'About VisionPath AI',
                  description: 'Vision, purpose, features and version.',
                  icon: Icons.info_outline_rounded,
                  accent: settingsBlue,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmReset(BuildContext context, SettingsService s) {
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
                s.resetToDefaults();
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

String _themeLabel(AppThemePreference t) {
  switch (t) {
    case AppThemePreference.system:
      return 'System Default';
    case AppThemePreference.light:
      return 'Light';
    case AppThemePreference.dark:
      return 'Dark';
  }
}

String _languageLabel(String code) {
  switch (code) {
    case 'en':
      return 'English';
    default:
      return code;
  }
}