import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/level.dart';

/// Persists puzzles made in the in-app editor, locally on-device (no server
/// submission — see the editor screens). Reuses the same JSON shape as the
/// bundled catalog (see assets/levels_catalog.json / [Level.fromJson]) so a
/// saved custom puzzle loads through the exact same code path as any other
/// level, and so the player's solving program is automatically persisted
/// and restored by the existing `ProgramStore` (keyed by [Level.id]) with
/// no special-casing needed.
class CustomPuzzleStore {
  static const _key = 'custom_puzzles';
  static const Uuid _uuid = Uuid();

  /// A fresh id for a new custom puzzle, prefixed distinctly from the
  /// scraped catalog's `catalog-` ids and the hand-authored `tutorial-`
  /// ones so they can never collide.
  static String newId() => 'custom-${_uuid.v4()}';

  Future<List<Level>> loadAll() async {
    final entries = await _loadEntries();
    return entries
        .map((e) => Level.fromJson(e, idPrefix: 'custom'))
        .toList();
  }

  /// Saves [level] as a custom puzzle, keyed by [Level.id] — overwrites any
  /// existing entry with the same id (re-saving an edited puzzle). Preserves
  /// the published flag across a re-save, since publishing is a one-way,
  /// server-side action independent of further local edits.
  Future<void> save(Level level) async {
    final entries = await _loadEntries();
    final sourceId = _sourceId(level.id);
    final wasPublished =
        entries.any((e) => e['sourceId'] == sourceId && e['published'] == true);
    entries.removeWhere((e) => e['sourceId'] == sourceId);
    final json = _toJson(level);
    if (wasPublished) json['published'] = true;
    entries.add(json);
    await _saveEntries(entries);
  }

  Future<void> delete(String levelId) async {
    final entries = await _loadEntries();
    entries.removeWhere((e) => e['sourceId'] == _sourceId(levelId));
    await _saveEntries(entries);
  }

  /// Marks [levelId] as published — irreversible, so this is only ever set,
  /// never cleared.
  Future<void> markPublished(String levelId) async {
    final entries = await _loadEntries();
    final sourceId = _sourceId(levelId);
    for (final e in entries) {
      if (e['sourceId'] == sourceId) e['published'] = true;
    }
    await _saveEntries(entries);
  }

  Future<Set<String>> loadPublishedIds() async {
    final entries = await _loadEntries();
    return {
      for (final e in entries)
        if (e['published'] == true) 'custom-${e['sourceId']}',
    };
  }

  String _sourceId(String levelId) => levelId.replaceFirst('custom-', '');

  Future<List<Map<String, dynamic>>> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveEntries(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(entries));
  }

  Map<String, dynamic> _toJson(Level level) {
    return {
      // Level.fromJson always builds the id as "custom-$sourceId" (see
      // idPrefixFor below) — sourceId itself just needs to be unique.
      'sourceId': _sourceId(level.id),
      'title': level.name,
      'author': level.author,
      'difficulty': level.difficulty,
      'popularity': level.popularity,
      'startRow': level.startRow,
      'startCol': level.startCol,
      'startDirection': level.startDirection.name,
      'allowedCommands': level.allowedCommandsBitmask,
      'slotsPerFunction': level.slotsPerFunction,
      'rows': level.rowStrings,
    };
  }
}
