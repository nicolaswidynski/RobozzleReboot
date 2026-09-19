import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/rating_prompt_store.dart';

void main() {
  group('RatingPromptStore', () {
    test('does not show on the first or second launch', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();

      await store.recordLaunch();
      expect(await store.shouldShow(), isFalse);
      await store.recordLaunch();
      expect(await store.shouldShow(), isFalse);
    });

    test('shows on the third launch', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();

      for (var i = 0; i < RatingPromptStore.promptOnLaunch; i++) {
        await store.recordLaunch();
      }
      expect(await store.shouldShow(), isTrue);
    });

    test('once shown, never shows again on any later launch', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();

      for (var i = 0; i < RatingPromptStore.promptOnLaunch; i++) {
        await store.recordLaunch();
      }
      await store.recordShown();

      expect(await store.shouldShow(), isFalse);
      for (var i = 0; i < 50; i++) {
        await store.recordLaunch();
      }
      expect(await store.shouldShow(), isFalse);
    });

    test('still shows on a later launch if the third one never got to '
        'show it', () async {
      SharedPreferences.setMockInitialValues({'rating_prompt_launch_count': 7});
      expect(await RatingPromptStore().shouldShow(), isTrue);
    });

    test('an install that was already asked under the old scheme is never '
        'asked again', () async {
      SharedPreferences.setMockInitialValues({
        'rating_prompt_launch_count': 10,
        'rating_prompt_last_shown_at': 1,
      });
      expect(await RatingPromptStore().shouldShow(), isFalse);

      SharedPreferences.setMockInitialValues({
        'rating_prompt_launch_count': 10,
        'rating_prompt_rated': true,
      });
      expect(await RatingPromptStore().shouldShow(), isFalse);
    });
  });
}
