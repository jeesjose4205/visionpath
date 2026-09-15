import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Accessibility settings: text size, high contrast, large buttons,
/// haptic feedback, voice-first mode and reduced animations.
class AccessibilitySettingsScreen extends StatelessWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Accessibility',
          subtitle:
              'Make VisionPath easier to see, hear and use. Every control '
              'works with the Android screen reader.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Display'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Text Size',
                      description:
                          'Affects text size throughout the app where '
                          'practical, including this screen.',
                      selected: _textSizeLabel(s.textSize),
                      choices: const [
                        (label: 'Standard', value: 'standard'),
                        (label: 'Large', value: 'large'),
                        (label: 'Extra Large', value: 'extraLarge'),
                      ],
                      onSelected: (v) => s.setTextSize(
                        TextSizeLevel.values.firstWhere((e) => e.name == v),
                      ),
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'High Contrast',
                      description:
                          'Strengthen contrast between background, text, '
                          'buttons and status indicators.',
                      value: s.highContrast,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setHighContrast(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Large Buttons',
                      description:
                          'Enlarge touch targets for buttons and controls '
                          'across the app.',
                      value: s.largeButtons,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setLargeButtons(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Interaction'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Haptic Feedback',
                      description:
                          'Vibrate on important actions such as button '
                          'activation, scan start/complete and SOS.',
                      value: s.hapticFeedback,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setHapticFeedback(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Voice-First Mode',
                      description:
                          'Prioritize spoken information for important '
                          'controls. Touch interaction still works normally.',
                      value: s.voiceFirstMode,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setVoiceFirstMode(v);
                      },
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Reduce Animations',
                      description:
                          'Minimize non-essential animations for a calmer '
                          'experience.',
                      value: s.reduceAnimations,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setReduceAnimations(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsNote(
                'Every control on this screen has a spoken label and works '
                'with TalkBack and other Android screen readers. Critical '
                'buttons such as Emergency SOS are always clearly announced.',
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);

String _textSizeLabel(TextSizeLevel t) {
  switch (t) {
    case TextSizeLevel.standard:
      return 'Standard';
    case TextSizeLevel.large:
      return 'Large';
    case TextSizeLevel.extraLarge:
      return 'Extra Large';
  }
}