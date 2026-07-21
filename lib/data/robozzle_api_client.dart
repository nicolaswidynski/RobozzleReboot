import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'secure_session_store.dart';

/// Talks to the `manage-robozzle-user` n8n webhook. Mirrors SecondStream's
/// `SecondStreamAPIClient`: a static bootstrap token authorizes the first
/// call (before any session exists), a rotating per-user session token
/// (`authorization_uuid` header) authorizes every call once one exists, and
/// the server may rotate that session token on any response.
class ApiError implements Exception {
  final int statusCode;
  final String message;

  ApiError(this.statusCode, this.message);

  @override
  String toString() => 'ApiError($statusCode, $message)';
}

class MissingBootstrapTokenError implements Exception {
  @override
  String toString() =>
      'Missing bootstrap token: fill in assets/robozzle_token.txt';
}

class MissingSessionTokenError implements Exception {
  @override
  String toString() => 'Not signed in: no session token stored.';
}

class MissingIdentityError implements Exception {
  @override
  String toString() => 'Not signed in: no Apple user id stored.';
}

class RobozzleApiClient {
  RobozzleApiClient._();
  static final RobozzleApiClient instance = RobozzleApiClient._();

  static const String _manageUserUrl =
      'https://n8n.nwidynski.com/webhook/manage-robozzle-user';
  static const String _leaderboardUrl =
      'https://n8n.nwidynski.com/webhook/robozzle-leaderboard';
  static const String _listPuzzlesUrl =
      'https://n8n.nwidynski.com/webhook/robozzle-list-puzzles';
  static const String _getPuzzleUrl =
      'https://n8n.nwidynski.com/webhook/robozzle-get-puzzle';
  static const String _ratePuzzleUrl =
      'https://n8n.nwidynski.com/webhook/robozzle-rate-puzzle';

  static const Uuid _uuid = Uuid();

  final SecureSessionStore _sessionStore = SecureSessionStore.instance;

  String? _bootstrapToken;

  Future<String> _loadBootstrapToken() async {
    if (_bootstrapToken != null) return _bootstrapToken!;
    final raw = await rootBundle.loadString('assets/robozzle_token.txt');
    final token = raw.trim();
    if (token.isEmpty || token == 'REPLACE_ME_WITH_BOOTSTRAP_TOKEN') {
      throw MissingBootstrapTokenError();
    }
    _bootstrapToken = token;
    return token;
  }

  /// POSTs [body] to `manage-robozzle-user`. Always attaches the bootstrap
  /// token as `Authorization`, and additionally attaches the session token
  /// (if one is stored) as `authorization_uuid`. Returns the decoded JSON
  /// object (handling both a bare `{...}` and an n8n array-wrapped `[{...}]`
  /// response) together with the HTTP status code.
  Future<(Map<String, dynamic>? json, int statusCode)> manageUser(
    Map<String, dynamic> body,
  ) async {
    final bootstrapToken = await _loadBootstrapToken();
    final sessionToken = await _sessionStore.readSessionToken();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $bootstrapToken',
    };
    if (sessionToken != null) {
      headers['authorization_uuid'] = 'Bearer $sessionToken';
    }

    final response = await http.post(
      Uri.parse(_manageUserUrl),
      headers: headers,
      body: jsonEncode(body),
    );

    final json = _firstJson(response.bodyBytes);

    // The server may rotate the session token on any response.
    final rotatedToken = json?['user_token'] as String?;
    if (rotatedToken != null && rotatedToken.isNotEmpty) {
      await _sessionStore.saveSessionToken(rotatedToken);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs the player's [score] to `robozzle-leaderboard`, identifying the
  /// player via `apple_user_id` (so the server can verify the account) and a
  /// freshly generated `request_id` (echoed back so responses can be matched
  /// to requests), same as every `manageUser` call. The session token is
  /// still attached as `authorization_uuid`. Returns the decoded JSON
  /// response (rank + full sorted leaderboard) together with the HTTP
  /// status code.
  Future<(Map<String, dynamic>? json, int statusCode)> postScore(
    int score,
  ) async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final appleUserId = await _sessionStore.readAppleUserId();
    if (appleUserId == null) throw MissingIdentityError();

    final response = await http.post(
      Uri.parse(_leaderboardUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'apple_user_id': appleUserId,
        'request_id': _uuid.v4(),
        'score': score,
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs `{apple_user_id, request_id}` to `robozzle-list-puzzles`.
  /// Returns the current server-side puzzle listing
  /// (title/author/difficulty/popularity per puzzle) together with the HTTP
  /// status code. Throws if the player isn't signed in; callers should only
  /// invoke this when there's a stored identity, since anonymous browsing
  /// should just keep using the last cached/bundled listing instead of
  /// calling this at all.
  Future<(Map<String, dynamic>? json, int statusCode)>
      fetchPuzzleListing() async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final appleUserId = await _sessionStore.readAppleUserId();
    if (appleUserId == null) throw MissingIdentityError();

    final response = await http.post(
      Uri.parse(_listPuzzlesUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'apple_user_id': appleUserId,
        'request_id': _uuid.v4(),
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs `{apple_user_id, puzzle_id, request_id}` to `robozzle-get-puzzle`
  /// — used when a puzzle's playable content isn't already known locally
  /// (see `ensurePuzzleContent` in puzzle_content.dart). Returns the raw
  /// response (start state + grid rows) together with the HTTP status code.
  Future<(Map<String, dynamic>? json, int statusCode)> fetchPuzzle(
    String puzzleId,
  ) async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final appleUserId = await _sessionStore.readAppleUserId();
    if (appleUserId == null) throw MissingIdentityError();

    final response = await http.post(
      Uri.parse(_getPuzzleUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'apple_user_id': appleUserId,
        'puzzle_id': puzzleId,
        'request_id': _uuid.v4(),
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs `{apple_user_id, puzzle_id, rate, like, request_id}` to
  /// `robozzle-rate-puzzle`. [rate] is `""` or `"1"`-`"5"`; [like] is `""`
  /// or `"yes"` (there's deliberately no "no" — see `_submitRatingIfNeeded`
  /// in game_screen.dart). Returns the raw response together with the HTTP
  /// status code.
  Future<(Map<String, dynamic>? json, int statusCode)> ratePuzzle({
    required String puzzleId,
    required String rate,
    required String like,
  }) async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final appleUserId = await _sessionStore.readAppleUserId();
    if (appleUserId == null) throw MissingIdentityError();

    final response = await http.post(
      Uri.parse(_ratePuzzleUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        'apple_user_id': appleUserId,
        'puzzle_id': puzzleId,
        'rate': rate,
        'like': like,
        'request_id': _uuid.v4(),
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  Map<String, dynamic>? _firstJson(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return Map<String, dynamic>.from(decoded.first as Map);
      }
    } catch (_) {
      // Fall through to null — caller treats a non-JSON body as "no data".
    }
    return null;
  }
}
