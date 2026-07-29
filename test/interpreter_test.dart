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

  group('callStack (drives the control bar\'s live status display)', () {
    test(
        'a self-recursive tail call replaces the frame instead of growing '
        'the stack', () {
      final level = _straightLine();
      final program = RobotProgram.empty(level);
      // F1: forward, then call F1 as the very last slot — the classic
      // "loop forever" pattern. Nothing follows the call, so there's no
      // caller state left to return to.
      program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
      program.setSlot(0, 1, const ProgramInstruction(ActionType.callF1));

      final interpreter = RobotInterpreter(level: level, program: program);
      expect(interpreter.callStack, [0]);

      interpreter.step(); // forward
      expect(interpreter.callStack, [0]);

      interpreter.step(); // call F1 — tail call: frame replaced, not pushed
      expect(interpreter.callStack, [0]);

      interpreter.step(); // forward again, inside the "new" F1 frame
      expect(interpreter.callStack, [0]);

      interpreter.step(); // call F1 again — still just the one frame
      expect(interpreter.callStack, [0]);
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
      expect(interpreter.callStack, [0, 1]);

      interpreter.step(); // F2's forward — F2 still hasn't returned
      expect(interpreter.callStack, [0, 1]);

      interpreter.step(); // F2 runs out and returns; F1's forward then runs
      expect(interpreter.callStack, [0]);
    });
  });
}
