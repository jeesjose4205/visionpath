import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';

/// The top-bar feedback switch shown on every screen: sound -> muted.
///
/// Tapping toggles between the two states. Use the bare [SoundModeButton] in
/// the standard white header containers; use [iconFor]/[toggle] with
/// [SoundModeIcon] to keep a screen's custom button container.
class SoundModeButton extends StatelessWidget {
  const SoundModeButton({super.key});

  /// The next state after [mode] when the toggle is pressed.
  static AlertMode nextOf(AlertMode mode) {
    return switch (mode) {
      AlertMode.sound => AlertMode.muted,
      AlertMode.muted => AlertMode.sound,
    };
  }

  /// Feedback icon for [mode].
  static IconData iconFor(AlertMode mode) {
    return switch (mode) {
      AlertMode.sound => Icons.volume_up,
      AlertMode.muted => Icons.volume_off,
    };
  }

  /// Semantics/tooltip label for [mode].
  static String labelFor(AlertMode mode) {
    return switch (mode) {
      AlertMode.sound => 'Speaker mode',
      AlertMode.muted => 'Mute mode',
    };
  }

  /// Advance the global ringer to its next state.
  static void toggle() {
    final s = SettingsService.instance;
    s.setAlertMode(nextOf(s.alertMode));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final mode = SettingsService.instance.alertMode;
        return Semantics(
          button: true,
          label: labelFor(mode),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Icon(
                  iconFor(mode),
                  color: const Color(0xFF344054),
                  size: 21,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Icon-only variant for screens with custom button containers; rebuilds when
/// the ringer state changes so the icon always matches the mode.
class SoundModeIcon extends StatelessWidget {
  const SoundModeIcon({
    super.key,
    this.size = 21,
    this.color = const Color(0xFF344054),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) => Icon(
        SoundModeButton.iconFor(SettingsService.instance.alertMode),
        size: size,
        color: color,
      ),
    );
  }
}