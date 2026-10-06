# Learned LDS ordering (experimental)

`solver --policy policy/linear_b.json` orders the children of every frontier
of the heuristic phase (LDS) by a learned model instead of the static
ranking (SPEC.md §17.3). It only reorders: exact search, the pruning rules
and verification are unchanged, so a bad model can only make the search
slower, never wrong. The default is off.

The model is log-linear over the live children of a frontier, in the style
of Levin tree search with context models: each child has 14 binary
contexts (`features.py`, `kid_contexts`; the solver computes the same
strings in `src/policy.rs`), its logit is the sum of their weights, and
children are tried in decreasing logit order, ties by the static rank.

## Files

| File | What |
|---|---|
| `linear_b.json` | The canonical weights ("model B"): trained on engine-found programs of catalog and archive puzzles, train split only. |
| `features.py` | Feature schema (the 14 context templates) and the convex training objective. |
| `train.py` | Trains a weights file from `policy_dump` output; also writes `test_vectors.json`. |
| `evaluate.py` | Offline ordering metrics on a split (a quick filter, not the judge). |
| `build_corpus.py` | Collects the solved programs of solver output files into `policy_dump` input. |
| `convert_archive.py` | Converts the robozzle.com level archive into the catalog format. |
| `make_splits.py`, `splits.json` | The frozen family-level split (see below). |
| `test_vectors.json` | 500 rows checked by the solver's `t_policy_vectors` test (Rust and Python contexts and logits agree). |

The training dump tool is `src/bin/policy_dump.rs`: it verifies each known
program, rewrites its turn runs into the canonical form the search
generates, shrinks it, canonicalizes it (`src/canon.rs`) and replays it
through the LDS tree (`Solver::replay_dump`, which uses the same feature
functions as the search).

## Data

- **Puzzles.** The catalog (`assets/levels_catalog.json`, 908 puzzles) and
  the robozzle.com archive puzzles that are not in it (8,941;
  <https://github.com/lostmsu/RoboZZle.LevelArchive>, `levels.xml` at commit
  56d4d73, converted with `convert_archive.py`).
- **Programs.** Only programs found by our own solver ("engine"): on the
  catalog, every solved program of our runs (the ledger and the experiment
  outputs, 2,148 distinct programs on 715 puzzles); on the archive, the
  default solver at 2 M and 20 M nodes and a policy run (12,635 programs on
  6,450 puzzles). Programs written by an LLM planner are kept outside the
  repository; they are used only in the C/C10 ablations, never in
  `linear_b.json`.
- **Split.** `splits.json` groups puzzles into families (same author and
  title stem, or identical board) and puts each family wholly in train
  (70 %), validation (10 %) or test (20 %); sha256
  `d0096886a3bd3c2d44b246ee9acbb67287e6a8000061df15805d462403490188`.
  Models train on train, choices are made on validation, and **test is not
  used until a final comparison**. Do not regenerate the split.

## Reproducing `linear_b.json`

```sh
cd solver
cargo build --release

# Archive puzzles (once)
python3 policy/convert_archive.py levels.xml ../assets/levels_catalog.json archive.json

# Programs: solver outputs to {"<id>": [programs]} (one file per puzzle set)
python3 policy/build_corpus.py --catalog ../assets/levels_catalog.json --out catalog_progs.json \
    ledger.json 'runs/catalog/*.json'
python3 policy/build_corpus.py --catalog archive.json --out archive_progs.json 'runs/archive/*.json'

# Decision dumps
./target/release/policy_dump ../assets/levels_catalog.json catalog_progs.json dump_catalog.jsonl
./target/release/policy_dump archive.json archive_progs.json dump_archive.jsonl

# Train (train split), write the weights and the Rust test vectors
python3 policy/train.py --dump dump_catalog.jsonl --dump dump_archive.jsonl \
    --splits policy/splits.json --out policy/linear_b.json \
    --vectors 500 --vectors-out policy/test_vectors.json

# Offline check on validation (static ordering without --weights)
python3 policy/evaluate.py --dump dump_catalog.jsonl --dump dump_archive.jsonl \
    --splits policy/splits.json --split val --weights policy/linear_b.json
```

`--dump FILE:N` weights a file N times (the C10 ablation used the LLM
programs ×10). Requirements: Python 3 with numpy and scipy.

## How a model is judged

The real solver on the validation puzzles, against the current baseline,
at equal node budget and at equal wall-clock (solved within 0.1 s, 1 s,
…), reported by puzzle size (known program ≤ 12 cells, 13–15, 16+) and for
4–5-function puzzles. Offline metrics only filter candidates. Results are
in BENCHMARKS.md ("Learned LDS ordering").
