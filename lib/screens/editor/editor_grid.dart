import 'package:flutter/material.dart' hide GridTile;

import '../../models/direction.dart';
import '../../models/grid_tile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tile_color_ui.dart';

/// A tappable grid for building a level in the editor — visually similar to
/// [RobotGrid] (same tile styling), but driven by raw edit state instead of
/// a [RobotInterpreter], and reports taps instead of animating a run.
class EditorGrid extends StatelessWidget {
  final List<List<GridTile?>> grid;
  final int startRow;
  final int startCol;
  final Direction startDirection;
  final void Function(int row, int col) onCellTap;

  const EditorGrid({
    super.key,
    required this.grid,
    required this.startRow,
    required this.startCol,
    required this.startDirection,
    required this.onCellTap,
  });

  int get _rowCount => grid.length;
  int get _colCount => grid.isEmpty ? 0 : grid[0].length;

  @override
  Widget build(BuildContext context) {
    if (_rowCount == 0 || _colCount == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = (constraints.maxWidth / _colCount)
            .clamp(0.0, constraints.maxHeight / _rowCount);
        final gridWidth = cellSize * _colCount;
        final gridHeight = cellSize * _rowCount;
        return Center(
          child: SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: Stack(
              children: [
                for (var r = 0; r < _rowCount; r++)
                  for (var c = 0; c < _colCount; c++) _buildCell(r, c, cellSize),
                if (startRow >= 0 &&
                    startRow < _rowCount &&
                    startCol >= 0 &&
                    startCol < _colCount)
                  _buildStartMarker(cellSize),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCell(int row, int col, double size) {
    final tile = grid[row][col];
    return Positioned(
      left: col * size,
      top: row * size,
      width: size,
      height: size,
      child: GestureDetector(
        key: ValueKey('editor_cell_${row}_$col'),
        onTap: () => onCellTap(row, col),
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: tile?.color.uiColor ?? Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: tile == null ? 0.08 : 0.18),
            ),
          ),
          child: tile != null && tile.hasStar
              ? Center(
                  child: Icon(Icons.star_rounded,
                      color: AppColors.star, size: size * 0.5),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildStartMarker(double size) {
    return Positioned(
      left: startCol * size,
      top: startRow * size,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Center(
          child: Transform.rotate(
            angle: startDirection.radians,
            child: Icon(Icons.navigation_rounded,
                color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}
