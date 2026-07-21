import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the in-progress "New Puzzle" draft in the editor — grid,
/// start state, function slots, allowed colors, title, and suggested
/// difficulty — so navigating away without finishing (no "Test Solution"
/// success yet) doesn't lose the work. There's only ever one slot (unlike
/// [CustomPuzzleStore], which is keyed per already-accepted puzzle), since
/// a draft doesn't have a stable id until it's actually saved.
class EditorDraftStore {
  static const _key = 'editor_new_puzzle_draft';

  /// The draft JSON uses the same shape as the bundled catalog (see
  /// [Level.fromJson]), so it can be parsed with the exact same code.
  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
