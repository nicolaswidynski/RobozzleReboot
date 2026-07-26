import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/auth_provider_type.dart';
import 'package:robozzle_reboot/data/secure_session_store.dart';

import 'fake_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  test(
      'signing in with a second provider does not erase the first '
      'provider\'s stored id', () async {
    final store = SecureSessionStore.instance;

    await store.saveIdentity(AuthProviderType.apple, 'apple-123');
    await store.saveIdentity(AuthProviderType.google, 'google-456');

    // Google is now active, but Apple's own id is still there, untouched.
    expect(await store.readIdentity(), (AuthProviderType.google, 'google-456'));
    expect(
      await store.readProviderUserId(AuthProviderType.apple),
      'apple-123',
    );
    expect(
      await store.readProviderUserId(AuthProviderType.google),
      'google-456',
    );
  });

  test(
      'switching back to a provider signed into earlier restores that '
      'provider\'s original id, not a stale one', () async {
    final store = SecureSessionStore.instance;

    await store.saveIdentity(AuthProviderType.apple, 'apple-123');
    await store.saveIdentity(AuthProviderType.google, 'google-456');
    await store.saveIdentity(AuthProviderType.apple, 'apple-123');

    expect(await store.readIdentity(), (AuthProviderType.apple, 'apple-123'));
  });

  test('clearAll wipes both providers\' stored ids, not just the active one',
      () async {
    final store = SecureSessionStore.instance;

    await store.saveIdentity(AuthProviderType.apple, 'apple-123');
    await store.saveIdentity(AuthProviderType.google, 'google-456');

    await store.clearAll();

    expect(await store.readIdentity(), isNull);
    expect(await store.readProviderUserId(AuthProviderType.apple), isNull);
    expect(await store.readProviderUserId(AuthProviderType.google), isNull);
  });
}
