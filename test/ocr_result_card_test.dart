import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/widgets/ocr_result_card.dart';

/// Pumps the card and returns its rendered height.
Future<double> pumpCard(
  WidgetTester tester,
  String text, {
  Size surface = const Size(400, 800),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: OcrResultCard(
            text: text,
            charCount: text.length,
            isReading: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(OcrResultCard)).height;
}

/// Swipes inside the card the way a finger would, in steps. A single-shot
/// [WidgetTester.drag] is not enough: the default drag start behaviour spends
/// the first move event on arming the recognizer.
Future<void> scrollCard(WidgetTester tester, double dy) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byType(OcrResultCard)),
  );
  for (int i = 0; i < 12; i++) {
    await gesture.moveBy(Offset(0, dy / 12));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

String bodyText(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(
      of: find.byType(OcrResultCard),
      matching: find.byType(Text),
    ).last).data!;

void main() {
  testWidgets('short text is not scrolled and shows in full', (tester) async {
    const String text = 'Hello world';
    await pumpCard(tester, text);

    // Nothing is clipped, so there is nothing to scroll.
    expect(bodyText(tester), text);
    expect(
      find.descendant(
        of: find.byType(OcrResultCard),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );

    final double before = tester.getTopLeft(find.byType(OcrResultCard)).dy;
    await scrollCard(tester, -200);
    expect(tester.getTopLeft(find.byType(OcrResultCard)).dy, before);
  });

  testWidgets('long text keeps the card height but scrolls to its end',
      (tester) async {
    // Many lines: far more than the 6 the card has ever displayed.
    final String text = List<String>.generate(
      30,
      (int i) => 'Recognized line ${i + 1}',
    ).join('\n');

    final double cardHeight = await pumpCard(tester, text);

    // The card is still the same bounded size, not one giant tall box.
    expect(cardHeight, lessThan(240.0));
    expect(tester.takeException(), isNull);

    // The whole text is genuinely laid out and reachable by scrolling.
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(OcrResultCard),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0.0));
    expect(scrollable.position.pixels, 0.0);

    // Negative dy swipes upward through the text, towards its end.
    await scrollCard(tester, -(scrollable.position.maxScrollExtent + 120));
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

    // The previously unreachable final line is now rendered on screen.
    expect(bodyText(tester), contains('Recognized line 30'));
    expect(find.textContaining('Recognized line 30'), findsOneWidget);
  });

  testWidgets('a tall text does not grow the card past its line budget',
      (tester) async {
    // Six lines is exactly the budget the card has always had.
    final String atBudget = List<String>.generate(
      6,
      (int i) => 'Budget line ${i + 1}',
    ).join('\n');
    final String wayOver = List<String>.generate(
      40,
      (int i) => 'Filler number ${i + 1}',
    ).join('\n');
    final String twoLines = 'Line one\nLine two';

    final double overHeight = await pumpCard(tester, wayOver);
    final double budgetHeight = await pumpCard(tester, atBudget);
    final double shortHeight = await pumpCard(tester, twoLines);

    // Forty lines must not exceed the six-line budget by even a pixel.
    expect(overHeight, budgetHeight);

    // A short result still hugs its own content instead of padding out.
    expect(shortHeight, lessThan(budgetHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty state card is unchanged', (tester) async {
    await pumpCard(tester, '   ');
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      find.text('No text was found in this picture. Try scanning again.'),
      findsOneWidget,
    );
  });
}