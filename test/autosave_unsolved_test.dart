import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'drag_helpers.dart';
import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'placing a single instruction (without solving) is still restored on reopen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // Place just one instruction — nowhere near solving the level (3
    // forwards are needed) — then leave it as-is.
    await placeInstruction(tester, ActionType.forward,
        find.byType(DragTarget<ProgramInstruction>).at(0));
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(0),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('Clear!'), findsNothing); // definitely not solved

    // Reopen the same level fresh.
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(0),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
  });
}
