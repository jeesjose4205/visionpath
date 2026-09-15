import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Detection settings control which objects VisionPath announces and how
/// confidently it reports them. The actual YOLO confidence threshold is
/// derived internally from the sensitivity choice, never shown as raw ML
/// terminology.
class DetectionSettingsScreen extends StatelessWidget {
  const DetectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Detection',
          subtitle:
              'Choose what VisionPath announces when it looks around you.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Voice'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Object Detection Voice',
                      description:
                          'Speak detected objects and obstacles.',
                      value: s.detectionVoiceEnabled,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setDetectionVoiceEnabled(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Announcements'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'People Announcements',
                      description: 'Announce \u201cPerson ahead.\u201d',
                      value: s.peopleAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setPeopleAnnouncements(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Vehicle Announcements',
                      description:
                          'Announce cars and other vehicles.',
                      value: s.vehicleAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setVehicleAnnouncements(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Animal Announcements',
                      description: 'Announce animals such as dogs and cats.',
                      value: s.animalAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setAnimalAnnouncements(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Furniture & Objects',
                      description:
                          'Announce common objects such as chairs, tables '
                          'and doors.',
                      value: s.furnitureAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setFurnitureAnnouncements(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Obstacle Announcements',
                      description:
                          'Announce anything blocking the path in front '
                          'of you.',
                      value: s.obstacleAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setObstacleAnnouncements(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Sensitivity'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Detection Sensitivity',
                      description:
                          'Conservative reports only clear objects, '
                          'reducing unreliable announcements.',
                      selected: _sensitivityLabel(s.detectionSensitivity),
                      choices: const [
                        (label: 'Conservative', value: 'conservative'),
                        (label: 'Balanced', value: 'balanced'),
                        (label: 'Sensitive', value: 'sensitive'),
                      ],
                      onSelected: (v) => s.setDetectionSensitivity(
                        DetectionSensitivity.values
                            .firstWhere((e) => e.name == v),
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsNote(
                'Sensitivity controls how likely VisionPath is to speak. '
                'Setting it higher can increase both useful reports and '
                'false reports. Setting it lower helps avoid unreliable '
                'announcements.',
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);

String _sensitivityLabel(DetectionSensitivity v) =>
    v.name[0].toUpperCase() + v.name.substring(1);