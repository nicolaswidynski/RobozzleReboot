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
      'long-press-dragging a filled slot onto another slot moves the '
      'instruction instead of copying it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // Place "forward" in the first slot.
    final slot0 = find.byType(DragTarget<ProgramInstruction>).at(0);
    final slot1 = find.byType(DragTarget<ProgramInstruction>).at(1);
    await placeInstruction(tester, ActionType.forward, slot0);
    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot1, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );

    await dragOnto(tester, slot0, slot1);

    // The instruction moved: gone from slot0, now in slot1.
    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );
    expect(
      find.descendant(of: slot1, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
  });

  testWidgets(
      'long-press-dragging a filled slot onto another filled slot swaps the '
      'two instructions instead of one clobbering the other', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final slot0 = find.byType(DragTarget<ProgramInstruction>).at(0);
    final slot1 = find.byType(DragTarget<ProgramInstruction>).at(1);

    await placeInstruction(tester, ActionType.forward, slot0);
    await placeInstruction(tester, ActionType.turnLeft, slot1);

    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot1, matching: find.byIcon(Icons.turn_left_rounded)),
      findsOneWidget,
    );

    await dragOnto(tester, slot0, slot1);

    // Swapped: slot0 now has "turn left", slot1 now has "forward".
    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.turn_left_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot1, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
  });
}
