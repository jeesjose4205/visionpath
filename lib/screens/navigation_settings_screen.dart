import 'package:flutter/material.dart';
import '../services/vibration_service.dart';

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
                        VibrationService.instance.selectionClick();
                        s.setNavigationVoiceEnabled(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Depth Analysis'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Depth Analysis',
                      description:
                          'Use the on-device relative-depth engine to refine '
                          'obstacle proximity and path blocking. When off or '
                          'unavailable, the app falls back to box-size '
                          'estimates. Depth is always relative, never exact '
                          'distance.',
                      value: s.depthAnalysisEnabled,
                      onChanged: (v) {
                        VibrationService.instance.selectionClick();
                        s.setDepthAnalysisEnabled(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Depth Debug Overlay',
                      description:
                          'Show the depth regions (LEFT / CENTER / RIGHT), '
                          'blocking level and relative depth over the camera '
                          'preview. For troubleshooting only.',
                      value: s.depthDebugOverlay,
                      onChanged: (v) {
                        VibrationService.instance.selectionClick();
                        s.setDepthDebugOverlay(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Distance Calibration'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Distance Estimates',
                      description:
                          'Estimate each detected object\u2019s distance in '
                          'meters below its bounding box. Distances are '
                          'calibrated estimates, not exact measurements.',
                      value: s.metricDistanceEnabled,
                      onChanged: (v) {
                        VibrationService.instance.selectionClick();
                        s.setMetricDistanceEnabled(v);
                      },
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Phone Height',
                      description:
                          'How high the phone is typically held when '
                          'navigating. Lower = closer-looking estimates.',
                      selected: _heightLabel(s.cameraHeightMeters),
                      choices: const [
                        (label: '1.2 m (waist)', value: 'h12'),
                        (label: '1.5 m (chest)', value: 'h15'),
                        (label: '1.8 m (eye)', value: 'h18'),
                      ],
                      onSelected: (v) {
                        final double h = switch (v) {
                          'h12' => 1.2,
                          'h18' => 1.8,
                          _ => 1.5,
                        };
                        s.setCameraHeightMeters(h);
                      },
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Phone Tilt',
                      description:
                          'How far the phone is pointed toward the floor. '
                          'More tilt = objects read as nearer.',
                      selected: _tiltLabel(s.cameraPitchDegrees),
                      choices: const [
                        (label: '10\u00B0 (mostly level)', value: 't10'),
                        (label: '20\u00B0 (slight tilt)', value: 't20'),
                        (label: '30\u00B0 (pointed down)', value: 't30'),
                      ],
                      onSelected: (v) {
                        final double t = switch (v) {
                          't10' => 10.0,
                          't30' => 30.0,
                          _ => 20.0,
                        };
                        s.setCameraPitchDegrees(t);
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
                        VibrationService.instance.selectionClick();
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

String _heightLabel(double h) => switch (h) {
      1.2 => '1.2 m (waist)',
      1.8 => '1.8 m (eye)',
      _ => '1.5 m (chest)',
    };

String _tiltLabel(double t) => switch (t) {
      10 => '10\u00B0 (mostly level)',
      30 => '30\u00B0 (pointed down)',
      _ => '20\u00B0 (slight tilt)',
    };

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
