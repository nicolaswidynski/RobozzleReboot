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

/// Computes the player's current score, posts it to `robozzle-leaderboard`,
/// and parses the response into the player's rank plus the full sorted
/// leaderboard.
Future<LeaderboardResult> fetchLeaderboard() async {
  final completedIds = await ProgressStore().loadCompleted();
  final levels = await loadCatalogLevels();
  final score = totalPoints(completedIds, levels);

  final (json, statusCode) =
      await RobozzleApiClient.instance.postScore(score);
  if (statusCode < 200 || statusCode > 299) {
    throw LeaderboardError(
      json?['message'] as String? ?? 'Unknown error ($statusCode)',
    );
  }
  if (json == null) {
    throw LeaderboardError('No response from server.');
  }

  return parseLeaderboardResult(json);
}

/// Parses a `robozzle-leaderboard` response body into [LeaderboardResult].
LeaderboardResult parseLeaderboardResult(Map<String, dynamic> json) {
  final userRank = int.tryParse('${json['user_rank']}') ?? -1;
  final entries = _parseEntries(json['leaderboard']);
  return LeaderboardResult(userRank: userRank, entries: entries);
}

/// n8n wraps the sorted list as `leaderboard: [{"json": {"sorted": [...]}}]`
/// (the raw output of the workflow node) instead of a plain array.
List<LeaderboardEntry> _parseEntries(dynamic leaderboardRaw) {
  if (leaderboardRaw is! List || leaderboardRaw.isEmpty) return const [];

  final first = leaderboardRaw.first;
  final wrapped = first is Map ? first['json'] : null;
  final sorted = wrapped is Map ? wrapped['sorted'] : null;
  if (sorted is! List) return const [];

  final entries = <LeaderboardEntry>[];
  // The server assigns each entry its own sequential rank rather than
  // giving tied scores the same one — when an entry's score matches the
  // one right before it (the list is already sorted descending by score),
  // reuse that entry's rank instead of trusting the server's for this one,
  // so a tie always displays the same rank.
  int? previousScore;
  int? previousRank;
  for (final e in sorted) {
    if (e is! Map) continue;
    final score = int.tryParse('${e['Score']}') ?? 0;
    final rank = (previousScore != null && score == previousScore)
        ? previousRank!
        : (int.tryParse('${e['rank']}') ?? 0);
    entries.add(LeaderboardEntry(
      rank: rank,
      pseudonym: '${e['Pseudo'] ?? ''}',
      score: score,
    ));
    previousScore = score;
    previousRank = rank;
  }
  return entries;
}
