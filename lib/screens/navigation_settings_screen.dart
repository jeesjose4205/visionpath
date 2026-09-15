import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Navigation settings for the camera-based navigation assistant.
///
/// IMPORTANT: this is NOT GPS route navigation. It analyses what the camera
/// sees and provides movement guidance. Nothing here guarantees safety.
class NavigationSettingsScreen extends StatelessWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Navigation',
          subtitle:
              'Camera-based navigation assistance. Guidance is never a '
              'guarantee of safety — always be aware of your surroundings.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Guidance'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Navigation Voice',
                      description:
                          'Announce movement guidance such as '
                          '\u201cPath appears clear. Move forward.\u201d',
                      value: s.navigationVoiceEnabled,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setNavigationVoiceEnabled(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Warnings'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Obstacle Warning Sensitivity',
                      description:
                          'Controls how readily obstacles are reported as '
                          'warnings. Does not affect detection guarantees.',
                      selected: _sensitivityLabel(s.obstacleSensitivity),
                      choices: const [
                        (label: 'Low', value: 'low'),
                        (label: 'Medium', value: 'medium'),
                        (label: 'High', value: 'high'),
                      ],
                      onSelected: (v) => s.setObstacleSensitivity(
                        ObstacleSensitivity.values
                            .firstWhere((e) => e.name == v),
                      ),
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Guidance Frequency',
                      description: 'How often navigation guidance is spoken.',
                      selected: _guidanceModeLabel(s.guidanceMode),
                      choices: const [
                        (label: 'More frequent guidance', value: 'moreFrequent'),
                        (label: 'Balanced', value: 'balanced'),
                        (label: 'Minimal guidance', value: 'minimal'),
                      ],
                      onSelected: (v) => s.setGuidanceMode(
                        GuidanceMode.values.firstWhere((e) => e.name == v),
                      ),
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Close-Obstacle Warnings',
                      description:
                          'Enable \u201cStop. Obstacle very close.\u201d '
                          'warnings. Critical obstacle warnings stay '
                          'prioritized whenever this is on.',
                      value: s.closeObstacleWarnings,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setCloseObstacleWarnings(v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);

String _sensitivityLabel(ObstacleSensitivity v) =>
    v.name[0].toUpperCase() + v.name.substring(1);

String _guidanceModeLabel(GuidanceMode v) {
  switch (v) {
    case GuidanceMode.balanced:
      return 'Balanced';
    case GuidanceMode.moreFrequent:
      return 'More frequent guidance';
    case GuidanceMode.minimal:
      return 'Minimal guidance';
  }
}