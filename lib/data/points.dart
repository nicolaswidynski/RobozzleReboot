import '../models/level.dart';
import '../models/program.dart';

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

/// How many of a solved program's instruction slots were left empty —
/// summed across every function the level offers, not just whichever one
/// happens to be showing. The raw ingredient for [bonusPoints] and for the
/// `par` value reported to the leaderboard (see `parForCatalogPuzzles` in
/// leaderboard.dart) — Robozzle's actual axis of skill, the tightest
/// program rather than just *a* program, turned into a number.
int unusedSlots(RobotProgram program) {
  var unused = 0;
  for (final fn in program.functions) {
    unused += fn.slots.where((slot) => slot == null).length;
  }
  return unused;
}

/// The "+X bonus points" shown alongside the base [pointsForDifficulty]
/// score when a puzzle is solved with slots to spare — unused slots scaled
/// by difficulty, same shape as the base score, so leftover slots on a
/// harder puzzle are worth more than on an easy one.
int bonusPoints(int unusedSlotCount, Level level) =>
    (unusedSlotCount * level.difficulty).round();
