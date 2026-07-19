/// The colors a tile (or a color-conditioned instruction) can have.
///
/// [any] is not a real tile color — it's used as the "no condition, always
/// run" marker on an instruction slot. Tiles themselves are always one of
/// red/green/blue.
///
/// Deliberately has no dependency on Flutter — this file is part of the
/// pure-Dart game engine/model layer so it can be unit-tested with plain
/// `dart test`, with no widget bindings required. UI color mappings live in
/// lib/widgets/tile_color_ui.dart instead.
enum TileColor { red, green, blue, any }

extension TileColorDisplay on TileColor {
  String get label {
    switch (this) {
      case TileColor.red:
        return 'Red';
      case TileColor.green:
        return 'Green';
      case TileColor.blue:
        return 'Blue';
      case TileColor.any:
        return 'Any';
    }
  }
}
