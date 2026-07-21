import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

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

  Future<void> _loadIdentity() async {
    if (_identityLoaded) return;
    _appleUserId = await _store.readAppleUserId();
    _pseudonymSet = await _store.readPseudonymSet();
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
    if (outcome == ManageUserOutcome.newUser) {
      _pseudonymSet = false;
      await _store.savePseudonymSet(false);
    }
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
    notifyListeners();
    return outcome;
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
    return _outcomeFor(statusCode, json);
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
    await _store.savePseudonymSet(true);
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
    _identityLoaded = true;
    await _store.clearAll();
    notifyListeners();
  }

  ManageUserOutcome _outcomeFor(int statusCode, Map<String, dynamic>? json) {
    if (statusCode < 200 || statusCode > 299) {
      _throwForStatus(statusCode, json);
    }
    switch (statusCode) {
      case 201:
        return ManageUserOutcome.existingUser;
      case 202:
        return ManageUserOutcome.newUser;
      default:
        return ManageUserOutcome.reconnected;
    }
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
