import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'long-press-dragging a filled slot onto another slot moves the '
      'instruction instead of copying it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // "forward" is selected by default; place it in the first slot.
    final slot0 = find.byType(DragTarget<ProgramInstruction>).at(0);
    final slot1 = find.byType(DragTarget<ProgramInstruction>).at(1);
    await tester.tap(slot0);
    await tester.pump();
    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot1, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );

    final start = tester.getCenter(slot0);
    // Same 56px lift as every other drag in this app (see _dragLift in
    // function_editor.dart's _SlotBox): the feedback renders above the
    // finger, so the finger must be that far below slot1 for the icon to
    // register as dropped there.
    final end = tester.getCenter(slot1) + const Offset(0, 56);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // exceed the long-press threshold
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

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
}
