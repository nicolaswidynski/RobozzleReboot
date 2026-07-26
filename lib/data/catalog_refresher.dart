import 'package:flutter/foundation.dart';

import 'catalog_metadata_store.dart';
import 'robozzle_api_client.dart';

/// Refreshes title/author/difficulty/popularity for the bundled catalog from
/// the `robozzle-list-puzzles` webhook, and caches the result locally so
/// [loadCatalogLevels] can merge it in.
///
/// Browsing stays fully open and offline-capable: refreshing is silently
/// skipped (never blocks, never errors the UI) when there's no network —
/// the bundled/cached listing is always shown. Signed in or not, the same
/// `robozzle-list-puzzles` request goes out; no identity is sent either way.
///
/// A [ChangeNotifier] so anything showing a score derived from the catalog
/// (e.g. the landing screen's points badge) can recompute it whenever
/// metadata actually changes — a puzzle's difficulty may have been
/// re-rated, or it may have disappeared from the listing entirely, either
/// of which changes the player's total.
class CatalogRefresher extends ChangeNotifier {
  CatalogRefresher._();
  static final CatalogRefresher instance = CatalogRefresher._();

  static const Duration dailyInterval = Duration(hours: 24);

  final CatalogMetadataStore _store = CatalogMetadataStore();
  bool _refreshing = false;

  /// Call once when the list first loads — refreshes at most once every
  /// [dailyInterval].
  Future<bool> refreshDaily() => _maybeRefresh(minInterval: dailyInterval);

  /// Call when the list is scrolled to the bottom — always attempts a fresh
  /// fetch (still coalesced against a refresh already in flight).
  Future<bool> refreshNow() => _maybeRefresh(minInterval: Duration.zero);

  /// Returns `true` only when new metadata was actually fetched and saved,
  /// so callers know whether to reload the levels they're showing.
  Future<bool> _maybeRefresh({required Duration minInterval}) async {
    if (_refreshing) return false;

    if (minInterval > Duration.zero) {
      final lastRefreshed = await _store.loadLastRefreshedAt();
      if (lastRefreshed != null &&
          DateTime.now().difference(lastRefreshed) < minInterval) {
        return false;
      }
    }

    _refreshing = true;
    try {
      final (json, statusCode) =
          await RobozzleApiClient.instance.fetchPuzzleListing();
      if (statusCode < 200 || statusCode > 299 || json == null) return false;

      final overrides = parseCatalogOverrides(json['puzzles_list']);
      if (overrides.isEmpty) return false;

      await _store.saveOverrides(overrides);
      await _store.saveLastRefreshedAt(DateTime.now());
      notifyListeners();
      return true;
    } catch (_) {
      // Offline or server error — keep using whatever's cached/bundled.
      return false;
    } finally {
      _refreshing = false;
    }
  }

}

/// Parses the `puzzles_list` field of a `robozzle-list-puzzles` response — a
/// flat array of `{sourceId, title, author, difficulty, popularity}`
/// objects — into overrides keyed by [Level.id]. `sourceId`/`difficulty`/
/// `popularity` come back as numbers (sometimes decimal, e.g. `3.0536...`),
/// not the string-typed fields other endpoints use.
Map<String, CatalogMetadataOverride> parseCatalogOverrides(dynamic raw) {
  if (raw is! List || raw.isEmpty) return {};

  final overrides = <String, CatalogMetadataOverride>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final sourceId = e['sourceId'];
    if (sourceId == null) continue;
    overrides['catalog-$sourceId'] = CatalogMetadataOverride(
      title: e['title'] as String?,
      author: e['author'] as String?,
      // A puzzle's rating is 1-5 stars — there's no such thing as a 0-star
      // difficulty, so a rounded average just under 1 (e.g. from a puzzle
      // with no ratings yet) is floored up to the minimum instead.
      difficulty: _roundedInt(e['difficulty'])?.clamp(1, 5),
      popularity: _roundedInt(e['popularity']),
    );
  }
  return overrides;
}

/// Parses a possibly-decimal numeric value (e.g. `"3.7"` — the server's
/// `difficulty` field isn't always a whole number) into a rounded int.
/// `int.tryParse` would silently return null on a decimal string, dropping
/// the field entirely.
int? _roundedInt(dynamic value) {
  if (value == null) return null;
  return double.tryParse('$value')?.round();
}
