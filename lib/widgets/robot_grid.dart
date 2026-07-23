import 'package:flutter/material.dart';

import '../engine/interpreter.dart';
import '../models/direction.dart';
import '../theme/app_colors.dart';
import 'tile_color_ui.dart';

/// Renders the level grid, painted tile colors, stars, and the robot
/// sprite (rotated to face [RobotInterpreter.direction]).
class RobotGrid extends StatelessWidget {
  final RobotInterpreter interpreter;

  /// How long the robot's move/turn animation takes. Must not exceed the
  /// interval between steps — otherwise, at high auto-run speeds, each new
  /// step retargets the animation before it finishes the previous tile,
  /// and the robot visually never catches up (looks like it's skipping
  /// tiles even though every step still executes correctly underneath).
  final Duration stepDuration;

  const RobotGrid({
    super.key,
    required this.interpreter,
    this.stepDuration = const Duration(milliseconds: 180),
  });

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
    // A fixed 6px radius reads fine on normal-sized cells, but on a puzzle
    // with enough rows/columns that cellSize shrinks well below that, it
    // rounds away most of the tile — scale it down with the cell instead,
    // capped at the original 6px so typical-sized grids look unchanged.
    final radius = (size * 0.18).clamp(1.5, 6.0);
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
                borderRadius: BorderRadius.circular(radius),
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
                      child: Icon(Icons.star_rounded,
                          color: AppColors.star, size: size * 0.5),
                    )
                  : null,
            ),
    );
  }

  Widget _buildRobot(double size) {
    return AnimatedPositioned(
      duration: stepDuration,
      curve: Curves.easeInOut,
      left: interpreter.col * size,
      top: interpreter.row * size,
      width: size,
      height: size,
      child: _RobotSprite(
        size: size,
        direction: interpreter.direction,
        crashed: interpreter.status == RunStatus.crashed,
        duration: stepDuration,
      ),
    );
  }
}

/// The rotating robot icon. Tracks rotation as a continuous (unwrapped)
/// turns value rather than always jumping to the new direction's absolute
/// fraction — [AnimatedRotation] just linearly interpolates the raw number
/// with no concept of "shortest path", so animating straight to the new
/// direction's absolute turns can spin the long way around (e.g. a single
/// 90° turn visually spinning 270° the other way when it wraps past 0).
class _RobotSprite extends StatefulWidget {
  final double size;
  final Direction direction;
  final bool crashed;
  final Duration duration;

  const _RobotSprite({
    required this.size,
    required this.direction,
    required this.crashed,
    required this.duration,
  });

  @override
  State<_RobotSprite> createState() => _RobotSpriteState();
}

class _RobotSpriteState extends State<_RobotSprite> {
  late double _turns = _absoluteTurns(widget.direction);

  @override
  void didUpdateWidget(_RobotSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction != widget.direction) {
      final target = _absoluteTurns(widget.direction);
      var delta = (target - _turns) % 1.0; // always in [0, 1) in Dart
      if (delta > 0.5) delta -= 1.0; // fold into (-0.5, 0.5]: shortest path
      _turns += delta;
    }
  }

  // Icons.navigation points up by default; convert radians to turns.
  double _absoluteTurns(Direction direction) =>
      direction.radians / (2 * 3.141592653589793);

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      duration: widget.duration,
      turns: _turns,
      child: Center(
        child: Icon(
          Icons.navigation_rounded,
          size: widget.size * 0.55,
          color: widget.crashed ? Colors.redAccent : Colors.white,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    );
  }
}
