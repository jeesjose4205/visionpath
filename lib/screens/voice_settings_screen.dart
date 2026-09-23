import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../widgets/settings_widgets.dart';

/// Voice & Audio settings: guidance, rate, volume, language, repeat,
/// announcement frequency and a test button that speaks a sample line.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final VoiceService _voice = VoiceService();

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _voice.setEnabled(s.voiceGuidanceEnabled && !s.globalVoiceMuted);
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    unawaited(_voice.dispose());
    super.dispose();
  }

  void _onSettingsChanged() {
    final s = SettingsService.instance;
    _voice.setEnabled(s.voiceGuidanceEnabled && !s.globalVoiceMuted);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        return SettingsScaffold(
          title: 'Voice & Audio',
          subtitle:
              'Voice is how VisionPath guides you. Tune how it sounds here.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('Voice Guidance'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Voice Guidance',
                      description:
                          'Receive spoken guidance from VisionPath for '
                          'navigation, detection, reading and faces.',
                      value: s.voiceGuidanceEnabled,
                      onChanged: (v) =>
                          s.setVoiceGuidanceEnabled(v),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Sound'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsChoice(
                      title: 'Speech Rate',
                      selected: _rateLabel(s.speechRate),
                      choices: const [
                        (label: 'Slow', value: 'slow'),
                        (label: 'Normal', value: 'normal'),
                        (label: 'Fast', value: 'fast'),
                      ],
                      onSelected: (v) => s.setSpeechRate(
                        SpeechRate.values.firstWhere((e) => e.name == v),
                      ),
                    ),
                    _divider(),
                    _VolumeControl(s: s),
                    _divider(),
                    SettingsChoice(
                      title: 'Voice Language',
                      selected: _languageLabel(s.voiceLanguage),
                      description:
                          'Only languages supported by the device\'s TTS '
                          'engine will be announced successfully.',
                      choices: const [
                        (label: 'English (US)', value: 'usEnglish'),
                        (label: 'English (UK)', value: 'ukEnglish'),
                      ],
                      onSelected: (v) => s.setVoiceLanguage(
                        VoiceLanguage.values.firstWhere((e) => e.name == v),
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Announcements'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Repeat Last Instruction',
                      description:
                          'Repeat the previous voice instruction when '
                          'requested by the user.',
                      value: s.repeatInstruction,
                      onChanged: (v) => s.setRepeatInstruction(v),
                    ),
                    _divider(),
                    SettingsChoice(
                      title: 'Announcement Frequency',
                      selected:
                          'Every ${s.announcementCooldownSeconds} seconds',
                      description:
                          'How often repeated information may be spoken. '
                          'Prevents the app from repeating the same '
                          'announcement constantly.',
                      choices: const [
                        (label: 'Often (every 2 seconds)', value: '2'),
                        (label: 'Normal (every 3 seconds)', value: '3'),
                        (label: 'Calm (every 5 seconds)', value: '5'),
                        (label: 'Rarely (every 8 seconds)', value: '8'),
                      ],
                      onSelected: (v) =>
                          s.setAnnouncementCooldown(int.parse(v)),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Preview'),
              SettingsCard(
                child: SettingsActionButton(
                  label: 'Test Voice',
                  icon: Icons.volume_up_outlined,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _voice.speak(
                      'This is VisionPath speaking. You can see beyond, '
                      'together.',
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
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.s});

  final SettingsService s;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.volume_down_outlined, color: settingsGreen, size: 20),
              SizedBox(width: 10),
              Text(
                'Voice Volume',
                style: TextStyle(
                  color: settingsInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: widget.s.voiceVolume,
            min: 0.2,
            max: 1.0,
            divisions: 4,
            activeColor: settingsBlue,
            label: '${(widget.s.voiceVolume * 100).round()}%',
            onChanged: (v) => widget.s.setVoiceVolume(v),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              '${(widget.s.voiceVolume * 100).round()}% volume',
              style: const TextStyle(
                color: settingsSubtext,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
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

String _languageLabel(VoiceLanguage l) {
  switch (l) {
    case VoiceLanguage.systemDefault:
      return 'English (US)';
    case VoiceLanguage.usEnglish:
      return 'English (US)';
    case VoiceLanguage.ukEnglish:
      return 'English (UK)';
  }
}