import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/tutorial_levels.dart';
import 'package:robozzle_reboot/engine/interpreter.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/program.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

RobotProgram _programFor(
  int levelIndex,
  List<ProgramInstruction?> f1Slots,
) {
  final program = RobotProgram.empty(tutorialLevels[levelIndex]);
  for (var i = 0; i < f1Slots.length; i++) {
    program.setSlot(0, i, f1Slots[i]);
  }
  return program;
}

void main() {
  test('tutorial 1 is solvable with only forward/turnLeft/turnRight', () {
    final program = _programFor(0, const [
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.turnRight),
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.turnLeft),
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.forward),
    ]);
    final interpreter =
        RobotInterpreter(level: tutorialLevels[0], program: program);
    expect(interpreter.runToCompletion(), RunStatus.success);
  });

  test('tutorial 2 is solvable with a 2-slot self-calling loop', () {
    final program = _programFor(1, const [
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.callF1),
    ]);
    final interpreter =
        RobotInterpreter(level: tutorialLevels[1], program: program);
    expect(interpreter.runToCompletion(), RunStatus.success);
  });

  test('tutorial 3 is solvable with a conditioned turn + paint inside the '
      'loop', () {
    final program = _programFor(2, const [
      ProgramInstruction(ActionType.turnRight, condition: TileColor.red),
      ProgramInstruction(ActionType.paintGreen, condition: TileColor.red),
      ProgramInstruction(ActionType.forward),
      ProgramInstruction(ActionType.callF1),
    ]);
    final interpreter =
        RobotInterpreter(level: tutorialLevels[2], program: program);
    expect(interpreter.runToCompletion(), RunStatus.success);
  });

  test('every tutorial has at least one star and a valid start tile', () {
    for (final level in tutorialLevels) {
      expect(level.totalStars, greaterThan(0), reason: level.id);
      expect(level.tileAt(level.startRow, level.startCol), isNotNull,
          reason: level.id);
    }
  });
}
