/// Google Sign-In OAuth client configuration.
///
/// [iosClientId] and [serverClientId] are registered in the same Google
/// Cloud project (console.cloud.google.com) and wired up — iOS/macOS sign-in
/// works. Still outstanding for Android: register an "Android" OAuth client
/// for package name `com.stdn.robozzleReboot` with your debug and release
/// SHA-1 fingerprints (`./gradlew signingReport` prints the debug one). No
/// client ID needs to go in this file for Android — the package discovers
/// it via Google Play Services once that client is registered.
///
/// [serverClientId] (the "Web application" OAuth client) is what makes
/// `GoogleSignInAccount.authentication.idToken` verifiable: the backend
/// (the `manage-robozzle-user` webhook) should check the token's `aud`
/// claim against this same client ID when it receives
/// `auth_provider: "google"`.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String iosClientId =
      '138287612260-6fquc47977ctsu0o6c7pn0lsq2b5k8fu.apps.googleusercontent.com';
  static const String serverClientId =
      '138287612260-6q4lc3a14sciahkm5ct58kvk42ns18f8.apps.googleusercontent.com';
}
