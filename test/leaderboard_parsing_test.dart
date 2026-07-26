import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/data/leaderboard.dart';

void main() {
  test('parses the n8n leaderboard response shape, including the wrapped '
      '[{"json": {"sorted": [...]}}] leaderboard field', () {
    final json = {
      "request_id": "c5a080a0-369c-4db5-bb4f-3413e677a287",
      "status": "success",
      "message": "User udpated",
      "user_rank": "14",
      "leaderboard": [
        {
          "json": {
            "sorted": [
              {"Score": 23434, "Pseudo": "steph", "rank": 1},
              {"Score": 5001, "Pseudo": "lol", "rank": 2},
              {"Score": 0, "Pseudo": "wido", "rank": 14},
            ],
          },
        },
      ],
    };

    final result = parseLeaderboardResult(json);

    expect(result.userRank, 14);
    expect(result.entries, hasLength(3));
    expect(result.entries[0].rank, 1);
    expect(result.entries[0].pseudonym, 'steph');
    expect(result.entries[0].score, 23434);
    expect(result.entries.last.pseudonym, 'wido');
    expect(result.entries.last.score, 0);
  });

  test('entries tied on score share the same rank, even when the server '
      'gave them sequential ranks instead', () {
    final json = {
      "user_rank": "1",
      "leaderboard": [
        {
          "json": {
            "sorted": [
              {"Score": 100, "Pseudo": "alice", "rank": 1},
              {"Score": 100, "Pseudo": "bob", "rank": 2},
              {"Score": 100, "Pseudo": "carol", "rank": 3},
              {"Score": 40, "Pseudo": "dave", "rank": 4},
              {"Score": 40, "Pseudo": "erin", "rank": 5},
              {"Score": 10, "Pseudo": "frank", "rank": 6},
            ],
          },
        },
      ],
    };

    final result = parseLeaderboardResult(json);

    expect(result.entries.map((e) => e.rank), [1, 1, 1, 4, 4, 6]);
  });

  test('returns an empty entry list when the leaderboard field is missing '
      'or malformed', () {
    expect(parseLeaderboardResult({'user_rank': '1'}).entries, isEmpty);
    expect(
      parseLeaderboardResult({'user_rank': '1', 'leaderboard': []}).entries,
      isEmpty,
    );
    expect(
      parseLeaderboardResult({
        'user_rank': '1',
        'leaderboard': [
          {'json': {}},
        ],
      }).entries,
      isEmpty,
    );
  });
}
