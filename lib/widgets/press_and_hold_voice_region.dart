import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/voice_command_controller.dart';

/// Wraps a screen so that pressing and holding anywhere inside it talks to the
/// assistant, and a short tap does not.
///
/// A [Listener] is used rather than a [GestureDetector] because the raw pointer
/// gives a reliable press and release anywhere on screen, including over the
/// camera feed and the header, without competing with the controls underneath.
/// [HitTestBehavior.opaque] is what makes the empty areas of the screen part of
/// the hit region at all.
class PressAndHoldVoiceRegion extends StatefulWidget {
  const PressAndHoldVoiceRegion({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
    this.holdThreshold = VoiceCommandController.holdThreshold,
  });

  final VoiceCommandController controller;

  /// Whether a hold may start right now. The assistant is unavailable while the
  /// camera is not running, so the region goes inert there.
  final bool enabled;

  /// How long the finger must stay down before the microphone opens.
  final Duration holdThreshold;

  final Widget child;

  @override
  State<PressAndHoldVoiceRegion> createState() =>
      _PressAndHoldVoiceRegionState();
}

class _PressAndHoldVoiceRegionState extends State<PressAndHoldVoiceRegion> {
  Timer? _holdTimer;
  int? _pointer;

  /// How far the finger has travelled while down.
  ///
  /// Press-and-hold means pressing and staying put. A finger that moves is
  /// dragging the page or scrolling, and treating that as a hold would open the
  /// microphone on every swipe across the carousel.
  double _travel = 0;

  @override
  void didUpdateWidget(PressAndHoldVoiceRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only on the enabled -> disabled edge. Ending the hold on every rebuild
    // would cut off a hold in progress the moment the screen repainted.
    if (oldWidget.enabled && !widget.enabled) _finishHold();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || !mounted) return;
    // One finger owns the hold. A second finger must not restart the timer and
    // so extend an already-open microphone.
    if (_pointer != null) return;
    _pointer = event.pointer;
    _travel = 0;
    _holdTimer?.cancel();
    _holdTimer = Timer(widget.holdThreshold, _openMicrophone);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    _travel += event.delta.distance;
    if (_travel > kTouchSlop) {
      // This is a drag, not a hold. Drop the pending activation; the finger can
      // still come to rest and the release will be ignored as normal.
      _holdTimer?.cancel();
      _holdTimer = null;
    }
  }

  void _openMicrophone() {
    _holdTimer = null;
    if (!mounted || !widget.enabled) return;
    unawaited(widget.controller.beginHold());
    HapticFeedback.mediumImpact();
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _finishHold();
  }

  void _onPointerCancel(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _finishHold();
  }

  /// Release the hold. Safe to call when no hold is active.
  void _finishHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pointer = null;
    _travel = 0;
    // A short tap never opened the assistant, so there is nothing to close.
    if (!widget.controller.isHolding) return;
    unawaited(widget.controller.endHold());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    unawaited(widget.controller.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}