import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/puzzle_content.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/level.dart';

void main() {
  test('parses the robozzle-get-puzzle response shape, including '
      'slotsPerFunction being a JSON-encoded string rather than an array',
      () {
    final json = {
      "request_id": "c5a080a0-369c-4db5-bb4f-3413e677a287",
      "status": "success",
      "message": "User udpated",
      "startRow": "6",
      "startCol": "7",
      "startDirection": "right",
      "allowedCommands": "0",
      "slotsPerFunction": "[4, 3, 5, 0, 0]",
      "rows": [
        "rgbbbbbbbbbbbr",
        "b            g",
        "b         g  b",
      ],
    };

    final content = parsePuzzleContent(json);

    expect(content.startRow, 6);
    expect(content.startCol, 7);
    expect(content.startDirection, 'right');
    expect(content.allowedCommands, 0);
    expect(content.slotsPerFunction, [4, 3, 5, 0, 0]);
    expect(content.rows, [
      "rgbbbbbbbbbbbr",
      "b            g",
      "b         g  b",
    ]);
  });

  test('buildLevelWithContent combines a placeholder\'s listing metadata '
      'with fetched content into a fully playable Level', () {
    final placeholder = Level(
      id: 'catalog-392',
      name: '2-Bit Something',
      author: 'evko',
      grid: const [],
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [0, 0, 0, 0, 0],
      difficulty: 4,
      popularity: 99,
    );
    final content = PuzzleContentFixture.content;

    final level = buildLevelWithContent(placeholder, content);

    expect(level.id, 'catalog-392');
    expect(level.name, '2-Bit Something');
    expect(level.author, 'evko');
    expect(level.difficulty, 4);
    expect(level.popularity, 99);
    expect(level.startRow, 6);
    expect(level.startCol, 7);
    expect(level.slotsPerFunction, [4, 3, 5, 0, 0]);
    expect(level.grid, isNotEmpty);
    expect(level.rowCount, 3);
  });
}

class PuzzleContentFixture {
  static final content = parsePuzzleContent({
    "startRow": "6",
    "startCol": "7",
    "startDirection": "right",
    "allowedCommands": "0",
    "slotsPerFunction": "[4, 3, 5, 0, 0]",
    "rows": ["rgbbbbbbbbbbbr", "b            g", "b         g  b"],
  });
}
