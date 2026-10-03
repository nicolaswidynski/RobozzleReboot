# Benchmarks

All runs: `assets/levels_catalog.json` (908 puzzles), release build, 12
parallel jobs on an Intel Core i7-1255U, default `Config` unless stated.

These are **batch throughput** measurements: the i7-1255U is a laptop CPU
with 2 performance and 8 efficiency cores (12 threads) and may throttle, so
per-puzzle times depend on which core a puzzle lands on. Node and
instruction counts are exact and machine-independent; times are not.
Comparisons of small implementation changes (a few tens of percent) need a
single-job run on a fixed puzzle set, repeated, reporting the median; the
figures below marked "batch" were not measured that way.

Every reported solution was re-checked on the game's own interpreter with
`flutter test test/solver_solutions_test.dart` (exact step counts). A
solution is **proven minimal** only when the output says `"optimal": true`;
heuristic solutions are valid but may be longer than necessary.

Difficulty is the catalog's player rating, rounded half away from zero.

## Default mode (20 M nodes per puzzle)

```sh
./target/release/solver ../assets/levels_catalog.json --all --out solutions.json
```

Deterministic: the limit is 20 million search nodes per puzzle, not time.
Exact search and the heuristic phase (LDS with the history heuristic,
SPEC.md §17.3) alternate in equal, doubling slices and both resume where
they stopped (SPEC.md §17.1). When the heuristic finds a solution, the rest
of the budget goes to exact search below its cost. Wall time for the whole
catalog: 29 minutes.

| Difficulty | Solved / total | Proven minimal |
|---|---|---|
| ★ | 7 / 7 | 7 |
| ★★ | 184 / 223 | 170 |
| ★★★ | 257 / 533 | 198 |
| ★★★★ | 29 / 134 | 17 |
| ★★★★★ | 1 / 11 | 1 |
| **All** | **478 / 908** | **393** |

- 133 solutions come from the heuristic phase (7 to 25 slots, median 11);
  48 of them were then proven minimal by the remaining exact search.
- For the 85 solutions not proven minimal, `cost − lowerBound` is 1 to 16
  (median 4).
- The 430 timeouts all have a proven lower bound: minimal cost ≥ 7 (51
  puzzles), 8 (318), 9 (42), 10 (11), 11 (2), 12 (4), 13 (1), 14 (1).
- By number of functions in the puzzle: 1 function 140 / 149, 2 functions
  206 / 278, 3 functions 105 / 246, 4 functions 18 / 133, 5 functions
  9 / 102. Multi-function puzzles remain the main open problem.

### How the heuristic phase evolved (20 M nodes per puzzle, except the first row)

Each row is a full catalog run; puzzle-by-puzzle comparisons in the notes.

| Version | Solved | Proven minimal | Notes |
|---|---|---|---|
| Exact only (10 s wall clock) | 358 | 358 | Baseline; times out from cost ~10. |
| Exact first (10 M), then heuristic (10 M) | 443 | 353 | +95 new, −10 that exact needed 10–18 M nodes for. |
| Portfolio, exact : heuristic = 2 : 1, resumable | 436 | 365 | Recovered 6 of those 10, but lost 13 heuristic solutions that needed 5–9 M heuristic nodes: a heuristic node was worth ~2× an exact node at the margin. |
| Portfolio 1 : 1 | 444 | 362 | |
| Portfolio 1 : 1 + history heuristic | 461 | 367 | +41 / −24 against the previous row; ★★★★ 24 → 31, 3-function puzzles 84 → 98. |
| + anonymous auxiliary functions (first version) | 460 | 372 | Lower bound higher on 73 puzzles, lower on none; +4 / −5 solved (heuristic reordering). |
| **+ review fixes, P-SINGLE, P-RESERVE, D-DEFER-SET** | **478** | **393** | Against the history row: +38 / −21 solved, lower bound higher on 282 puzzles. |

The union of all these runs solves 502 puzzles: changing the search order
trades some puzzles for others (for example #851 was proven minimal when an
early heuristic solution handed exact search 19 M nodes, and timed out when
the heuristic found nothing and exact search had 10 M). Running several
orderings would therefore solve more, at a proportional cost in nodes.

### Exact-search tree size: anonymous auxiliary functions

On the 250 puzzles whose auxiliary functions have at least two distinct
capacities (exact search only, 5 M nodes each, first version without the
review fixes), the number of nodes needed to exhaust a budget fell by a
median factor of 1.84 (10th–90th percentile 1.49–2.81, max 7.8, 604
budgets), and the proven lower bound rose on 58 puzzles. An adversarial
review then showed that the first version could be up to 2 % larger on
some budgets (nodes whose only child is END, lost tail calls); after its two
fixes (close a body as soon as INV-FIT forbids growth; stronger P-ENDDEAD)
every reported case is smaller than or equal to the labelled search, for
example #1191 at budget 7: 933 530 nodes against 946 948.

### Conflict learning, measured and rejected

SAT-style nogood learning with backjumping was evaluated before building
it. On 1.82 M dead leaves of 16 exactly solved puzzles, a sound reason set
contained 99.6 % (crash), 99.1 % (program ended) and 98.7 % (loop) of the
path's decisions, and 100 % on paint-free hard puzzles; classic
conflict-directed backjumping saved 1.8 % and 0.1 % of nodes. In lazy
synthesis every decided cell executes before the failure and every
executed instruction affects the pose or the control flow, so learned
clauses are nearly whole paths that never recur. The only real
generalization (between deferred color siblings) is obtained more cheaply
by D-DEFER-SET.

### Failure analysis that led to the history heuristic

On a stratified sample of 30 timed-out puzzles, telemetry recorded the best
progress the heuristic reached:

- In many puzzles, dead branches had collected far more stars than any live
  branch (e.g. #155: 86 / 89 dead vs 48 / 89 alive; #294: 132 / 145 vs
  100 / 145). The search reached near-solutions that crashed at the end and
  then forgot them, because a dead branch has no children.
- Single-star puzzles (#4899 "My first maze") give the star count no
  gradient at all.
- Solve rate falls steeply with the number of functions.

The history heuristic addresses the first point: it remembers the best
progress below each decision, dead branches included, and tries those
decisions first. On the 30-puzzle sample it solved 3 against 0 without it.

## Exact-only mode (10 s per puzzle)

```sh
./target/release/solver ../assets/levels_catalog.json --all --exact-only --timeout-ms 10000 --out solutions.json
```

(Run before the heuristic phase existed, with a 10 s wall-clock limit, so
the result depends on machine speed.)

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

A timeout still proves something: every budget below the one being searched
when time ran out was searched exhaustively, so no shorter program exists.
For the 550 timeouts, the proven lower bound on the minimal cost was:

| Proven: minimal cost ≥ | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|
| Puzzles | 1 | 198 | 294 | 40 | 10 | 5 | 1 | 1 |

Minimal cost of the solved puzzles:

| Cost | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|
| Puzzles | 2 | 15 | 46 | 78 | 101 | 71 | 33 | 10 | 2 |

The search is exponential in the minimal cost: each extra slot multiplies
the work by about 10 (median). Timeouts become dominant as the search
reaches the cost-10/11 regime. Many timed-out puzzles are likely to need
longer programs (their median slot capacity is 18, against 8 for the solved
ones), but a timeout does not establish their minimal cost; some may have a
short solution in a hard-to-search space.

## Compared with brute force

A brute-force solver tries every program. To find a minimal program of cost
`K` it must try every left-packed program of cost ≤ `K`: with `O` choices
per slot (conditions × actions), that is `Σ splits(k) · O^k` programs. The
table compares that count with the search nodes the solver actually used on
the same solved puzzles. The two count columns are medians per cost; the
**ratio is the median of the per-puzzle ratios**, not the ratio of the two
displayed medians.

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
| + allocation-free candidate lists, linear-scan cycle detector | 289 / 908 | About +18 % nodes per second (batch measurement, not a controlled benchmark); the solved count is the same within timing noise. |

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
