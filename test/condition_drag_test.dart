import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';
import 'package:robozzle_reboot/widgets/tile_color_ui.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'long-press-dragging a color dot onto a filled slot sets its condition '
      'without changing the action', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    // "forward" is selected by default; place it in the first slot.
    final slotTarget = find.byType(DragTarget<ProgramInstruction>).first;
    await tester.tap(slotTarget);
    await tester.pump();
    expect(
      find.descendant(of: slotTarget, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );

    // Drag the "red" condition dot (first in TileColor.values) onto that slot.
    final redDot = find.byType(LongPressDraggable<TileColor>).first;
    final start = tester.getCenter(redDot);
    // Same 56px lift as the action-icon drag (see instruction_palette.dart's
    // _dragLift): the feedback renders above the finger, so the finger must
    // be that far below the slot for the (visually raised) dot to register.
    final end = tester.getCenter(slotTarget) + const Offset(0, 56);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // exceed the long-press threshold
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
