import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('long-press-dragging an instruction from the palette onto a slot places it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final forwardButton = find.byIcon(Icons.arrow_upward_rounded);
    expect(forwardButton, findsOneWidget); // only the palette shows it before the drop

    final slotTarget = find.byType(DragTarget<ProgramInstruction>).first;

    final start = tester.getCenter(forwardButton);
    // The feedback icon is lifted 56px above the actual touch point (see
    // _dragLift in instruction_palette.dart) so the finger doesn't cover it,
    // and feedbackOffset shifts the drop hit-test to match — so the finger
    // must be that far *below* the slot for the (visually raised) icon to
    // register as dropped on it.
    final end = tester.getCenter(slotTarget) + const Offset(0, 56);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // exceed the long-press threshold
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final droppedGlyph = find.descendant(
      of: slotTarget,
      matching: find.byIcon(Icons.arrow_upward_rounded),
    );
    expect(droppedGlyph, findsOneWidget);
  });
}
