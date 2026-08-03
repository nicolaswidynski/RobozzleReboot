import '../models/level.dart';

/// Points earned for solving a puzzle: its difficulty rating squared, so
/// harder puzzles are worth quadratically more. Uses the precise decimal
/// [Level.difficulty] as-is rather than rounding it to a whole star first,
/// so two puzzles that both display as "3 stars" but rate 2.6 and 3.4
/// aren't scored identically.
double pointsForDifficulty(Level level) => level.difficulty * level.difficulty;

/// Total points across every level in [levels] whose id is in
/// [completedIds]. Summed as the precise per-puzzle value and rounded only
/// once, at the end, rather than per puzzle — so rounding a handful of
/// puzzles' contributions up or down doesn't compound across a large
/// completed set the way rounding each one individually would.
int totalPoints(Set<String> completedIds, List<Level> levels) {
  var total = 0.0;
  for (final level in levels) {
    if (completedIds.contains(level.id)) {
      total += pointsForDifficulty(level);
    }
  }
  return total.round();
}
