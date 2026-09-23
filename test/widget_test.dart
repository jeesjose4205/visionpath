import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/main.dart';
import 'package:visionpath/screens/navigate_screen.dart';

void main() {
  testWidgets('VisionPathApp boots straight into the Navigate screen',
      (WidgetTester tester) async {
    // Phone-portrait surface, matching a real device.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VisionPathApp());
    await tester.pump();

    expect(find.byType(NavigateScreen), findsOneWidget);
  });
}