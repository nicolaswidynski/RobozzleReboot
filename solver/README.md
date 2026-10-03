# RoboZZle solver

Finds, for a RoboZZle puzzle, a program that solves it in the app's engine
([`lib/engine/interpreter.dart`](../lib/engine/interpreter.dart)). Easy and
medium puzzles get a **proven shortest** program (fewest occupied slots);
for harder ones a heuristic phase finds a valid, not necessarily shortest,
program and reports a proven lower bound. Results are deterministic.

- [`SPEC.md`](SPEC.md): the normative specification (data model, transition
  rules, search, invariants, test vectors).
- [`DESIGN.md`](DESIGN.md): the rationale behind each rule (Turkish and
  English).
- [`BENCHMARKS.md`](BENCHMARKS.md): measured results on the bundled catalog.

## How it works, in one paragraph

Exact phase: iterative deepening on the number of occupied slots. Inside
each budget, a depth-first search synthesizes the program *while executing it*: the
interpreter runs until it reaches a slot nobody has decided yet, and only
then does the search branch. Decisions that are not yet observable are
postponed (a conditional cell's action until its color is first seen, and
`Any` vs. `current color` until the cell runs on another color). Branches
are cut only by rules with a proof in SPEC.md: exact loop and stack-pumping
detection, function symmetry, local equivalences, and the engine's
20 000-step limit. If that runs out of its share of the node budget, a
heuristic phase (limited discrepancy search) explores the same tree,
trying first the children that collect more stars, or whose decision led
to the most stars anywhere so far (a history heuristic), and shrinks the
program it finds. The two phases alternate and resume where they stopped. Every solution is re-run on an independent reference interpreter
before it is reported.

## Build and run

```sh
cd solver
cargo build --release

# One or more puzzles by sourceId
./target/release/solver ../assets/levels_catalog.json --id 195 --id 53

# The whole catalog (20 M nodes per puzzle, all CPUs), results to solutions.json
./target/release/solver ../assets/levels_catalog.json --all --out solutions.json

# Exact search only (every reported solution is proven shortest)
./target/release/solver ../assets/levels_catalog.json --all --exact-only --out solutions.json
```

`--node-limit N` sets the per-puzzle budget; the result depends only on it,
not on machine speed. `--timeout-ms` adds an optional wall-clock limit.

Progress and a per-difficulty summary go to stderr; the JSON result
(SPEC.md §26) goes to `--out` or stdout. `--jobs N` limits parallelism. The
`--no-*` flags switch off individual optimizations for experiments; they
never change which programs are found, only how fast (SPEC.md §16).

## Test

```sh
cd solver
cargo test                 # unit, differential and end-to-end tests (~10 s)

# From the repository root, after writing solver/solutions.json:
flutter test test/solver_solutions_test.dart
```

The Flutter test runs every solved program on the game's own interpreter and
requires the exact step count the solver reported. It is skipped when
`solver/solutions.json` does not exist.
