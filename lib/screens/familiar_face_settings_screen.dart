import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'familiar_faces_screen.dart';

/// Familiar Faces settings. This is distinct from generic person detection:
/// recognition identifies a previously registered person by name using the
/// MobileFaceNet/TFLite embedding pipeline.
///
/// A wrong identification is worse than saying "Unknown person", so the
/// default sensitivity is conservative.
class FamiliarFaceSettingsScreen extends StatelessWidget {
  const FamiliarFaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Familiar Faces',
          subtitle:
              'Recognize the people you have registered, by name.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Recognition'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Familiar Face Recognition',
                      description:
                          'Recognize registered people using the on-device '
                          'face recognition model.',
                      value: s.familiarFacesEnabled,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setFamiliarFacesEnabled(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Voice Announcements',
                      description:
                          'Announce recognized people by name, for example '
                          '\u201cSarah is ahead.\u201d',
                      value: s.familiarFaceVoice,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setFamiliarFaceVoice(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Unknown Person Announcements',
                      description:
                          'Announce \u201cUnknown person.\u201d Off by '
                          'default to avoid excessive speech.',
                      value: s.unknownPersonAnnouncements,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setUnknownPersonAnnouncements(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Recognition Settings'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Recognition Sensitivity',
                      description:
                          'Conservative favours \u201cUnknown person\u201d '
                          'over a possible wrong name. Wrong identification '
                          'is worse than an unknown result.',
                      selected: _sensitivityLabel(s.familiarFaceSensitivity),
                      choices: const [
                        (label: 'Conservative', value: 'conservative'),
                        (label: 'Balanced', value: 'balanced'),
                        (label: 'Sensitive', value: 'sensitive'),
                      ],
                      onSelected: (v) => s.setFamiliarFaceSensitivity(
                        FamiliarFaceSensitivity.values
                            .firstWhere((e) => e.name == v),
                      ),
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Announcement Cooldown',
                      selected: 'Every ${s.familiarFaceCooldownSeconds} seconds',
                      description:
                          'How frequently an announced identity may repeat.',
                      choices: const [
                        (label: 'Often (every 2 seconds)', value: '2'),
                        (label: 'Normal (every 3 seconds)', value: '3'),
                        (label: 'Calm (every 5 seconds)', value: '5'),
                      ],
                      onSelected: (v) =>
                          s.setFamiliarFaceCooldown(int.parse(v)),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Manage'),
              SettingsCard(
                child: SettingsLink(
                  title: 'Manage Familiar Faces',
                  description:
                      'Add, view, edit or delete registered people.',
                  icon: Icons.manage_accounts_outlined,
                  accent: settingsBlue,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamiliarFacesScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SettingsNote(
                'Registered face data is sensitive biometric information. '
                'VisionPath keeps it local to this device and uses it only '
                'to recognize people you have chosen to register.',
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);

String _sensitivityLabel(FamiliarFaceSensitivity v) =>
    v.name[0].toUpperCase() + v.name.substring(1);