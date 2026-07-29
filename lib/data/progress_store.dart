import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists which levels the player has solved (all stars collected, robot
/// reached the end), keyed by [Level.id], across app runs — and, being
/// Keychain-backed rather than plain prefs, typically across an app
/// deletion/reinstall on the same device too (unlike `SharedPreferences`,
/// which iOS always wipes on uninstall).
class ProgressStore {
  static const _key = 'completed_level_ids';
  static const _serverScoreKey = 'server_score';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Set<String>> loadCompleted() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<void> markCompleted(String levelId) async {
    final ids = await loadCompleted()
      ..add(levelId);
    await _storage.write(key: _key, value: jsonEncode(ids.toList()));
  }

  /// Merges [levelIds] into the completed set in one read-modify-write,
  /// rather than one round-trip per id — used to apply the server's
  /// completed-puzzles superset (see `fetchLeaderboard`), which recovers
  /// progress from other devices/a reinstall in one shot.
  Future<void> markAllCompleted(Iterable<String> levelIds) async {
    final ids = await loadCompleted()
      ..addAll(levelIds);
    await _storage.write(key: _key, value: jsonEncode(ids.toList()));
  }

  /// The account's score as last reported by `robozzle-leaderboard` — the
  /// server is the authority on this once an account is synced even once,
  /// so callers that display "the player's score" (e.g. the landing
  /// screen's points badge) should prefer this over recomputing locally
  /// from [loadCompleted] when it's available. Null until the first sync.
  Future<int?> loadServerScore() async {
    final raw = await _storage.read(key: _serverScoreKey);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Overwrites the cached server score unconditionally — the server's
  /// number always wins, even if it disagrees with what [loadCompleted]
  /// would locally add up to.
  Future<void> saveServerScore(int score) async {
    await _storage.write(key: _serverScoreKey, value: '$score');
  }
}
