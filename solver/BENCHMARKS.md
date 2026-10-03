# Benchmarks

All runs: `assets/levels_catalog.json` (908 puzzles), release build, 12
parallel jobs on an Intel Core i7-1255U (laptop, 10 cores / 12 threads),
default `Config` unless stated. Every reported solution is minimal in
occupied slots (SPEC.md §22) and was re-checked on the game's own
interpreter with `flutter test test/solver_solutions_test.dart` (exact step
counts).

Difficulty is the catalog's player rating, rounded.

## Current result (10 s per puzzle)

```sh
./target/release/solver ../assets/levels_catalog.json --all --timeout-ms 10000 --out solutions.json
```

| Difficulty | Solved / total | Avg ms per puzzle | Search nodes | Instructions |
|---|---|---|---|---|
| ★ | 7 / 7 | 7 | 213 895 | 670 049 |
| ★★ | 160 / 223 | 3 514 | 1 222 044 936 | 8 502 563 606 |
| ★★★ | 177 / 533 | 7 179 | 7 172 533 880 | 46 229 954 518 |
| ★★★★ | 13 / 134 | 9 314 | 2 337 199 543 | 14 930 272 981 |
| ★★★★★ | 1 / 11 | 9 094 | 211 469 813 | 1 177 987 832 |
| **All** | **358 / 908** | 6 562 | 10 943 462 067 | 70 841 448 986 |

The other 550 puzzles timed out; none was proven unsolvable. Solved puzzles
take a median of 125 ms (90th percentile: 5.0 s).

Minimal cost of the solved puzzles:

| Cost | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|
| Puzzles | 2 | 15 | 46 | 78 | 101 | 71 | 33 | 10 | 2 |

The search is exponential in the minimal cost: each extra slot multiplies
the work by about 10 (median), so the unsolved puzzles are those whose
shortest program needs more than about 10–11 slots.

## Compared with brute force

A brute-force solver tries every program. To find a minimal program of cost
`K` it must try every left-packed program of cost ≤ `K`: with `O` choices
per slot (conditions × actions), that is `Σ splits(k) · O^k` programs. The
table compares that count with the search nodes the solver actually used on
the same solved puzzles (medians per cost).

| Minimal cost | Puzzles | Brute-force programs | Solver nodes | Ratio |
|---|---|---|---|---|
| 3 | 2 | 1.9 × 10³ | 75 | 27× |
| 4 | 15 | 7.0 × 10⁴ | 448 | 171× |
| 5 | 46 | 3.4 × 10⁶ | 5.2 × 10³ | 424× |
| 6 | 78 | 6.7 × 10⁷ | 3.2 × 10⁴ | 1.8 × 10³× |
| 7 | 101 | 2.8 × 10⁹ | 4.2 × 10⁵ | 7.2 × 10³× |
| 8 | 71 | 2.8 × 10¹⁰ | 2.5 × 10⁶ | 1.6 × 10⁴× |
| 9 | 33 | 8.5 × 10¹⁰ | 6.5 × 10⁶ | 2.7 × 10⁴× |
| 10 | 10 | 1.2 × 10¹² | 2.8 × 10⁶ | 2.3 × 10⁵× |

The gap grows with the cost. The extreme case is puzzle 158 (cost 10):
4.1 × 10¹⁴ programs for brute force, 2.0 × 10⁷ nodes (6 s) for the solver.
Even at an optimistic 10 million programs per second, brute force would
need about 1.3 years of CPU time for it.

Measured over the whole run, the solver processes 1.8 million nodes per
second per core (a node includes running the robot to the next decision),
and each extra slot multiplies the work by a median of 10.2 (10th–90th
percentile: 5.9–14.9), against 12–40 choices per slot for brute force.

## How we got here (2 s per puzzle)

Each row adds one change to the previous one.

| Change | Solved (2 s) | Note |
|---|---|---|
| First complete search (SPEC v1.0 rules) | — | On puzzles 53, 195 and 654: ~6 000 nodes/s, 1 750 instructions per node; 0 / 3 solved in 5 s. Non-tail recursion ran to the 20 000-step limit on almost every branch. |
| + C-PUMP (stack-pumping loop detection) | 239 / 908 | ~7.4 M nodes/s on the same three puzzles (~1 200×). |
| + D-PENDING / D-CHOOSE, P-CRASH, P-ENDDEAD | 290 / 908 | ★ puzzles: 74 → 9 ms on average. |
| + allocation-free candidate lists, linear-scan cycle detector | 289 / 908 | +18 % nodes per second; the solved count is the same within timing noise. |

## Ablation

Each optimization switched off on its own, on the 265 puzzles the default
configuration solves in ≤ 1 s, with a 10 s limit. Every run that solved a
puzzle found the same minimal cost (checked by the script). For runs with
timeouts, nodes and instructions are lower bounds: the search was cut off.

| Configuration | Solved | Search nodes | Instructions | Total time |
|---|---|---|---|---|
| all on (default) | 265 / 265 | 8.1 × 10⁷ | 4.9 × 10⁸ | 24 s |
| `--no-lazy-conditions` | 253 / 265 | 1.9 × 10⁹ (23×) | 5.4 × 10⁹ | 372 s |
| `--no-lazy-active-conditions` | 264 / 265 | 5.8 × 10⁸ (7.2×) | 2.8 × 10⁹ | 171 s |
| `--no-function-symmetry` | 265 / 265 | 9.2 × 10⁷ (1.14×) | 5.4 × 10⁸ | 39 s |
| `--no-peephole` | 265 / 265 | 1.4 × 10⁸ (1.7×) | 7.4 × 10⁸ | 51 s |
| `--no-cycle-detection` | 167 / 265 | 2.4 × 10⁷ | 6.7 × 10¹⁰ (137×) | 1 363 s |
| `--no-step-cut` | 265 / 265 | identical | identical | (timing noise) |

- **Lazy conditions** (`CondOnly`) and **lazy active conditions**
  (`Pending`) are the biggest wins: deciding a condition only when it becomes
  observable removes most of the branching.
- **Cycle detection** (C-OBSERVE + C-PUMP) does not reduce nodes; without it
  every looping branch runs to the 20 000-step limit, so time explodes.
- **Function symmetry** matters little here because most puzzles in this set
  have at most one function per capacity class.
- **P-STEPCUT** never fires on this set: with C-PUMP, no branch gets near
  20 000 steps. It stays as a cheap guarantee.
