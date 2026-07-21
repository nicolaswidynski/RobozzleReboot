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
    description:
        'Robozzle is about programming a robot to collect every star on '
        'the board.\n\n'
        'Drag instructions from the palette below into the F1 slots to '
        'build your program: Forward moves the robot one tile in the '
        'direction it\'s facing, and Turn Left / Turn Right rotate it in '
        'place without moving.\n\n'
        'Once your program is ready, press Play to run it, or Step to run '
        'one instruction at a time. Walking off the edge of the grid or '
        'into a gap crashes the robot, so plan your turns before you '
        'collect that last star.',
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
    description:
        'This corridor has 5 stars, but F1 only has 2 slots — not enough '
        'to write "Forward" five times by hand.\n\n'
        'A function can call itself: place "Call F1" as an instruction '
        'inside F1, and it will run itself again as soon as it finishes — '
        'like a loop that repeats until the puzzle is solved.\n\n'
        'Try: Forward, then Call F1. That\'s the whole program.',
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
    description:
        'Every instruction can carry a color condition: after placing it, '
        'tap a color dot and that instruction will only run when the '
        'robot is standing on a tile of that color — otherwise it\'s '
        'skipped.\n\n'
        'This corridor is green all the way, then bends at a single red '
        'tile. Loop with Forward + Call F1 like before, but add a Turn '
        'Right conditioned on red right before the Forward — it\'ll do '
        'nothing on the green tiles and turn exactly once, right when it '
        'reaches the bend.\n\n'
        'You can also paint the tile you\'re standing on with Paint Green '
        '/ Red / Blue, which is how later puzzles mark tiles for a loop '
        'to react to.',
  ),
];
