import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider_type.dart';

/// Mirrors SecondStream's storage split: the account identity is not secret
/// and lives in plain prefs (like `UserDefaults`), while the rotating
/// session token lives in the Keychain (`flutter_secure_storage` on iOS).
///
/// Apple's and Google's user ids are stored in *separate* slots, each
/// keyed by provider — signing in with one doesn't overwrite the other, so
/// switching back and forth (Apple, then Google, then Apple again) doesn't
/// lose either id. [_authProviderKey] tracks only which one is currently
/// *active* (the one [readIdentity] returns and API calls use); the other
/// provider's id just sits there unused until it's signed into again.
class SecureSessionStore {
  SecureSessionStore._();
  static final SecureSessionStore instance = SecureSessionStore._();

  static const _authProviderKey = 'auth_provider';
  static const _appleUserIdKey = 'apple_user_id';
  static const _googleUserIdKey = 'google_user_id';
  static const _sessionTokenKey = 'robozzle_user_session_token';
  static const _applePseudonymSetKey = 'apple_pseudonym_set';
  static const _googlePseudonymSetKey = 'google_pseudonym_set';
  static const _applePseudonymKey = 'apple_pseudonym';
  static const _googlePseudonymKey = 'google_pseudonym';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String _userIdKeyFor(AuthProviderType provider) => switch (provider) {
        AuthProviderType.apple => _appleUserIdKey,
        AuthProviderType.google => _googleUserIdKey,
      };

  String _pseudonymSetKeyFor(AuthProviderType provider) => switch (provider) {
        AuthProviderType.apple => _applePseudonymSetKey,
        AuthProviderType.google => _googlePseudonymSetKey,
      };

  String _pseudonymKeyFor(AuthProviderType provider) => switch (provider) {
        AuthProviderType.apple => _applePseudonymKey,
        AuthProviderType.google => _googlePseudonymKey,
      };

  Future<AuthProviderType?> readActiveProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthProviderType.fromWireValue(prefs.getString(_authProviderKey));
  }

  /// [provider]'s own stored user id, independent of which provider is
  /// currently active — null if that provider has never been signed into
  /// on this device (or its id was cleared).
  Future<String?> readProviderUserId(AuthProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKeyFor(provider));
  }

  /// The active provider plus *its* stored user id, or null if either piece
  /// is missing — should only be null for a signed-out player, or one who
  /// somehow has an active-provider pointer but no id saved for it.
  Future<(AuthProviderType provider, String providerUserId)?>
      readIdentity() async {
    final provider = await readActiveProvider();
    if (provider == null) return null;
    final providerUserId = await readProviderUserId(provider);
    if (providerUserId == null) return null;
    return (provider, providerUserId);
  }

  /// Saves [providerUserId] into [provider]'s own slot (never touching the
  /// other provider's stored id) and marks [provider] as the active one.
  Future<void> saveIdentity(
      AuthProviderType provider, String providerUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKeyFor(provider), providerUserId);
    await prefs.setString(_authProviderKey, provider.wireValue);
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

  /// Whether [provider]'s account has a pseudonym set server-side — kept
  /// per provider, same reasoning as the user ids: Apple and Google are
  /// different accounts, each with their own pseudonym, so this can't be a
  /// single shared flag without one provider's state bleeding into the
  /// other's after switching.
  Future<bool> readPseudonymSet(AuthProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pseudonymSetKeyFor(provider)) ?? false;
  }

  Future<void> savePseudonymSet(AuthProviderType provider, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pseudonymSetKeyFor(provider), value);
  }

  /// [provider]'s chosen pseudonym text itself, cached locally purely for
  /// display (e.g. the landing screen badge) — the server remains the
  /// source of truth for whether a pseudonym exists at all
  /// ([readPseudonymSet]).
  Future<String?> readPseudonym(AuthProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pseudonymKeyFor(provider));
  }

  Future<void> savePseudonym(AuthProviderType provider, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pseudonymKeyFor(provider), value);
  }

  /// Wipes both providers' identity, pseudonym state, and the session —
  /// used on account deletion.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authProviderKey);
    await prefs.remove(_appleUserIdKey);
    await prefs.remove(_googleUserIdKey);
    await prefs.remove(_applePseudonymSetKey);
    await prefs.remove(_googlePseudonymSetKey);
    await prefs.remove(_applePseudonymKey);
    await prefs.remove(_googlePseudonymKey);
    await _secureStorage.delete(key: _sessionTokenKey);
  }
}
