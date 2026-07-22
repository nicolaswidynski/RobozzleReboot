import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import 'leaderboard.dart';
import 'level_catalog.dart';
import 'points.dart';
import 'progress_store.dart';
import 'robozzle_api_client.dart';
import 'secure_session_store.dart';

/// Mirrors SecondStream's `AuthManager`: owns Apple identity + session state,
/// drives the `manage-robozzle-user` webhook (creation / reconnection /
/// deletion / pseudonym), and decides when a fresh Apple Sign In UI is
/// needed versus a silent reconnect.
enum ManageUserOutcome { existingUser, newUser, reconnected }

/// `manage-robozzle-user` status codes: 200 = reconnection (pseudonym
/// already set), 201 = existing user (pseudonym already set), 202 = brand
/// new user (no pseudonym yet — the only case that needs the prompt).
ManageUserOutcome outcomeForManageUserStatus(int statusCode) {
  switch (statusCode) {
    case 200:
      return ManageUserOutcome.reconnected;
    case 201:
      return ManageUserOutcome.existingUser;
    case 202:
      return ManageUserOutcome.newUser;
    default:
      return ManageUserOutcome.reconnected;
  }
}

class AuthError implements Exception {
  final String message;
  AuthError(this.message);

  @override
  String toString() => message;
}

class UserNotFoundError extends AuthError {
  UserNotFoundError()
      : super('No account found on the server for this Apple ID.');
}

class PseudonymTakenError extends AuthError {
  PseudonymTakenError() : super('That pseudonym is already taken.');
}

class ServerError extends AuthError {
  final int statusCode;
  ServerError(this.statusCode, super.message);
}

class AuthManager extends ChangeNotifier {
  AuthManager._();
  static final AuthManager instance = AuthManager._();

  final SecureSessionStore _store = SecureSessionStore.instance;
  final RobozzleApiClient _api = RobozzleApiClient.instance;
  static const Uuid _uuid = Uuid();

  String? _appleUserId;
  bool _isExplicitlyDisconnected = false;
  bool _pseudonymSet = false;
  String? _pseudonym;
  bool _identityLoaded = false;

  /// The exact fields sent on the most recent creation/reconnection call
  /// (apple_user_id, operation, and — when present — email/name info).
  /// Kept so [setPseudonym] can resend the same information plus a
  /// `pseudonym` field, rather than sending a bare minimal request.
  Map<String, dynamic>? _lastManageUserFields;

  bool get isRegistered => _appleUserId != null;
  bool get isConnected => isRegistered && !_isExplicitlyDisconnected;
  bool get needsPseudonym => isConnected && !_pseudonymSet;
  String? get appleUserId => _appleUserId;

  /// The player's chosen pseudonym, when we actually have it cached locally
  /// — e.g. for display on the landing screen. May be `null` even when
  /// [needsPseudonym] is `false`, if the server already had one set before
  /// this device ever learned its text (see [_applyPseudonymOutcome]).
  String? get pseudonym => _pseudonym;

  Future<void> _loadIdentity() async {
    if (_identityLoaded) return;
    _appleUserId = await _store.readAppleUserId();
    _pseudonymSet = await _store.readPseudonymSet();
    _pseudonym = await _store.readPseudonym();
    _identityLoaded = true;
  }

  /// Call before gating a feature behind auth. Mirrors
  /// `LaunchLoadingViewController`: checks Apple's credential state for a
  /// stored identity, clears it if revoked/not found, and silently
  /// reconnects if there's no live session token yet.
  Future<void> restoreSession() async {
    await _loadIdentity();
    if (_appleUserId == null) return;

    try {
      final state = await SignInWithApple.getCredentialState(_appleUserId!);
      if (state == CredentialState.revoked ||
          state == CredentialState.notFound) {
        await clearStoredIdentity();
        return;
      }
    } catch (_) {
      // Non-fatal — leave identity untouched and fall through, matching
      // SecondStream's launch-time behavior when the check itself fails.
    }

    if (isConnected) {
      final sessionToken = await _store.readSessionToken();
      if (sessionToken == null) {
        try {
          await reconnect();
        } catch (_) {
          // Reconnect failed silently — the caller's flow will fall back to
          // showing the Sign in with Apple screen.
        }
      }
    }
  }

  /// Runs the native Sign in with Apple flow, then registers/reconnects with
  /// the backend. Throws [SignInWithAppleAuthorizationException] (code
  /// `canceled`) if the user dismisses the sheet, or an [AuthError] on a
  /// backend failure.
  Future<ManageUserOutcome> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final appleUserId = credential.userIdentifier;
    if (appleUserId == null) {
      throw AuthError('Apple did not return a user identifier.');
    }

    final outcome = await _manageUser(
      appleUserId: appleUserId,
      email: credential.email,
      firstName: credential.givenName,
      lastName: credential.familyName,
      isPrivateEmail: _isPrivateEmailClaim(credential.identityToken),
    );

    _appleUserId = appleUserId;
    _isExplicitlyDisconnected = false;
    _identityLoaded = true;
    await _store.saveAppleUserId(appleUserId);
    await _applyPseudonymOutcome(outcome);
    notifyListeners();
    return outcome;
  }

  /// Silent reconnect using the stored Apple user id — no Apple UI shown.
  /// Mirrors the Face ID fast path in SecondStream.
  Future<ManageUserOutcome> reconnect() async {
    await _loadIdentity();
    final appleUserId = _appleUserId;
    if (appleUserId == null) {
      throw AuthError('No stored identity to reconnect with.');
    }

    final outcome = await _manageUser(appleUserId: appleUserId);
    _isExplicitlyDisconnected = false;
    await _applyPseudonymOutcome(outcome);
    notifyListeners();
    return outcome;
  }

  /// Syncs the local "has a pseudonym" flag with what the server just said:
  /// 202 (new user) is the only outcome that means a pseudonym still needs
  /// to be chosen. 200 (reconnection) and 201 (existing user) both mean one
  /// is already set server-side — without this, a fresh install signing
  /// back into an existing account would default to "no pseudonym" locally
  /// and wrongly show the pseudonym screen again.
  Future<void> _applyPseudonymOutcome(ManageUserOutcome outcome) async {
    _pseudonymSet = outcome != ManageUserOutcome.newUser;
    await _store.savePseudonymSet(_pseudonymSet);
    if (_pseudonymSet && _pseudonym == null) {
      await _backfillPseudonymFromLeaderboard();
    }
  }

  /// Installs from before pseudonym *text* caching existed only ever saved
  /// whether one was set, not what it was — so a returning player can have
  /// [_pseudonymSet] true with [_pseudonym] still null. The leaderboard
  /// response includes every player's own pseudonym, so it doubles as a way
  /// to backfill this device's local cache without a dedicated endpoint.
  Future<void> _backfillPseudonymFromLeaderboard() async {
    try {
      final result = await fetchLeaderboard();
      String? ownPseudonym;
      for (final entry in result.entries) {
        if (entry.rank == result.userRank) {
          ownPseudonym = entry.pseudonym;
          break;
        }
      }
      if (ownPseudonym == null || ownPseudonym.isEmpty) return;
      _pseudonym = ownPseudonym;
      await _store.savePseudonym(ownPseudonym);
    } catch (_) {
      // Best-effort — leave it for the next reconnect or Leaderboard visit.
    }
  }

  Future<ManageUserOutcome> _manageUser({
    required String appleUserId,
    String? email,
    String? firstName,
    String? lastName,
    bool? isPrivateEmail,
  }) async {
    final sessionToken = await _store.readSessionToken();
    final hasEmail = email != null && email.isNotEmpty;
    // Send "creation" if Apple provided an email (first authorization) or we
    // have no stored session token (e.g. app was reinstalled and the server
    // doesn't know us yet); "reconnection" only once we're sure the server
    // already has the account.
    final operation =
        (hasEmail || sessionToken == null) ? 'creation' : 'reconnection';
    final requestId = _uuid.v4();

    final fields = <String, dynamic>{
      'apple_user_id': appleUserId,
      'operation': operation,
    };
    if (hasEmail) {
      fields['email'] = email;
      fields['is_private_email'] = isPrivateEmail ?? false;
      if (firstName != null) fields['first_name'] = firstName;
      if (lastName != null) fields['last_name'] = lastName;
    }
    _lastManageUserFields = fields;

    final (json, statusCode) = await _api.manageUser({
      ...fields,
      'request_id': requestId,
    });
    await _capturePseudonymIfPresent(json);
    return _outcomeFor(statusCode, json);
  }

  /// Best-effort: if the server happens to echo the pseudonym back on a
  /// creation/reconnection response, cache it locally so it can be
  /// displayed — otherwise we'd only learn it the moment this exact device
  /// sets one via [setPseudonym].
  Future<void> _capturePseudonymIfPresent(Map<String, dynamic>? json) async {
    final serverPseudonym = json?['pseudonym'] as String?;
    if (serverPseudonym == null || serverPseudonym.isEmpty) return;
    _pseudonym = serverPseudonym;
    await _store.savePseudonym(serverPseudonym);
  }

  /// Resends the same information from the most recent creation/reconnection
  /// call (apple_user_id, operation, email/name if present), plus the chosen
  /// [pseudonym] and the player's current score, to `manage-robozzle-user`.
  Future<void> setPseudonym(String pseudonym) async {
    await _loadIdentity();
    final appleUserId = _appleUserId;
    if (appleUserId == null) throw AuthError('Not signed in.');

    final baseFields = _lastManageUserFields ??
        <String, dynamic>{
          'apple_user_id': appleUserId,
          'operation': 'reconnection',
        };

    final body = <String, dynamic>{
      ...baseFields,
      'pseudonym': pseudonym,
      'score': await _currentScore(),
      'request_id': _uuid.v4(),
    };

    final (json, statusCode) = await _api.manageUser(body);
    if (statusCode < 200 || statusCode > 299) {
      _throwForStatus(statusCode, json);
    }

    _pseudonymSet = true;
    _pseudonym = pseudonym;
    await _store.savePseudonymSet(true);
    await _store.savePseudonym(pseudonym);
    _lastManageUserFields = null;
    notifyListeners();
  }

  Future<int> _currentScore() async {
    final completedIds = await ProgressStore().loadCompleted();
    final levels = await loadCatalogLevels();
    return totalPoints(completedIds, levels);
  }

  Future<void> deleteAccount() async {
    await _loadIdentity();
    final appleUserId = _appleUserId;
    if (appleUserId == null) return;

    final body = <String, dynamic>{
      'apple_user_id': appleUserId,
      'operation': 'deletion',
      'request_id': _uuid.v4(),
    };
    final (json, statusCode) = await _api.manageUser(body);
    if (statusCode < 200 || statusCode > 299) {
      _throwForStatus(statusCode, json);
    }
    await clearStoredIdentity();
  }

  /// Non-destructive local sign-out: identity and session token stay in
  /// storage so a later [reconnect] can restore access without a fresh
  /// Apple Sign In prompt.
  void disconnect() {
    _isExplicitlyDisconnected = true;
    notifyListeners();
  }

  Future<void> clearStoredIdentity() async {
    _appleUserId = null;
    _isExplicitlyDisconnected = false;
    _pseudonymSet = false;
    _pseudonym = null;
    _identityLoaded = true;
    await _store.clearAll();
    notifyListeners();
  }

  ManageUserOutcome _outcomeFor(int statusCode, Map<String, dynamic>? json) {
    if (statusCode < 200 || statusCode > 299) {
      _throwForStatus(statusCode, json);
    }
    return outcomeForManageUserStatus(statusCode);
  }

  Never _throwForStatus(int statusCode, Map<String, dynamic>? json) {
    if (statusCode == 553) throw UserNotFoundError();
    if (statusCode == 560) throw PseudonymTakenError();
    // Session token is no longer valid — clear local auth state so the UI
    // re-routes through Sign in with Apple.
    if (statusCode == 401 || statusCode == 403) {
      notifyListeners();
    }
    throw ServerError(
      statusCode,
      json?['message'] as String? ?? 'Unknown error ($statusCode)',
    );
  }

  bool? _isPrivateEmailClaim(String? identityToken) {
    if (identityToken == null) return null;
    final parts = identityToken.split('.');
    if (parts.length != 3) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map;
      final claim = payload['is_private_email'];
      if (claim is bool) return claim;
      if (claim is String) return claim == 'true';
    } catch (_) {
      // Malformed/unexpected JWT payload — treat as unknown.
    }
    return null;
  }
}
