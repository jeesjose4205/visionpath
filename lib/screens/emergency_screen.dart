import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency_contact.dart';
import '../services/emergency_contact_service.dart';
import '../services/voice_service.dart';
import '../widgets/emergency_contact_card.dart';
import '../widgets/emergency_location_card.dart';
import '../widgets/emergency_sos_button.dart';

enum _SosStatus { ready, activating, activated }

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  static const Color _ink = Color(0xFF15233D);
  static const Color _sub = Color(0xFF718096);
  static const Color _accent = Color(0xFF1769E0);
  static const Color _border = Color(0xFFE3E8EF);
  static const Map<int, String> _numberWords = {
    1: 'one',
    2: 'two',
    3: 'three',
    4: 'four',
    5: 'five',
  };

  final EmergencyContactService _contactService = EmergencyContactService();
  final VoiceService _voice = VoiceService();

  bool _voiceEnabled = true;
  _SosStatus _status = _SosStatus.ready;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    _voice.setEnabled(_voiceEnabled);
    _contactService.addListener(_onContactsChanged);
    _loadContacts();
  }

  void _onContactsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContacts() async {
    await _contactService.load();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _contactService.removeListener(_onContactsChanged);
    _voice.setEnabled(false);
    unawaited(_voice.dispose());
    super.dispose();
  }

  void _toggleVoice() {
    setState(() => _voiceEnabled = !_voiceEnabled);
    _voice.setEnabled(_voiceEnabled);
    if (_voiceEnabled) _voice.speak('Voice prompts enabled.');
  }

  void _onTick(int remaining) {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.activating;
      _countdown = remaining;
    });
    if (remaining == 5) {
      _voice.speak('Emergency activation in five seconds.');
    } else {
      _voice.speak(_numberWords[remaining] ?? '$remaining');
    }
  }

  void _onActivated() {
    if (!mounted) return;
    setState(() => _status = _SosStatus.activated);
    _voice.speak('SOS activated.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showContactSheet();
    });
  }

  void _onCancelled() {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.ready;
      _countdown = 5;
    });
    _voice.speak('SOS cancelled.');
    showMessage(context, 'SOS cancelled.');
  }

  void _onReset() {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.ready;
      _countdown = 5;
    });
    _voice.speak('SOS deactivated. Stay safe.');
    showMessage(context, 'SOS reset.');
  }

  void _showContactSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final contacts = _contactService.contacts;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: contacts.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 46,
                        color: _sub.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No emergency contacts yet',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add a contact so you can call someone for help '
                        'after activating SOS.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _sub),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _openAddContact();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add Emergency Contact'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Choose an emergency contact to call',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The dialer will open with the number ready.',
                        style: TextStyle(color: _sub, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      for (final contact in contacts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFFFF0EE),
                                ),
                                child: Center(
                                  child: Text(
                                    contact.name.trim().isEmpty
                                        ? '?'
                                        : contact.name.trim().characters.first
                                            .toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFFE63B3B),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                contact.name,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                contact.phone,
                                style: const TextStyle(color: _sub),
                              ),
                              trailing: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _callContact(contact);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.call_rounded,
                                  size: 18,
                                ),
                                label: const Text('Call'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _callContact(EmergencyContact contact) async {
    _voice.speak('Calling ${contact.name}.');
    final uri = Uri(scheme: 'tel', path: contact.phone);
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (!mounted) return;
      if (canLaunch) {
        await launchUrl(uri);
        if (!mounted) return;
        showMessage(context, 'Opening dialer for ${contact.name}...');
      } else {
        showMessage(context, 'Unable to open the phone dialer.');
      }
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'Unable to open the phone dialer.');
    }
  }

  Future<void> _openAddContact() async {
    if (_contactService.hasReachedMax) {
      showMessage(context, 'Maximum 5 emergency contacts allowed.');
      return;
    }
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const ContactFormDialog(),
    );
    if (result == null || !mounted) return;
    final outcome = await _contactService.addContact(result.$1, result.$2);
    if (!mounted) return;
    _showOutcome(outcome);
  }

  Future<void> _openEditContact(int index) async {
    final current = _contactService.contactAt(index);
    if (current == null) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => ContactFormDialog(
        initialName: current.name,
        initialPhone: current.phone,
        title: 'Edit Emergency Contact',
        saveLabel: 'Save Contact',
      ),
    );
    if (result == null || !mounted) return;
    final outcome = await _contactService.updateContact(
      index,
      result.$1,
      result.$2,
      currentPhone: current.phone,
    );
    if (!mounted) return;
    _showOutcome(outcome);
  }

  void _showOutcome(ContactSaveResult outcome) {
    switch (outcome) {
      case ContactSaveResult.success:
        showMessage(context, 'Emergency contact saved.');
      case ContactSaveResult.duplicate:
        showMessage(context, 'This phone number is already saved.');
      case ContactSaveResult.maxReached:
        showMessage(context, 'Maximum 5 emergency contacts allowed.');
      case ContactSaveResult.invalid:
        showMessage(context, 'Please enter a name and a valid phone number.');
    }
  }

  void _confirmDelete(int index) {
    final contact = _contactService.contactAt(index);
    if (contact == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text(
          'Remove ${contact.name} (${contact.phone}) from emergency contacts?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _contactService.deleteContact(index);
              showMessage(context, 'Contact removed.');
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD92D20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final contacts = _contactService.contacts;
              final n = contacts.length;

              var cardH = 48.0;
              if (n > 0) {
                while (true) {
                  final budget =
                      height - 60 - 66 - _contactsHeight(cardH, n);
                  if (budget >= 130 || cardH <= 32) break;
                  cardH -= 2;
                }
              }
              final contactsBlock = _contactsHeight(cardH, n);
              var sosH = height - 60 - 66 - contactsBlock;
              if (sosH > 360) sosH = 360;

              return Column(
                children: [
                  SizedBox(height: 56, child: _buildHeader()),
                  const SizedBox(height: 4),
                  SizedBox(height: sosH < 0 ? 0 : sosH, child: _buildSosPanel()),
                  const Spacer(),
                  _buildContactsCard(cardH),
                  const SizedBox(height: 10),
                  const EmergencyLocationCard(),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _contactsHeight(double cardH, int n) {
    const double padV = 10;
    const double headerRow = 40;
    const double addButton = 46;
    if (n == 0) {
      return padV * 2 + headerRow + 10 + 66 + 10 + addButton;
    }
    return padV * 2 + headerRow + (n * cardH + (n - 1) * 7) + 12 + addButton;
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _CircleButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          color: _ink,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Quick access to help',
                style: TextStyle(color: _sub, fontSize: 12),
              ),
            ],
          ),
        ),
        _CircleButton(
          icon: _voiceEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          tooltip: _voiceEnabled ? 'Voice prompts: ON' : 'Voice prompts: OFF',
          color: _voiceEnabled ? _accent : const Color(0xFF9AA4B2),
          onTap: _toggleVoice,
        ),
      ],
    );
  }

  Widget _buildSosPanel() {
    final (Color bg, Color fg, Color dot, String text) = switch (_status) {
      _SosStatus.ready => (
          const Color(0xFFE4F8EF),
          const Color(0xFF15805A),
          const Color(0xFF2EBD6E),
          'READY',
        ),
      _SosStatus.activating => (
          const Color(0xFFFFF4E0),
          const Color(0xFFB26A00),
          const Color(0xFFE6A700),
          'ACTIVATING · $_countdown',
        ),
      _SosStatus.activated => (
          const Color(0xFFFFE8E8),
          const Color(0xFFC62828),
          const Color(0xFFFF5C63),
          'ACTIVATED',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F15233D),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: EmergencySOSButton(
                  onActivated: _onActivated,
                  onTick: _onTick,
                  onCancelled: _onCancelled,
                  onReset: _onReset,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsCard(double cardH) {
    final contacts = _contactService.contacts;
    final n = contacts.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F15233D),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'EMERGENCY CONTACTS',
                style: TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$n/5',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (n == 0)
            Container(
              height: 66,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEAF0F7)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 22,
                    color: _sub.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'No emergency contacts yet',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Add up to 5 trusted people',
                    style: TextStyle(color: _sub, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < n; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == n - 1 ? 0 : 7),
                child: EmergencyContactCard(
                  height: cardH,
                  contact: contacts[i],
                  onCall: () => _callContact(contacts[i]),
                  onEdit: () => _openEditContact(i),
                  onDelete: () => _confirmDelete(i),
                ),
              ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onAddPressed,
              borderRadius: BorderRadius.circular(16),
              child: Semantics(
                button: true,
                label: 'Add emergency contact',
                child: Container(
                  height: 46,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF2E7BE6), _accent],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x331769E0),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'ADD EMERGENCY CONTACT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onAddPressed() {
    if (_contactService.hasReachedMax) {
      showMessage(context, 'Maximum 5 emergency contacts allowed.');
      return;
    }
    _openAddContact();
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE3E8EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F15233D),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 23),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CONTACT FORM DIALOG
// ============================================================

class ContactFormDialog extends StatefulWidget {
  const ContactFormDialog({
    super.key,
    this.initialName = '',
    this.initialPhone = '',
    this.title = 'Add Emergency Contact',
    this.saveLabel = 'Add Contact',
  });

  final String initialName;
  final String initialPhone;
  final String title;
  final String saveLabel;

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _nameError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    setState(() {
      _nameError =
          EmergencyContactService.isValidName(name) ? null : 'Enter a name.';
      _phoneError = EmergencyContactService.isValidPhone(phone)
          ? null
          : 'Enter a valid phone number.';
    });
    if (_nameError != null || _phoneError != null) return;
    Navigator.of(context).pop((name, phone));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Mom',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9+\-() ]'),
              ),
              LengthLimitingTextInputFormatter(20),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: 'e.g. +1 555 123 4567',
              errorText: _phoneError,
              helperText: '8-15 digits',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD92D20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

// ============================================================
// GLOBAL MESSAGE
// ============================================================

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}