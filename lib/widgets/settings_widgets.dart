import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// VisionPath AI settings palette (matches the Home screen).
const Color settingsInk = Color(0xFF15233D);
const Color settingsBlue = Color(0xFF1769E0);
const Color settingsGreen = Color(0xFF1E8E3E);
const Color settingsRed = Color(0xFFE63B3B);
const Color settingsSubtext = Color(0xFF718096);
const Color settingsBg = Color(0xFFF8FAFD);
const Color settingsBorder = Color(0xFFE3E8EF);

/// Consistent settings-scaffold header.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: settingsBg,
      appBar: AppBar(
        backgroundColor: settingsBg,
        foregroundColor: settingsInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: settingsInk,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: subtitle == null
            ? body
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: settingsSubtext,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
      ),
    );
  }
}

/// Rounded white card used for every settings group.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: settingsBorder),
      ),
      child: child,
    );
  }
}

/// Section heading above a group of settings.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: settingsBlue,
        ),
      ),
    );
  }
}

/// Toggle row: label + description + [Switch]. Records feedback loud enough
/// for the screen reader and (optionally) haptic feedback.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.haptics = true,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool haptics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $description. ${value ? 'On.' : 'Off.'}',
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(
            color: settingsInk,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(
            color: settingsSubtext,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        value: value,
        activeTrackColor: settingsBlue,
        onChanged: (next) {
          if (haptics) {
            HapticFeedback.selectionClick();
          }
          onChanged(next);
        },
      ),
    );
  }
}

/// Selection row that opens a bottom-sheet list of [Choice] options.
class SettingsChoice extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.title,
    required this.selected,
    required this.choices,
    required this.onSelected,
    this.description,
  });

  final String title;
  final String selected;
  final List<({String label, String value})> choices;
  final void Function(String value) onSelected;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. Currently $selected.',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune_rounded, color: settingsGreen),
        title: Text(
          title,
          style: const TextStyle(
            color: settingsInk,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: description == null
            ? Text(
                selected,
                style: const TextStyle(
                  color: settingsBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description!,
                    style: const TextStyle(
                      color: settingsSubtext,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selected,
                    style: const TextStyle(
                      color: settingsBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: settingsSubtext,
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          _showChoiceSheet(
            context,
            title: title,
            choices: choices,
            selected: selected,
            onSelected: onSelected,
          );
        },
      ),
    );
  }

  void _showChoiceSheet(
    BuildContext context, {
    required String title,
    required List<({String label, String value})> choices,
    required String selected,
    required void Function(String value) onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: settingsInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final choice in choices)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    choice.label,
                    style: const TextStyle(
                      color: settingsInk,
                      fontSize: 16,
                    ),
                  ),
                  trailing: choice.value == selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: settingsBlue)
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onSelected(choice.value);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Navigation row that pushes another screen.
class SettingsLink extends StatelessWidget {
  const SettingsLink({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.accent = settingsBlue,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: accent, size: 26),
        title: Text(
          title,
          style: const TextStyle(
            color: settingsInk,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(
            color: settingsSubtext,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        trailing: trailing ??
            const Icon(Icons.chevron_right_rounded, color: settingsSubtext),
        onTap: onTap,
      ),
    );
  }
}

/// Primary action button inside a card (e.g. destructive ones).
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.onTap,
    this.description,
  });

  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback? onTap;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? settingsRed : settingsInk;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      style: const TextStyle(
                        color: settingsSubtext,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill label used to tag options that affect live services.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E4FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: settingsBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: settingsInk,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}