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

  test('also parses the newer flat-array leaderboard shape (no '
      '[{"json": {"sorted": [...]}}] wrapper)', () {
    final json = {
      "user_rank": "12",
      "score": "19",
      "leaderboard": [
        {"Score": 501, "Pseudo": "mike", "rank": 1},
        {"Score": 501, "Pseudo": "jen", "rank": 1},
        {"Score": 19, "Pseudo": "wido", "rank": 12},
      ],
    };

    final result = parseLeaderboardResult(json);

    expect(result.userRank, 12);
    expect(result.entries, hasLength(3));
    expect(result.entries[0].pseudonym, 'mike');
    expect(result.entries[0].rank, 1);
    expect(result.entries[1].pseudonym, 'jen');
    expect(result.entries[1].rank, 1);
    expect(result.entries.last.pseudonym, 'wido');
  });

  test('parses a full real response: flat leaderboard, string-encoded '
      'completed_puzzles, and server-side skip-ranking on ties', () {
    final json = {
      "request_id": "c5a080a0-369c-4db5-bb4f-3413e677a287",
      "status": "success",
      "message": "User updated",
      "user_rank": "12",
      "score": "19",
      "completed_puzzles": "[500,392,240766]",
      "leaderboard": [
        {"Score": 501, "Pseudo": "mike", "rank": 1},
        {"Score": 501, "Pseudo": "jen", "rank": 1},
        {"Score": 501, "Pseudo": "zike", "rank": 1},
        {"Score": 491, "Pseudo": "shawn", "rank": 4},
        {"Score": 310, "Pseudo": "jon", "rank": 5},
        {"Score": 123, "Pseudo": "mcroy", "rank": 6},
        {"Score": 123, "Pseudo": "chris", "rank": 6},
        {"Score": 87, "Pseudo": "nolan", "rank": 8},
        {"Score": 79, "Pseudo": "allister", "rank": 9},
        {"Score": 23, "Pseudo": "tom", "rank": 10},
        {"Score": 22, "Pseudo": "lyse", "rank": 11},
        {"Score": 19, "Pseudo": "wido", "rank": 12},
        {"Score": 1, "Pseudo": "alock", "rank": 13},
        {"Score": 1, "Pseudo": "demo", "rank": 13},
        {"Score": 0, "Pseudo": "Steph", "rank": 15},
        {"Score": 0, "Pseudo": "test", "rank": 15},
      ],
    };

    final result = parseLeaderboardResult(json);

    expect(result.userRank, 12);
    expect(result.entries, hasLength(16));
    // Ranks pass through exactly as the server sent them, ties and skips
    // (1,1,1,4,5,6,6,8...) included -- no client-side reprocessing.
    expect(
      result.entries.map((e) => e.rank),
      [1, 1, 1, 4, 5, 6, 6, 8, 9, 10, 11, 12, 13, 13, 15, 15],
    );
    expect(
      parseCompletedPuzzleIds(json['completed_puzzles']),
      {'catalog-500', 'catalog-392', 'catalog-240766'},
    );
  });

  test('ranks are trusted as-is, even for entries tied on score -- the '
      'server deliberately doesn\'t give ties a shared rank', () {
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
            ],
          },
        },
      ],
    };

    final result = parseLeaderboardResult(json);

    expect(result.entries.map((e) => e.rank), [1, 2, 3, 4]);
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

  test('catalogPuzzleNumbers extracts bare numbers from catalog- ids, '
      'skipping anything else (tutorials, malformed ids)', () {
    expect(
      catalogPuzzleNumbers({'catalog-1', 'catalog-234', 'tutorial-1', 'catalog-not-a-number'}),
      unorderedEquals([1, 234]),
    );
    expect(catalogPuzzleNumbers({}), isEmpty);
  });

  test('parseCompletedPuzzleIds decodes a JSON-encoded-string array of '
      'numbers into catalog- ids', () {
    expect(
      parseCompletedPuzzleIds('[1,234,54]'),
      {'catalog-1', 'catalog-234', 'catalog-54'},
    );
  });

  test('parseCompletedPuzzleIds also accepts an already-decoded list', () {
    expect(parseCompletedPuzzleIds([1, 234, 54]), {'catalog-1', 'catalog-234', 'catalog-54'});
  });

  test('parseCompletedPuzzleIds returns an empty set for null/malformed '
      'input rather than throwing', () {
    expect(parseCompletedPuzzleIds(null), isEmpty);
    expect(parseCompletedPuzzleIds('not json'), isEmpty);
    expect(parseCompletedPuzzleIds('{"not": "a list"}'), isEmpty);
    expect(parseCompletedPuzzleIds(42), isEmpty);
  });

  test('parForCatalogPuzzles negates each puzzle\'s recorded par (golf '
      'convention: slots to spare is "under par"), 0 for anything not '
      'locally recorded, in the same order as the input list', () {
    expect(
      parForCatalogPuzzles(
        [662461, 140, 27],
        {'catalog-662461': 0, 'catalog-140': 2, 'catalog-27': 1},
      ),
      [0, -2, -1],
    );

    // No entry at all for 999 -- treated as exactly at par (0), not an error.
    expect(
      parForCatalogPuzzles([999], {}),
      [0],
    );
  });
}
