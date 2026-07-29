import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/leaderboard_sync.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('syncIfDue does nothing (and touches no network) when not signed in',
      () async {
    // No stored identity in this fresh test -> AuthManager.instance
    // .isConnected reads false without needing any setup, and syncIfDue
    // checks that before it would otherwise call fetchLeaderboard.
    final synced = await LeaderboardSync.instance.syncIfDue();
    expect(synced, isFalse);
  });
}
