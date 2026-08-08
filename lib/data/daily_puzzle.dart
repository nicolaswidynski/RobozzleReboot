import '../models/direction.dart';
import '../models/level.dart';
import 'level_catalog.dart';
import 'puzzle_content.dart';
import 'robozzle_api_client.dart';

class DailyPuzzleError implements Exception {
  final String message;
  DailyPuzzleError(this.message);

  @override
  String toString() => message;
}

/// Extracts the source id of today's featured puzzle from a `daily-puzzle`
/// response (`{"daily_puzzle": <id>}` — the id may come back as a number or
/// a numeric string depending on how the n8n workflow serializes it). Null
/// if the field is missing or isn't a number.
int? parseDailyPuzzleSourceId(Map<String, dynamic> json) =>
    int.tryParse('${json['daily_puzzle']}');

/// Fetches today's featured puzzle id from `daily-puzzle` and resolves it
/// to a fully playable [Level] — from the bundled/server-listed catalog if
/// it's there (see [loadCatalogLevels]), fetching its content directly via
/// `robozzle-get-puzzle` otherwise (see [ensurePuzzleContent]), same as
/// opening any other puzzle by raw id. Every player is handed the same
/// puzzle on a given day; solving it goes through the exact same
/// interpreter/points/leaderboard machinery as any other puzzle.
Future<Level> fetchDailyPuzzleLevel() async {
  final (json, statusCode) = await RobozzleApiClient.instance.fetchDailyPuzzle();
  if (statusCode < 200 || statusCode > 299 || json == null) {
    throw DailyPuzzleError(
      json?['message'] as String? ??
          'Could not load the daily puzzle ($statusCode).',
    );
  }

  final sourceId = parseDailyPuzzleSourceId(json);
  if (sourceId == null) {
    throw DailyPuzzleError('Daily puzzle response is missing an id.');
  }
  final levelId = 'catalog-$sourceId';

  final levels = await loadCatalogLevels();
  for (final level in levels) {
    if (level.id == levelId) return ensurePuzzleContent(level);
  }

  // Not listed by the server/bundled catalog at all — fetch it directly,
  // same as opening any puzzle the catalog only has a placeholder for.
  return ensurePuzzleContent(Level(
    id: levelId,
    name: 'Daily Puzzle',
    grid: const [],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [0, 0, 0, 0, 0],
  ));
}
