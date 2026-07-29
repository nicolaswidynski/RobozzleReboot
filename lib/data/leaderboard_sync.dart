import 'package:shared_preferences/shared_preferences.dart';

import 'auth_manager.dart';
import 'leaderboard.dart';

/// Keeps a signed-in account's score and completed-puzzles list in sync
/// with `robozzle-leaderboard` at least once a day, independent of whether
/// the player ever opens the Leaderboard screen. This is also how a
/// reinstalled app (or a second device on the same account) recovers
/// puzzles solved elsewhere — see `fetchLeaderboard`'s completed-puzzles
/// merge in leaderboard.dart.
class LeaderboardSync {
  LeaderboardSync._();
  static final LeaderboardSync instance = LeaderboardSync._();

  static const Duration dailyInterval = Duration(hours: 24);
  static const _lastSyncedKey = 'leaderboard_last_synced_at';

  bool _syncing = false;

  /// Call on app launch (or any other convenient touchpoint) — silently
  /// does nothing if there's no signed-in account, a sync already ran
  /// within [dailyInterval], or one is already in flight. Returns whether
  /// a sync actually happened, so callers that show derived state (e.g. a
  /// points badge) know when to recompute it.
  Future<bool> syncIfDue() async {
    if (_syncing) return false;
    if (!AuthManager.instance.isConnected) return false;

    final prefs = await SharedPreferences.getInstance();
    final lastSyncedMillis = prefs.getInt(_lastSyncedKey);
    if (lastSyncedMillis != null) {
      final lastSynced = DateTime.fromMillisecondsSinceEpoch(lastSyncedMillis);
      if (DateTime.now().difference(lastSynced) < dailyInterval) return false;
    }

    _syncing = true;
    try {
      await fetchLeaderboard();
      await prefs.setInt(_lastSyncedKey, DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (_) {
      // Offline or server error — leave the timestamp alone so the next
      // touchpoint (or the daily interval elapsing) tries again.
      return false;
    } finally {
      _syncing = false;
    }
  }
}
