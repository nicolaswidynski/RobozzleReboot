import 'package:flutter/material.dart' hide GridTile;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'the instruction line paginates with </> buttons instead of '
      'scrolling, when it does not all fit on a narrow screen', (tester) async {
    // A narrow, old-phone-width viewport, small enough that movement +
    // colors + paint + F1..F5 don't all fit on one line.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // All 5 functions active, so every F1..F5 call button is offered.
    final level = Level(
      id: 'test-pagination',
      name: 'Pagination Test',
      grid: [
        [GridTile(color: TileColor.green, hasStar: true)],
      ],
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [2, 2, 2, 2, 2],
    );

    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [level])));
    await tester.pumpAndSettle();

    final rightChevronInkWell = find.ancestor(
      of: find.byIcon(Icons.keyboard_arrow_right_rounded),
      matching: find.byType(InkWell),
    );
    final leftChevronInkWell = find.ancestor(
      of: find.byIcon(Icons.keyboard_arrow_left_rounded),
      matching: find.byType(InkWell),
    );

    // Starts at the first page: nothing to page back to yet, but there's
    // more to see ahead.
    expect(tester.widget<InkWell>(leftChevronInkWell).onTap, isNull);
    expect(tester.widget<InkWell>(rightChevronInkWell).onTap, isNotNull);

    await tester.tap(rightChevronInkWell);
    await tester.pumpAndSettle();

    // Paging forward moved off the start, so paging back is now available.
    expect(tester.widget<InkWell>(leftChevronInkWell).onTap, isNotNull);
  });
}
