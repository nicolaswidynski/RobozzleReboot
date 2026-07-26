import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/auth_provider_type.dart';
import 'package:robozzle_reboot/data/secure_session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pseudonym text round-trips through storage, absent until saved', () async {
    final store = SecureSessionStore.instance;

    expect(await store.readPseudonym(AuthProviderType.apple), isNull);

    await store.savePseudonym(AuthProviderType.apple, 'RoboFan');

    expect(await store.readPseudonym(AuthProviderType.apple), 'RoboFan');
  });

  test(
      'each provider has its own pseudonym — saving one does not overwrite '
      'or leak into the other', () async {
    final store = SecureSessionStore.instance;

    await store.savePseudonym(AuthProviderType.apple, 'AppleFan');
    await store.savePseudonym(AuthProviderType.google, 'GoogleFan');

    expect(await store.readPseudonym(AuthProviderType.apple), 'AppleFan');
    expect(await store.readPseudonym(AuthProviderType.google), 'GoogleFan');

    await store.savePseudonymSet(AuthProviderType.apple, true);
    expect(await store.readPseudonymSet(AuthProviderType.apple), isTrue);
    expect(await store.readPseudonymSet(AuthProviderType.google), isFalse);
  });
}
