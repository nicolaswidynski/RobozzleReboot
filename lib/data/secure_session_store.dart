import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors SecondStream's storage split: the Apple user id is not secret and
/// lives in plain prefs (like `UserDefaults`), while the rotating session
/// token lives in the Keychain (`flutter_secure_storage` on iOS).
class SecureSessionStore {
  SecureSessionStore._();
  static final SecureSessionStore instance = SecureSessionStore._();

  static const _appleUserIdKey = 'apple_user_id';
  static const _sessionTokenKey = 'robozzle_user_session_token';
  static const _pseudonymSetKey = 'robozzle_pseudonym_set';
  static const _pseudonymKey = 'robozzle_pseudonym';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<String?> readAppleUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appleUserIdKey);
  }

  Future<void> saveAppleUserId(String appleUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appleUserIdKey, appleUserId);
  }

  Future<String?> readSessionToken() {
    return _secureStorage.read(key: _sessionTokenKey);
  }

  Future<void> saveSessionToken(String token) {
    return _secureStorage.write(key: _sessionTokenKey, value: token);
  }

  Future<void> clearSessionToken() {
    return _secureStorage.delete(key: _sessionTokenKey);
  }

  Future<bool> readPseudonymSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pseudonymSetKey) ?? false;
  }

  Future<void> savePseudonymSet(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pseudonymSetKey, value);
  }

  /// The chosen pseudonym text itself, cached locally purely for display
  /// (e.g. the landing screen badge) — the server remains the source of
  /// truth for whether a pseudonym exists at all ([readPseudonymSet]).
  Future<String?> readPseudonym() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pseudonymKey);
  }

  Future<void> savePseudonym(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pseudonymKey, value);
  }

  /// Wipes both identity and session — used on account deletion.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_appleUserIdKey);
    await prefs.remove(_pseudonymSetKey);
    await prefs.remove(_pseudonymKey);
    await _secureStorage.delete(key: _sessionTokenKey);
  }
}
