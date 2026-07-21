import 'auth_manager.dart';
import 'catalog_metadata_store.dart';
import 'robozzle_api_client.dart';

/// Refreshes title/author/difficulty/popularity for the bundled catalog from
/// the `robozzle-leaderboard` webhook's listing operation, and caches the
/// result locally so [loadCatalogLevels] can merge it in.
///
/// Browsing stays fully open and offline-capable: refreshing is silently
/// skipped (never blocks, never errors the UI) when the player isn't signed
/// in or there's no network — the bundled/cached listing is always shown.
class CatalogRefresher {
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

    final authManager = AuthManager.instance;
    await authManager.restoreSession();
    if (!authManager.isConnected) return false;

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
      return true;
    } catch (_) {
      // Offline or server error — keep using whatever's cached/bundled.
      return false;
    } finally {
      _refreshing = false;
    }
  }

}

/// Parses the `puzzles_list` field of a `robozzle-leaderboard` listing
/// response into overrides keyed by [Level.id]. n8n wraps the actual list as
/// `puzzles_list: [{"json": {"list": [...]}}]`, the same quirk as the
/// leaderboard's `sorted` field.
Map<String, CatalogMetadataOverride> parseCatalogOverrides(dynamic raw) {
  if (raw is! List || raw.isEmpty) return {};

  final first = raw.first;
  final wrapped = first is Map ? first['json'] : null;
  final list = wrapped is Map ? wrapped['list'] : null;
  if (list is! List) return {};

  final overrides = <String, CatalogMetadataOverride>{};
  for (final e in list) {
    if (e is! Map) continue;
    final sourceId = e['sourceId'];
    if (sourceId == null) continue;
    overrides['catalog-$sourceId'] = CatalogMetadataOverride(
      title: e['title'] as String?,
      author: e['author'] as String?,
      difficulty: int.tryParse('${e['difficulty']}'),
      popularity: int.tryParse('${e['popularity']}'),
    );
  }
  return overrides;
}
