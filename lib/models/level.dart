import 'direction.dart';
import 'grid_tile.dart';
import 'tile_color.dart';

/// A puzzle level: a grid of tiles (with gaps), a robot start state, and
/// constraints on how big a program the player is allowed to build.
class Level {
  /// Stable across app runs (used as the key for persisting completion) —
  /// unlike [name], which isn't guaranteed unique across the scraped catalog.
  final String id;
  final String name;
  final List<List<GridTile?>> grid; // grid[row][col], null = gap
  final int startRow;
  final int startCol;
  final Direction startDirection;

  /// Number of instruction slots available in each of the 5 functions.
  /// A value of 0 means that function is not offered to the player at all.
  final List<int> slotsPerFunction;

  /// Placeholder difficulty rating (1 = easiest) used to sort the level
  /// list. How this gets set for real (author-assigned vs. derived from
  /// solve stats) is still to be decided.
  final int difficulty;

  /// Placeholder popularity score (higher = more popular) used to sort the
  /// level list. How this gets set for real (e.g. play counts) is still to
  /// be decided.
  final int popularity;

  /// Which paint colors the instruction palette offers for this level.
  /// Some scraped levels restrict this (e.g. red-only); hand-authored
  /// levels default to all three.
  final Set<TileColor> allowedPaintColors;

  const Level({
    required this.id,
    required this.name,
    required this.grid,
    required this.startRow,
    required this.startCol,
    required this.startDirection,
    required this.slotsPerFunction,
    this.difficulty = 1,
    this.popularity = 0,
    this.allowedPaintColors = const {TileColor.red, TileColor.green, TileColor.blue},
  }) : assert(slotsPerFunction.length == 5);

  /// Parses a level from a `levels_catalog.json` entry (see
  /// lib/data/level_catalog.dart for the scrape that produced it).
  factory Level.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List).cast<String>();
    final allowedCommands = json['allowedCommands'] as int;
    return Level(
      id: 'catalog-${json['sourceId']}',
      name: json['title'] as String,
      grid: rows.map((row) => row.split('').map(gridTileFromChar).toList()).toList(),
      startRow: json['startRow'] as int,
      startCol: json['startCol'] as int,
      startDirection: Direction.values.byName(json['startDirection'] as String),
      slotsPerFunction: (json['slotsPerFunction'] as List).cast<int>(),
      difficulty: json['difficulty'] as int,
      popularity: json['popularity'] as int,
      allowedPaintColors: {
        if (allowedCommands & 1 != 0) TileColor.red,
        if (allowedCommands & 2 != 0) TileColor.green,
        if (allowedCommands & 4 != 0) TileColor.blue,
      },
    );
  }

  int get rowCount => grid.length;
  int get colCount => grid.isEmpty ? 0 : grid[0].length;

  GridTile? tileAt(int row, int col) {
    if (row < 0 || row >= rowCount) return null;
    if (col < 0 || col >= colCount) return null;
    return grid[row][col];
  }

  int get totalStars {
    var count = 0;
    for (final row in grid) {
      for (final tile in row) {
        if (tile != null && tile.hasStar) count++;
      }
    }
    return count;
  }
}
