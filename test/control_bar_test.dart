import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'drag_helpers.dart';
import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('step, step back, and speed buttons drive the interpreter correctly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // Place "forward" in F1's first two slots so stepping/running actually
    // moves the robot instead of immediately hitting end-of-program.
    await placeInstruction(tester, ActionType.forward,
        find.byType(DragTarget<ProgramInstruction>).first);
    await placeInstruction(tester, ActionType.forward,
        find.byType(DragTarget<ProgramInstruction>).at(1));

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
    await tester.tap(find.byKey(const ValueKey('speed_2x')));
    await tester.pump(); // process the tap itself, before any ticks fire

    // The command list is frozen while actively auto-running: dragging an
    // instruction onto an empty slot at this point should not place
    // anything, since IgnorePointer blocks the palette's drag sources too.
    final emptySlot = find.byType(DragTarget<ProgramInstruction>).at(2);
    await dragOnto(tester, paletteAction(ActionType.forward), emptySlot);
    expect(
      find.descendant(of: emptySlot, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.getTopLeft(robotIcon).dx, isNot(startX));

    // Tapping the active speed again pauses it.
    await tester.tap(find.byKey(const ValueKey('speed_2x')));
    await tester.pump();
    final pausedX = tester.getTopLeft(robotIcon).dx;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.getTopLeft(robotIcon).dx, pausedX); // no further movement while paused
  });

  testWidgets(
      'status line shows the pending instructions (not a static '
      '"Running…") while running, and stays flat through a self-recursive '
      'tail call', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // F1: forward, then call F1 as the very last slot — the classic
    // "loop forever" pattern. Nothing follows the call, so it has no
    // caller state left to return to.
    await placeInstruction(tester, ActionType.forward,
        find.byType(DragTarget<ProgramInstruction>).first);
    await placeInstruction(tester, ActionType.callF1,
        find.byType(DragTarget<ProgramInstruction>).at(1));

    // "F1" also appears elsewhere on screen (the palette's call button,
    // the function badge), so scope every check to the status area itself.
    final statusArea = find.byKey(const ValueKey('controlBarStatusText'));
    Finder statusText(String text) =>
        find.descendant(of: statusArea, matching: find.text(text));
    Finder statusIcon(IconData icon) =>
        find.descendant(of: statusArea, matching: find.byIcon(icon));

    expect(statusText('Running…'), findsNothing);

    // First step runs "forward" — only "call F1" is left pending, drawn as
    // plain text (calls don't have a dedicated icon anywhere in the app).
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();
    expect(statusText('F1'), findsOneWidget);
    expect(statusIcon(Icons.arrow_upward_rounded), findsNothing);

    // Second step executes "call F1". Since that call was the last thing
    // in F1, it replaces the frame instead of stacking a second one on
    // top — the display should show F1's whole body pending again (both
    // instructions, grouped in parens), not a meaningless "F1 → F1". The
    // "forward" half is drawn with the real icon, not a text arrow.
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();
    expect(statusIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(statusText('F1'), findsOneWidget);
    expect(statusText('('), findsOneWidget);
    expect(statusText(')'), findsOneWidget);
  });

  testWidgets(
      'pending turn instructions draw with the same icons the palette and '
      'function slots use, not the old text arrows', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // F1: forward, turn right, turn left — step past "forward" so "turn
    // right, turn left" are what's left pending while running.
    await placeInstruction(tester, ActionType.forward,
        find.byType(DragTarget<ProgramInstruction>).first);
    await placeInstruction(tester, ActionType.turnRight,
        find.byType(DragTarget<ProgramInstruction>).at(1));
    await placeInstruction(tester, ActionType.turnLeft,
        find.byType(DragTarget<ProgramInstruction>).at(2));

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();

    final statusArea = find.byKey(const ValueKey('controlBarStatusText'));
    expect(
      find.descendant(
          of: statusArea, matching: find.byIcon(Icons.turn_right_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: statusArea, matching: find.byIcon(Icons.turn_left_rounded)),
      findsOneWidget,
    );
  });
}
