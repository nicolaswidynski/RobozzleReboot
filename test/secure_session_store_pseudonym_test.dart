import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/secure_session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pseudonym text round-trips through storage, absent until saved', () async {
    final store = SecureSessionStore.instance;

    expect(await store.readPseudonym(), isNull);

    await store.savePseudonym('RoboFan');

    expect(await store.readPseudonym(), 'RoboFan');
  });
}
