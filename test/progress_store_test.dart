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

  test('markAllCompleted merges a whole set in one go, keeping what was '
      'already there', () async {
    final store = ProgressStore();

    await store.markCompleted('catalog-1');
    await store.markAllCompleted({'catalog-2', 'catalog-3', 'catalog-1'});

    expect(await store.loadCompleted(), {'catalog-1', 'catalog-2', 'catalog-3'});
  });

  test('server score round-trips, absent until saved, and always takes '
      'the newest value written', () async {
    final store = ProgressStore();

    expect(await store.loadServerScore(), isNull);

    await store.saveServerScore(19);
    expect(await store.loadServerScore(), 19);

    // Overwrites unconditionally -- the server's number always wins, even
    // if it goes down (e.g. after a rescoring/re-rating on the backend).
    await store.saveServerScore(12);
    expect(await store.loadServerScore(), 12);
  });

  test('par is empty until recorded, then round-trips through storage',
      () async {
    final store = ProgressStore();

    expect(await store.loadPar(), isEmpty);

    await store.recordPar('catalog-1', 3);
    expect(await store.loadPar(), {'catalog-1': 3});
  });

  test('recordPar keeps the best (highest) value, ignoring a worse replay',
      () async {
    final store = ProgressStore();

    await store.recordPar('catalog-1', 3);
    await store.recordPar('catalog-1', 1); // worse -- fewer unused slots
    expect(await store.loadPar(), {'catalog-1': 3});

    await store.recordPar('catalog-1', 5); // better -- overwrites
    expect(await store.loadPar(), {'catalog-1': 5});
  });
}
