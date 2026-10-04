import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/voice_command_controller.dart';
import 'package:visionpath/widgets/voice_search_overlay.dart';

/// The overlay is the only feedback a user gets while holding, so it has to
/// react to the controller on its own. These tests cover the bug where it read
/// controller state without ever listening to it, which left the whole feature
/// invisible until some unrelated rebuild happened.
void main() {
  Widget harness(VoiceCommandController controller) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            const Center(child: Text('camera feed')),
            Positioned.fill(
              child: VoiceSearchOverlay(controller: controller),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('shows nothing between holds', (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    expect(find.text('Listening...'), findsNothing);
    expect(find.text('Getting ready...'), findsNothing);
  });

  testWidgets('appears on hold without a parent rebuild',
      (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    expect(find.text('Getting ready...'), findsNothing);

    controller.debugSetHoldState(holding: true);
    await tester.pump();

    // The overlay listens to the controller itself, so this needs no rebuild
    // from the parent screen.
    expect(find.text('Getting ready...'), findsOneWidget);
  });

  testWidgets('shows the transcript as it is recognized',
      (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    controller.debugSetHoldState(
      holding: true,
      listening: true,
      transcript: 'find the chair',
    );
    await tester.pump();

    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text('find the chair'), findsOneWidget);
  });

  testWidgets('hides again on release', (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    controller.debugSetHoldState(holding: true, listening: true);
    await tester.pump();
    expect(find.text('Listening...'), findsOneWidget);

    controller.debugSetHoldState();
    await tester.pump();

    expect(find.text('Listening...'), findsNothing);
  });

  testWidgets('never intercepts the release that closes the hold',
      (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    controller.debugSetHoldState(holding: true, listening: true);
    await tester.pump();

    // The gesture that opened the overlay owns the release, so the overlay
    // must let pointer events through.
    expect(
      find.descendant(
        of: find.byType(VoiceSearchOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the camera stays visible behind the overlay',
      (WidgetTester tester) async {
    final VoiceCommandController controller = VoiceCommandController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    controller.debugSetHoldState(holding: true, listening: true);
    await tester.pump();

    // Translucent, not opaque: the user must keep seeing what they walk past.
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('camera feed'), findsOneWidget);
  });
}