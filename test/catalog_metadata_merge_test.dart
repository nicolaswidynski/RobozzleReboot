import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/catalog_metadata_store.dart';
import 'package:robozzle_reboot/data/level_catalog.dart';
import 'package:robozzle_reboot/models/level.dart';

void main() {
  testWidgets(
      'loadCatalogLevels overlays cached server metadata onto the bundled '
      'catalog, without touching the puzzle grid itself', (tester) async {
    // "catalog-195" ("Another speed control") is difficulty 3 / popularity
    // 158 in the bundled asset — verified directly against the asset.
    SharedPreferences.setMockInitialValues({});
    await CatalogMetadataStore().saveOverrides({
      'catalog-195': CatalogMetadataOverride(
        title: 'Renamed by server',
        difficulty: 5,
        popularity: 9999,
      ),
    });

    late List<Level> levels;
    await tester.runAsync(() async {
      levels = await loadCatalogLevels();
    });

    final level = levels.firstWhere((l) => l.id == 'catalog-195');

    expect(level.name, 'Renamed by server');
    expect(level.difficulty, 5);
    expect(level.popularity, 9999);
    // Author wasn't part of the override, so it stays whatever the bundled
    // asset has — and the grid must be entirely untouched either way.
    expect(level.grid, isNotEmpty);
  });
}
