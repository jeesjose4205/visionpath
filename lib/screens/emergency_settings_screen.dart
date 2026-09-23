import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/sos_gesture.dart';
import 'emergency_screen.dart';

/// Emergency settings: contact management entry, SOS hold duration and SOS
/// confirmation. Emergency access must stay simple and fast — none of these
/// settings remove emergency functionality.
class EmergencySettingsScreen extends StatelessWidget {
  const EmergencySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Emergency',
          subtitle:
              'Emergency stays simple and fast. These options tune how SOS '
              'behaves without removing it.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Contacts'),
              SettingsCard(
                child: SettingsLink(
                  title: 'Manage Emergency Contacts',
                  description:
                      'Add, edit, delete and view up to 5 contacts. '
                      'Fire existing contact management.',
                  icon: Icons.contacts_outlined,
                  accent: settingsRed,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(name: kSosRouteName),
                        builder: (_) => const EmergencyScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SettingsSectionTitle('SOS'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'SOS Hold Duration',
                      selected: '${s.sosHoldDurationSeconds} seconds',
                      description:
                          'How long the SOS button must be held before it '
                          'activates. Prevents accidental activation.',
                      choices: const [
                        (label: '3 seconds', value: '3'),
                        (label: '5 seconds', value: '5'),
                        (label: '7 seconds', value: '7'),
                      ],
                      onSelected: (v) =>
                          s.setSosHoldDuration(int.parse(v)),
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'SOS Confirmation',
                      description:
                          'Speak a short confirmation before dispatching. '
                          'Keep this on to avoid accidental calls.',
                      value: s.sosConfirmation,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setSosConfirmation(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsNote(
                'Disabling close-obstacle warnings or adjusting SOS behavior '
                'does not create a fully safe environment. VisionPath is an '
                'assistive tool, not a safety guarantee.',
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);