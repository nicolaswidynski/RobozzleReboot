import 'package:flutter/material.dart';

import '../models/tile_color.dart';

/// Flutter [Color] mapping for [TileColor]. Kept separate from the model
/// file so the engine/models layer stays pure Dart (testable without the
/// Flutter widget bindings).
extension TileColorUi on TileColor {
  Color get uiColor {
    switch (this) {
      case TileColor.red:
        return const Color(0xFFE0554F);
      case TileColor.green:
        return const Color(0xFF5CA85C);
      case TileColor.blue:
        return const Color(0xFF4C7FD6);
      case TileColor.any:
        return const Color(0xFF9E9E9E);
    }
  }
}
