import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';
import 'package:robozzle_reboot/widgets/group_selection.dart';
import 'package:robozzle_reboot/widgets/tile_color_ui.dart';

import 'drag_helpers.dart';
import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'long-press-dragging the condition color group past its fan-out menu '
      'onto a filled slot sets its condition without changing the action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // Place "forward" in the first slot.
    final slotTarget = find.byType(DragTarget<ProgramInstruction>).first;
    await placeInstruction(tester, ActionType.forward, slotTarget);
    expect(
      find.descendant(of: slotTarget, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );

    // The 3 condition colors collapse into one group button. Red is first
    // in the group's option list, so it's the default-hovered option — a
    // single continuous drag straight up past the fan-out menu (skipping
    // any intermediate hover) and on to the slot commits it without ever
    // needing to pause over "Red" explicitly.
    final colorGroup =
        find.byType(LongPressDraggable<GroupSelection<TileColor>>);
    final start = tester.getCenter(colorGroup);
    // Same 56px lift as the action-icon drag (see instruction_palette.dart's
    // _dragLift): the feedback renders above the finger, so the finger must
    // be that far below the slot for the (visually raised) icon to register.
    final end = tester.getCenter(slotTarget) + const Offset(0, 56);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // exceed the long-press threshold
    // Two steps, not one straight jump: the group commits its hovered
    // option (writing it into the GroupSelection holder) only *after*
    // Flutter's own hit-test for that same pointer event has already run,
    // so the first move's hit-test still sees no value and doesn't enter
    // the slot's target. A real drag has many move events in between,
    // giving a later hit-test the now-committed value; the test needs a
    // second move to reproduce that.
    await gesture.moveTo(Offset.lerp(start, end, 0.6)!);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // The action glyph is unchanged — only the condition was set.
    expect(
      find.descendant(of: slotTarget, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );

    final slotContainer = tester.widget<Container>(
      find.descendant(of: slotTarget, matching: find.byType(Container)).first,
    );
    final border = (slotContainer.decoration as BoxDecoration).border as Border;
    expect(border.top.color, TileColor.red.uiColor);
  });
}
