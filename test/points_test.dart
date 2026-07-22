import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/points.dart';

import 'test_level.dart';

void main() {
  test('pointsForDifficulty is difficulty^2', () {
    expect(pointsForDifficulty(0), 0);
    expect(pointsForDifficulty(1), 1);
    expect(pointsForDifficulty(3), 9);
    expect(pointsForDifficulty(5), 25);
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
}
