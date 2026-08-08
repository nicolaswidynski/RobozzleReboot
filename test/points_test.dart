import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/points.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/program.dart';

import 'test_level.dart';

Level _levelWithDifficulty(double difficulty, {String id = ''}) {
  final key = '$difficulty$id';
  return Level(
    id: 'diff-$key',
    name: 'diff-$key',
    grid: const [],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [0, 0, 0, 0, 0],
    difficulty: difficulty,
  );
}

void main() {
  test('pointsForDifficulty is difficulty^2', () {
    expect(pointsForDifficulty(_levelWithDifficulty(0)), 0);
    expect(pointsForDifficulty(_levelWithDifficulty(1)), 1);
    expect(pointsForDifficulty(_levelWithDifficulty(3)), 9);
    expect(pointsForDifficulty(_levelWithDifficulty(5)), 25);
  });

  test('pointsForDifficulty uses the precise decimal rating, not a '
      'rounded whole star', () {
    // 2.5^2 = 6.25 -- if this were rounded to 3 first, it'd be 9 instead.
    expect(pointsForDifficulty(_levelWithDifficulty(2.5)), 6.25);
  });

  test('totalPoints sums points only for completed levels', () {
    final level1 = testLevel(); // difficulty 1 -> 1 point
    final level2 = testLevel2(); // difficulty 1 -> 1 point
    final levels = [level1, level2];

    expect(totalPoints({}, levels), 0);
    expect(totalPoints({level1.id}, levels), 1);
    expect(totalPoints({level1.id, level2.id}, levels), 2);
  });

  test('totalPoints ignores completed ids not present in levels', () {
    final level = testLevel();
    expect(totalPoints({'unknown-id'}, [level]), 0);
  });

  test('totalPoints rounds only the final sum, not each puzzle', () {
    // 2.5^2 + 2.5^2 = 12.5 -> rounds to 13, not 6+6=12 or 6.25.round()*2=12.
    final levels = [
      _levelWithDifficulty(2.5, id: 'a'),
      _levelWithDifficulty(2.5, id: 'b'),
    ];
    final ids = levels.map((l) => l.id).toSet();
    expect(totalPoints(ids, levels), 13);
  });

  test('unusedSlots counts empty slots across every function, not just '
      'the one in use', () {
    final level = _levelWithDifficulty(1); // slotsPerFunction: [0,0,0,0,0]
    final program = RobotProgram.empty(level);
    expect(unusedSlots(program), 0); // no slots offered at all

    final program2 = RobotProgram.empty(testLevel()); // slots: [6,0,0,0,0]
    expect(unusedSlots(program2), 6); // nothing placed yet

    program2.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
    program2.setSlot(0, 1, const ProgramInstruction(ActionType.forward));
    expect(unusedSlots(program2), 4);
  });

  test('bonusPoints scales unused slots by difficulty, same shape as the '
      'base score', () {
    expect(bonusPoints(3, _levelWithDifficulty(1)), 3);
    expect(bonusPoints(3, _levelWithDifficulty(2)), 6);
    expect(bonusPoints(0, _levelWithDifficulty(5)), 0);
    // 3 * 2.5 = 7.5 -> rounds to 8.
    expect(bonusPoints(3, _levelWithDifficulty(2.5)), 8);
  });
}
