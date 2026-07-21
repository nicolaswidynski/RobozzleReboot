import 'dart:convert';

import '../models/level.dart';
import 'puzzle_content_store.dart';
import 'robozzle_api_client.dart';

class PuzzleContentError implements Exception {
  final String message;
  PuzzleContentError(this.message);

  @override
  String toString() => message;
}

/// Parses a `robozzle-get-puzzle` response into [PuzzleContent]. Several
/// fields come back as strings even though they're numeric/structured
/// (`"startRow": "6"`, `"slotsPerFunction": "[4, 3, 5, 0, 0]"` — a
/// JSON-encoded string, not an actual array) — normalized here.
PuzzleContent parsePuzzleContent(Map<String, dynamic> json) {
  final rowsRaw = json['rows'];
  if (rowsRaw is! List) {
    throw PuzzleContentError('Puzzle response is missing rows.');
  }

  final slotsRaw = json['slotsPerFunction'];
  final slotsList = slotsRaw is String
      ? jsonDecode(slotsRaw) as List
      : slotsRaw as List;

  return PuzzleContent(
    startRow: int.parse('${json['startRow']}'),
    startCol: int.parse('${json['startCol']}'),
    startDirection: json['startDirection'] as String,
    allowedCommands: int.parse('${json['allowedCommands']}'),
    slotsPerFunction: slotsList.map((e) => int.parse('$e')).toList(),
    rows: rowsRaw.cast<String>(),
  );
}

/// Combines a [placeholder] level's listing metadata (title/author/
/// difficulty/popularity, already known from `robozzle-list-puzzles`) with
/// its fetched [content] into a fully playable [Level].
Level buildLevelWithContent(Level placeholder, PuzzleContent content) {
  return Level.fromJson({
    'sourceId': placeholder.id.replaceFirst('catalog-', ''),
    'title': placeholder.name,
    'author': placeholder.author,
    'difficulty': placeholder.difficulty,
    'popularity': placeholder.popularity,
    'startRow': content.startRow,
    'startCol': content.startCol,
    'startDirection': content.startDirection,
    'allowedCommands': content.allowedCommands,
    'slotsPerFunction': content.slotsPerFunction,
    'rows': content.rows,
  });
}

/// Returns [level] unchanged if its playable content is already known
/// (non-empty grid — true for every bundled puzzle). Otherwise loads it from
/// the local cache, or fetches it from `robozzle-get-puzzle` and caches it.
Future<Level> ensurePuzzleContent(Level level) async {
  if (level.grid.isNotEmpty) return level;

  final store = PuzzleContentStore();
  final cached = await store.load(level.id);
  if (cached != null) return buildLevelWithContent(level, cached);

  final sourceId = level.id.replaceFirst('catalog-', '');
  final (json, statusCode) =
      await RobozzleApiClient.instance.fetchPuzzle(sourceId);
  if (statusCode < 200 || statusCode > 299 || json == null) {
    throw PuzzleContentError(
      json?['message'] as String? ?? 'Could not load puzzle ($statusCode).',
    );
  }

  final content = parsePuzzleContent(json);
  await store.save(level.id, content);
  return buildLevelWithContent(level, content);
}
