import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';
import 'package:robozzle_reboot/widgets/tile_color_ui.dart';

import 'drag_helpers.dart';
import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> setCondition(
    WidgetTester tester,
    Finder slot,
    TileColor color,
  ) async {
    final dot = find.byWidgetPredicate((widget) =>
        widget is LongPressDraggable<TileColor> && widget.data == color);
    await dragOnto(tester, dot, slot);
  }

  Border borderOf(WidgetTester tester, Finder slot) {
    final container = tester.widget<Container>(
      find.descendant(of: slot, matching: find.byType(Container)).first,
    );
    return (container.decoration as BoxDecoration).border as Border;
  }

  testWidgets(
      'dropping a different instruction on an already-conditioned slot '
      'keeps the condition, only the action changes', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final slot = find.byType(DragTarget<ProgramInstruction>).first;
    await placeInstruction(tester, ActionType.forward, slot);
    await setCondition(tester, slot, TileColor.red);
    expect(borderOf(tester, slot).top.color, TileColor.red.uiColor);

    // Drop a different action onto the same, already-conditioned slot.
    await placeInstruction(tester, ActionType.turnLeft, slot);

    expect(
      find.descendant(of: slot, matching: find.byIcon(Icons.turn_left_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsNothing,
    );
    // The condition survived the drop.
    expect(borderOf(tester, slot).top.color, TileColor.red.uiColor);
  });

  testWidgets(
      'dropping the same instruction again on an already-conditioned slot '
      'also keeps the condition', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final slot = find.byType(DragTarget<ProgramInstruction>).first;
    await placeInstruction(tester, ActionType.forward, slot);
    await setCondition(tester, slot, TileColor.blue);
    expect(borderOf(tester, slot).top.color, TileColor.blue.uiColor);

    await placeInstruction(tester, ActionType.forward, slot);

    expect(
      find.descendant(of: slot, matching: find.byIcon(Icons.arrow_upward_rounded)),
      findsOneWidget,
    );
    expect(borderOf(tester, slot).top.color, TileColor.blue.uiColor);
  });

  testWidgets(
      'dropping onto an empty slot still starts with no condition',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final slot = find.byType(DragTarget<ProgramInstruction>).first;
    await placeInstruction(tester, ActionType.forward, slot);

    final container = tester.widget<Container>(
      find.descendant(of: slot, matching: find.byType(Container)).first,
    );
    final border = (container.decoration as BoxDecoration).border;
    expect(border, isNull);
  });
}
