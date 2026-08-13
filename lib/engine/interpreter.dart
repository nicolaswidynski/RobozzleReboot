import '../models/direction.dart';
import '../models/grid_tile.dart';
import '../models/instruction.dart';
import '../models/level.dart';
import '../models/program.dart';
import '../models/tile_color.dart';

enum RunStatus {
  /// Program built but not yet started.
  notStarted,

  /// Currently executing / paused mid-run.
  running,

  /// All stars collected.
  success,

  /// Robot moved into a gap or off the edge of the grid.
  crashed,

  /// Program ended (ran out of instructions) with stars still uncollected.
  outOfInstructions,

  /// Exceeded the step budget — almost certainly an infinite loop.
  stuck,
}

extension RunStatusData on RunStatus {
  bool get isTerminal => this != RunStatus.notStarted && this != RunStatus.running;
}

class _Frame {
  final int functionIndex;
  int slotIndex;
  _Frame(this.functionIndex, this.slotIndex);
}

/// A point-in-time copy of everything [step] mutates, so [RobotInterpreter]
/// can rewind one visible instruction via [RobotInterpreter.stepBack].
class _Snapshot {
  final int row;
  final int col;
  final Direction direction;
  final List<List<GridTile?>> grid;
  final int starsRemaining;
  final List<_Frame> stack;
  final RunStatus status;
  final int stepsExecuted;
  final int? highlightFunction;
  final int? highlightSlot;

  _Snapshot({
    required this.row,
    required this.col,
    required this.direction,
    required this.grid,
    required this.starsRemaining,
    required this.stack,
    required this.status,
    required this.stepsExecuted,
    required this.highlightFunction,
    required this.highlightSlot,
  });
}

/// Executes a [RobotProgram] against a [Level], one visible instruction at
/// a time via [step]. Holds all mutable runtime state (robot position,
/// painted tiles, remaining stars, call stack) so a level attempt can be
/// stepped, run continuously, or reset without touching the original level
/// data.
class RobotInterpreter {
  final Level level;
  final RobotProgram program;
  final int maxSteps;

  late int row;
  late int col;
  late Direction direction;
  late List<List<GridTile?>> grid; // deep-copied, paintable
  late int starsRemaining;
  late List<_Frame> _stack;
  late RunStatus status;
  late int stepsExecuted;
  final List<_Snapshot> _history = [];

  /// The function/slot index most recently evaluated, for UI highlighting.
  int? highlightFunction;
  int? highlightSlot;

  RobotInterpreter({
    required this.level,
    required this.program,
    this.maxSteps = 20000,
  }) {
    reset();
  }

  void reset() {
    row = level.startRow;
    col = level.startCol;
    direction = level.startDirection;
    grid = level.grid
        .map((r) => r
            .map((t) => t == null ? null : GridTile(color: t.color, hasStar: t.hasStar))
            .toList())
        .toList();
    starsRemaining = level.totalStars;
    stepsExecuted = 0;
    highlightFunction = null;
    highlightSlot = null;
    status = starsRemaining == 0 ? RunStatus.success : RunStatus.notStarted;
    _stack = program.functions[0].slots.isEmpty
        ? []
        : [_Frame(0, 0)];
    _history.clear();
  }

  GridTile? get currentTile => grid[row][col];

  /// The still-pending (not yet executed) instructions in each active stack
  /// frame, in the order they'll actually run: the currently active
  /// (innermost) frame first, then each paused caller's remaining
  /// instructions in the order control returns to them. A frame that has
  /// genuinely nothing left (about to be popped on the next [step]) is
  /// omitted. For UI display while running: naming which function is
  /// active (e.g. "F2") tells you nothing new once several nested/
  /// recursive frames all share the same function, but the pending
  /// instructions do — e.g. five frames each still holding "turn right,
  /// forward" makes it obvious what happens as the recursion unwinds.
  List<List<ProgramInstruction>> get pendingByFrame => _stack.reversed
      .map((f) => program.functions[f.functionIndex].slots
          .sublist(f.slotIndex)
          .whereType<ProgramInstruction>()
          .toList())
      .where((pending) => pending.isNotEmpty)
      .toList();

  /// Whether [stepBack] has anything to rewind to.
  bool get canStepBack => _history.isNotEmpty;

  List<List<GridTile?>> _copyGrid() => grid
      .map((r) => r.map((t) => t == null ? null : GridTile(color: t.color, hasStar: t.hasStar)).toList())
      .toList();

  /// Rewinds exactly one visible instruction, undoing whatever the most
  /// recent [step] call did (movement, paint, call/return, status change).
  /// A no-op if there is nothing to rewind ([canStepBack] is false).
  RunStatus stepBack() {
    if (_history.isEmpty) return status;
    final snapshot = _history.removeLast();
    row = snapshot.row;
    col = snapshot.col;
    direction = snapshot.direction;
    grid = snapshot.grid;
    starsRemaining = snapshot.starsRemaining;
    _stack = snapshot.stack;
    status = snapshot.status;
    stepsExecuted = snapshot.stepsExecuted;
    highlightFunction = snapshot.highlightFunction;
    highlightSlot = snapshot.highlightSlot;
    return status;
  }

  /// Executes exactly one visible instruction (skipping empty slots,
  /// function returns, and condition-mismatched instructions along the
  /// way without those counting as a "visible" step). Returns the status
  /// after the step.
  RunStatus step() {
    if (status.isTerminal) return status;
    _history.add(_Snapshot(
      row: row,
      col: col,
      direction: direction,
      grid: _copyGrid(),
      starsRemaining: starsRemaining,
      stack: _stack.map((f) => _Frame(f.functionIndex, f.slotIndex)).toList(),
      status: status,
      stepsExecuted: stepsExecuted,
      highlightFunction: highlightFunction,
      highlightSlot: highlightSlot,
    ));
    status = RunStatus.running;

    while (true) {
      if (_stack.isEmpty) {
        status = starsRemaining == 0 ? RunStatus.success : RunStatus.outOfInstructions;
        return status;
      }

      final frame = _stack.last;
      final fn = program.functions[frame.functionIndex];

      if (frame.slotIndex >= fn.slots.length) {
        _stack.removeLast();
        continue; // returning from a call is free, keep unwinding
      }

      final instr = fn.slots[frame.slotIndex];
      final evaluatedSlot = frame.slotIndex;
      frame.slotIndex++;

      if (instr == null) {
        continue; // empty slot, no-op, free
      }

      stepsExecuted++;
      if (stepsExecuted > maxSteps) {
        status = RunStatus.stuck;
        return status;
      }

      // Default/fallback highlight — the instruction now executing. Every
      // path below that completes normally overrides this to point at the
      // *next* instruction instead (see _updateHighlightToNext) so the UI
      // highlight shows what's about to happen, not what just did; a crash
      // is the one case that deliberately keeps pointing here, at whatever
      // instruction caused it.
      highlightFunction = frame.functionIndex;
      highlightSlot = evaluatedSlot;

      if (instr.condition != TileColor.any) {
        final tile = currentTile;
        if (tile == null || tile.color != instr.condition) {
          continue; // condition false, skip this instruction
        }
      }

      final action = instr.action;

      if (action.isCall) {
        final target = action.callTarget;
        if (program.functions[target].slots.isEmpty) {
          continue; // calling a disabled/empty function is a no-op
        }
        // A call with nothing left after it in the caller (the common
        // "call F1 as the last slot" loop) has nothing to return to —
        // replace the caller's frame instead of stacking on top of it, or
        // a self-recursive loop would grow the stack forever even though
        // there's no real nesting to show for it.
        final isTailCall =
            fn.slots.skip(frame.slotIndex).every((slot) => slot == null);
        if (isTailCall) {
          _stack.removeLast();
        }
        _stack.add(_Frame(target, 0));
        _updateHighlightToNext();
        return status;
      }

      switch (action) {
        case ActionType.turnLeft:
          direction = direction.turnLeft();
          _updateHighlightToNext();
          return status;
        case ActionType.turnRight:
          direction = direction.turnRight();
          _updateHighlightToNext();
          return status;
        case ActionType.paintRed:
          grid[row][col] = currentTile!.copyWith(color: TileColor.red);
          _updateHighlightToNext();
          return status;
        case ActionType.paintGreen:
          grid[row][col] = currentTile!.copyWith(color: TileColor.green);
          _updateHighlightToNext();
          return status;
        case ActionType.paintBlue:
          grid[row][col] = currentTile!.copyWith(color: TileColor.blue);
          _updateHighlightToNext();
          return status;
        case ActionType.forward:
          final (dRow, dCol) = direction.delta;
          final nr = row + dRow;
          final nc = col + dCol;
          final target = (nr < 0 || nr >= level.rowCount || nc < 0 || nc >= level.colCount)
              ? null
              : grid[nr][nc];
          if (target == null) {
            status = RunStatus.crashed;
            return status; // keep highlighting the instruction that crashed
          }
          row = nr;
          col = nc;
          if (target.hasStar) {
            target.hasStar = false;
            starsRemaining--;
          }
          if (starsRemaining == 0) {
            status = RunStatus.success;
          }
          _updateHighlightToNext();
          return status;
        default:
          return status; // unreachable (calls handled above)
      }
    }
  }

  /// Points [highlightFunction]/[highlightSlot] at the next instruction
  /// that will actually run — skipping empty slots, condition-mismatched
  /// instructions, and calls to empty/disabled functions the exact same
  /// way [step]'s own loop does, but on a throwaway copy of [_stack] so
  /// none of that lookahead actually mutates real execution state. Null
  /// when nothing's left to run (the program is about to end). Called
  /// after every instruction that completes normally, so the UI's
  /// highlight always shows what's about to happen, not what just did.
  void _updateHighlightToNext() {
    final peekStack = _stack.map((f) => _Frame(f.functionIndex, f.slotIndex)).toList();
    while (peekStack.isNotEmpty) {
      final frame = peekStack.last;
      final fn = program.functions[frame.functionIndex];

      if (frame.slotIndex >= fn.slots.length) {
        peekStack.removeLast();
        continue;
      }

      final instr = fn.slots[frame.slotIndex];
      if (instr == null) {
        frame.slotIndex++;
        continue;
      }
      if (instr.condition != TileColor.any) {
        final tile = currentTile;
        if (tile == null || tile.color != instr.condition) {
          frame.slotIndex++;
          continue;
        }
      }
      if (instr.action.isCall &&
          program.functions[instr.action.callTarget].slots.isEmpty) {
        frame.slotIndex++;
        continue;
      }

      highlightFunction = frame.functionIndex;
      highlightSlot = frame.slotIndex;
      return;
    }
    highlightFunction = null;
    highlightSlot = null;
  }

  /// Runs to completion for tests/tools. Not used by the interactive UI,
  /// which steps on a timer so it can animate and be paused.
  RunStatus runToCompletion() {
    while (!status.isTerminal) {
      step();
    }
    return status;
  }
}
