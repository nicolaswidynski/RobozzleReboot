import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/custom_puzzle_store.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

Level _puzzle(String id) => Level(
      id: id,
      name: 'My Puzzle',
      grid: [
        [GridTile(color: TileColor.red), GridTile(color: TileColor.green, hasStar: true)],
        [null, GridTile(color: TileColor.blue)],
      ],
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [3, 0, 0, 0, 0],
      allowedPaintColors: const {TileColor.blue},
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save/loadAll round-trips a custom puzzle exactly', () async {
    final store = CustomPuzzleStore();
    final id = CustomPuzzleStore.newId();
    expect(id, startsWith('custom-'));

    await store.save(_puzzle(id));
    final loaded = await store.loadAll();

    expect(loaded, hasLength(1));
    final level = loaded.first;
    expect(level.id, id);
    expect(level.name, 'My Puzzle');
    expect(level.startRow, 0);
    expect(level.startCol, 0);
    expect(level.startDirection, Direction.right);
    expect(level.slotsPerFunction, [3, 0, 0, 0, 0]);
    expect(level.allowedPaintColors, {TileColor.blue});
    expect(level.rowCount, 2);
    expect(level.colCount, 2);
    expect(level.tileAt(0, 0)?.color, TileColor.red);
    expect(level.tileAt(0, 1)?.color, TileColor.green);
    expect(level.tileAt(0, 1)?.hasStar, isTrue);
    expect(level.tileAt(1, 0), isNull); // gap preserved
    expect(level.tileAt(1, 1)?.color, TileColor.blue);
  });

  test('save overwrites an existing puzzle with the same id', () async {
    final store = CustomPuzzleStore();
    final id = CustomPuzzleStore.newId();

    await store.save(_puzzle(id));
    final renamed = Level(
      id: id,
      name: 'Renamed',
      grid: _puzzle(id).grid,
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [1, 0, 0, 0, 0],
    );
    await store.save(renamed);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.name, 'Renamed');
  });

  test('delete removes only the matching puzzle', () async {
    final store = CustomPuzzleStore();
    final idA = CustomPuzzleStore.newId();
    final idB = CustomPuzzleStore.newId();
    await store.save(_puzzle(idA));
    await store.save(_puzzle(idB));

    await store.delete(idA);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, idB);
  });

  test('markPublished/loadPublishedIds tracks publish state per puzzle, '
      'and it survives a re-save', () async {
    final store = CustomPuzzleStore();
    final idA = CustomPuzzleStore.newId();
    final idB = CustomPuzzleStore.newId();
    await store.save(_puzzle(idA));
    await store.save(_puzzle(idB));

    expect(await store.loadPublishedIds(), isEmpty);

    await store.markPublished(idA);
    expect(await store.loadPublishedIds(), {idA});

    // Publishing is one-way — re-saving (e.g. after editing) keeps it
    // marked published rather than resetting the flag.
    await store.save(Level(
      id: idA,
      name: 'Edited after publishing',
      grid: _puzzle(idA).grid,
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [1, 0, 0, 0, 0],
    ));
    expect(await store.loadPublishedIds(), {idA});

    final loaded = await store.loadAll();
    expect(loaded.firstWhere((l) => l.id == idA).name, 'Edited after publishing');
  });
}
