import '../models/direction.dart';
import '../models/grid_tile.dart';
import '../models/level.dart';
import '../models/tile_color.dart';

List<List<GridTile?>> _grid(List<String> rows) =>
    [for (final row in rows) row.split('').map(gridTileFromChar).toList()];

/// Three short, hand-authored levels that introduce Robozzle's core
/// mechanics in order: movement, loops (via F1 calling itself), then
/// conditions + painting. Not part of the scraped catalog — ids are
/// prefixed `tutorial-` instead of `catalog-` so they never collide with it.
final List<Level> tutorialLevels = [
  // Straight line + one right turn + one left turn, no functions or paint
  // needed — just forward/turnLeft/turnRight, one instruction per slot.
  Level(
    id: 'tutorial-1',
    name: 'Tutorial 1: Moving & Turning',
    grid: _grid(const [
      'bbB  ',
      '  b  ',
      '  BbB',
    ]),
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [8, 0, 0, 0, 0],
    difficulty: 1,
    allowedPaintColors: const {},
  ),

  // A 5-star corridor with only 2 slots in F1 — too short to lay the path
  // out by hand, so it forces F1 to call itself: [forward, callF1].
  Level(
    id: 'tutorial-2',
    name: 'Tutorial 2: Loops with F1',
    grid: _grid(const [
      'rRRRRR',
    ]),
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [2, 0, 0, 0, 0],
    difficulty: 2,
    allowedPaintColors: const {},
  ),

  // Same self-calling loop as tutorial 2, but the corridor bends at a red
  // tile — reaching the star needs a conditioned turn (only fires on red)
  // folded into the loop body, plus a conditioned repaint right after it.
  Level(
    id: 'tutorial-3',
    name: 'Tutorial 3: Paint & Conditions',
    grid: _grid(const [
      'ggggr',
      '    g',
      '    G',
    ]),
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [4, 0, 0, 0, 0],
    difficulty: 3,
    allowedPaintColors: const {TileColor.green},
  ),
];
