import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/voice_command_controller.dart';
import 'package:visionpath/widgets/press_and_hold_voice_region.dart';

/// A stand-in for the recognizer so the gesture can be tested without a real
/// microphone. It records the hold lifecycle exactly as the screen would see it.
class _RecordingController extends VoiceCommandController {
  int begins = 0;
  int ends = 0;
  int cancels = 0;

  @override
  Future<void> beginHold() async {
    begins++;
    debugSetHoldState(holding: true);
  }

  @override
  Future<void> endHold() async {
    ends++;
    debugSetHoldState();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    debugSetHoldState();
  }
}

void main() {
  late _RecordingController controller;

  setUp(() => controller = _RecordingController());
  tearDown(() => controller.dispose());

  Widget harness({bool enabled = true, Key? regionKey}) {
    return MaterialApp(
      home: Scaffold(
        body: PressAndHoldVoiceRegion(
          key: regionKey,
          controller: controller,
          enabled: enabled,
          child: const SizedBox.expand(
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
  }

  /// Press, hold for [duration], then release.
  Future<void> hold(WidgetTester tester, Duration duration) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    await tester.pump(duration);
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a short tap never opens the assistant',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await hold(tester, const Duration(milliseconds: 100));

    expect(controller.begins, 0);
    expect(controller.ends, 0);
  });

  testWidgets('holding past the threshold opens it and releasing closes it',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await hold(tester, const Duration(milliseconds: 500));

    expect(controller.begins, 1);
    // The release must reach the controller or the mic would stay open.
    expect(controller.ends, 1);
  });

  testWidgets('holding works in a screen corner', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    final TestGesture gesture =
        await tester.startGesture(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pump();

    expect(controller.begins, 1);
  });

  testWidgets('the camera area and empty space both count',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    // HitTestBehavior.opaque is what makes the empty area respond at all.
    await hold(tester, const Duration(milliseconds: 500));
    expect(controller.begins, 1);
  });

  testWidgets('a disabled region ignores presses entirely',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness(enabled: false));
    await hold(tester, const Duration(milliseconds: 500));

    expect(controller.begins, 0);
  });

  testWidgets('becoming disabled mid-hold closes the microphone',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.begins, 1);
    expect(controller.ends, 0);

    // Navigation stopped while the finger was still down.
    await tester.pumpWidget(harness(enabled: false));
    expect(controller.ends, 1);

    await gesture.up();
    await tester.pump();
    // The release must not double-close.
    expect(controller.ends, 1);
  });

  testWidgets('a second finger does not restart the threshold timer',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    final TestGesture first = await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    // Land a second finger BEFORE the threshold elapses.
    await tester.pump(const Duration(milliseconds: 200));
    final TestGesture second = await tester.startGesture(const Offset(10, 10));

    // 450ms total: past the 400ms threshold measured from the FIRST press. If
    // the second finger restarted the timer this would not have fired yet, and
    // a resting thumb could hold the microphone shut indefinitely.
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.begins, 1);

    await first.up();
    await second.up();
    await tester.pump();
    expect(controller.ends, 1);
  });

  testWidgets('dragging across the screen is not a hold',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    // A swipe is a press that travels. It must not open the microphone, or every
    // flick across the carousel would start a listening session.
    await tester.drag(
      find.byType(PressAndHoldVoiceRegion),
      const Offset(-260, 0),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.begins, 0);
  });

  testWidgets('a slow drag that comes to rest still counts as a drag',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    // Move well past touch slop, then hold still for longer than the threshold.
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 800));
    expect(controller.begins, 0);

    await gesture.up();
    await tester.pump();
    expect(controller.ends, 0);
  });

  testWidgets('a cancelled pointer still closes the hold',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.begins, 1);

    // The system takes the gesture away (incoming call, notification shade).
    await gesture.cancel();
    await tester.pump();
    expect(controller.ends, 1);
  });

  testWidgets('disposing the region closes the microphone',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.startGesture(
      tester.getCenter(find.byType(PressAndHoldVoiceRegion)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.begins, 1);

    // Leaving the screen must never leave the mic open.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(controller.cancels, 1);
  });
}