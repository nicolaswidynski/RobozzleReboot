import 'package:flutter/material.dart' hide GridTile;
import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/engine/interpreter.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/program.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/widgets/robot_grid.dart';

Level _levelWithGrid(int rows, int cols) {
  return Level(
    id: 'test-grid-$rows-$cols',
    name: 'Test Grid',
    grid: [
      for (var r = 0; r < rows; r++)
        [for (var c = 0; c < cols; c++) GridTile(color: TileColor.blue)],
    ],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [1, 0, 0, 0, 0],
  );
}

Future<BorderRadius> _pumpAndGetTileRadius(
  WidgetTester tester,
  Level level,
) async {
  final interpreter = RobotInterpreter(
    level: level,
    program: RobotProgram.empty(level),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 300,
        height: 300,
        child: RobotGrid(interpreter: interpreter),
      ),
    ),
  );
  final container = tester.widget<Container>(find.byType(Container).first);
  return (container.decoration as BoxDecoration).borderRadius as BorderRadius;
}

void main() {
  testWidgets(
      'tiles keep a small, non-circular corner radius on a puzzle with '
      'enough rows/columns that cells shrink well below the normal size',
      (tester) async {
    // 300x300 viewport / 20 columns = 15px cells — a fixed 6px radius would
    // round away most of a tile that size.
    final radius = await _pumpAndGetTileRadius(tester, _levelWithGrid(20, 20));

    expect(radius.topLeft.x, lessThan(6.0));
    expect(radius.topLeft.x, greaterThanOrEqualTo(1.5));
  });

  testWidgets(
      'tiles keep the normal 6px corner radius on an ordinarily-sized '
      'puzzle', (tester) async {
    // 300x300 viewport / 4 columns = 75px cells — comfortably above the
    // size where the radius needs to shrink.
    final radius = await _pumpAndGetTileRadius(tester, _levelWithGrid(1, 4));

    expect(radius.topLeft.x, 6.0);
  });
}
