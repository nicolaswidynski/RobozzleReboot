import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/progress_store.dart';

import 'fake_secure_storage.dart';

void main() {
  setUp(() => installFakeSecureStorage());

  test('completed levels round-trip through storage, empty until marked',
      () async {
    final store = ProgressStore();

    expect(await store.loadCompleted(), isEmpty);

    await store.markCompleted('catalog-1');
    await store.markCompleted('catalog-2');

    expect(await store.loadCompleted(), {'catalog-1', 'catalog-2'});
  });

  test('marking the same level completed twice does not duplicate it',
      () async {
    final store = ProgressStore();

    await store.markCompleted('catalog-1');
    await store.markCompleted('catalog-1');

    expect(await store.loadCompleted(), {'catalog-1'});
  });
}
