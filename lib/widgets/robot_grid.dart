import 'package:flutter/material.dart';

import '../engine/interpreter.dart';
import '../models/direction.dart';
import '../theme/app_colors.dart';
import 'tile_color_ui.dart';

/// Renders the level grid, painted tile colors, stars, and the robot
/// sprite (rotated to face [RobotInterpreter.direction]).
class RobotGrid extends StatelessWidget {
  final RobotInterpreter interpreter;

  const RobotGrid({super.key, required this.interpreter});

  @override
  Widget build(BuildContext context) {
    final level = interpreter.level;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = (constraints.maxWidth / level.colCount)
            .clamp(0.0, constraints.maxHeight / level.rowCount);
        final gridWidth = cellSize * level.colCount;
        final gridHeight = cellSize * level.rowCount;
        return Center(
          child: SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: Stack(
              children: [
                for (var r = 0; r < level.rowCount; r++)
                  for (var c = 0; c < level.colCount; c++)
                    _buildCell(r, c, cellSize),
                _buildRobot(cellSize),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCell(int row, int col, double size) {
    final tile = interpreter.grid[row][col];
    return Positioned(
      left: col * size,
      top: row * size,
      width: size,
      height: size,
      child: tile == null
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: tile.color.uiColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: tile.hasStar
                  ? Center(
                      child: Icon(Icons.star_rounded, color: AppColors.star, size: size * 0.5),
                    )
                  : null,
            ),
    );
  }

  Widget _buildRobot(double size) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      left: interpreter.col * size,
      top: interpreter.row * size,
      width: size,
      height: size,
      child: AnimatedRotation(
        duration: const Duration(milliseconds: 180),
        turns: _turnsFor(interpreter.direction),
        child: Center(
          child: Icon(
            Icons.navigation_rounded,
            size: size * 0.55,
            color: interpreter.status == RunStatus.crashed
                ? Colors.redAccent
                : Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  double _turnsFor(Direction direction) {
    // Icons.navigation points up by default; convert radians to turns.
    return direction.radians / (2 * 3.141592653589793);
  }
}
