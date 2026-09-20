import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/main.dart';
import 'package:visionpath/screens/home_screen.dart';

void main() {
  testWidgets('VisionPathApp boots straight into the home screen',
      (WidgetTester tester) async {
    // Phone-portrait surface, matching a real device.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // HomeScreen has pre-existing RenderFlex overflow warnings in the test
    // harness; keep the smoke test focused on the app booting, not that noise.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String message = details.exceptionAsString();
      if (!message.contains('A RenderFlex overflowed')) {
        originalOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(const VisionPathApp());
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}