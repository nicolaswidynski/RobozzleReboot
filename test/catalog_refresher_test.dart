import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/catalog_refresher.dart';

void main() {
  test('parses the real robozzle-list-puzzles shape — a flat array, not '
      'n8n-wrapped', () {
    final raw = [
      {
        "sourceId": 195,
        "title": "Another speed control",
        "author": "evko",
        "difficulty": 3,
        "popularity": 158,
      },
      {
        "sourceId": 53,
        "title": "Branches",
        "author": "igoro",
        "difficulty": 4,
        "popularity": 135,
      },
    ];

    final overrides = parseCatalogOverrides(raw);

    expect(overrides, hasLength(2));
    expect(overrides['catalog-195']!.title, 'Another speed control');
    expect(overrides['catalog-195']!.author, 'evko');
    expect(overrides['catalog-195']!.difficulty, 3);
    expect(overrides['catalog-195']!.popularity, 158);
    expect(overrides['catalog-53']!.title, 'Branches');
  });

  test('rounds a decimal difficulty instead of dropping it — real puzzles '
      'do come back with e.g. difficulty 3.053571428571428', () {
    final raw = [
      {
        "sourceId": 392,
        "title": "2-Bit Instructions",
        "author": "shahbawany",
        "difficulty": 3.053571428571428,
        "popularity": 318,
      },
      {
        "sourceId": 23,
        "title": "Two stripes",
        "author": "igoro",
        "difficulty": 2.000687127805772,
        "popularity": 4366,
      },
    ];

    final overrides = parseCatalogOverrides(raw);

    expect(overrides['catalog-392']!.difficulty, 3);
    expect(overrides['catalog-23']!.difficulty, 2);
  });

  test('a difficulty that rounds below 1 (e.g. an unrated puzzle averaging '
      'near 0) is floored to 1 — there is no such thing as a 0-star puzzle',
      () {
    final raw = [
      {
        "sourceId": 999,
        "title": "Brand New",
        "author": "someone",
        "difficulty": 0.2,
        "popularity": 0,
      },
    ];

    final overrides = parseCatalogOverrides(raw);

    expect(overrides['catalog-999']!.difficulty, 1);
  });

  test('a newly published (self-authored) puzzle parses the same as any '
      'other entry', () {
    final raw = [
      {
        "sourceId": 240766,
        "title": "Baby Steps",
        "author": "wido",
        "difficulty": 1,
        "popularity": 1,
      },
    ];

    final overrides = parseCatalogOverrides(raw);

    expect(overrides, hasLength(1));
    final entry = overrides['catalog-240766'];
    expect(entry, isNotNull);
    expect(entry!.title, 'Baby Steps');
    expect(entry.author, 'wido');
    expect(entry.difficulty, 1);
    expect(entry.popularity, 1);
  });

  test('a null author (some scraped puzzles have none) parses as null, '
      'not a crash', () {
    final raw = [
      {
        "sourceId": 29,
        "title": "Space Invader",
        "author": null,
        "difficulty": 4,
        "popularity": 37,
      },
    ];

    final overrides = parseCatalogOverrides(raw);

    expect(overrides['catalog-29']!.author, isNull);
  });

  test('returns no overrides when puzzles_list is missing, empty, or '
      'entries have no sourceId', () {
    expect(parseCatalogOverrides(null), isEmpty);
    expect(parseCatalogOverrides([]), isEmpty);
    expect(
      parseCatalogOverrides([
        {'title': 'No source id'},
      ]),
      isEmpty,
    );
  });
}
