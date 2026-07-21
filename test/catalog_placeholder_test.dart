import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/catalog_metadata_store.dart';
import 'package:robozzle_reboot/data/level_catalog.dart';
import 'package:robozzle_reboot/data/puzzle_content_store.dart';
import 'package:robozzle_reboot/models/level.dart';

void main() {
  testWidgets(
      'a server-listed puzzle with no bundled entry shows up as an empty '
      "placeholder, and gets filled in immediately if it's already cached",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CatalogMetadataStore().saveOverrides({
      // "catalog-999999" doesn't exist in the bundled asset.
      'catalog-999999': CatalogMetadataOverride(
        title: 'Brand New Puzzle',
        author: 'someone',
        difficulty: 2,
        popularity: 5,
      ),
      // Neither does this one, but its content was already fetched and
      // cached in an earlier session.
      'catalog-888888': CatalogMetadataOverride(
        title: 'Already Fetched Puzzle',
        difficulty: 1,
        popularity: 1,
      ),
    });
    await PuzzleContentStore().save(
      'catalog-888888',
      PuzzleContent(
        startRow: 0,
        startCol: 0,
        startDirection: 'right',
        allowedCommands: 0,
        slotsPerFunction: [3, 0, 0, 0, 0],
        rows: ['r  b', '   b', 'bbbg'],
      ),
    );

    late List<Level> levels;
    await tester.runAsync(() async {
      levels = await loadCatalogLevels();
    });

    final newPuzzle =
        levels.firstWhere((l) => l.id == 'catalog-999999');
    expect(newPuzzle.name, 'Brand New Puzzle');
    expect(newPuzzle.author, 'someone');
    expect(newPuzzle.difficulty, 2);
    expect(newPuzzle.grid, isEmpty);

    final cachedPuzzle =
        levels.firstWhere((l) => l.id == 'catalog-888888');
    expect(cachedPuzzle.name, 'Already Fetched Puzzle');
    expect(cachedPuzzle.grid, isNotEmpty);
    expect(cachedPuzzle.rowCount, 3);
  });
}
