import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/familiar_face.dart';
import '../services/familiar_face_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../widgets/settings_button.dart';

/// Registered faces management screen - lists every person stored on this
/// device and lets the user speak a name aloud, rename a person, or delete
/// them entirely (privacy: deletion removes all biometric data).
///
/// The list is live: it re-renders whenever [FamiliarFaceService] notifies,
/// so people added from the registration flow appear immediately on return.
class RegisteredFacesScreen extends StatefulWidget {
  const RegisteredFacesScreen({super.key});

  @override
  State<RegisteredFacesScreen> createState() => _RegisteredFacesScreenState();
}

class _RegisteredFacesScreenState extends State<RegisteredFacesScreen> {
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final VoiceService _voice = VoiceService();
  bool _voiceEnabled = true;
  DateTime? _lastVoiceAt;

  @override
  void initState() {
    super.initState();
    _applyVoiceSettings();
    SettingsService.instance.addListener(_applyVoiceSettings);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applyVoiceSettings);
    _voice.dispose();
    super.dispose();
  }

  void _applyVoiceSettings() {
    final s = SettingsService.instance;
    _voiceEnabled = s.voiceGuidanceEnabled && !s.globalVoiceMuted;
    _voice.setEnabled(_voiceEnabled);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
    if (mounted) setState(() {});
  }

  void _toggleVoice() {
    SettingsService.instance.setGlobalVoiceMuted(
      !SettingsService.instance.globalVoiceMuted,
    );
  }

  void _speak(String message) {
    if (!_voiceEnabled) return;
    final now = DateTime.now();
    final last = _lastVoiceAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastVoiceAt = now;
    _voice.speak(message);
  }

  String _formatAdded(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _renamePerson(BuildContext context, FamiliarFace person) async {
    final service = context.read<FamiliarFaceService>();
    final nameCtrl = TextEditingController(text: person.name);
    final relCtrl = TextEditingController(text: person.relationship ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit person',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: relCtrl,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  labelText: 'Relationship (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) {
      nameCtrl.dispose();
      relCtrl.dispose();
      return;
    }

    final newName = nameCtrl.text.trim();
    final newRel = relCtrl.text.trim();
    nameCtrl.dispose();
    relCtrl.dispose();

    if (!mounted) return;
    final updated = await service.updatePerson(
      person.id,
      name: newName,
      relationship: newRel.isEmpty ? null : newRel,
    );
    if (updated && mounted) {
      _speak('$newName updated.');
    }
  }

  Future<void> _deletePerson(BuildContext context, FamiliarFace person) async {
    final service = context.read<FamiliarFaceService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete person?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove ${person.name} from this device entirely? '
          'All stored face data will be erased.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD92D20)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    await service.deletePerson(person.id);
    if (mounted) {
      _speak('${person.name} deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool compact = size.height < 700;
    final people = context.watch<FamiliarFaceService>().people;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(compact),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  8,
                  compact ? 14 : 18,
                  compact ? 10 : 16,
                ),
                child: Column(
                  children: [
                    _buildTitleRow(compact, people.length),
                    SizedBox(height: compact ? 8 : 12),
                    Expanded(
                      child: people.isEmpty
                          ? _buildEmptyState(compact)
                          : _buildPersonList(compact, people),
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    _buildPrivacyNote(compact),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        compact ? 8 : 14,
        compact ? 12 : 18,
        4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              label: 'VisionPath AI',
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'VisionPath '),
                    const TextSpan(
                      text: 'AI',
                      style: TextStyle(color: Color(0xFF1769E0)),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 20 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: const Color(0xFF182230),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _HeaderButton(
            icon: _voiceEnabled
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            label: 'Speaker',
            onTap: _toggleVoice,
          ),
          const SizedBox(width: 10),
          const SettingsButton(),
        ],
      ),
    );
  }

  Widget _buildTitleRow(bool compact, int count) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registered Faces',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF182230),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                count == 0
                    ? 'No one registered yet'
                    : '$count ${count == 1 ? 'person is' : 'people are'} '
                        'stored on this device',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF5FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF175CD3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool compact) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 20 : 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E7EC)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF5FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: Color(0xFF175CD3),
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No one registered yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 15 : 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF182230),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Press Add Person on the Familiar Faces screen to register '
              'the first face.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                height: 1.4,
                color: const Color(0xFF667085),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonList(bool compact, List<FamiliarFace> people) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final person = people[index];
        return _buildPersonCard(compact, person);
      },
    );
  }

  Widget _buildPersonCard(bool compact, FamiliarFace person) {
    final initial = person.name
        .trim()
        .isEmpty
        ? '?'
        : person.name.trim()[0].toUpperCase();
    final subtitleParts = <String>[
      '${person.sampleCount} ${person.sampleCount == 1 ? 'sample' : 'samples'}',
      'Added ${_formatAdded(person.createdAt)}',
      if (person.relationship != null &&
          person.relationship!.isNotEmpty)
        person.relationship!,
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E7CF6), Color(0xFF6E5BFF)],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF182230),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _IconAction(
            icon: Icons.volume_up_outlined,
            label: 'Speak ${person.name}',
            onTap: () => _speak('${person.name} is registered.'),
          ),
          _IconAction(
            icon: Icons.edit_outlined,
            label: 'Edit ${person.name}',
            onTap: () => _renamePerson(context, person),
          ),
          _IconAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete ${person.name}',
            destructive: true,
            onTap: () => _deletePerson(context, person),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNote(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Color(0xFF1E8E3E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Faces are stored only on this device. Nothing is uploaded.',
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                color: const Color(0xFF3E6447),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HEADER BUTTON
// ============================================================

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF344054),
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ICON ACTION BUTTON
// ============================================================

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Icon(
              icon,
              color: destructive
                  ? const Color(0xFFD92D20)
                  : const Color(0xFF344054),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}