import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Server-provided overrides for a single bundled level's listing metadata.
/// The puzzle's actual playable content (grid, start position, etc.) always
/// comes from the bundled catalog asset — only these fields get refreshed.
class CatalogMetadataOverride {
  final String? title;
  final String? author;
  final int? difficulty;
  final int? popularity;

  CatalogMetadataOverride({
    this.title,
    this.author,
    this.difficulty,
    this.popularity,
  });

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (author != null) 'author': author,
        if (difficulty != null) 'difficulty': difficulty,
        if (popularity != null) 'popularity': popularity,
      };

  factory CatalogMetadataOverride.fromJson(Map<String, dynamic> json) {
    return CatalogMetadataOverride(
      title: json['title'] as String?,
      author: json['author'] as String?,
      difficulty: json['difficulty'] as int?,
      popularity: json['popularity'] as int?,
    );
  }
}

/// Persists the last server-fetched listing metadata (keyed by [Level.id]),
/// plus when it was last refreshed, so the catalog stays browsable offline
/// between refreshes.
class CatalogMetadataStore {
  static const _overridesKey = 'catalog_metadata_overrides';
  static const _lastRefreshedKey = 'catalog_metadata_last_refreshed_at';

  Future<Map<String, CatalogMetadataOverride>> loadOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_overridesKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(
        key,
        CatalogMetadataOverride.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  Future<void> saveOverrides(
    Map<String, CatalogMetadataOverride> overrides,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      overrides.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_overridesKey, encoded);
  }

  Future<DateTime?> loadLastRefreshedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastRefreshedKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveLastRefreshedAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRefreshedKey, time.toIso8601String());
  }
}
