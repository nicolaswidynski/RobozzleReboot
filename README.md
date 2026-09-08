# Robozzle Reboot

A Flutter recreation of [Robozzle](https://robozzle.com/) — Igor Ostrovsky's
original robot-programming puzzle game — built with the original author's
agreement. Program a robot with drag-and-drop instructions (move, turn,
paint, call one of 5 subroutines) to collect every star on a grid. Any
instruction can be conditioned on the color of the tile the robot is
standing on, so a handful of slots can express surprisingly deep logic.

Available on the [App Store](https://apps.apple.com/us/app/robozzlereboot/id6792399726).

<p align="center">
  <img src="www/images/screenshot-play.png" alt="Robozzle Reboot gameplay screenshot" width="280" />
</p>

<p align="center">
  <img src="www/images/screenshot-menu.png" alt="Mode selection screen" width="220" />
  <img src="www/images/screenshot-campaign.png" alt="Campaign puzzle list" width="220" />
  <img src="www/images/screenshot-editor.png" alt="Puzzle editor" width="220" />
</p>

## Features

- **Campaign** — a curated set of puzzles sorted by difficulty, from first
  steps to genuine head-scratchers.
- **Community Puzzles** — the full scraped catalog (900+ puzzles),
  searchable and sortable by difficulty or popularity, with ratings from
  other players.
- **Daily Challenge** — the same featured puzzle for every player on a
  given day, solved through the exact same engine as everything else.
- **Editor** — design your own puzzles (grid, stars, colored tiles, start
  position), test your solution, then publish it to the community catalog.
- **Leaderboard** — sign in with Apple or Google, claim a pseudonym, and
  climb the global rankings. Points are difficulty-squared per solve, plus
  a bonus for solving with instruction slots to spare — the tightest
  program wins, not just *a* working one.
- **Tutorials** — a short hand-authored series that introduces each
  instruction one at a time.
- Automatic progress and program saving — pick up any puzzle right where
  you left off.

## How it works

Drag an instruction (or a color dot, for a condition) from the palette at
the bottom into a slot in one of the function rows (F1–F5) above it. Drag a
slot's contents out to clear it, or drag one slot onto another to move it.
Step advances the program one instruction at a time; the three speed
buttons run it continuously. Reset restarts the level with the same
program; the back arrow rewinds one step.

The engine ([`lib/engine/interpreter.dart`](lib/engine/interpreter.dart))
executes one visible instruction per step: movement, turning, painting,
star collection, subroutine calls (with tail-call handling so a
self-recursive loop doesn't grow the call stack), condition checks, crash
detection, and an infinite-loop guard.

## Project layout

- `lib/models/` — pure Dart data types with no Flutter dependency: grid
  tiles, tile colors, directions, instructions, levels, and the player's
  program.
- `lib/engine/interpreter.dart` — the interpreter described above.
- `lib/data/` — everything that isn't pure game logic: the bundled/scraped
  puzzle catalog and its background refresh, the backend API client,
  leaderboard/scoring, auth (Apple/Google sign-in), and the various local
  stores (progress, saved programs, ratings, editor drafts).
- `lib/widgets/` — the grid/robot renderer, the instruction palette, and
  the function (F1–F5) editor rows.
- `lib/screens/` — Campaign/Community Puzzles/Daily Challenge, the game
  screen itself, the puzzle editor, sign-in, leaderboard, and tutorials.
- `test/` — unit tests (engine, scoring, data parsing) and widget tests
  (drag-and-drop, navigation, live status displays).
- `www/` — the marketing site (also the source of the screenshots above).

## Running it

```
flutter pub get
flutter test        # run the unit + widget test suite
flutter run          # launch on a simulator or connected device
```

The bundled catalog, tutorials, and puzzle-solving engine all work fully
offline — nothing above needs a backend. Signing in, the Leaderboard,
Daily Challenge, and publishing from the Editor talk to a backend that
isn't part of this repo (a set of webhook endpoints — see
[`lib/data/robozzle_api_client.dart`](lib/data/robozzle_api_client.dart)
for the exact shape); those features need two local files, neither of
which is committed:

- `assets/server.txt` — the backend's base URL.
- `assets/robozzle_token.txt` — a bootstrap token shared with the backend.

Without them, everything else in the app still works — those specific
features fail with a clear error (`MissingServerUrlError` /
`MissingBootstrapTokenError`) instead of a confusing one.

## License

MIT — see [LICENSE](LICENSE). The bundled puzzle catalog
(`assets/levels_catalog.json`) is scraped community content credited to
Igor Ostrovsky and the original Robozzle's other contributors, not
original work covered by that license.
