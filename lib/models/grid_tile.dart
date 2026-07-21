import 'tile_color.dart';

/// A single cell of the level grid. `null` in the grid means "no tile here"
/// (a gap the robot cannot stand on or move onto — walking off the edge of
/// a tile, or into a gap, crashes the robot).
class GridTile {
  TileColor color; // never TileColor.any for an actual tile
  bool hasStar;

  GridTile({required this.color, this.hasStar = false});

  GridTile copyWith({TileColor? color, bool? hasStar}) {
    return GridTile(
      color: color ?? this.color,
      hasStar: hasStar ?? this.hasStar,
    );
  }
}

/// Decodes a single board character using the encoding shared by
/// hand-authored levels and the scraped catalog:
///   ' ' or '.' = gap (no tile)
///   'r'/'g'/'b' = tile colored red/green/blue
///   'R'/'G'/'B' = same, but with a star on it
GridTile? gridTileFromChar(String ch) {
  switch (ch) {
    case ' ':
    case '.':
      return null;
    case 'r':
      return GridTile(color: TileColor.red);
    case 'g':
      return GridTile(color: TileColor.green);
    case 'b':
      return GridTile(color: TileColor.blue);
    case 'R':
      return GridTile(color: TileColor.red, hasStar: true);
    case 'G':
      return GridTile(color: TileColor.green, hasStar: true);
    case 'B':
      return GridTile(color: TileColor.blue, hasStar: true);
    default:
      throw ArgumentError('Unknown tile char "$ch"');
  }
}

/// Inverse of [gridTileFromChar] — used by the level editor to serialize an
/// edited grid back into the same row-string encoding the catalog uses.
String gridTileToChar(GridTile? tile) {
  if (tile == null) return ' ';
  switch (tile.color) {
    case TileColor.red:
      return tile.hasStar ? 'R' : 'r';
    case TileColor.green:
      return tile.hasStar ? 'G' : 'g';
    case TileColor.blue:
      return tile.hasStar ? 'B' : 'b';
    case TileColor.any:
      throw ArgumentError('A tile can never be TileColor.any');
  }
}
