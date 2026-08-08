import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/progress_store.dart';
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
    // testLevel() is difficulty 1 (1 point) with 6 slots in F1; solving it
    // with exactly 3 forwards leaves 3 unused, so the bonus is 3*1=3.
    expect(find.text('+1 points'), findsOneWidget);
    expect(find.text('+3 bonus points'), findsOneWidget);
    final nextButton = find.widgetWithText(ElevatedButton, 'Next');
    expect(nextButton, findsOneWidget);

    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    // Moved to the next level in GameScreen.levels order, and the overlay
    // is gone since the new level hasn't been solved yet.
    expect(find.text('Test Level 2'), findsOneWidget);
    expect(find.text('Clear!'), findsNothing);
  });

  testWidgets('no bonus line shown when the winning program used every '
      'available slot', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // Fill all 6 of F1's slots -- only the first 3 forwards actually run
    // (the level is solved and the interpreter stops stepping once it
    // hits success), but unusedSlots counts occupancy, not execution, so
    // this should leave nothing unused.
    for (var i = 0; i < 6; i++) {
      await placeInstruction(tester, ActionType.forward,
          find.byType(DragTarget<ProgramInstruction>).at(i));
    }
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
    }

    expect(find.text('Clear!'), findsOneWidget);
    expect(find.text('+1 points'), findsOneWidget);
    expect(find.textContaining('bonus points'), findsNothing);
  });

  testWidgets(
      'Next skips over a level already completed (e.g. from a previous '
      'session), landing on the next one that still needs solving',
      (tester) async {
    await ProgressStore().markCompleted('test-fixture-2');

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(levels: [testLevel(), testLevel2(), testLevel3()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Level'), findsOneWidget);

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

    // "Test Level 2" (already completed) is skipped entirely.
    expect(find.text('Test Level 2'), findsNothing);
    expect(find.text('Test Level 3'), findsOneWidget);
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
