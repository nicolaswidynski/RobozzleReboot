import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'long-press-dragging a filled slot to empty space (no drop target) removes it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // "forward" is selected by default; place it in the first slot.
    final slot0 = find.byType(DragTarget<ProgramInstruction>).at(0);
    await tester.tap(slot0);
    await tester.pump();
    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );

    final start = tester.getCenter(slot0);
    // Well outside the rendered app (and thus every DragTarget) — nothing
    // accepts the drop, so it should read as "drag it away to delete it".
    const end = Offset(2000, 2000);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // exceed the long-press threshold
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: slot0, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );
  });
}
