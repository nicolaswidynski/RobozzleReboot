import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'solving a puzzle shows a Clear overlay, and Next advances to the '
      'next level in catalog order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel(), testLevel2()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Level'), findsOneWidget);
    expect(find.text('Clear!'), findsNothing);

    // "forward" is selected by default; 3 forwards solves the 4-tile strip.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(DragTarget<ProgramInstruction>).at(i));
      await tester.pump();
    }

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
    }

    expect(find.text('Clear!'), findsOneWidget);
    final nextButton = find.widgetWithText(ElevatedButton, 'Next');
    expect(nextButton, findsOneWidget);

    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    // Moved to the next level in GameScreen.levels order, and the overlay
    // is gone since the new level hasn't been solved yet.
    expect(find.text('Test Level 2'), findsOneWidget);
    expect(find.text('Clear!'), findsNothing);
  });
}
