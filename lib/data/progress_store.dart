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
  static const _parKey = 'par_by_level_id';

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

  /// The best-ever [unusedSlots] (see points.dart) recorded per level id —
  /// see [recordPar]. Empty until a puzzle's first completion after this
  /// feature shipped; a puzzle solved before then (or recovered from
  /// another device via the server's completed-puzzles superset) simply
  /// has no entry.
  Future<Map<String, int>> loadPar() async {
    final raw = await _storage.read(key: _parKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, value as int));
  }

  /// Records [unusedSlots] as [levelId]'s best-ever value if it beats
  /// whatever's already stored (or nothing is yet) — a less efficient
  /// replay never erases a previous better solve. This is what's reported
  /// to the leaderboard as `par` (see `parForCatalogPuzzles` in
  /// leaderboard.dart), so it needs to persist across sessions the same
  /// way completion itself does.
  Future<void> recordPar(String levelId, int unusedSlots) async {
    final map = await loadPar();
    final existing = map[levelId];
    if (existing != null && existing >= unusedSlots) return;
    map[levelId] = unusedSlots;
    await _storage.write(key: _parKey, value: jsonEncode(map));
  }
}
