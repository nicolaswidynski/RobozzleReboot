import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'drag_helpers.dart';
import 'fake_secure_storage.dart';
import 'test_level.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  testWidgets(
      'solving a puzzle shows a Clear overlay, and Next advances to the '
      'next level in catalog order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel(), testLevel2()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Level'), findsOneWidget);
    expect(find.text('Clear!'), findsNothing);

    // 3 forwards solves the 4-tile strip.
    for (var i = 0; i < 3; i++) {
      await placeInstruction(tester, ActionType.forward,
          find.byType(DragTarget<ProgramInstruction>).at(i));
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

  testWidgets(
      'solving the last puzzle in the list shows "Go Back" instead of '
      '"Next", and it stays clickable — tapping it returns to the '
      'previous screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GameScreen(levels: [testLevel()]),
                  ),
                ),
                child: const Text('Open puzzle'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open puzzle'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await placeInstruction(tester, ActionType.forward,
          find.byType(DragTarget<ProgramInstruction>).at(i));
    }
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
    }

    expect(find.text('Clear!'), findsOneWidget);
    final goBackButton = find.widgetWithText(ElevatedButton, 'Go Back');
    expect(goBackButton, findsOneWidget);

    // Actually enabled, not disabled/inert.
    final button = tester.widget<ElevatedButton>(goBackButton);
    expect(button.onPressed, isNotNull);

    await tester.tap(goBackButton);
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Open puzzle'), findsOneWidget);
  });
}
