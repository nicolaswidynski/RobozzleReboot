import 'package:shared_preferences/shared_preferences.dart';

/// Decides when to show the "rate the game" prompt: first once the player
/// has solved [minCompletedForFirstPrompt] puzzles, then at most once every
/// [reminderInterval] after that — unless they've already rated, in which
/// case never again.
class RatingPromptStore {
  static const _lastShownKey = 'rating_prompt_last_shown_at';
  static const _ratedKey = 'rating_prompt_rated';

  static const int minCompletedForFirstPrompt = 5;
  static const Duration reminderInterval = Duration(days: 30);

  Future<bool> shouldShow(int completedCount) async {
    if (completedCount < minCompletedForFirstPrompt) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_ratedKey) ?? false) return false;
    final lastShownMillis = prefs.getInt(_lastShownKey);
    if (lastShownMillis == null) return true;
    final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMillis);
    return DateTime.now().difference(lastShown) >= reminderInterval;
  }

  Future<void> recordShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> recordRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ratedKey, true);
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
  }
}
