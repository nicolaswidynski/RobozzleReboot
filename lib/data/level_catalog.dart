import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/direction.dart';
import '../models/level.dart';
import 'catalog_metadata_store.dart';
import 'puzzle_content.dart';
import 'puzzle_content_store.dart';

/// Loads every scraped Robozzle level from the bundled JSON catalog
/// (assets/levels_catalog.json — see the scrape scripts used to build it),
/// then:
///  - overlays any fresher title/author/difficulty/popularity fetched from
///    the server (see [CatalogRefresher]);
///  - adds a placeholder entry (empty grid) for any puzzle the server lists
///    that isn't in the bundled catalog at all — its playable content is
///    fetched lazily, right before it's actually opened (see
///    `ensurePuzzleContent` in puzzle_content.dart);
///  - fills in a placeholder's grid immediately if it was already fetched
///    and cached in an earlier session, so it stays playable offline.
Future<List<Level>> loadCatalogLevels() async {
  final jsonString = await rootBundle.loadString('assets/levels_catalog.json');
  final entries = json.decode(jsonString) as List;
  final bundledLevels =
      entries.map((e) => Level.fromJson(e as Map<String, dynamic>)).toList();

  final overrides = await CatalogMetadataStore().loadOverrides();
  final bundledIds = bundledLevels.map((l) => l.id).toSet();

  final levels = [
    for (final level in bundledLevels) _applyOverride(level, overrides[level.id]),
    for (final id in overrides.keys)
      if (!bundledIds.contains(id)) _placeholderLevel(id, overrides[id]!),
  ];

  final contentStore = PuzzleContentStore();
  return [
    for (final level in levels) await _applyCachedContent(level, contentStore),
  ];
}

Level _applyOverride(Level level, CatalogMetadataOverride? override) {
  if (override == null) return level;
  return Level(
    id: level.id,
    name: override.title ?? level.name,
    author: override.author ?? level.author,
    grid: level.grid,
    startRow: level.startRow,
    startCol: level.startCol,
    startDirection: level.startDirection,
    slotsPerFunction: level.slotsPerFunction,
    difficulty: override.difficulty ?? level.difficulty,
    popularity: override.popularity ?? level.popularity,
    allowedPaintColors: level.allowedPaintColors,
  );
}

Level _placeholderLevel(String id, CatalogMetadataOverride override) {
  return Level(
    id: id,
    name: override.title ?? 'Untitled',
    author: override.author ?? '',
    grid: const [],
    startRow: 0,
    startCol: 0,
    startDirection: Direction.right,
    slotsPerFunction: const [0, 0, 0, 0, 0],
    difficulty: override.difficulty ?? 1,
    popularity: override.popularity ?? 0,
  );
}

Future<Level> _applyCachedContent(
  Level level,
  PuzzleContentStore contentStore,
) async {
  if (level.grid.isNotEmpty) return level;
  final cached = await contentStore.load(level.id);
  if (cached == null) return level;
  return buildLevelWithContent(level, cached);
}
