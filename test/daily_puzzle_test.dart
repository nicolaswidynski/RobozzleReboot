import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/daily_puzzle.dart';

void main() {
  test('parseDailyPuzzleSourceId reads daily_puzzle whether it comes back '
      'as a number or a numeric string', () {
    expect(
      parseDailyPuzzleSourceId({
        'request_id': 'abc',
        'status': 'success',
        'message': 'Daily Puzzle',
        'daily_puzzle': 662461,
      }),
      662461,
    );
    expect(
      parseDailyPuzzleSourceId({'daily_puzzle': '662461'}),
      662461,
    );
  });

  test('parseDailyPuzzleSourceId returns null when the field is missing '
      'or not a number', () {
    expect(parseDailyPuzzleSourceId({}), isNull);
    expect(parseDailyPuzzleSourceId({'daily_puzzle': null}), isNull);
    expect(parseDailyPuzzleSourceId({'daily_puzzle': 'not-a-number'}), isNull);
  });
}
