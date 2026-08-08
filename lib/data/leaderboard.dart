import 'dart:convert';

import 'catalog_refresher.dart';
import 'level_catalog.dart';
import 'points.dart';
import 'progress_store.dart';
import 'robozzle_api_client.dart';

class LeaderboardEntry {
  final int rank;
  final String pseudonym;
  final int score;

  LeaderboardEntry({
    required this.rank,
    required this.pseudonym,
    required this.score,
  });
}

class LeaderboardResult {
  final int userRank;
  final List<LeaderboardEntry> entries;

  LeaderboardResult({required this.userRank, required this.entries});
}

class LeaderboardError implements Exception {
  final String message;
  LeaderboardError(this.message);

  @override
  String toString() => message;
}

/// Computes the player's current score, posts it (plus the bare catalog
/// numbers of every completed puzzle) to `robozzle-leaderboard`, merges
/// the server's completed-puzzles superset back into local storage (see
/// [parseCompletedPuzzleIds] — this is how a reinstall/new device recovers
/// puzzles solved elsewhere on the same account) and caches its `score` as
/// the account's authoritative one (see [ProgressStore.saveServerScore]),
/// and parses the response into the player's rank plus the full sorted
/// leaderboard.
Future<LeaderboardResult> fetchLeaderboard() async {
  final completedIds = await ProgressStore().loadCompleted();
  final levels = await loadCatalogLevels();
  final score = totalPoints(completedIds, levels);

  final puzzleNumbers = catalogPuzzleNumbers(completedIds);
  final parByLevelId = await ProgressStore().loadPar();

  final (json, statusCode) = await RobozzleApiClient.instance.postScore(
    score,
    completedPuzzleIds: puzzleNumbers,
    par: parForCatalogPuzzles(puzzleNumbers, parByLevelId),
  );
  if (statusCode < 200 || statusCode > 299) {
    throw LeaderboardError(
      json?['message'] as String? ?? 'Unknown error ($statusCode)',
    );
  }
  if (json == null) {
    throw LeaderboardError('No response from server.');
  }

  // The server's completed-puzzles field is every catalog puzzle this
  // account has ever solved, on any device — a superset of what's stored
  // locally, not just what this install already knows about. Merging it
  // in (rather than replacing local state) is how a reinstall/new device
  // recovers puzzles solved elsewhere on the same account.
  final recovered = parseCompletedPuzzleIds(json['completed_puzzles']);
  if (recovered.isNotEmpty) {
    await ProgressStore().markAllCompleted(recovered);
  }

  // The server is the authority on the account's score — cache it
  // unconditionally, even if it disagrees with what the locally completed
  // set adds up to.
  final serverScore = int.tryParse('${json['score']}');
  if (serverScore != null) {
    await ProgressStore().saveServerScore(serverScore);
  }

  // The server computes its score from puzzle difficulty that can have
  // moved on since this device's own catalog metadata was last refreshed
  // (itself on its own, independent up-to-daily schedule) — e.g. a newly
  // completed puzzle this device has never fetched metadata for at all,
  // or one whose average rating crossed a rounding boundary. Refreshing
  // right after a leaderboard sync keeps the two in step, instead of
  // leaving a locally-recomputed score to disagree with the server's
  // until whatever the catalog's own refresh schedule happens to be.
  await CatalogRefresher.instance.refreshNow();

  return parseLeaderboardResult(json);
}

/// The bare catalog numbers (e.g. `234` for `catalog-234`) of every
/// completed id that's actually a catalog puzzle — tutorials and anything
/// else non-numeric aren't part of this account-wide sync.
List<int> catalogPuzzleNumbers(Set<String> completedIds) {
  const prefix = 'catalog-';
  final numbers = <int>[];
  for (final id in completedIds) {
    if (!id.startsWith(prefix)) continue;
    final n = int.tryParse(id.substring(prefix.length));
    if (n != null) numbers.add(n);
  }
  return numbers;
}

/// The best-ever unused-slot count (see [ProgressStore.recordPar]) for
/// each puzzle in [puzzleNumbers], in the same order, sent to the server
/// as `par` alongside `completed_puzzles`. Negated to match golf-style
/// scoring: a puzzle solved with slots to spare comes out negative
/// ("under par"), one solved using every slot is exactly `0`, and so is
/// any puzzle this device has no locally recorded value for (completed
/// before this feature shipped, or only known here via the server's
/// completed-puzzles superset).
List<int> parForCatalogPuzzles(
  List<int> puzzleNumbers,
  Map<String, int> parByLevelId,
) {
  return [
    for (final n in puzzleNumbers) -(parByLevelId['catalog-$n'] ?? 0),
  ];
}

/// Parses `completed_puzzles` (a JSON-encoded array of bare catalog
/// numbers, e.g. `"[1,234,54]"` — or an already-decoded list) into the
/// level ids it represents. Malformed or missing input just yields an
/// empty set rather than throwing, since this is best-effort recovery.
Set<String> parseCompletedPuzzleIds(dynamic raw) {
  if (raw == null) return {};
  dynamic decoded;
  try {
    decoded = raw is String ? jsonDecode(raw) : raw;
  } catch (_) {
    return {};
  }
  if (decoded is! List) return {};

  return {
    for (final n in decoded)
      if (int.tryParse('$n') case final number?) 'catalog-$number',
  };
}

/// Parses a `robozzle-leaderboard` response body into [LeaderboardResult].
LeaderboardResult parseLeaderboardResult(Map<String, dynamic> json) {
  final userRank = int.tryParse('${json['user_rank']}') ?? -1;
  final entries = _parseEntries(json['leaderboard']);
  return LeaderboardResult(userRank: userRank, entries: entries);
}

/// `leaderboard` is a flat array of entries directly. Older responses (and
/// possibly still some n8n workflow paths) instead wrap it as
/// `[{"json": {"sorted": [...]}}]` — the raw output of an n8n node — so
/// both shapes are accepted. Ranks are trusted as-is either way — the
/// server assigns each entry its own rank and whether tied scores share
/// one is entirely up to it, not something this parses around.
List<LeaderboardEntry> _parseEntries(dynamic leaderboardRaw) {
  if (leaderboardRaw is! List || leaderboardRaw.isEmpty) return const [];

  final first = leaderboardRaw.first;
  final List<dynamic> sorted;
  if (first is Map && first['json'] != null) {
    final wrapped = first['json'];
    final maybeSorted = wrapped is Map ? wrapped['sorted'] : null;
    if (maybeSorted is! List) return const [];
    sorted = maybeSorted;
  } else {
    sorted = leaderboardRaw;
  }

  final entries = <LeaderboardEntry>[];
  for (final e in sorted) {
    if (e is! Map) continue;
    entries.add(LeaderboardEntry(
      rank: int.tryParse('${e['rank']}') ?? 0,
      pseudonym: '${e['Pseudo'] ?? ''}',
      score: int.tryParse('${e['Score']}') ?? 0,
    ));
  }
  return entries;
}
