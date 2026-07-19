import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

/// A minimal straight-line level for widget tests that just need *some*
/// playable level (drag/drop, controls, function visibility) — not tied to
/// any specific shipped puzzle. The real puzzle set is the scraped catalog
/// (see lib/data/level_catalog.dart); the app no longer ships hand-authored
/// levels.
Level testLevel() {
  return Level(
    id: 'test-fixture',
    name: 'Test Level',
    grid: [
      [
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.green, hasStar: true),
      ],
    ],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [6, 0, 0, 0, 0],
  );
}

/// A second, distinctly-named fixture with the same shape as [testLevel],
/// for tests that need to confirm navigation moved to a *different* level.
Level testLevel2() {
  return Level(
    id: 'test-fixture-2',
    name: 'Test Level 2',
    grid: [
      [
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.green, hasStar: true),
      ],
    ],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [6, 0, 0, 0, 0],
  );
}
