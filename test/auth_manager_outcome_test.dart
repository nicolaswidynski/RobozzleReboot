import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/auth_manager.dart';

void main() {
  test(
      '200 (reconnection) and 201 (existing user) both mean a pseudonym is '
      'already set; only 202 (brand new user) means the prompt is needed',
      () {
    expect(outcomeForManageUserStatus(200), ManageUserOutcome.reconnected);
    expect(outcomeForManageUserStatus(201), ManageUserOutcome.existingUser);
    expect(outcomeForManageUserStatus(202), ManageUserOutcome.newUser);

    for (final outcome in [
      outcomeForManageUserStatus(200),
      outcomeForManageUserStatus(201),
    ]) {
      expect(outcome, isNot(ManageUserOutcome.newUser));
    }
  });
}
