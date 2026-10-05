import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/emergency_contact.dart';
import '../models/sos_session.dart';
import '../services/emergency_contact_service.dart';
import '../services/settings_service.dart';
import '../services/sos_platform.dart';
import '../services/sos_service.dart';
import '../services/voice_service.dart';
import '../widgets/emergency_contact_card.dart';
import '../widgets/emergency_location_card.dart';
import '../widgets/emergency_sos_button.dart';
import '../widgets/sound_mode_button.dart';

/// The screen's own view of the hold, before the service takes over.
///
/// Once SOS is running the service's [SosState] is authoritative, so this is
/// only used for the idle and counting phases.
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
    6: 'six',
    7: 'seven',
  };

  /// The app-wide contact store, so the emergency flow and this screen always
  /// see the same list rather than two divergent copies.
  final EmergencyContactService _contactService = EmergencyContactService.instance;

  final VoiceService _voice = VoiceService();

  /// The single owner of the emergency procedure.
  ///
  /// The screen renders [SosService.session] and never calls, texts or plays a
  /// tone itself, which is what lets the alert keep sounding after the user
  /// navigates away.
  final SosService _sos = SosService.instance;

  /// Renders the pill and live status as the session progresses.
  void _onSosChanged() {
    if (mounted) setState(() {});
  }

  /// The one SOS press-and-hold state machine.
  ///
  /// The whole screen forwards its raw pointer stream here, so holding the SOS
  /// button, holding the middle of the screen and holding an empty corner all
  /// run the exact same countdown and trigger the exact same activation. The
  /// button renders this controller; it does not own a second copy of it.
  late final SosHoldController _hold;

  bool _voiceEnabled = true;
  _SosStatus _status = _SosStatus.ready;
  int _holdSeconds = 5;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    _hold = SosHoldController(
      onActivated: _onActivated,
      onTick: _onTick,
      onCancelled: _onCancelled,
      onReset: _onReset,
    );
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    _voice.setEnabled(_voiceEnabled);
    _contactService.addListener(_onContactsChanged);
    _sos.addListener(_onSosChanged);
    _loadContacts();
    unawaited(_announceScreen());
  }

  /// Announces which screen is open once the entrance has settled. Like every
  /// other screen's announcement, it follows the global voice switch and the
  /// on-screen speaker mute via VoiceService.speak() itself.
  Future<void> _announceScreen() async {
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted || !_voiceEnabled) return;
    _voice.speak(
      'Emergency screen. Quick access to help and your emergency contacts.',
    );
  }

  void _applySettings() {
    final s = SettingsService.instance;
    _voiceEnabled = s.voiceGuidanceEnabled && !s.globalVoiceMuted && !s.vibrateMode;
    _holdSeconds = s.sosHoldDurationSeconds;
    _countdown = s.sosHoldDurationSeconds;
    _voice.setEnabled(_voiceEnabled);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
    if (mounted) setState(() {});
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
    SettingsService.instance.removeListener(_applySettings);
    _contactService.removeListener(_onContactsChanged);
    // Only the observer is removed. The SOS session deliberately keeps running
    // after this screen is gone, so the alert survives leaving the screen.
    _sos.removeListener(_onSosChanged);
    _hold.dispose();
    _voice.setEnabled(false);
    unawaited(_voice.dispose());
    super.dispose();
  }

  void _onTick(int remaining) {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.activating;
      _countdown = remaining;
    });
    if (remaining == _holdSeconds) {
      _voice.speak('Emergency activation in $_holdSeconds seconds.');
    } else {
      _voice.speak(_numberWords[remaining] ?? '$remaining');
    }
  }

  /// Hands over to [SosService] and renders whatever it reports.
  ///
  /// There is deliberately no contact picker and no Call button here: the
  /// service places the call itself, so a second tap is never required.
  void _onActivated() {
    if (!mounted) return;
    setState(() => _status = _SosStatus.activated);
    // The service owns the alert tone, the vibration, the call, GPS and the
    // message. Starting it is the whole activation.
    unawaited(_sos.activate());
  }

  void _onCancelled() {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.ready;
      _countdown = _holdSeconds;
    });
    _voice.speak('SOS cancelled.');
    showMessage(context, 'SOS cancelled.');
  }

  void _onReset() {
    if (!mounted) return;
    setState(() {
      _status = _SosStatus.ready;
      _countdown = _holdSeconds;
    });
    // Ends the tone, the speech suppression and the whole session. Reset is the
    // only thing the user has to do to stop the emergency.
    unawaited(_sos.reset());
    _voice.speak('SOS deactivated. Stay safe.');
    showMessage(context, 'SOS reset.');
  }

  /// Manually calls one contact from the contacts card.
  ///
  /// This is contact management, not part of the automatic SOS procedure, which
  /// never asks the user to choose anyone. It uses the same direct-call path so
  /// an explicit tap also connects without a second confirmation.
  Future<void> _callContact(EmergencyContact contact) async {
    final SosCallResult result =
        await const SosPlatform().placeDirectCall(contact.phone);
    if (!mounted) return;
    if (result.succeeded) {
      showMessage(context, 'Calling ${contact.name}.');
    } else if (result.openedDialerInstead) {
      showMessage(context, 'Press call on the dialer to connect.');
    } else {
      showMessage(
        context,
        result.blocker?.message ?? 'The call could not be placed.',
      );
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
      // Swallowing the SOS screen's own horizontal drags guarantees no other
      // screen can ever open by swiping from here; leave it with the back
      // button and the system back gesture, which pop to the previous screen.
      //
      // The Listener is what makes the hold work ANYWHERE on this screen. A raw
      // Listener observes without consuming, so every control underneath (back,
      // sound mode, contact cards, Call, add contact, reset) still receives its
      // normal taps: a quick press starts and abandons the hold in well under a
      // second without announcing anything, and only a genuine sustained press
      // runs the SOS countdown.
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _hold.pointerDown,
        onPointerMove: _hold.pointerMove,
        onPointerUp: _hold.pointerUp,
        onPointerCancel: _hold.pointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: SafeArea(
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
                  // The live status needs more vertical room than the idle
                  // button, but only while SOS is actually running.
                  final double cap = _sos.session.canReset ? 460 : 360;
                  if (sosH > cap) sosH = cap;

                  return Column(
                    children: [
                      SizedBox(height: 56, child: _buildHeader()),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: sosH < 0 ? 0 : sosH,
                        child: _buildSosPanel(),
                      ),
                      const Spacer(),
                      _buildContactsCard(cardH),
                      const SizedBox(height: 10),
                      EmergencyLocationCard(session: _sos.session),
                      const SizedBox(height: 10),
                    ],
                  );
                },
              ),
            ),
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
        ListenableBuilder(
          listenable: SettingsService.instance,
          builder: (context, _) {
            final mode = SettingsService.instance.alertMode;
            return _CircleButton(
              icon: SoundModeButton.iconFor(mode),
              tooltip: SoundModeButton.labelFor(mode),
              color: mode == AlertMode.muted
                  ? const Color(0xFF9AA4B2)
                  : _accent,
              onTap: SoundModeButton.toggle,
            );
          },
        ),
      ],
    );
  }

  /// Status pill, button, and the live emergency status while SOS runs.
  ///
  /// The service's state is authoritative once SOS starts, so the pill can
  /// never claim "ACTIVATED" while the session is actually inactive.
  Widget _buildSosPanel() {
    final SosSession live = _sos.session;
    // Null means the service has no live session, so the hold UI is in charge.
    final SosState? state = live.canReset ? live.state : null;
    final bool countingDown =
        _status == _SosStatus.activating && state == null;

    final (Color bg, Color fg, Color dot, String text) = switch (state) {
      SosState.activating => (
          const Color(0xFFFFF4E0),
          const Color(0xFFB26A00),
          const Color(0xFFE6A700),
          'ACTIVATING',
        ),
      SosState.active => (
          const Color(0xFFFFE8E8),
          const Color(0xFFC62828),
          const Color(0xFFFF5C63),
          'SOS ACTIVE',
        ),
      SosState.resetting => (
          const Color(0xFFF1F5F9),
          const Color(0xFF475569),
          const Color(0xFF94A3B8),
          'STOPPING',
        ),
      _ => countingDown
          ? (
              const Color(0xFFFFF4E0),
              const Color(0xFFB26A00),
              const Color(0xFFE6A700),
              'ACTIVATING · $_countdown',
            )
          : (
              const Color(0xFFE4F8EF),
              const Color(0xFF15805A),
              const Color(0xFF2EBD6E),
              'READY',
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
              child: _sos.session.canReset
                  ? _buildActiveStatus()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: EmergencySOSButton(controller: _hold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live status for a running SOS session.
  ///
  /// Replaces the hold button while the emergency is in progress: there is no
  /// Call button here, because the call has already been placed automatically,
  /// and no second confirmation is ever asked for.
  Widget _buildActiveStatus() {
    final SosSession s = _sos.session;

    /// One status row: an icon, a label, and an optional explanation.
  Widget _buildStatusRow({
    required String label,
    required SosStep step,
    required bool done,
    String? detail,
  }) {
    final Color color = done
        ? const Color(0xFF15805A)
        : step == SosStep.pending
            ? _sub
            : const Color(0xFFB26A00);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : step == SosStep.pending
                    ? Icons.circle_outlined
                    : Icons.pending_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    style: const TextStyle(
                      color: _sub,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.hasContact ? s.contactName : 'No contact saved',
            style: const TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Emergency assistance is being contacted.',
            style: TextStyle(color: _sub, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            label: 'Calling',
            step: s.callStep,
            done: s.callStep == SosStep.callConnected,
            detail: switch (s.callStep) {
              SosStep.callConnected => 'Call placed automatically.',
              SosStep.callNeedsUserTap => s.callBlockerMessage,
              SosStep.callFailed => s.callBlockerMessage,
              SosStep.calling => 'Starting the call…',
              _ => null,
            },
          ),
          _buildStatusRow(
            label: 'Location',
            step: s.locationStep,
            done: s.locationStep == SosStep.locationFound,
            detail: switch (s.locationStep) {
              SosStep.locationFound =>
                s.location?.coordinates ?? 'Fix obtained.',
              SosStep.locationUnavailable => s.locationBlockerMessage,
              SosStep.locating => 'Getting your position…',
              _ => null,
            },
          ),
          _buildStatusRow(
            label: 'Message',
            step: s.smsStep,
            done: s.smsStep == SosStep.messageDelivered,
            detail: switch (s.smsStep) {
              SosStep.messageDelivered => 'Location sent and delivered.',
              SosStep.messageNotDelivered => s.smsBlockerMessage,
              SosStep.sendingMessage => 'Sending your location…',
              _ => null,
            },
          ),
          _buildStatusRow(
            label: 'Alert',
            step: SosStep.alerting,
            done: s.alerting,
            detail: s.alerting
                ? 'Repeating alert is sounding.'
                : 'Alert sound is switched off.',
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _onReset,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF64748B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 19),
            label: const Text('Reset SOS'),
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
