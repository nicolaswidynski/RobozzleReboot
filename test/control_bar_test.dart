import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('step, step back, and speed buttons drive the interpreter correctly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // "forward" is selected by default; place it in F1's first two slots so
    // stepping/running actually moves the robot instead of immediately
    // hitting end-of-program.
    await tester.tap(find.byType(DragTarget<ProgramInstruction>).first);
    await tester.pump();
    await tester.tap(find.byType(DragTarget<ProgramInstruction>).at(1));
    await tester.pump();

    final robotIcon = find.byIcon(Icons.navigation_rounded);
    final startX = tester.getTopLeft(robotIcon).dx;

    // Back button starts disabled: nothing to undo yet.
    final backButtonInkWell = find.ancestor(
      of: find.byIcon(Icons.skip_previous_rounded),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(backButtonInkWell).onTap, isNull);

    // Step forward once — the robot should move.
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();
    final afterStepX = tester.getTopLeft(robotIcon).dx;
    expect(afterStepX, isNot(startX));

    // Back is now enabled and undoes that exact move.
    expect(tester.widget<InkWell>(backButtonInkWell).onTap, isNotNull);
    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(robotIcon).dx, startX);

    // Starting 2x auto-run should advance the robot without further taps.
    // Can't use pumpAndSettle here — the periodic timer never stops on its
    // own — so advance the fake clock in small increments instead.
    await tester.tap(find.text('2x'));
    await tester.pump(); // process the tap itself, before any ticks fire

    // The command list is frozen while actively auto-running: tapping an
    // empty slot at this point should not place anything. The tap is
    // expected to miss (IgnorePointer swallows it), hence warnIfMissed: false.
    final emptySlot = find.byType(DragTarget<ProgramInstruction>).at(2);
    await tester.tap(emptySlot, warnIfMissed: false);
    await tester.pump();
    expect(
      find.descendant(of: emptySlot, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.getTopLeft(robotIcon).dx, isNot(startX));

    // Tapping the active speed again pauses it.
    await tester.tap(find.text('2x'));
    await tester.pump();
    final pausedX = tester.getTopLeft(robotIcon).dx;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.getTopLeft(robotIcon).dx, pausedX); // no further movement while paused
  });
}
