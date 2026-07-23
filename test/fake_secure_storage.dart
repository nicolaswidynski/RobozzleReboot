import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// In-memory stand-in for the Keychain-backed `flutter_secure_storage`
/// platform channel, which has no implementation under `flutter test` and
/// hangs forever rather than throwing. Any test that exercises code storing
/// data via `FlutterSecureStorage` (e.g. solving a puzzle, which marks it
/// completed) must install this first — see [installFakeSecureStorage].
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

/// Installs a fresh [FakeSecureStoragePlatform] as the backing store for
/// every `FlutterSecureStorage` instance for the rest of the current test.
/// Call from `setUp` in any test that solves a puzzle or otherwise touches
/// [ProgressStore]/`SecureSessionStore`.
FakeSecureStoragePlatform installFakeSecureStorage() {
  final fake = FakeSecureStoragePlatform();
  FlutterSecureStoragePlatform.instance = fake;
  return fake;
}
