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
      'reopening a solved level restores the winning program instead of a blank one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

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

    // Simulate leaving and reopening the same level fresh — a brand new
    // GameScreen instance, as HomeScreen would create.
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // The saved program should already be in place, not a blank slate.
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(0),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(1),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(2),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'startBlank skips restoring a saved program even though one exists '
      '(Daily Challenge, when the puzzle was already solved elsewhere)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // Solve it once, so a winning program is saved for this level id.
    for (var i = 0; i < 3; i++) {
      await placeInstruction(tester, ActionType.forward,
          find.byType(DragTarget<ProgramInstruction>).at(i));
    }
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('Clear!'), findsOneWidget);

    // Reopen with startBlank: true -- the saved program must not appear.
    // A distinct key forces Flutter to actually tear down and recreate
    // GameScreen's State here, rather than diffing it as an update to the
    // still-live one from above (which — same widget type, same tree
    // position, no key — is what pumpWidget would otherwise do, silently
    // reusing initState()'s already-solved in-memory state instead of
    // genuinely reloading, unlike a real re-navigation via Navigator).
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          key: const ValueKey('reopened'),
          levels: [testLevel()],
          startBlank: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clear!'), findsNothing);
    for (var i = 0; i < 3; i++) {
      expect(
        find.descendant(
          of: find.byType(DragTarget<ProgramInstruction>).at(i),
          matching: find.byIcon(Icons.arrow_upward_rounded),
        ),
        findsNothing,
      );
    }
  });
}
