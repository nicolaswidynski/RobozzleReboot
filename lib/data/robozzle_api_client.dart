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
  String toString() => 'Not signed in: no account identity stored.';
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
  static const String _savePuzzleUrl =
      'https://n8n.nwidynski.com/webhook/robozzle-save-puzzle';

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

  /// POSTs the player's [score] and [completedPuzzleIds] (the bare catalog
  /// numbers, e.g. `[1, 234, 54]` for level ids `catalog-1`/`catalog-234`/
  /// `catalog-54` — JSON-encoded to a string, same convention as
  /// `slotsPerFunction` in [publishPuzzle]) to `robozzle-leaderboard`,
  /// identifying the player via `auth_provider` + `provider_user_id` (so
  /// the server can verify the account) and a freshly generated
  /// `request_id` (echoed back so responses can be matched to requests),
  /// same as every `manageUser` call. The session token is still attached
  /// as `authorization_uuid`. Returns the decoded JSON response (rank,
  /// full sorted leaderboard, and the server's completed-puzzles superset
  /// — see `fetchLeaderboard` in leaderboard.dart) together with the HTTP
  /// status code.
  Future<(Map<String, dynamic>? json, int statusCode)> postScore(
    int score, {
    required List<int> completedPuzzleIds,
  }) async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final identityFields = await _identityFields();

    final response = await http.post(
      Uri.parse(_leaderboardUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        ...identityFields,
        'request_id': _uuid.v4(),
        'score': score,
        'completed_puzzles': jsonEncode(completedPuzzleIds),
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs `{request_id}` to `robozzle-list-puzzles` — no identity, signed
  /// in or not; the server doesn't need one to list puzzles. Returns the
  /// current server-side puzzle listing (title/author/difficulty/popularity
  /// per puzzle) together with the HTTP status code. The session token is
  /// still attached as `authorization_uuid` when there is one, but it's
  /// never required.
  Future<(Map<String, dynamic>? json, int statusCode)>
      fetchPuzzleListing() async {
    final sessionToken = await _sessionStore.readSessionToken();

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (sessionToken != null) {
      headers['authorization_uuid'] = 'Bearer $sessionToken';
    }

    final response = await http.post(
      Uri.parse(_listPuzzlesUrl),
      headers: headers,
      body: jsonEncode({
        'request_id': _uuid.v4(),
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// POSTs `{puzzle_id, request_id}` to `robozzle-get-puzzle` — no identity
  /// either, same as [fetchPuzzleListing] — used when a puzzle's playable
  /// content isn't already known locally (see `ensurePuzzleContent` in
  /// puzzle_content.dart). Returns the raw response (start state + grid
  /// rows) together with the HTTP status code.
  Future<(Map<String, dynamic>? json, int statusCode)> fetchPuzzle(
    String puzzleId,
  ) async {
    final sessionToken = await _sessionStore.readSessionToken();

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (sessionToken != null) {
      headers['authorization_uuid'] = 'Bearer $sessionToken';
    }

    final response = await http.post(
      Uri.parse(_getPuzzleUrl),
      headers: headers,
      body: jsonEncode({
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

  /// POSTs `{puzzle_id, rate, like, request_id}` to `robozzle-rate-puzzle`
  /// — no identity, same as [fetchPuzzleListing]/[fetchPuzzle]. [rate] is
  /// `""` or `"1"`-`"5"`; [like] is `""` or `"yes"` (there's deliberately
  /// no "no" — see `_submitRatingIfNeeded` in game_screen.dart). Returns
  /// the raw response together with the HTTP status code.
  Future<(Map<String, dynamic>? json, int statusCode)> ratePuzzle({
    required String puzzleId,
    required String rate,
    required String like,
  }) async {
    final sessionToken = await _sessionStore.readSessionToken();

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (sessionToken != null) {
      headers['authorization_uuid'] = 'Bearer $sessionToken';
    }

    final response = await http.post(
      Uri.parse(_ratePuzzleUrl),
      headers: headers,
      body: jsonEncode({
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

  /// POSTs `{auth_provider, provider_user_id, request_id}` plus the
  /// puzzle's [title], structural data, and the author's suggested
  /// [difficulty] (1-5), to `robozzle-save-puzzle`, to publish an
  /// editor-made puzzle to the server. No `puzzle_id` — this is a
  /// brand-new puzzle that doesn't have a server-assigned id yet; the
  /// server creates one. Field typing deliberately mirrors what
  /// `robozzle-get-puzzle` sends back on a fetch —
  /// `startRow`/`startCol`/`allowedCommands`/`difficulty` as strings,
  /// `slotsPerFunction` as a JSON-encoded string, `rows` as a real string
  /// array — rather than the natural Dart types. Returns the raw response
  /// together with the HTTP status code; the caller only needs to check
  /// for 200.
  Future<(Map<String, dynamic>? json, int statusCode)> publishPuzzle({
    required String title,
    required int startRow,
    required int startCol,
    required String startDirection,
    required int allowedCommands,
    required List<int> slotsPerFunction,
    required List<String> rows,
    required int difficulty,
  }) async {
    final sessionToken = await _sessionStore.readSessionToken();
    if (sessionToken == null) throw MissingSessionTokenError();

    final identityFields = await _identityFields();

    final response = await http.post(
      Uri.parse(_savePuzzleUrl),
      headers: {
        'Content-Type': 'application/json',
        'authorization_uuid': 'Bearer $sessionToken',
      },
      body: jsonEncode({
        ...identityFields,
        'request_id': _uuid.v4(),
        'title': title,
        'startRow': '$startRow',
        'startCol': '$startCol',
        'startDirection': startDirection,
        'allowedCommands': '$allowedCommands',
        'slotsPerFunction': jsonEncode(slotsPerFunction),
        'rows': rows,
        'difficulty': '$difficulty',
      }),
    );

    final json = _firstJson(response.bodyBytes);

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _sessionStore.clearSessionToken();
    }

    return (json, response.statusCode);
  }

  /// The signed-in identity as the two wire fields the endpoints that need
  /// one send (`auth_provider` + `provider_user_id`), replacing the old
  /// Apple-only `apple_user_id` field. Throws [MissingIdentityError] if
  /// there's no stored identity — only [postScore] and [publishPuzzle]
  /// call this; every other endpoint here works whether signed in or not
  /// and never sends identity at all.
  Future<Map<String, dynamic>> _identityFields() async {
    final identity = await _sessionStore.readIdentity();
    if (identity == null) throw MissingIdentityError();
    final (provider, providerUserId) = identity;
    return {
      'auth_provider': provider.wireValue,
      'provider_user_id': providerUserId,
    };
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
