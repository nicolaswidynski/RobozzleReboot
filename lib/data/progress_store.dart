import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists which levels the player has solved (all stars collected, robot
/// reached the end), keyed by [Level.id], across app runs — and, being
/// Keychain-backed rather than plain prefs, typically across an app
/// deletion/reinstall on the same device too (unlike `SharedPreferences`,
/// which iOS always wipes on uninstall).
class ProgressStore {
  static const _key = 'completed_level_ids';

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
}
