import 'package:flutter_test/flutter_test.dart';
import 'package:robozzle_reboot/engine/interpreter.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/program.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

Level _straightLine() {
  return Level(
    id: 'test-straight',
    name: 'test-straight',
    grid: [
      [
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue, hasStar: true),
      ],
    ],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [6, 0, 0, 0, 0],
  );
}

/// Same idea as [_straightLine], but long enough that a few "forward" steps
/// don't accidentally collect the star and end the run — for tests that
/// care about interpreter/stack state mid-loop, not about solving anything.
Level _longStraightLine() {
  return Level(
    id: 'test-long-straight',
    name: 'test-long-straight',
    grid: [
      [
        for (var i = 0; i < 7; i++) GridTile(color: TileColor.blue),
        GridTile(color: TileColor.blue, hasStar: true),
      ],
    ],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [6, 0, 0, 0, 0],
  );
}

/// An L-shaped path: three tiles east, then a red corner tile, then three
/// tiles south — exercises movement, turning, color conditionals, subroutine
/// calls, and star collection all together.
Level _lShapedLevel() {
  const rows = [
    'bbbR',
    '...b',
    '...b',
    '...G',
  ];
  return Level(
    id: 'test-l-shaped',
    name: 'test-l-shaped',
    grid: rows.map((row) => row.split('').map(gridTileFromChar).toList()).toList(),
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [8, 4, 0, 0, 0],
  );
}

void main() {
  group('basic movement', () {
    test('forward moves the robot and collects a star, then succeeds', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));

      final interpreter = RobotInterpreter(level: level, program: program);
      expect(interpreter.starsRemaining, 1);

      interpreter.step(); // first forward: (0,0) -> (0,1)
      expect(interpreter.row, 0);
      expect(interpreter.col, 1);
      expect(interpreter.status, RunStatus.running);

      interpreter.step(); // second forward: (0,1) -> (0,2), star tile
      expect(interpreter.col, 2);
      expect(interpreter.starsRemaining, 0);
      expect(interpreter.status, RunStatus.success);
    });

    test('turnLeft/turnRight rotate without moving', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.turnRight));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step();
      expect(interpreter.direction, Direction.down);
      expect(interpreter.col, 0); // did not move
    });

    test('walking off the edge of the grid crashes', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      // Face left immediately, then try to move forward off the grid.
      program.setSlot(0, 0, const ProgramInstruction(ActionType.turnLeft));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.turnLeft));
      program.setSlot(0, 2, const ProgramInstruction(ActionType.forward));

      final interpreter = RobotInterpreter(level: level, program: program);
      interpreter.step(); // turnLeft x2 -> facing left
      interpreter.step();
      expect(interpreter.direction, Direction.left);

      interpreter.step(); // forward into the void off col -1
      expect(interpreter.status, RunStatus.crashed);
    });

    test('walking into a gap tile crashes', () {
      final level = Level(
        id: 'gap-test',
        name: 'gap-test',
        grid: [
          [GridTile(color: TileColor.blue, hasStar: true), null],
        ],
        startRow: 0,
        startCol: 0,
        startDirection: Direction.right,
        slotsPerFunction: const [2, 0, 0, 0, 0],
      );
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);
      interpreter.step();
      expect(interpreter.status, RunStatus.crashed);
    });
  });

  group('step back / undo', () {
    test('canStepBack is false until a step has been taken', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      expect(interpreter.canStepBack, isFalse);
      interpreter.step();
      expect(interpreter.canStepBack, isTrue);
    });

    test('stepBack undoes a forward move and restores status/highlight', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      expect(interpreter.status, RunStatus.notStarted);
      interpreter.step();
      expect(interpreter.col, 1);
      expect(interpreter.status, RunStatus.running);

      interpreter.stepBack();
      expect(interpreter.col, 0);
      expect(interpreter.status, RunStatus.notStarted);
      expect(interpreter.canStepBack, isFalse);
    });

    test('stepBack undoes star collection and a success status', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step();
      interpreter.step(); // reaches the star tile -> success
      expect(interpreter.status, RunStatus.success);
      expect(interpreter.starsRemaining, 0);

      interpreter.stepBack();
      expect(interpreter.status, RunStatus.running);
      expect(interpreter.starsRemaining, 1);
      expect(interpreter.col, 1);
    });

    test('stepBack undoes a paint action', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.paintGreen));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step();
      expect(interpreter.grid[0][0]!.color, TileColor.green);

      interpreter.stepBack();
      expect(interpreter.grid[0][0]!.color, TileColor.blue);
    });

    test('stepping forward again after a stepBack replays correctly', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // col 0 -> 1
      interpreter.stepBack(); // back to col 0
      interpreter.step(); // col 0 -> 1 again
      interpreter.step(); // col 1 -> 2, star tile -> success
      expect(interpreter.status, RunStatus.success);
      expect(interpreter.col, 2);
    });
  });

  test('running out of instructions with stars left does not count as success', () {
    final level = _straightLine();
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
    // Only one forward placed; robot stops one tile short of the star.
    final interpreter = RobotInterpreter(level: level, program: program);
    interpreter.step(); // executes the one forward (col0 -> col1)
    expect(interpreter.status, RunStatus.running);
    interpreter.step(); // no more real instructions left, function returns
    expect(interpreter.status, RunStatus.outOfInstructions);
    expect(interpreter.starsRemaining, 1);
  });

  test('paint changes the tile color, affecting a later conditional', () {
    final level = _straightLine();
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.paintGreen));
    // This forward is conditioned on green — only fires because we just
    // painted the starting tile green.
    program.setSlot(
      0,
      1,
      const ProgramInstruction(ActionType.forward, condition: TileColor.green),
    );
    final interpreter = RobotInterpreter(level: level, program: program);

    interpreter.step(); // paint
    expect(interpreter.grid[0][0]!.color, TileColor.green);
    expect(interpreter.col, 0); // paint doesn't move the robot

    interpreter.step(); // conditional forward, should now fire
    expect(interpreter.col, 1);
  });

  test('a color-conditioned instruction is skipped when the tile does not match', () {
    final level = _straightLine(); // all blue tiles
    final program = RobotProgram.empty(level);
    program.setSlot(
      0,
      0,
      const ProgramInstruction(ActionType.forward, condition: TileColor.red),
    );
    program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
    final interpreter = RobotInterpreter(level: level, program: program);

    interpreter.step(); // slot 0 skipped (not red), falls through to slot 1
    expect(interpreter.col, 1);
    expect(interpreter.status, RunStatus.running);
  });

  test('subroutine calls execute the callee and return to the caller', () {
    final level = Level(
      id: 'subroutine-test',
      name: 'subroutine-test',
      grid: [
        [
          GridTile(color: TileColor.blue),
          GridTile(color: TileColor.blue),
          GridTile(color: TileColor.blue, hasStar: true),
        ],
      ],
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [2, 2, 0, 0, 0],
    );
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.callF2));
    program.setSlot(1, 0, const ProgramInstruction(ActionType.forward));
    program.setSlot(1, 1, const ProgramInstruction(ActionType.forward));

    final interpreter = RobotInterpreter(level: level, program: program);
    interpreter.step(); // call F2 (no movement yet)
    expect(interpreter.col, 0);
    interpreter.step(); // F2 slot 0: forward
    expect(interpreter.col, 1);
    interpreter.step(); // F2 slot 1: forward, collects star -> success
    expect(interpreter.col, 2);
    expect(interpreter.status, RunStatus.success);
  });

  test('unconditional self-recursion is eventually flagged as stuck', () {
    final level = _straightLine();
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.callF1));
    final interpreter = RobotInterpreter(level: level, program: program, maxSteps: 500);

    final status = interpreter.runToCompletion();
    expect(status, RunStatus.stuck);
  });

  test('an L-shaped level is solvable with a subroutine and a '
      'color-conditioned turn', () {
    final level = _lShapedLevel();
    final program = RobotProgram.empty(level);
    // F1: forward x3 (reach the red corner + collect its star), turn right
    // only once on the red tile, then call F2.
    program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
    program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
    program.setSlot(0, 2, const ProgramInstruction(ActionType.forward));
    program.setSlot(
      0,
      3,
      const ProgramInstruction(ActionType.turnRight, condition: TileColor.red),
    );
    program.setSlot(0, 4, const ProgramInstruction(ActionType.callF2));
    // F2: forward x3 down the second corridor to the final star.
    program.setSlot(1, 0, const ProgramInstruction(ActionType.forward));
    program.setSlot(1, 1, const ProgramInstruction(ActionType.forward));
    program.setSlot(1, 2, const ProgramInstruction(ActionType.forward));

    final interpreter = RobotInterpreter(level: level, program: program);
    final status = interpreter.runToCompletion();

    expect(status, RunStatus.success);
    expect(interpreter.starsRemaining, 0);
    expect(interpreter.row, 3);
    expect(interpreter.col, 3);
  });

  group('pendingByFrame (drives the control bar\'s live status display)', () {
    List<List<ActionType>> actionsOnly(RobotInterpreter i) => i.pendingByFrame
        .map((frame) => frame.map((instr) => instr.action).toList())
        .toList();

    test(
        'a self-recursive tail call replaces the frame instead of growing '
        'the stack', () {
      final level = _longStraightLine();
      final program = RobotProgram.empty(level);
      // F1: forward, then call F1 as the very last slot — the classic
      // "loop forever" pattern. Nothing follows the call, so there's no
      // caller state left to return to.
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.callF1));

      final interpreter = RobotInterpreter(level: level, program: program);
      expect(actionsOnly(interpreter), [
        [ActionType.forward, ActionType.callF1]
      ]);

      interpreter.step(); // forward
      expect(actionsOnly(interpreter), [
        [ActionType.callF1]
      ]);

      interpreter.step(); // call F1 — tail call: frame replaced, not pushed
      expect(actionsOnly(interpreter), [
        [ActionType.forward, ActionType.callF1]
      ]);

      interpreter.step(); // forward again, inside the "new" F1 frame
      expect(actionsOnly(interpreter), [
        [ActionType.callF1]
      ]);

      interpreter.step(); // call F1 again — still just the one frame
      expect(actionsOnly(interpreter), [
        [ActionType.forward, ActionType.callF1]
      ]);
    });

    test('a genuine nested call shows both frames until the callee returns',
        () {
      final level = _lShapedLevel();
      final program = RobotProgram.empty(level);
      // F1: call F2, then forward — the call is *not* the last slot, so F1
      // still has work left to resume once F2 returns.
      program.setSlot(0, 0, const ProgramInstruction(ActionType.callF2));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
      // F2: forward.
      program.setSlot(1, 0, const ProgramInstruction(ActionType.forward));

      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // call F2 — F1 has more to do, so it stays stacked
      expect(actionsOnly(interpreter), [
        [ActionType.forward],
        [ActionType.forward],
      ]);

      interpreter.step(); // F2's forward — F2 now has nothing left, so it's omitted
      expect(actionsOnly(interpreter), [
        [ActionType.forward]
      ]);

      interpreter.step(); // F2 returns and F1's forward runs, leaving nothing pending
      expect(actionsOnly(interpreter), []);
    });

    test(
        'recursing down a run of red tiles: repeated frames collapse into '
        'one group instead of listing the same function over and over',
        () {
      // Reproduces a real bug report. F1: call F2. F2: forward, call F2
      // (if red), turn right, forward. Every red tile recurses one level
      // deeper. The old display just named the active function per frame
      // ("F2", "F2", "F2", ...) — useless once it's the same function at
      // every level. What's actually useful is what each paused frame
      // still has left to run once it resumes: "turn right, forward" —
      // identical across every waiting frame, so it should collapse into
      // one "×N" group instead of repeating "F2" N times.
      final level = Level(
        id: 'test-red-run',
        name: 'test-red-run',
        grid: [
          [
            for (var i = 0; i < 6; i++) GridTile(color: TileColor.red),
            GridTile(color: TileColor.blue, hasStar: true),
          ],
        ],
        startRow: 0,
        startCol: 0,
        startDirection: Direction.right,
        slotsPerFunction: const [1, 4, 0, 0, 0],
      );
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.callF2));
      program.setSlot(1, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(
        1,
        1,
        const ProgramInstruction(ActionType.callF2, condition: TileColor.red),
      );
      program.setSlot(1, 2, const ProgramInstruction(ActionType.turnRight));
      program.setSlot(1, 3, const ProgramInstruction(ActionType.forward));

      final interpreter = RobotInterpreter(level: level, program: program);
      interpreter.step(); // F1 calls F2 (tail call: F1 has nothing after it)
      // Walk onto 4 red tiles, recursing one level deeper each time.
      for (var i = 0; i < 4; i++) {
        interpreter.step(); // forward
        interpreter.step(); // call F2 (red) — condition holds, recurse
      }

      // 4 outer frames are all paused right after their own "call F2",
      // each with the identical tail still to run; the 5th (innermost,
      // freshly pushed) frame hasn't done anything yet, so its pending is
      // its whole body instead.
      expect(actionsOnly(interpreter), [
        [ActionType.turnRight, ActionType.forward],
        [ActionType.turnRight, ActionType.forward],
        [ActionType.turnRight, ActionType.forward],
        [ActionType.turnRight, ActionType.forward],
        [
          ActionType.forward,
          ActionType.callF2,
          ActionType.turnRight,
          ActionType.forward
        ],
      ]);
    });
  });

  group('highlightFunction/highlightSlot (drives the yellow highlight in '
      'the UI)', () {
    test('after a step, the highlight points at the next instruction to '
        'run, not the one that just ran', () {
      final level = _longStraightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // executes slot 0
      expect(interpreter.highlightFunction, 0);
      expect(interpreter.highlightSlot, 1); // slot 1, not the one that ran

      interpreter.step(); // executes slot 1
      // Nothing real left in F1 -- the program is about to end.
      expect(interpreter.highlightFunction, isNull);
      expect(interpreter.highlightSlot, isNull);
    });

    test('the highlight skips over empty slots to the next real '
        'instruction', () {
      final level = _longStraightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      // slot 1 left empty
      program.setSlot(0, 2, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step();
      expect(interpreter.highlightFunction, 0);
      expect(interpreter.highlightSlot, 2);
    });

    test('the highlight skips a condition-mismatched instruction to the '
        'next one that will actually run', () {
      final level = _longStraightLine(); // every tile is blue
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(
          0, 1, const ProgramInstruction(ActionType.turnRight, condition: TileColor.red));
      program.setSlot(0, 2, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // slot 0: forward, lands on a blue tile
      // slot 1's condition (red) doesn't match the blue tile it'll be
      // evaluated against, so the highlight jumps straight past it to 2.
      expect(interpreter.highlightFunction, 0);
      expect(interpreter.highlightSlot, 2);
    });

    test('a call moves the highlight straight into the called function, '
        'not to whatever follows the call', () {
      final level = _lShapedLevel(); // has a real F2 (slotsPerFunction[1] > 0)
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.callF2));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.turnRight));
      program.setSlot(1, 0, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // executes the call, pushing a frame for F2
      expect(interpreter.highlightFunction, 1);
      expect(interpreter.highlightSlot, 0);
    });

    test('a self-recursive tail call wraps the highlight back to the '
        'start of the loop', () {
      final level = _longStraightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.callF1));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // slot 0: forward
      expect(interpreter.highlightSlot, 1);

      interpreter.step(); // slot 1: tail call back into F1
      expect(interpreter.highlightFunction, 0);
      expect(interpreter.highlightSlot, 0); // back to the top of the loop
    });

    test('a crash keeps the highlight on the instruction that caused it, '
        'rather than advancing past it', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      program.setSlot(0, 0, const ProgramInstruction(ActionType.turnLeft));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
      final interpreter = RobotInterpreter(level: level, program: program);

      interpreter.step(); // turnLeft
      interpreter.step(); // forward off the edge -> crashed

      expect(interpreter.status, RunStatus.crashed);
      expect(interpreter.highlightFunction, 0);
      expect(interpreter.highlightSlot, 1); // the forward that crashed
    });
  });
}
