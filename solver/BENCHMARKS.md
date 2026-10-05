# Benchmarks

## Current status (2026-10-05)

| | Solved / 908 | Proven minimal |
|---|---|---|
| **Ledger: best of every run so far** (`solver/ledger.json`, details below) | **642** | 219 |
| One default run of the solver (`solver --all`, 20 M nodes, v1.8) | 544 | 187 |
| Known to have a solution (ledger, other solvers, top human players) | 907 | — |

The default run is what the solver does by itself in one pass; the ledger
adds the runs that only work on still-unsolved puzzles (longer exact
searches, seeded orderings, whole-program MCMC). #384 is the only puzzle
with no known solution in the sources checked. Campaign runs are still in
progress, so the ledger figures will grow.

Full-catalog runs: `assets/levels_catalog.json` (908 puzzles), release
build, 12 parallel jobs on an Intel Core i7-1255U, default `Config` unless
stated. The ledger's campaign runs used one niced core per queue.

These are **batch throughput** measurements: the i7-1255U is a laptop CPU
with 2 performance and 8 efficiency cores (12 threads) and may throttle, so
per-puzzle times depend on which core a puzzle lands on. Node and
instruction counts are exact and machine-independent; times are not.
Comparisons of small implementation changes (a few tens of percent) need a
single-job run on a fixed puzzle set, repeated, reporting the median; the
figures below marked "batch" were not measured that way.

Every reported solution was re-checked on the game's own interpreter with
`flutter test test/solver_solutions_test.dart` (exact step counts); the test
also checks `solver/ledger.json`, the best verified program per puzzle from
every run (see "Solution ledger" below). A solution is **proven minimal**
only when the output says `"optimal": true`; heuristic solutions are valid
but may be longer than necessary.

Difficulty is the catalog's player rating, rounded half away from zero.

## Solution ledger: every run combined

`solver/ledger.json` keeps the best verified program per puzzle from every
run, re-verified on the reference interpreter and on the game's own engine.
Runs beyond the default mode only work on puzzles the ledger has not
solved, so a stage can only add solutions (an ordering that "trades
puzzles" becomes a pure gain). Status on 2026-10-05, with the campaign
still running: **642 / 908**, of which 219 are proven minimal (cost equal
to a proven lower bound; earlier proofs whose runs were not kept are not
counted).

| Source | Puzzles added |
|---|---|
| Solver runs up to v1.6 (known programs) | 564 |
| v1.8 default run | 544 (union with the above: 571) |
| Research experiments: exact search 15–93 M nodes (14), seeded LDS (7), a deterministic 40 M run (2), whole-program MCMC (3) | +26 → 597 |
| Exact search to 2 × 10⁹ nodes on 19 short-program puzzles (15 tried, 4 already solved) | +15, all proven minimal (cost 9–12, 81 M–1.4 × 10⁹ nodes) |
| Seeded heuristic search, 20 M nodes, seeds 1–6 | +29 (per seed: 12, 2, 4, 4, 4, 3) |
| Whole-program MCMC (running) | +1 so far |
| Exact search with a per-puzzle budget, 160 M-node heuristic search, seeds 7– (running) | — |

A **seed** changes only the last tie-break of the LDS ranking (seed 0 is the
default order): the same algorithm in a different order. Seeds are not
better on average (dev set 39 and 39 against 40) but solve different
puzzles, and a few long runs beat many short ones (4 × 4 M solved more than
8 × 2 M). Yield per CPU-hour (new puzzles for the ledger, one niced core):

| Stage | New puzzles | CPU-hours | New per CPU-hour |
|---|---|---|---|
| Exact search to 2 × 10⁹ nodes | 15 | 0.65 | 23.0 |
| Seed 1 | 12 | 0.84 | 14.4 |
| Seeds 2–6 | 2–4 each | 0.62–0.66 each | 3.0–6.2 |

Runs that hit the 20 000-step limit used at most 5 % of the campaign's
instructions (3 % in the seeded runs), so loop-detection work would not
speed it up further.

By number of functions in the puzzle: 1 function 149 / 149, 2 functions
254 / 278, 3 functions 163 / 246, 4 functions 51 / 133, 5 functions
25 / 102. By the size of the shortest human solution: 319 / 319 (100 %) at
≤ 8 cells, 174 / 178 (98 %) at 9–10, 61 / 97 (63 %) at 11–12, 22 / 83 (27 %)
at 13–15, 7 / 75 (9 %) at 16–20, 3 / 31 (10 %) above 20, 56 / 125 unknown.
Of the 266 unsolved puzzles, 40 have a human solution of at most 12 cells,
36 of 13–14, 121 of 15 or more, and 69 have no recorded size.

**Other solvers and the best humans** (archived robozzle.com profiles,
collected by the research agents): the genetic-algorithm account robozlov
solved 618 of these puzzles, the evolutionary solver zlej-rob 234; the
three strongest human accounts solved 901, 856 and 736, together 904 (not
#294, #384, #573, #1623). Together with the ledger, 907 of the 908 puzzles
have a known solution; **#384 has none** in the sources checked.

### Oracle ablation: which structure is hard to find

For the 51 puzzles with at least 4 functions whose known solution uses at
least 3, the search was given facts about a known solution and the nodes to
the first solution were measured. Exact search ran at the known cost only
(20 M-node cap); FINDER at 5 M. Ratios are geometric means against no facts,
over the puzzles both runs solve.

| Facts given | Exact: solved (gained / lost) | Exact: nodes | FINDER: solved (gained / lost) | FINDER: nodes |
|---|---|---|---|---|
| none | 17 | 1× | 28 | 1× |
| number of functions | 17 (+0 / −0) | 0.93× | — | — |
| body lengths | 20 (+3 / −0) | 0.52× | — | — |
| call graph | 15 (+1 / −3) | 0.12× | 24 (+7 / −11) | 0.42× |
| call sites (which slot calls which function) | 27 (+12 / −2) | 0.002× | — | — |
| lengths + call graph | 16 (+3 / −4) | 0.085× | 27 (+8 / −9) | 0.44× |
| lengths + call sites | 34 (+19 / −2) | 0.0007× | 42 (+15 / −1) | 0.115× |

Call placement is the hidden variable: knowing it makes exact search
500–1 400× cheaper, while the number of functions tells nothing. It cannot
be bought cheaply, though: guessing a 4–5-function skeleton costs an
estimated 24–43 bits (every 4–5-function call graph in the known solutions
is unique, and bodies of 6 or more cells never recur across puzzles), and
even the full skeleton speeds up the heuristic phase only 8.7×, with 9 of
51 puzzles still unsolved: the contents of the other slots (conditions,
turns) remain a large cost. A structure-first search was therefore not
built. Partial facts can lose puzzles because many puzzles have several
solutions (#1806 has 17 known call graphs), so a fact taken from one
solution excludes the others.

### Chess-engine techniques: what transfers

A study of the Stockfish source (master 49ea5de: `search.cpp`,
`movepick.cpp`, `history.h`) sorted its techniques by their premises.
Alpha-beta, PVS, aspiration windows, null move, razoring, futility pruning,
ProbCut and singular extensions need an opponent and an evaluation
calibrated against a bound; here a leaf is only solved, dead or unknown,
and the star count is not calibrated (a near-solution may have to lose 16
stars on the way to a solution). Stockfish itself relaxes razoring,
singular extensions and reverse futility when it searches for a mate
(`seekMate`), the closest analogue to this search. Late move reductions are
what the LDS rank cost already does; the history heuristic is in use (the
Stockfish-style gravity tables measured worse, above). What transfers is
the method: several diverse searches at full budget (Lazy SMP: the seeds),
budget scaling tests, statistical tests before changing a default, and
extra effort where the ordering has no signal (exact escalation).

## Three benchmarks, kept separate

The product mode shares one node budget between exact search and the
heuristic, so a change can help one and hurt the other while the total
barely moves (puzzle #851 below is an example). Changes are therefore
judged on the benchmark they target:

| Benchmark | Command | Measures |
|---|---|---|
| **EXACT** | `--exact-only` | proof coverage: proven optima, lower bounds, nodes per budget |
| **FINDER** | `--heuristic-only` | solutions found (any cost), nodes to first solution |
| **PRODUCT** | default | what users get |

Development runs use a fixed **dev set** of 150 puzzles (120 puzzles the
product mode does not solve at 20 M nodes, sampled evenly by number of
functions and difficulty, then 30 it solves with the heuristic, as a
regression check) at 5 M nodes; the full catalog is used only to confirm a
change. At 5 M nodes on the dev set, v1.5 solved FINDER 26 / 150 (0 hard,
26 regression) and PRODUCT 20 / 150 (0 hard, 20 regression); v1.6 solves
FINDER 40 / 150 (11 hard, 29 regression) and PRODUCT 29 / 150 (6 hard, 23
regression).

## Default mode (20 M nodes per puzzle)

```sh
./target/release/solver ../assets/levels_catalog.json --all --out solutions.json
```

Deterministic: the limit is 20 million search nodes per puzzle, not time.
Since v1.7 the solver returns the **first** valid program it finds (FIND,
SPEC.md §17.1): exact search gets 10 % of each doubling round and the
heuristic phase (LDS with the decaying history heuristic, plus local
repair; SPEC.md §17.3, §17.5) the rest, and both resume where they stopped.
A program found by exact search is proven minimal; so is a heuristic
program whose cost equals the budget exact search has reached. Wall time
for the whole catalog: 27 minutes in v1.7 (v1.6: 34). v1.8 changed only the
loop detector, which cannot change the search (SPEC.md §12.4): its results
are identical to the table below, and it is faster on the slow puzzles
(section "v1.8" below); the whole catalog was not re-timed.

| Difficulty | Solved / total | Proven minimal |
|---|---|---|
| ★ | 7 / 7 | 7 |
| ★★ | 195 / 223 | 97 |
| ★★★ | 306 / 533 | 80 |
| ★★★★ | 34 / 134 | 2 |
| ★★★★★ | 2 / 11 | 1 |
| **All** | **544 / 908** | **187** |

- Time to the solution, on the 544 solved puzzles: median 178 ms (v1.6,
  whose time includes the proof phase: 811 ms), 90th percentile 10.6 s;
  234 are solved within 0.1 s, 366 within 1 s and 487 within 10 s. Nodes
  to the solution: median 206 k, 90th percentile 6.8 M.
- Solved within a smaller node limit (the search does not depend on the
  limit, so this is the same run cut earlier): 358 at 0.625 M, 396 at
  1.25 M, 438 at 2.5 M, 472 at 5 M, 506 at 10 M, 544 at 20 M: +34 to +42 per
  doubling.
- By the size of the shortest human solution (archived robozzle.com
  statistics, known for 783 puzzles): 313 / 319 (98 %) at ≤ 8 cells,
  134 / 178 (75 %) at 9–10, 33 / 97 (34 %) at 11–12, 16 / 83 (19 %) at
  13–15, 6 / 75 (8 %) at 16–20, 1 / 31 (3 %) above 20. The size of the
  program, not the board, is the wall.
- 170 solutions come from exact search (all proven minimal), 296 from LDS
  (6 to 28 slots, median 10) and 78 from local repair (7 to 28 slots,
  median 12); 17 of the heuristic ones are proven minimal because exact
  search had already exhausted every smaller budget.
- For the 357 solutions not proven minimal, `cost − lowerBound` is 1 to 22
  (median 4).
- By number of functions in the puzzle: 1 function 142 / 149, 2 functions
  221 / 278, 3 functions 129 / 246, 4 functions 36 / 133, 5 functions
  16 / 102.
- Against v1.6 (521 solved): +28 / −5. The 5 lost were found by exact
  search in v1.6 (cost 7 to 9). The price of not proving: on the 516
  puzzles both versions solve, v1.7's program is longer for 122 (no phase
  looks for a shorter one), and the lower bounds are lower (exact search
  gets 10 % of the nodes instead of half). `--prove-minimal --exact-share
  50` restores the v1.6 algorithm (v1.6: 521 solved, 399 proven minimal);
  with `--no-repair` it reproduces v1.6 node for node, and with repair the
  results can differ slightly because an interrupted repair is now resumed
  (SPEC.md §17.5).
- Seven puzzles were solved for the first time by any run; the union of all
  runs up to v1.7 was 571 (the ledger below now has more).
- The 17 rows proven minimal by the reached budget were rerun with the final
  binary (the same programs, steps and node counts; only `optimal`
  changed).
- Slow puzzles: in v1.7 a few timeouts took minutes (e.g. #1877: 822 s for
  20 M nodes, already 496 s in v1.6). The cause was the loop detector's own
  cost; v1.8 fixed it (14× faster on #1877, section "v1.8" below).

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
| + review fixes, P-SINGLE, P-RESERVE, D-DEFER-SET (v1.5) | 478 | 393 | Against the history row: +38 / −21 solved, lower bound higher on 282 puzzles. |
| + decaying history (v1.6 with `--no-repair`) | 513 | 399 | Against v1.5: +57 / −22 solved; 4-function puzzles 18 → 32. |
| + local repair (v1.6 default) | 521 | 399 | Against the previous row: +11 / −3 solved (all 11 found by repair); against v1.5: +61 / −18, 4-function puzzles 18 → 34. |
| FIND first, exact share 10 %, no proof phase (v1.7 default) | 544 | 187 | Against v1.6: +28 / −5; 5-function puzzles 12 → 16, 3-function 119 → 129. Time to the solution: median 178 ms. |
| **Faster loop detector (v1.8 default)** | **544** | **187** | Identical results by construction (SPEC.md §12.4); 4.1× less CPU on the 20 slowest puzzles. |

The union of all these runs solves 571 puzzles (7 of them only in the
v1.7 run): changing the search order trades some puzzles for others (for
example #851 was proven minimal when an early heuristic solution handed
exact search 19 M nodes, and timed out when the heuristic found nothing and
exact search had 10 M). Running several orderings, each at its full budget,
solves more; the ledger below does exactly that.

### Finder improvements in v1.6 (dev set, 5 M nodes)

| Change | FINDER (hard + regression) | PRODUCT (hard + regression) |
|---|---|---|
| v1.5 | 26 (0 + 26) | 20 (0 + 20) |
| Decaying history | 37 (9 + 28) | 29 (5 + 24) |
| Local repair | 29 (1 + 28) | 24 (0 + 24) |
| **Both (v1.6 default)** | **40 (11 + 29)** | **29 (6 + 23)** |

- **Decaying history** (SPEC.md §17.3): +13 / −2 against v1.5 in FINDER,
  +11 / −2 in PRODUCT. It changes only the order of the search, at no cost
  in nodes.
- **Local repair** (SPEC.md §17.5): +3 / −0 in FINDER and +4 / −0 in
  PRODUCT on its own; on top of the decaying history +3 / −0 in FINDER and
  +2 / −2 in PRODUCT. The two PRODUCT losses (#4725, #4605) needed 1.9 M
  and 2.3 M LDS nodes; with repair on, LDS got 1.8 M of the heuristic
  phase's 2.4 M. They are at the edge of the 5 M budget.
  Repair found 13 of the 40 FINDER solutions. On the 37 puzzles solved
  with and without repair, the cost is the same for 35, one shorter and
  one longer.
- The repair share was first counted against all nodes, so in PRODUCT
  repair could take half of the heuristic phase's nodes; it is now counted
  against the heuristic phase's nodes, as in FINDER (no change on the dev
  set).

History variants, FINDER on the 30 regression puzzles of the dev set:

| History variant | Solved |
|---|---|
| Plain maximum (v1.5) | 26 |
| Stockfish-style gravity table (bonus / malus) by (function, slot, decision) | 20 |
| Gravity table keyed by the previous decision (continuation history) | 22 |
| Gravity table keyed by the robot's tile color and the tile ahead | 22 |
| All three gravity tables / ranked after the walking distance | 21 / 24 |
| Maximum keyed by the previous decision | 27 |
| **Decaying maximum, ¼ per update** | **28** |
| Decaying maximum, ½ / ⅛ per update | 24 / 27 |
| Decaying maximum keyed by the tile color and the tile ahead | 28 |
| Decaying maximum keyed by the previous decision | 27 |
| Decaying maximum, dead kids decay their entry too | 26 |

On the whole dev set the two best variants tied (FINDER 37, PRODUCT 29);
the simpler one was kept. The gravity tables, which work well for move
ordering in chess, lose here, probably because a bonus / malus records how
often a decision helped and not how far it got, while the star count of
the best subtree is the signal that matters in RoboZZle.

Measured and not adopted (both trade puzzles rather than add them):

- **A portfolio of LDS orderings**, run round robin (different ranking
  keys, history on and off). Each ordering alone solved fewer than the
  default (FINDER 18–25 against 26); the best pair solved 30 against 26 on
  a 35-puzzle validation subset, +9 / −5, at a proportional cost in nodes.
  Measured on v1.5, before the decaying history.
- **Trace first, compress second** (for multi-function puzzles): a guided
  search in which every `Forward` must bring the robot one tile closer to
  the nearest remaining star (with some slack for detours), as a share of
  the heuristic budget. FINDER 27 against 26 (+5 / −4).

### v1.8: the loop detector was the bottleneck of the slow puzzles

A few timeouts took minutes (#1877: 822 s for 20 M nodes in v1.7). Telemetry
on the 20 slowest puzzles (default mode, 2 M nodes each) recorded, for every
normalization that died at the 20 000-step limit (6 312 of them):

- an exact repeat of the full state (position, direction, colors, stars,
  frame and caller stack) inside the normalization: **0**. A full-state
  check at every instruction would catch nothing, and could not: without a
  call, execution runs straight through a function body, so every endless
  run calls, and C-OBSERVE already compares full states at calls;
- no star collected in the last 10 000 steps: 98.8 %;
- the same position, direction and frame at a different stack depth: 38 %;
  about 300 distinct (physical state, frame) keys per 20 000-step window,
  and almost no paints. The robot walks the same small loop while recursion
  grows and shrinks the stack like a counter, so the full state does not
  recur within 20 000 steps.

The time went into the detector itself. Each call was compared with every
earlier observation of the same key, and each comparison walked the caller
chains: per executed instruction, 160 detector operations on #10581, 86 on
#1877, 15 on #4936, 11 on #283, quadratic in the length of the run. v1.8
compares chain hashes before walking, answers C-PUMP's ancestor test with
low-water marks of the stack depth, and in long normalizations compares a
call with the last 8 observations of its key and a Brent checkpoint only
(SPEC.md §12.2, §12.4). Detection cannot change the search (an undetected
endless loop still dies at the step limit), and indeed nothing changed:

| | v1.7 | v1.8 |
|---|---|---|
| Slow 20, 2 M nodes: results, node counts, loops and step-limit deaths detected, instructions | | identical |
| Slow 20: CPU time | 215 s | 53 s (4.1×) |
| #10581 / #1877 | 62.0 s / 29.6 s | 5.5 s / 2.1 s |
| Dev set (150 puzzles, default mode, 5 M nodes): results and node counts | | identical |
| Dev set: CPU time | 715 s | 494 s (1.45×) |

A "no star for K steps" cutoff (the way a human gives up on a program) was
not added: in the heuristic phase only, it would save at most about half of
the step-limit runs' instructions, about 6 % on the slow puzzles, and unlike
the detector it would change the search.

### v1.7: find first (measurements behind the new default)

**FINDER alone against the v1.6 default.** On the first 559 puzzles of the
catalog (a FINDER run at 20 M nodes, stopped there), FINDER alone solved
345 against 325 for the v1.6 default mode: +24 / −4. The four it missed were
all found by exact search, after 0.27, 0.73, 0.88 and 3.27 M exact nodes.
Over the whole v1.6 run, exact search needed a median of 50 k nodes for the
335 puzzles it solved, and 272 of them needed at most 1 M. Hence the v1.7
default: exact search gets 10 % of each portfolio round (`exact_share`), and
the first solution is returned without the proof phase (`--prove-minimal`
restores it). With `--exact-share 50 --prove-minimal --no-repair`, v1.7
reproduces v1.6 node for node (20 puzzles checked).

**Where the LDS spends its discrepancies.** Each known solution
(`oracle/known.json`: 1 342 verified programs for the 564 puzzles any run
has solved) was replayed through the LDS tree with the static ranking (no
history), recording the rank of the kid consistent with the program at
every decision. 558 of the 564 puzzles replay (6 end at a sibling that
solves the puzzle first). Minimum total discrepancy per puzzle:

| Functions used | Puzzles | Median | 75th pct. | 90th pct. |
|---|---|---|---|---|
| 1 | 171 | 11 | 16 | 22 |
| 2 | 231 | 14 | 21 | 27 |
| 3 | 111 | 13 | 23 | 30 |
| 4 | 32 | 20.5 | 36 | 45 |
| 5 | 13 | 22 | 36 | 45 |

Share of the total by decision type: deferred-condition cells 29.8 % (mean
rank 4.4), turns 19.4 %, calls to new functions 15.1 % (mean rank 2.2),
calls to introduced functions 10.0 %, condition choices 7.5 %, paints 6.1 %
(mean rank 3.6), narrowing a deferred cell 5.7 % (mean rank 3.8), forward
5.2 %, END 1.3 %.

**Ranking variants, dev set, FINDER, 5 M nodes** (v1.6: 40 / 150, 11 hard):

| Variant | Solved (hard) | Gained / lost | Nodes on puzzles both solve |
|---|---|---|---|
| New-function cost ≤ 1, ties cost ½ | 35 (8) | +4 / −9 | 0.48× |
| + deferred-condition cost ≤ 1 | 37 (11) | +7 / −10 | 0.49× |
| New-function cost ≤ 1, deferred cost ≤ 2 | 38 (12) | +8 / −10 | 0.54× |
| No used-slots tie-break | 34 (8) | +4 / −10 | 1.35× |

Capping the cost of the expensive decision types finds the puzzles it
solves about twice as fast, but loses others, including some v1.6 solves
in under 1 M nodes: a different order searches a different region. The
used-slots tie-break (between siblings it means "prefer END when tied")
helps. Running two orders side by side on half the budget each would solve
36: the puzzles need their whole budget. The v1.6 ranking stays.

**Near-solutions are far from solutions.** A FINDER run at 1 M nodes logged
every program admitted to the repair pool and a sample of those it
rejected, and their edit distance to the nearest known solution was
computed (minimum over relabelings of the auxiliary functions, Levenshtein
per function). On the 173 known puzzles FINDER did not solve within 1 M:
admitted programs are a median of 8 edits away (10th–90th percentile 6–14),
only 0.09 % are within 2 edits (what repair can reach), and the rejected
lower-star programs are farther still (median 10). Per puzzle, the closest
admitted program is within 2 edits for 7 % of the puzzles. A wider or more
diverse repair pool would therefore not help much: the search does not get
stuck one step short of a solution, it does not reach the right program
structure.

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
