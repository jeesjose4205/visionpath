import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/familiar_face.dart';
import '../services/familiar_face_service.dart';
import '../services/voice_service.dart';
import 'face_recognition_screen.dart';
import 'face_registration_screen.dart';

/// Familiar Faces hub: register, browse, edit, delete and recognize people.
///
/// Accessibility-first: large touch targets, high contrast, minimal chrome,
/// and every person can be read aloud.
class FamiliarFacesScreen extends StatefulWidget {
  const FamiliarFacesScreen({super.key});

  @override
  State<FamiliarFacesScreen> createState() => _FamiliarFacesScreenState();
}

class _FamiliarFacesScreenState extends State<FamiliarFacesScreen> {
  static const Color _navy = Color(0xFF0E2A47);
  static const Color _accent = Color(0xFF1769E0);

  final VoiceService _voice = VoiceService();

  FamiliarFaceService get _service =>
      context.read<FamiliarFaceService>();

  @override
  void initState() {
    super.initState();
    _voice.setEnabled(true);
    // The registry is provided and pre-loaded by the app; no need to load
    // again here.
    Future<void>.microtask(() {
      if (!_service.loaded) {
        _service.load();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _voice.speak('Familiar Faces. ' +
            (_service.people.isEmpty
                ? 'No people registered yet. Press add to register someone.'
                : '${_service.people.length} ${_service.people.length == 1 ? 'person is' : 'people are'} registered.'));
      }
    });
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _openRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FaceRegistrationScreen()),
    );
  }

  Future<void> _openRecognition() async {
    if (_service.people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register at least one person first.'),
        ),
      );
      _voice.speak('Register at least one person first.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FaceRecognitionScreen()),
    );
  }

  Future<void> _editPerson(FamiliarFace person) async {
    final nameController = TextEditingController(text: person.name);
    final relController = TextEditingController(text: person.relationship ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit person'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'e.g. Mother, Father, Jees',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: relController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship (optional)',
                    helperText: 'e.g. Mother, Friend, Teacher',
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved == true && mounted) {
      await _service.updatePerson(
        person.id,
        name: nameController.text.trim(),
        relationship: relController.text.trim(),
      );
      _voice.speak('Updated ${nameController.text.trim()}.');
    }
  }

  Future<void> _deletePerson(FamiliarFace person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete person?'),
          content: Text(
            'This permanently removes ${person.name}\'s face data '
            'and embeddings from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _service.deletePerson(person.id);
      _voice.speak('${person.name} removed.');
    }
  }

  void _speakPerson(FamiliarFace person) {
    final rel =
        (person.relationship?.isNotEmpty ?? false) ? person.relationship! : null;
    _voice.speak(rel == null
        ? '${person.name}. Registered with ${person.sampleCount} '
            '${person.sampleCount == 1 ? 'sample' : 'samples'}.'
        : '$rel, ${person.name}. Registered with ${person.sampleCount} '
            '${person.sampleCount == 1 ? 'sample' : 'samples'}.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(
              child: ListenableBuilder(
                listenable: _service,
                builder: (context, _) {
                  final people = _service.people;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    itemCount: people.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildActions(people.isNotEmpty);
                      }
                      final person = people[index - 1];
                      return _PersonCard(
                        person: person,
                        onRecognize: _openRecognition,
                        onEdit: () => _editPerson(person),
                        onDelete: () => _deletePerson(person),
                        onSpeak: () => _speakPerson(person),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------- HEADER ---------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, Color(0xFF123A63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            dark: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Familiar Faces',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'The app remembers these people by name',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 10),
                ListenableBuilder(
                  listenable: _service,
                  builder: (context, _) {
                    final count = _service.people.length;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        '$count REGISTERED',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- ACTIONS ---------------------------

  Widget _buildActions(bool hasPeople) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Add Person',
                  hint: 'Voice-guided registration',
                  foreground: Colors.white,
                  background: const Color(0xFF1E8E3E),
                  onTap: _openRegistration,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.face_retouching_natural_rounded,
                  label: 'Recognize',
                  hint: hasPeople ? 'Live camera scanning' : 'Needs 1+ person',
                  foreground: Colors.white,
                  background: hasPeople ? _accent : const Color(0xFF8A97AB),
                  onTap: _openRecognition,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: Color(0xFF8A97AB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Face data never leaves this device.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------- PERSON CARD ---------------------------

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26, color: foreground),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11.5,
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.onRecognize,
    required this.onEdit,
    required this.onDelete,
    required this.onSpeak,
  });

  final FamiliarFace person;
  final VoidCallback onRecognize;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final rel = person.relationship;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E8E3E), Color(0xFF2FBF6A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              _FamiliarFacesScreenState._initials(person.name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15233D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rel == null
                      ? '${person.sampleCount} '
                          '${person.sampleCount == 1 ? 'sample' : 'samples'}'
                      : '$rel · ${person.sampleCount} '
                          '${person.sampleCount == 1 ? 'sample' : 'samples'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Recognize',
            onPressed: onRecognize,
            icon: const Icon(
              Icons.face_rounded,
              color: Color(0xFF1769E0),
            ),
            iconSize: 26,
          ),
          IconButton(
            tooltip: 'Speak name',
            onPressed: onSpeak,
            icon:
                const Icon(Icons.volume_up_outlined, color: Color(0xFF1769E0)),
            iconSize: 24,
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF8A5A00)),
            iconSize: 22,
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFC62828)),
            iconSize: 22,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.dark = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF15233D);
    final bg = dark ? Colors.white.withValues(alpha: 0.12) : Colors.white;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: dark ? 0 : 1,
      child: IconButton(
        icon: Icon(icon, color: fg),
        onPressed: onPressed,
        iconSize: 24,
        padding: const EdgeInsets.all(11),
      ),
    );
  }
}