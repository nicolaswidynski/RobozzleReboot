import 'package:flutter/material.dart';

import '../models/instruction.dart';
import '../models/tile_color.dart';
import 'tile_color_ui.dart';

/// Visual glyph for an [ActionType], shared by the instruction palette and
/// the function slot editor so both render identically.
Widget actionGlyph(ActionType action, {double size = 20, Color color = Colors.white}) {
  final paint = _paintTileColor(action);
  if (paint != null) {
    return Icon(Icons.format_paint_rounded, size: size, color: paint.uiColor);
  }
  switch (action) {
    case ActionType.forward:
      return Icon(Icons.arrow_upward_rounded, size: size, color: color);
    case ActionType.turnLeft:
      return Icon(Icons.turn_left_rounded, size: size, color: color);
    case ActionType.turnRight:
      return Icon(Icons.turn_right_rounded, size: size, color: color);
    default:
      return Text(
        action.shortLabel,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.55),
      );
  }
}

TileColor? _paintTileColor(ActionType action) {
  switch (action) {
    case ActionType.paintRed:
      return TileColor.red;
    case ActionType.paintGreen:
      return TileColor.green;
    case ActionType.paintBlue:
      return TileColor.blue;
    default:
      return null;
  }
}
