import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

void main() {
  test('Level.fromJson parses a scraped catalog entry correctly', () {
    // A real entry from assets/levels_catalog.json (puzzle 195, "Another
    // speed control"): a spiral maze, robot starts bottom-left facing
    // right, ends on a red tile with only paintRed allowed.
    final json = {
      'sourceId': 195,
      'title': 'Another speed control',
      'author': 'evko',
      'difficulty': 3,
      'popularity': 158,
      'about': '',
      'rows': [
        ' bbbbbbbbbbb',
        ' b         b',
        ' b bbbbbbb b',
        ' b b     b b',
        ' b b bbb b b',
        ' b b B b b b',
        ' b b   b b b',
        ' b bbbbb b b',
        ' b       b b',
        ' bbbbbbbbb b',
        '           b',
        'bbbbbbbbbbbr',
      ],
      'startRow': 11,
      'startCol': 0,
      'startDirection': 'right',
      'slotsPerFunction': [7, 4, 4, 0, 0],
      'allowedCommands': 1,
    };

    final level = Level.fromJson(json);

    expect(level.name, 'Another speed control');
    expect(level.author, 'evko');
    expect(level.difficulty, 3);
    expect(level.popularity, 158);
    expect(level.startRow, 11);
    expect(level.startCol, 0);
    expect(level.startDirection, Direction.right);
    expect(level.slotsPerFunction, [7, 4, 4, 0, 0]);
    expect(level.rowCount, 12);
    expect(level.colCount, 12);
    expect(level.totalStars, 1);

    // allowedCommands: 1 -> only bit 0 (paintRed) set.
    expect(level.allowedPaintColors, {TileColor.red});

    // Spot-check a few decoded tiles: col0 row0 is a gap (' '), the star
    // sits at row5/col5 ('B'), the end tile is red ('r') at the far
    // bottom-right corner.
    expect(level.tileAt(0, 0), isNull);
    final star = level.tileAt(5, 5)!;
    expect(star.color, TileColor.blue);
    expect(star.hasStar, isTrue);
    final end = level.tileAt(11, 11)!;
    expect(end.color, TileColor.red);
    expect(end.hasStar, isFalse);
  });

  test('Level.fromJson decodes allowedCommands bitmask combinations', () {
    Map<String, dynamic> baseJson(int allowedCommands) => {
          'title': 'test',
          'difficulty': 1,
          'popularity': 0,
          'rows': ['r'],
          'startRow': 0,
          'startCol': 0,
          'startDirection': 'up',
          'slotsPerFunction': [1, 0, 0, 0, 0],
          'allowedCommands': allowedCommands,
        };

    // No "author" key in this fixture — defaults to empty, not a crash.
    expect(Level.fromJson(baseJson(0)).author, '');
    expect(Level.fromJson(baseJson(0)).allowedPaintColors, isEmpty);
    expect(Level.fromJson(baseJson(1)).allowedPaintColors, {TileColor.red});
    expect(Level.fromJson(baseJson(2)).allowedPaintColors, {TileColor.green});
    expect(Level.fromJson(baseJson(4)).allowedPaintColors, {TileColor.blue});
    expect(
      Level.fromJson(baseJson(7)).allowedPaintColors,
      {TileColor.red, TileColor.green, TileColor.blue},
    );
  });
}
