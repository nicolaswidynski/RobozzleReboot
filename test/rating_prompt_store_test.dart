import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/rating_prompt_store.dart';

void main() {
  group('RatingPromptStore', () {
    test('does not show before the 5th completed puzzle', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();
      expect(await store.shouldShow(4), isFalse);
    });

    test('shows the first time completedCount reaches 5, having never shown before',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();
      expect(await store.shouldShow(5), isTrue);
      expect(await store.shouldShow(20), isTrue); // still true well past 5
    });

    test('does not re-show again right after being shown', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();
      await store.recordShown();
      expect(await store.shouldShow(10), isFalse);
    });

    test('re-shows once the reminder interval has fully elapsed', () async {
      final longAgo = DateTime.now()
          .subtract(RatingPromptStore.reminderInterval)
          .subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        'rating_prompt_last_shown_at': longAgo.millisecondsSinceEpoch,
      });
      final store = RatingPromptStore();
      expect(await store.shouldShow(10), isTrue);
    });

    test('does not re-show before the reminder interval has elapsed', () async {
      final recently = DateTime.now()
          .subtract(RatingPromptStore.reminderInterval)
          .add(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'rating_prompt_last_shown_at': recently.millisecondsSinceEpoch,
      });
      final store = RatingPromptStore();
      expect(await store.shouldShow(10), isFalse);
    });

    test('never shows again once the player has rated', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RatingPromptStore();
      await store.recordRated();
      expect(await store.shouldShow(1000), isFalse);
    });
  });
}
