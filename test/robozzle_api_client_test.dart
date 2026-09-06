import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/robozzle_api_client.dart';

void main() {
  group('isWellFormedServerUrl', () {
    test('accepts a plain http(s) URL, with or without a trailing slash', () {
      expect(isWellFormedServerUrl('https://n8n.example.com/webhook'), isTrue);
      expect(isWellFormedServerUrl('https://n8n.example.com/webhook/'), isTrue);
      expect(isWellFormedServerUrl('http://localhost:5678/webhook'), isTrue);
    });

    test('rejects an empty value', () {
      expect(isWellFormedServerUrl(''), isFalse);
    });

    test('rejects the unfilled placeholder', () {
      expect(isWellFormedServerUrl('REPLACE_ME_WITH_SERVER_URL'), isFalse);
    });

    test('rejects garbage that is not a URL at all', () {
      // Uri.parse doesn't reject most garbage -- it happily parses "not a
      // url" as a relative path with no scheme/host -- so this has to be
      // checked explicitly rather than trusting Uri.tryParse alone.
      expect(isWellFormedServerUrl('not a url'), isFalse);
      expect(isWellFormedServerUrl('just-some-text'), isFalse);
    });

    test('rejects a scheme-less or host-less value', () {
      expect(isWellFormedServerUrl('n8n.example.com/webhook'), isFalse);
      expect(isWellFormedServerUrl('//n8n.example.com/webhook'), isFalse);
      expect(isWellFormedServerUrl('https://'), isFalse);
    });

    test('rejects a non-http(s) scheme', () {
      expect(isWellFormedServerUrl('ftp://example.com'), isFalse);
      expect(isWellFormedServerUrl('file:///etc/passwd'), isFalse);
    });
  });

  group('MissingServerUrlError', () {
    test('toString reports why the value was rejected and where to fix it',
        () {
      expect(
        MissingServerUrlError('empty or unfilled placeholder').toString(),
        contains('empty or unfilled placeholder'),
      );
      expect(
        MissingServerUrlError('not a valid http(s) URL').toString(),
        contains('assets/server.txt'),
      );
    });
  });
}
