import 'package:shared_preferences/shared_preferences.dart';

/// Decides when to show the "rate the game" prompt: exactly once, on the
/// [promptOnLaunch]th app launch — never again afterwards, whatever the
/// player answered (or whether they answered at all).
class RatingPromptStore {
  static const _launchCountKey = 'rating_prompt_launch_count';
  static const _shownKey = 'rating_prompt_shown';

  // Written by the earlier scheme (5 solved puzzles, then a reminder every
  // 30 days). Either being present means the player has already been asked
  // once, so honoring them keeps existing installs from getting a second
  // "first" prompt under the new rule.
  static const _legacyLastShownKey = 'rating_prompt_last_shown_at';
  static const _legacyRatedKey = 'rating_prompt_rated';

  static const int promptOnLaunch = 3;

  /// Counts one more app launch. Call exactly once per process start.
  Future<void> recordLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_launchCountKey) ?? 0;
    await prefs.setInt(_launchCountKey, count + 1);
  }

  /// True from the [promptOnLaunch]th launch onward until the prompt has
  /// been shown once (`>=`, not `==`, so a launch where it couldn't be
  /// shown for some reason still gets it next time).
  Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_shownKey) ?? false) return false;
    if (prefs.containsKey(_legacyLastShownKey)) return false;
    if (prefs.getBool(_legacyRatedKey) ?? false) return false;
    return (prefs.getInt(_launchCountKey) ?? 0) >= promptOnLaunch;
  }

  /// Marks the prompt as asked. Recorded when it's put on screen rather
  /// than when a button is tapped, so dismissing it (or force-quitting the
  /// app with it open) still counts as the one ask.
  Future<void> recordShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
  }
}
