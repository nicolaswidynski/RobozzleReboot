import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/catalog_refresher.dart';

void main() {
  test('parses the n8n listing response shape, including the wrapped '
      '[{"json": {"list": [...]}}] puzzles_list field', () {
    final raw = [
      {
        "json": {
          "list": [
            {
              "sourceId": "195",
              "title": "Another speed control",
              "author": "evko",
              "difficulty": "3",
              "popularity": "158",
            },
            {
              "sourceId": "53",
              "title": "Branches",
              "author": "igoro",
              "difficulty": "4",
              "popularity": "135",
            },
          ],
        },
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

  test('returns no overrides when puzzles_list is missing or malformed', () {
    expect(parseCatalogOverrides(null), isEmpty);
    expect(parseCatalogOverrides([]), isEmpty);
    expect(
      parseCatalogOverrides([
        {'json': {}},
      ]),
      isEmpty,
    );
    expect(
      parseCatalogOverrides([
        {
          'json': {
            'list': [
              {'title': 'No source id'},
            ],
          },
        },
      ]),
      isEmpty,
    );
  });
}
