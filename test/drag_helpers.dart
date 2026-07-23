import 'package:flutter/material.dart' hide GridTile;
import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/models/instruction.dart';

/// Drags [from] onto [to] the way every long-press-draggable in this app
/// expects: hold past the long-press threshold, then move down by the same
/// lift the feedback icon renders above the finger (see `_dragLift` in
/// instruction_palette.dart / function_editor.dart) so it lines up with the
/// target instead of the raw, unlifted touch point.
Future<void> dragOnto(WidgetTester tester, Finder from, Finder to) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to) + const Offset(0, 56);

  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The palette's drag source for [action] — distinct from any already-placed
/// slot showing the same glyph, which isn't a `LongPressDraggable
/// <ProgramInstruction>` itself once filled (it becomes a
/// `LongPressDraggable<SlotInstructionMove>` instead).
Finder paletteAction(ActionType action) {
  return find.byWidgetPredicate((widget) =>
      widget is LongPressDraggable<ProgramInstruction> &&
      widget.data?.action == action);
}

/// Drags [action] from the palette onto [slot] — the everything-is-drag
/// replacement for the old "select then tap to place" flow.
Future<void> placeInstruction(
  WidgetTester tester,
  ActionType action,
  Finder slot,
) =>
    dragOnto(tester, paletteAction(action), slot);
