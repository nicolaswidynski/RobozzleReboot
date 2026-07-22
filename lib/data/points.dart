import '../models/level.dart';

/// Points earned for solving a puzzle of the given difficulty:
/// difficulty^2, so harder puzzles are worth quadratically more.
int pointsForDifficulty(int difficulty) {
  return difficulty * difficulty;
}

/// Total points across every level in [levels] whose id is in
/// [completedIds].
int totalPoints(Set<String> completedIds, List<Level> levels) {
  var total = 0;
  for (final level in levels) {
    if (completedIds.contains(level.id)) {
      total += pointsForDifficulty(level.difficulty);
    }
  }
  return total;
}
