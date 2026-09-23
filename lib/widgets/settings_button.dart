import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// Fixed, always-available Settings access button used on every main screen.
///
/// Opens the existing [SettingsScreen]; the system back button returns to the
/// launching screen. Matches the visual language of the per-screen header
/// icon buttons (white rounded tile with a border).
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Settings',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            );
          },
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: Color(0xFF344054),
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}