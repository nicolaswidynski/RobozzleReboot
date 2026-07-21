import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A puzzle's playable content (grid + start state), independent of its
/// listing metadata (title/author/difficulty/popularity).
class PuzzleContent {
  final int startRow;
  final int startCol;
  final String startDirection;
  final int allowedCommands;
  final List<int> slotsPerFunction;
  final List<String> rows;

  PuzzleContent({
    required this.startRow,
    required this.startCol,
    required this.startDirection,
    required this.allowedCommands,
    required this.slotsPerFunction,
    required this.rows,
  });

  Map<String, dynamic> toJson() => {
        'startRow': startRow,
        'startCol': startCol,
        'startDirection': startDirection,
        'allowedCommands': allowedCommands,
        'slotsPerFunction': slotsPerFunction,
        'rows': rows,
      };
}

/// Caches fetched [PuzzleContent] locally (keyed by [Level.id]) so a puzzle
/// only needs to be fetched from `robozzle-get-puzzle` once, and stays
/// playable offline afterwards.
class PuzzleContentStore {
  static const _keyPrefix = 'puzzle_content_';

  Future<PuzzleContent?> load(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$levelId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PuzzleContent(
        startRow: json['startRow'] as int,
        startCol: json['startCol'] as int,
        startDirection: json['startDirection'] as String,
        allowedCommands: json['allowedCommands'] as int,
        slotsPerFunction: (json['slotsPerFunction'] as List).cast<int>(),
        rows: (json['rows'] as List).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String levelId, PuzzleContent content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$levelId', jsonEncode(content.toJson()));
  }
}
