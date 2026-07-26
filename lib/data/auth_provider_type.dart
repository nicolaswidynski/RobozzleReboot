/// Which identity provider a signed-in account authenticated with. Sent to
/// the backend as `auth_provider` (alongside `provider_user_id`, the
/// provider's own stable user id) on every request, instead of the old
/// Apple-only `apple_user_id` field — see AuthManager for where those are
/// built.
enum AuthProviderType {
  apple,
  google;

  String get wireValue => name;

  static AuthProviderType? fromWireValue(String? value) {
    for (final provider in values) {
      if (provider.wireValue == value) return provider;
    }
    return null;
  }
}
