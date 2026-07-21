import 'package:shared_preferences/shared_preferences.dart';

/// Persists which puzzles the player has already been offered a rate/like
/// prompt for (regardless of whether they actually picked anything), so the
/// prompt only ever shows once per puzzle — mirrors [ProgressStore].
class PuzzleRatingStore {
  static const _key = 'rated_puzzle_ids';

  Future<Set<String>> loadRated() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<void> markRated(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet()..add(levelId);
    await prefs.setStringList(_key, ids.toList());
  }
}
