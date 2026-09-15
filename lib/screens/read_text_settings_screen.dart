import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Read Text settings: auto-read, camera guidance, OCR language and reading
/// speed. Read Text uses camera → positioning guidance → capture → OCR →
/// voice output; nothing here introduces fake results.
class ReadTextSettingsScreen extends StatelessWidget {
  const ReadTextSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Read Text',
          subtitle:
              'Camera-based text recognition. Turn the phone toward text '
              'and VisionPath will read it aloud.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Reading'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Automatic Text Reading',
                      description:
                          'Begin reading automatically when steady text is '
                          'detected.',
                      value: s.readTextAutoRead,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setReadTextAutoRead(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Camera'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Camera Position Guidance',
                      description:
                          'Speak directions such as \u201cMove closer\u201d '
                          'and \u201cText is centered.\u201d while framing.',
                      value: s.textPositionGuidance,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        s.setTextPositionGuidance(v);
                      },
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Recognition'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'OCR Language',
                      selected: _ocrLabel(s.ocrLanguage),
                      description:
                          'Language script used for text recognition. '
                          'Unsupported scripts will be silently skipped '
                          'by the recognition engine.',
                      choices: const [
                        (label: 'Latin (English, etc.)', value: 'latin'),
                      ],
                      onSelected: (v) => s.setOcrLanguage(v),
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Reading Speed',
                      selected: _rateLabel(s.readingSpeed),
                      description:
                          'Speed of the spoken text after recognition.',
                      choices: const [
                        (label: 'Slow', value: 'slow'),
                        (label: 'Normal', value: 'normal'),
                        (label: 'Fast', value: 'fast'),
                      ],
                      onSelected: (v) => s.setReadingSpeed(
                        SpeechRate.values.firstWhere((e) => e.name == v),
                      ),
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

String _rateLabel(SpeechRate r) {
  switch (r) {
    case SpeechRate.slow:
      return 'Slow';
    case SpeechRate.normal:
      return 'Normal';
    case SpeechRate.fast:
      return 'Fast';
  }
}

String _ocrLabel(String v) {
  switch (v) {
    case 'latin':
      return 'Latin (English, etc.)';
    default:
      return v;
  }
}