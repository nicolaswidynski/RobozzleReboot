import 'package:shared_preferences/shared_preferences.dart';

/// Persists which levels the player has solved (all stars collected, robot
/// reached the end), keyed by [Level.id], across app runs.
class ProgressStore {
  static const _key = 'completed_level_ids';

  Future<Set<String>> loadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<void> markCompleted(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet()..add(levelId);
    await prefs.setStringList(_key, ids.toList());
  }
}
