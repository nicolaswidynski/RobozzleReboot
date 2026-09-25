# Robozzle Solver — Technical Specification

| | |
|---|---|
| **Version** | 1.0-draft |
| **Status** | Normative implementation specification |
| **Engine** | `lib/engine/interpreter.dart` at commit `37b5ede` |
| **Rationale** | [`DESIGN.md`](DESIGN.md) (why each rule exists, alternatives considered) |

This document states **what the solver must do**. It is written as a mini
RFC: a data model, formal transition rules, the search algorithm, invariants,
and conformance test vectors. [`DESIGN.md`](DESIGN.md) explains *why*; this
file is the contract. If the two disagree, this file wins, and both are fixed
in the same change.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT** and **MAY**
are used as in RFC 2119. Rule identifiers (`R-*`, `N-*`, `S-*`, `C-*`, `D-*`,
`P-*`, `INV-*`, `TV-*`, `t_*`) are stable; code comments and test names refer
to them.

**Contents**

- Part I — Data model: §1–§7
- Part II — State-transition rules: §8–§13
- Part III — Search algorithm: §14–§20
- Part IV — Invariants and correctness: §21–§23
- Part V — Conformance: §24–§26
- Appendices: A (CLI), B (module layout and implementation order), C (non-goals), D (traceability)

---

# Part I — Data model

## 1. Constants and primitive types

```rust
pub const MAX_FUNCTIONS: usize = 5;
pub const MAX_FUNCTION_SLOTS: usize = 12;  // the app's editor allows 12 (editor_screen.dart:45)
pub const MAX_TILES: usize = 256;          // rows × cols; the editor allows 14×14 = 196
pub const MAX_STEPS: u32 = 20_000;         // interpreter.dart:93

pub type TileId = u8;   // row * cols + col; MAX_TILES = 256 makes u8 exact
pub type FnId = u8;     // 0..=4, F1 = 0

#[repr(u8)] pub enum Color { Red = 0, Green = 1, Blue = 2 }
#[repr(u8)] pub enum Direction { Up = 0, Right = 1, Down = 2, Left = 3 }

pub enum Condition { Any, Color(Color) }
pub enum Action { Forward, TurnLeft, TurnRight, Paint(Color), Call(FnId) }
pub struct Instruction { pub condition: Condition, pub action: Action }
```

All of these types MUST be `Copy`.

- `Direction::left(d) = (d + 3) % 4`, `Direction::right(d) = (d + 1) % 4`.
- Movement deltas `(dRow, dCol)`: `Up = (-1, 0)`, `Right = (0, 1)`,
  `Down = (1, 0)`, `Left = (0, -1)`. Row 0 is the top row.
- `Condition::Any` matches every tile. `Condition::Color(c)` matches a tile
  whose current color is `c`.

The specification is parametric in `MAX_STEPS`: every rule and proof holds
for any positive value. Tests and prototypes MAY use a smaller value; the
shipped solver MUST use 20 000.

## 2. Static puzzle

### 2.1 Input

A puzzle is a catalog entry (`assets/levels_catalog.json`) or an editor
puzzle with the same fields:

| Field | Meaning |
|---|---|
| `sourceId` | Integer id. |
| `rows` | List of strings. `' '` or `'.'` = gap; `r g b` = tile of that color; `R G B` = tile of that color with a star. |
| `startRow`, `startCol` | Start tile. |
| `startDirection` | `up`, `right`, `down` or `left`. |
| `slotsPerFunction` | Five capacities, `cap[0..5]`. |
| `allowedCommands` | Paint bitmask: `1` = red, `2` = green, `4` = blue. Other bits are ignored. |

### 2.2 Validation

The loader MUST reject a puzzle with `Unsupported(reason)` if any of these
holds, and MUST NOT panic or truncate:

1. `rows` is empty, or rows differ in length, or `rows × cols > MAX_TILES`;
2. a row contains a character other than `' ' . r g b R G B`;
3. the start tile is outside the grid or is a gap;
4. `startDirection` is not one of the four names;
5. `slotsPerFunction` does not have exactly 5 entries, any entry exceeds
   `MAX_FUNCTION_SLOTS`, or `cap[0] == 0`.

One rejected puzzle MUST NOT prevent other puzzles from being solved.

A puzzle with no stars is valid. The empty program solves it (§17).

### 2.3 Compiled form

The loader MUST compile a valid puzzle once into an immutable
`StaticPuzzle`; the search hot path MUST NOT use row/column arithmetic.

```rust
pub struct StaticPuzzle {
    pub source_id: u32,
    pub tile_count: u16,                       // rows × cols, gaps included
    pub is_tile: [bool; MAX_TILES],
    pub neighbors: [[Option<TileId>; 4]; MAX_TILES], // None: off grid or gap
    pub initial_colors: PackedColors,          // gaps: unspecified, never read
    pub initial_stars: StarSet,
    pub start_tile: TileId,
    pub start_direction: Direction,
    pub capacities: [u8; MAX_FUNCTIONS],
    pub allowed_paints: ColorMask,
    pub possible_colors: ColorMask,            // §2.4
    pub function_classes: FunctionClasses,     // §2.5
}
```

`ColorMask` uses bit `1 << (color as u8)`, which is the same layout as
`allowedCommands`.

`StaticPuzzle` is never copied during search, so its container types are not
normative (for example `neighbors` MAY be a `Vec`); its fields and their
meaning are.

### 2.4 Possible colors

```text
possible_colors = { color of every tile at load time } ∪ allowed_paints
```

A tile can never have a color outside this set.

### 2.5 Function classes

The functions `F2..F5` with `cap > 0` are partitioned into **capacity
classes**: two functions are in the same class if and only if their
capacities are equal. `F1` belongs to no class. Each class is ordered by
function index.

Example: `cap = [7, 4, 2, 4, 2]` gives the classes `{F2, F4}` and `{F3, F5}`.

### 2.6 Connectivity (P-CONN)

If some star tile is not reachable from the start tile through tile
adjacency, the puzzle MUST be reported `Unsolvable(Disconnected)` without
searching. Painting never changes adjacency, so this check MUST run once,
before the search, and never during it.

## 3. Program model

### 3.1 Cells and functions

```rust
pub enum Cell {
    Unused,                 // storage filler only; has no program meaning
    Resolved(Instruction),  // a complete instruction
    CondOnly(Color),        // an occupied slot whose condition is chosen
                            // and whose action is not yet chosen
}

pub struct FunctionDraft {
    pub cells: [Cell; MAX_FUNCTION_SLOTS],
    pub len: u8,       // cells[0..len) are the decided cells
    pub capacity: u8,  // cap[f]
    pub ended: bool,   // true: every slot at index >= len is empty
}

pub struct PartialProgram { pub functions: [FunctionDraft; MAX_FUNCTIONS] }
```

A `FunctionDraft` MUST satisfy, at all times:

- every cell in `cells[0..len)` is `Resolved` or `CondOnly` (never `Unused`);
- every cell in `cells[len..]` is `Unused`;
- `len <= capacity`;
- `capacity == 0` implies `ended == true` (an absent function is closed).

There is no "unknown" cell and no "empty" cell: the representation is a
**left-packed prefix** plus a flag.

- If `len < capacity && !ended`, slot `len` is **open**: not yet decided.
- If `ended`, all slots from `len` on are empty.

### 3.2 Derived predicates

```text
closed(f)        := functions[f].ended || functions[f].len == functions[f].capacity
exhausted(f, pc) := pc == functions[f].len && closed(f)
```

A frame `(f, pc)` with `exhausted(f, pc)` definitely has no instruction left
to execute.

### 3.3 Physical form

The **physical program** is what the game stores (Dart's `RobotProgram`):

```rust
pub struct ResolvedProgram { pub functions: [Vec<Option<Instruction>>; MAX_FUNCTIONS] }
```

For a partial program with no `CondOnly` cells:

```text
physical(f) = [Some(i) for Resolved(i) in cells[0..len)] ++ [None; capacity - len]
```

**Lemma L1 (left packing).** Moving the `None` slots of a physical function
to its end does not change execution: `None` slots are skipped for free
(R-NULL), the tail-call test (R-TAIL) only asks whether any non-`None` slot
remains, and no instruction addresses a slot index. Hence every physical
program has a left-packed form with identical behavior and cost, and
searching only left-packed forms loses no solution.

## 4. Machine

### 4.1 Board state

```rust
pub struct PackedColors { words: [u64; 8] }   // 2 bits per tile: MAX_TILES × 2 = 512 bits
pub struct StarSet { words: [u64; 4] }        // 1 bit per tile
```

`PackedColors` encodes `Red = 0`, `Green = 1`, `Blue = 2`; the value `3`
MUST never be stored. Because 64 is divisible by 2, a tile's two bits never
straddle a word boundary.

### 4.2 Frames and the machine

```rust
pub struct Frame { pub function: FnId, pub pc: u8 }

pub struct Machine {
    pub position: TileId,
    pub direction: Direction,
    pub colors: PackedColors,
    pub stars: StarSet,
    pub current: Option<Frame>,    // the running frame
    pub callers: Option<NodeId>,   // top of the suspended-caller chain (§5)
    pub steps: u32,
    pub physical_hash: u128,       // §7.1
}
```

The **logical call stack** of a machine is, from bottom to top:

```text
stack(M) = chain(M.callers) ++ [M.current]      (the last element omitted if current is None)
```

where `chain(None) = []` and `chain(Some(id)) = chain(arena[id].parent) ++ [arena[id].frame]`.

`Machine` MUST NOT own a heap-allocated stack.

## 5. Stack arena

```rust
pub struct NodeId(pub u32);

pub struct StackNode {
    pub frame: Frame,
    pub parent: Option<NodeId>,
    pub depth: u16,     // number of frames in chain(Some(this)); ≤ MAX_STEPS
    pub hash: u128,     // stack_hash(parent.hash or 0, frame), §7.2
}

pub struct StackArena { nodes: Vec<StackNode> }
```

- Nodes MUST be immutable once created.
- `push(parent, frame) -> NodeId`, `get(id) -> &StackNode`, `mark() -> usize`
  and `truncate(mark)` MUST each be O(1) (amortized for `push`).
- `depth` fits in `u16`: every push is caused by a call, every call consumes
  a step, and at most `MAX_STEPS` steps are consumed on any path.

The running frame is deliberately **not** in the arena: advancing `pc`
changes only `Machine.current` and never allocates.

## 6. Search state and solver context

```rust
#[derive(Clone, Copy)]
pub struct SearchState {
    pub program: PartialProgram,
    pub machine: Machine,
    pub used_slots: u8,            // INV-COST
    pub introduced_functions: u8,  // bit f set: F(f+1) is introduced (§14.4)
}

pub struct Solver {
    pub puzzle: StaticPuzzle,
    pub config: Config,       // §16
    pub limits: Limits,       // time and node limits
    pub stack_arena: StackArena,
    pub stats: SearchStats,   // §20
}
```

- `SearchState` MUST be `Copy` and MUST NOT own heap memory.
- A child branch is created by **copying** the parent's `SearchState`
  ("copy-make"). The implementation SHOULD NOT use an undo trail unless
  profiling shows copying to be a bottleneck.
- `Config`, `Limits`, `SearchStats` and `StackArena` MUST NOT be part of
  `SearchState`.
- The arena is shared by all branches and is rewound with
  `mark` / `truncate` (§17.2). This is not an undo log: it discards immutable
  nodes that only the finished child could reference.

## 7. Hashing

### 7.1 Physical hash (Zobrist)

The implementation MUST maintain `Machine.physical_hash` as:

```text
physical_hash = ROBOT[position][direction]
              ⊕ ⨁ { STAR[t]            : t ∈ stars }
              ⊕ ⨁ { COLOR[t][colors[t]] : t is a tile }
```

`ROBOT`, `STAR` and `COLOR` are tables of `u128` values generated from a
**fixed seed** (for example two `splitmix64` draws per entry). Moving,
turning, painting and collecting a star MUST update the hash incrementally
with XOR. The root state's hash MUST be computed from the puzzle, not left
as zero.

### 7.2 Stack hash

```text
node.hash       = mix(parent_hash, frame)        parent_hash = 0 for a root node
stack_key_hash  = mix(hash(M.callers), M.current)
key_hash(M)     = mix(physical_hash, stack_key_hash)
```

`mix` is any fixed, deterministic 128-bit mixing function (the constants
are not normative).

### 7.3 Determinism

All hash tables and seeds MUST be deterministic across runs. No search
decision may depend on the iteration order of a hash map. The same input
and `Config` MUST produce the same `SolveResult` and the same statistics.

---

# Part II — State-transition rules

## 8. Reference semantics (engine contract)

This is an exact restatement of `interpreter.dart`. Numbers in parentheses
are line numbers in that file. `REFERENCE_RUN` operates on a
`ResolvedProgram` and knows nothing about synthesis.

```text
REFERENCE_RUN(puzzle, program, steps0 = 0):                    # R-RUN
    pos, dir, colors, stars := puzzle start state
    steps := steps0
    stack := [(F1, 0)] if cap[F1] > 0 else []                   (112)
    if stars = ∅: return SUCCESS                                (111)
    loop:
        if stack = []:                                          (185)
            return SUCCESS if stars = ∅ else OUT_OF_INSTRUCTIONS
        (f, i) := top(stack)
        if i >= cap[f]: pop(stack); continue                    (193)  # R-POP
        slot := program[f][i];  top(stack).i += 1
        if slot = None: continue                                (202)  # R-NULL
        steps += 1                                              (206)  # R-STEP
        if steps > MAX_STEPS: return STUCK                      (207)
        if slot.condition = Color(c) and colors[pos] ≠ c:       (221)  # R-COND
            continue
        match slot.action:
            Call(g):
                if cap[g] = 0: continue                         (232)  # R-CALL0
                if program[f][top(stack).i ..] are all None:    (240)  # R-TAIL
                    pop(stack)
                push(stack, (g, 0))
            TurnLeft:  dir := left(dir)
            TurnRight: dir := right(dir)
            Paint(c):  colors[pos] := c
            Forward:                                            (271)
                n := neighbor(pos, dir)
                if n = None: return CRASHED                     (279)
                pos := n
                if n ∈ stars: stars := stars \ {n}
                if stars = ∅: return SUCCESS                    (288)
```

Consequences that implementations MUST reproduce:

- **R-STEP:** the step limit is checked **before** the condition and
  **before** the action. The instruction that would be step `MAX_STEPS + 1`
  has no effect: the robot does not move and no star is collected.
- A condition-mismatched instruction consumes a step (R-COND).
- A call to a function with `cap = 0` consumes a step and does nothing
  (R-CALL0).
- `None` slots and function returns consume no step.
- A star is collected only when the robot **enters** its tile.
- Stack depth is unbounded; the solver MUST NOT add a depth limit.

## 9. Step consumption

```rust
impl Machine {
    pub fn consume_instruction(&mut self) -> Result<(), DeadReason> {
        self.steps += 1;
        if self.steps > MAX_STEPS { Err(DeadReason::StepLimit) } else { Ok(()) }
    }
}
```

This function MUST be the only code that modifies `Machine.steps` (test
fixtures that preset `steps` excepted). It MUST be called for every
evaluated occupied cell, before its condition is tested and before its
action runs.

## 10. Normalization

`normalize(puzzle, arena, config, stats, state: &mut SearchState) -> NormalizeResult`
executes the partial program deterministically until it cannot continue
without a synthesis decision.

```rust
pub enum DeadReason { Crash, ProgramEnded, StepLimit, Loop }

pub enum NormalizeResult {
    Solved,
    Dead(DeadReason),
    OpenSlot   { function: FnId, index: u8 },
    NeedAction { function: FnId, index: u8, condition: Color },
}
```

**Preconditions.** `state` satisfies INV-PREFIX, INV-COST and INV-STACK
(§21).

**Postconditions.**

- `normalize` MUST NOT modify `state.program` (INV-PURE).
- On `OpenSlot` or `NeedAction`, `current` points at the frontier cell, and
  that cell has consumed no step (INV-FRONTIER).
- On `Dead`, only `steps`, `position`, `direction`, `colors` and `stars` are
  meaningful; the stack is unspecified.

### 10.1 Transition table

At each iteration, the **first** rule whose guard holds fires. Let
`(f, pc) = current`, `D = program.functions[f]`, `tile = colors[position]`.

| Rule | Guard | Effect | Steps |
|---|---|---|---|
| **N-SOLVED** | `stars = ∅` | return `Solved` | 0 |
| **N-NOFRAME** | `current = None` | return `Dead(ProgramEnded)` | 0 |
| **N-RETURN** | `pc == D.len` and `closed(f)` | S-POP (§11.3) | 0 |
| **N-OPEN** | `pc == D.len` and not `closed(f)` | return `OpenSlot{f, pc}` | 0 |
| **N-NEED** | `D.cells[pc] = CondOnly(c)` and `tile == c` | return `NeedAction{f, pc, c}` | 0 |
| **N-SKIP** | `D.cells[pc] = CondOnly(c)` and `tile ≠ c` | `consume_instruction()?`; `pc += 1` | 1 |
| **N-EXEC** | `D.cells[pc] = Resolved(i)` | `consume_instruction()?`; `pc += 1`; if `i.condition` matches `tile`, apply the X-rule for `i.action` | 1 |

`consume_instruction()?` means: on `Err(StepLimit)`, return
`Dead(StepLimit)` immediately.

### 10.2 Action rules

Applied by N-EXEC after the step is consumed, `pc` has advanced, and the
condition has matched.

| Rule | Action | Effect |
|---|---|---|
| **X-FORWARD** | `Forward` | `n = neighbors[position][direction]`; if `None`, return `Dead(Crash)`; else `position = n`, and if `n ∈ stars`, remove it. Update `physical_hash`. |
| **X-TURN** | `TurnLeft` / `TurnRight` | `direction = left/right(direction)`. Update `physical_hash`. |
| **X-PAINT** | `Paint(c)` | `colors[position] = c`. Update `physical_hash`. |
| **X-CALL** | `Call(g)` | S-CALL (§11.1), then C-OBSERVE (§12) if `config.cycle_detection`. |

The solver never creates `Call(g)` with `cap[g] == 0` (P-DISABLED), so R-CALL0
has no counterpart in `normalize`. `REFERENCE_RUN` MUST still implement it.

**Lemma L2 (frontier).** On `OpenSlot` / `NeedAction`, the machine is in
the state immediately before the frontier cell would be evaluated. After the
search decides the cell, `normalize` evaluates it exactly as the engine
would, so each occupied cell is counted exactly once.

**Lemma L3 (resumption).** Execution up to a frontier never read the cell
being decided (reading it would have stopped execution there). Every child
branch MAY therefore resume from a copy of the frontier machine.

**Lemma L4 (equivalence).** If every cell of `P` is `Resolved` and
`normalize` returns `Solved`, `Dead(Crash)`, `Dead(StepLimit)` or
`Dead(ProgramEnded)`, then `REFERENCE_RUN(physical(P))` returns
`SUCCESS`, `CRASHED`, `STUCK` or `OUT_OF_INSTRUCTIONS` respectively, with
the same `steps`, `position`, `direction`, `colors` and `stars`. If
`normalize` returns `Dead(Loop)`, `REFERENCE_RUN` returns `STUCK`.

## 11. Stack transitions

### 11.1 S-CALL

Executed by X-CALL. At this point `current.pc` already points **past** the
call cell.

```text
S-CALL(g):
    let caller = current
    if exhausted(caller.function, caller.pc):          # S-TAIL
        current := Frame(g, 0)
    else:                                               # S-PUSH
        callers := arena.push(callers, caller)
        current := Frame(g, 0)
```

A caller whose continuation is undecided (`pc == len` but not `closed`) is
**not** a tail call: that slot may later receive an instruction.

**Equivalence with R-TAIL.** The engine drops the caller when all its
remaining *physical* slots are `None`. S-CALL keeps the caller when its
remainder is still undecided. If that remainder later becomes empty (END),
the extra frame would have been popped for free anyway; the difference is
one of representation only, and S-REBUILD (§11.4) removes it.

### 11.2 Canonical stack

**INV-STACK:** no suspended frame (a frame in `chain(callers)`) is
exhausted. The current frame MAY be exhausted; N-RETURN then pops it.

**Lemma L5.** INV-STACK is preserved by `normalize`: S-PUSH only suspends
non-exhausted frames, and whether a frame is exhausted depends only on the
program, which `normalize` does not change.

**Lemma L6.** Of the synthesis decisions (§13), only D-END can break
INV-STACK:

| Decision | Effect on suspended frames |
|---|---|
| D-PLACE, D-DEFER (`len += 1`) | A frame with `pc == old len` gains an instruction. No frame has `pc > len`. Creates no exhausted frame. |
| D-RESOLVE | The cell already existed. No effect. |
| D-END on `(f, k)` | Every suspended frame `(f, k)` becomes exhausted. |

### 11.3 S-POP

```text
S-POP:
    if callers = Some(id):
        current := arena[id].frame
        callers := arena[id].parent
    else:
        current := None
```

S-POP consumes no step.

### 11.4 S-REBUILD

Applied by the search immediately after D-END on `(f, k)`, to the child's
machine only. At that point `current = (f, k)` (the END was decided for the
current frame's own slot).

```text
S-REBUILD(f, k):
    walk chain(callers) from top to bottom
    if no suspended frame equals (f, k): return          # SHOULD: no allocation
    kept := the suspended frames not equal to (f, k), in bottom-to-top order
    callers := re-push kept onto the arena               # depth and hash recomputed
```

- S-REBUILD MUST preserve the relative order of kept frames.
- S-REBUILD SHOULD NOT pop `current`. The exhausted current frame is popped
  by N-RETURN in the next `normalize`, so that every return goes through a
  single code path.
- The implementation MAY reuse the unchanged part of the chain below the
  deepest removed frame instead of re-pushing it.
- Cost O(call depth), paid once per D-END, never per call.

**Reachable example** (TV-10): if `B` calls itself through `C`, the logical
stack at `OpenSlot{B, k}` can be `[B@k, C@j, B@k (current)]`. After D-END,
S-REBUILD leaves `callers = [C@j]` and `current = B@k`; N-RETURN then makes
`C@j` current.

## 12. Cycle observation (C-OBSERVE)

A `CycleDetector` is created fresh at the start of every `normalize` call
(§12.3). When `config.cycle_detection` is set, after every S-CALL:

```text
C-OBSERVE:
    key := (position, direction, stars, colors, stack(M))       # steps excluded
    if key was observed earlier in this normalize call: return Dead(Loop)
    record key
```

### 12.1 Soundness

**Lemma L7.** Under a fixed program, execution is deterministic. If the
same key recurs, the execution between the two observations repeats forever.
Stars are part of the key, so no star is collected in the cycle and the
branch can never reach `Solved`.

A cycle need only be checked at calls: without a call, execution advances
monotonically through a finite function body. So an infinite execution
performs infinitely many calls, and a repeated state also repeats at a call.

### 12.2 Hashing and exact equality

- The detector MUST index entries by `key_hash(M)` (§7.2).
- A hash match MUST be confirmed by **exact** equality of `position`,
  `direction`, `stars`, `colors`, `current`, and the caller chain.
- Chain comparison walks both chains in lockstep: equal `NodeId`s mean the
  rest is equal (nodes are immutable); different `depth`s mean the chains
  differ; otherwise compare frames and move to the parents.
- An entry MUST store the caller chain as a `NodeId`, not as a copied stack.

A hash collision accepted without exact equality would prune a branch that
may contain a solution. The verifier (§18) cannot detect this, because it
only checks the solutions that were found. Completeness therefore depends on
exact equality.

### 12.3 Lifetime

v1 MUST create a new detector for every `normalize` call. Observations MUST
NOT be shared between sibling branches.

*Rationale:* a path-scoped detector could safely survive synthesis decisions
on the same DFS ancestry, because cells are only ever added and a completed
repeated path depends only on cells fixed along that ancestry. v1 resets per
call for simplicity; the cost is detecting a loop at most one iteration
later.

## 13. Synthesis decisions

Decisions are made only by the search (§17), only at frontiers, and only on
a child's copy of the state.

| Rule | Frontier | Effect on `program` | `used_slots` | `introduced_functions` |
|---|---|---|---|---|
| **D-END** | `OpenSlot{f, k}` | `functions[f].ended = true`; then S-REBUILD(f, k) | +0 | — |
| **D-PLACE(i)** | `OpenSlot{f, k}` | `cells[k] = Resolved(i)`; `len += 1` | +1 | `|= bit(g)` if `i.action = Call(g)` |
| **D-DEFER(c)** | `OpenSlot{f, k}` | `cells[k] = CondOnly(c)`; `len += 1` | +1 | — |
| **D-RESOLVE(a)** | `NeedAction{f, k, c}` | `cells[k] = Resolved{Color(c), a}` | +0 | `|= bit(g)` if `a = Call(g)` |

After every decision, `normalize` resumes from the frontier machine (L3).

---

# Part III — Search algorithm

## 14. Candidate generation

### 14.1 Open slots

At `OpenSlot{f, k}`, let `cur = colors[position]` and
`PC = possible_colors`.

| Candidate | Generated when |
|---|---|
| D-END | always, subject to P-EMPTYFN (§15.3) |
| D-PLACE(`Any: a`) | for every action `a` (§14.3) |
| D-PLACE(`Color(cur): a`) | if `|PC| ≥ 2` (P-COLOR), for every action `a` |
| D-DEFER(`d`) | if `|PC| ≥ 2` and `config.lazy_conditions`, for every `d ∈ PC`, `d ≠ cur` |
| D-PLACE(`Color(d): a`) | if `|PC| ≥ 2` and **not** `config.lazy_conditions`, for every `d ∈ PC`, `d ≠ cur`, and every action `a` |

- A candidate with cost 1 MUST NOT be generated if `used_slots + 1 > budget`
  (counted as `prune_budget`).
- **P-COLOR.** Conditions on colors outside `PC` MUST NOT be generated. If
  `|PC| = 1`, only `Any` is generated. (*Proof:* a cell conditioned on an
  impossible color never runs and can be removed; with one color,
  `Color(c)` and `Any` behave identically and `Any` is the canonical form.)
- `Any: a` and `Color(cur): a` MUST NOT be merged: they differ when the slot
  is later evaluated on another color.

### 14.2 Need-action frontiers

At `NeedAction{f, k, c}`, the candidates are D-RESOLVE(`a`) for every action
`a` (§14.3), subject to canonicalization (§15). The condition is fixed to
`Color(c)`.

### 14.3 Actions

```text
Forward, TurnLeft, TurnRight,
Paint(p)   for every p ∈ allowed_paints,
Call(g)    for every g ∈ callable(state)            (§14.4)
```

- **P-DISABLED:** `Call(g)` MUST NOT be generated when `cap[g] = 0`.
  (*Proof:* R-CALL0 makes it a no-op that still costs a slot and a step.)

### 14.4 Function symmetry (P-SYM)

- A function is **introduced** when a `Resolved` cell with action
  `Call(g)` is created (D-PLACE or D-RESOLVE). `CondOnly` does not introduce
  anything. `F1` is introduced at the root.
- With `config.function_symmetry`:

  ```text
  callable = introduced ∪ { the lowest-index non-introduced member of each capacity class }
  ```

  Without it: `callable = { g : cap[g] > 0 }`.
- P-SYM SHOULD be implemented by constructing `callable` directly, not by
  filtering generated candidates.

*Proof:* swapping the names of two functions of equal capacity (bodies and
all calls) yields a valid program of equal cost and identical execution.
Renaming each class in the order of first introduction, which execution
determines, maps every solution to one that satisfies this rule. Functions
of different capacities are not interchangeable, and F1 is the entry point.

## 15. Canonicalization

Canonicalization rules MAY discard a candidate only if every program
containing it can be rewritten into a program that has cost less than or
equal to it, identical observable behavior, fewer or equal steps, and passes
all canonicalization rules. They MUST NOT rely on heuristic judgment.
Generation and canonicalization SHOULD be separate components (P-SYM is the
exception).

Canonicalization MUST run after D-PLACE, D-DEFER and D-RESOLVE, looking at
the modified index `i` and its neighbors in `cells[i-2 ..= i+2]` (both
sides: at D-RESOLVE, cells to the right may already exist).

### 15.1 P-PAINT

`Resolved{Color(c), Paint(c)}` MUST NOT be created, whether by D-PLACE or by
D-RESOLVE. (*Proof:* it runs only when the tile is already `c`, so it never
changes state; removing it lowers cost and steps.) `Any: Paint(cur)` MUST
still be generated.

### 15.2 P-TURN

For consecutive `Resolved` turn cells of the same function **with the same
condition**, these windows are forbidden:

| Forbidden | Equivalent to |
|---|---|
| `L R`, `R L` | nothing |
| `L L L` | `R` |
| `R R R` | `L` |
| `R R` | `L L` (canonical 180° turn) |

Allowed same-condition turn runs are therefore exactly `L`, `R` and `L L`.
`CondOnly` cells are not turns; they are checked when resolved.

*Proof:* functions are entered only at index 0 and cells run in order, so
cell `i + 1` is evaluated immediately after cell `i`. A turn does not change
the tile color. So two adjacent turns with the same condition either both
run or both skip, and each rewrite above preserves the state with lower or
equal cost and steps.

### 15.3 P-EMPTYFN

D-END MUST NOT be generated at `index = 0`. (*Proof:* for F1 the program
does nothing; for any other function every call to it is a no-op that costs
a slot and can be removed.)

### 15.4 P-STEPCUT

If `machine.steps == MAX_STEPS` at a frontier:

- at `NeedAction`, the search MUST return `NotFound` without generating
  candidates;
- at `OpenSlot`, only D-END is generated (and P-EMPTYFN still applies).

(*Proof:* the next evaluated occupied cell would be step `MAX_STEPS + 1`
and dies by R-STEP; D-END consumes no step.)

## 16. Configuration (ablation)

```rust
pub struct Config {
    pub lazy_conditions: bool,    // D-DEFER / NeedAction (§14.1)
    pub function_symmetry: bool,  // P-SYM (§14.4)
    pub peephole: bool,           // P-PAINT, P-TURN, P-EMPTYFN (§15.1–15.3)
    pub cycle_detection: bool,    // C-OBSERVE (§12)
    pub step_cut: bool,           // P-STEPCUT (§15.4)
}   // Default: all true
```

Disabling a flag MUST remove only the optimization; it MUST NOT forbid any
program. In particular, disabling `lazy_conditions` MUST expand dormant
conditions eagerly (the last row of §14.1), not drop them. Every
`Config` MUST yield the same minimal cost.

P-CONN, P-COLOR and P-DISABLED are part of the representation and have no
flag.

## 17. Search

### 17.1 Outer loop (iterative deepening)

```text
SOLVE(puzzle, config, limits) -> SolveResult:
    if P-CONN fails: return Unsolvable(Disconnected)
    for budget in 0 ..= sum(cap):
        stack_arena.clear()
        root := SearchState {
            program: every function empty (len 0; ended iff capacity 0),
            machine: start position, direction, colors, stars;
                     current = Some(Frame(0, 0)); callers = None;
                     steps = 0; physical_hash from §7.1,
            used_slots: 0,
            introduced_functions: 0b00001,
        }
        match SEARCH(root, budget):
            Found(solution) -> return Solved(solution)
            Timeout         -> return Timeout
            NotFound        -> continue
    return Unsolvable(Exhausted)
```

### 17.2 Recursive search

```text
SEARCH(state, budget) -> Found(Solution) | NotFound | Timeout:
    limits.check()?                                    # Timeout
    stats.search_nodes += 1
    result := normalize(state)                         # mutates the local copy
    match result:
        Solved:
            return Found(FINALIZE(state))              # before any truncate
        Dead(reason):
            stats.dead[reason] += 1
            return NotFound
        OpenSlot{f, k}:
            for cand in OPEN_CANDIDATES(state, f, k, budget):     # §14–§15, ordered
                mark  := stack_arena.mark()            # BEFORE applying: S-REBUILD allocates
                child := state                         # Copy
                apply cand to child (§13)
                r := SEARCH(child, budget)
                stack_arena.truncate(mark)
                if r is Found or Timeout: return r
            return NotFound
        NeedAction{f, k, c}:
            if config.step_cut and state.machine.steps == MAX_STEPS:
                stats.prune_step_cut += 1
                return NotFound
            for a in NEED_CANDIDATES(state, f, k, c):
                mark  := stack_arena.mark()
                child := state
                apply D-RESOLVE(a) to child
                r := SEARCH(child, budget)
                stack_arena.truncate(mark)
                if r is Found or Timeout: return r
            return NotFound
```

`limits.check()` SHOULD read the clock only every N nodes (for example
every 4096) to keep it off the hot path.

## 18. Finalization and verification

```text
FINALIZE(state) -> Solution:
    debug_assert!(no CondOnly cell remains)            # INV-FIN
    program := physical(state.program)                 # undecided tails become None
    run := REFERENCE_RUN(puzzle, program)
    assert!(run.status == SUCCESS)                     # INV-VERIFY, in release builds too
    return Solution { program, cost: state.used_slots, steps: run.steps }
```

`REFERENCE_RUN` MUST be a separate, unoptimized implementation of §8 with no
synthesis logic. `normalize` and `REFERENCE_RUN` together are the solver's
safety belt: a bug in `normalize` cannot produce a wrong answer, only a
missed one.

## 19. Candidate ordering (non-normative)

Ordering affects only how early the final budget iteration reaches a
solution; failed budgets are always searched exhaustively. Heuristics MAY
reorder candidates and MUST NOT remove any (INV-ORDER-ONLY). A reasonable
v1 order:

```text
OpenSlot:   Any:Forward, cur:Forward, Any:Call(introduced), Any:TurnLeft, Any:TurnRight,
            cur:(same order), Any:Call(new), Paint…, D-DEFER…, D-END
NeedAction: Forward, Call(introduced), TurnLeft, TurnRight, Call(new), Paint…
```

## 20. Statistics

`SearchStats` lives in `Solver`, never in `SearchState`. It SHOULD be kept
both in total and per budget iteration.

| Counter | Incremented |
|---|---|
| `search_nodes` | per `SEARCH` call |
| `normalize_calls` | per `normalize` call |
| `instructions_evaluated` | per `consume_instruction` call |
| `open_frontiers`, `need_action_frontiers` | per frontier returned |
| `candidates_generated`, `candidates_searched` | per candidate produced / recursed into |
| `dead_crash`, `dead_program_ended`, `dead_step_limit`, `dead_loop` | per `Dead` result, by reason |
| `prune_budget`, `prune_step_cut`, `prune_symmetry`, `prune_peephole` | per candidate eliminated by that rule |
| `ends_selected`, `condonly_created`, `condonly_resolved` | per decision applied |
| `stack_pushes`, `tail_calls`, `returns`, `stack_rebuilds`, `stack_nodes_rebuilt` | per stack operation |
| `max_search_depth`, `max_call_depth` | maximum observed |

`instructions_evaluated` matters as much as `search_nodes`: an optimization
that removes nodes but adds normalization work may not reduce wall-clock
time.

---

# Part IV — Invariants and correctness

## 21. Invariants

| ID | Invariant | Checked by |
|---|---|---|
| **INV-PREFIX** | Every `FunctionDraft` satisfies §3.1. | `debug_assert` on every decision |
| **INV-COST** | `used_slots` equals the number of `Resolved` and `CondOnly` cells. | `debug_assert` on every decision |
| **INV-STEP** | Every evaluated occupied cell consumes exactly one step, before its condition is tested and before its action runs. | TV-03, TV-09, T-DIFF |
| **INV-FRONTIER** | At `OpenSlot` / `NeedAction`, `current` points at the frontier cell and it has consumed no step. | TV-13 |
| **INV-PURE** | `normalize` never modifies the program. | code structure (`&PartialProgram`) |
| **INV-STACK** | No suspended frame is exhausted (§11.2). | TV-10, `t_rebuild_middle` |
| **INV-FIN** | The first solution found contains no `CondOnly`. | `debug_assert` in FINALIZE |
| **INV-VERIFY** | Every returned solution succeeds in `REFERENCE_RUN`. | `assert` in FINALIZE |
| **INV-ORDER-ONLY** | Heuristics reorder candidates and never remove them. | code review |
| **INV-DETERMINISM** | Same input and `Config` give the same result and statistics. | run twice, compare |

**Proof of INV-FIN.** A `CondOnly` still present at `Solved` was skipped
every time it was reached. Removing it preserves behavior and lowers both
cost and steps by at least one, which gives a solution at a smaller budget.
Smaller budgets were searched exhaustively and failed. Contradiction.

## 22. Correctness

**Soundness.** Every `Solved` result is a program that the engine accepts:
FINALIZE checks it with `REFERENCE_RUN` (INV-VERIFY), and L4 guarantees that
`normalize` agrees with `REFERENCE_RUN` on fully resolved programs.

**Completeness and optimality.** If a program of cost `K` solves the puzzle,
`SOLVE` returns a solution of cost exactly `K` for the smallest such `K`
(given no timeout, for every `Config`).

*Proof sketch.* Take a minimal solution `Q`. Left-pack it (L1); rename its
auxiliary functions by first introduction (P-SYM); apply the P-TURN,
P-PAINT and P-COLOR rewrites. None increases cost, steps or changes
behavior. `Q` contains no empty called function (P-EMPTYFN) and no
never-firing conditional cell (the INV-FIN argument). Follow `Q` through the
search at budget `K`: at every `OpenSlot`, `Q`'s cell is either a D-PLACE
candidate (active condition), a D-DEFER candidate whose action a later
D-RESOLVE supplies (or a direct D-PLACE when `lazy_conditions` is off), or a
D-END. P-STEPCUT never cuts `Q`, because `Q` succeeds. C-OBSERVE never cuts
`Q`, because a repeated state would mean `Q` never succeeds (L7). Every
budget `< K` fails, so the first solution found has cost `K`.

Each pruning rule's proof obligation is stated next to the rule. A new
pruning rule MUST come with such a proof and a conformance test, and MUST be
switchable through `Config`.

## 23. Solver contract

```rust
pub enum SolveResult {
    Solved { program: ResolvedProgram, cost: u8, steps: u32, stats: SearchStats },
    Unsolvable { reason: UnsolvableReason, stats: SearchStats },  // Disconnected | Exhausted
    Timeout { stats: SearchStats },
    Unsupported { reason: String },
}
```

`Solved` guarantees:

1. `program` has exactly `cap[f]` slots in function `f`, uses only paint
   colors in `allowed_paints`, and never calls a function with `cap = 0`;
2. `REFERENCE_RUN(program)` returns `SUCCESS` with `steps` steps;
3. no program with fewer occupied slots solves the puzzle under §8.

`Unsolvable(Exhausted)` guarantees that no program of any cost solves the
puzzle under §8.

---

# Part V — Conformance

## 24. Test vectors

Expected values below were computed with an independent Python mirror of
`interpreter.dart`. Every implementation MUST reproduce them.

Notation: puzzles use the catalog row encoding; programs use the output
syntax of §26 (`"red:turnLeft"`, `"callF2"`, `null` for an empty slot).
Unless stated otherwise the start is `(0, 0)` facing `right`,
`allowedCommands = 0`, and absent functions have capacity 0.

### 24.1 Reference-run vectors (`REFERENCE_RUN` and full-program `normalize`)

For vectors marked ‡, `normalize` on the left-packed program MUST agree
(L4). Final position is `(row, col)`.

| ID | Rows | Caps | Program | Expected |
|---|---|---|---|---|
| TV-01 ‡ | `bbbB` | `[2]` | F1 `[forward, callF1]` | `SUCCESS`, steps 5, pos (0,3) |
| TV-02 ‡ | `bB` | `[2]` | F1 `[turnLeft, forward]` | `CRASHED`, steps 2, pos (0,0), facing up |
| TV-03 ‡ | `bB` | `[2]` | F1 `[red:forward, forward]` | `SUCCESS`, steps 2 (the mismatch consumed step 1) |
| TV-04 ‡ | `bB`, `allowedCommands = 1` | `[2]` | F1 `[paintRed, red:forward]` | `SUCCESS`, steps 2 |
| TV-05 ‡ | `bB`, start facing `up` | `[2, 1]` | F1 `[callF2, forward]`, F2 `[turnRight]` | `SUCCESS`, steps 3; max stack depth 2 |
| TV-06 | `bB` | `[2, 0]` | F1 `[callF2, forward]` | `SUCCESS`, steps 2 (R-CALL0 consumed a step) |
| TV-07 | `bB` | `[1]` | F1 `[callF1]` | Reference: `STUCK`, steps 20001. `normalize`: `Dead(Loop)` at steps 2 with cycle detection; `Dead(StepLimit)` at steps 20001 without. |
| TV-08 | `bbB` | `[2]` | F1 `[callF1, forward]` | Reference: `STUCK`, steps 20001, stack depth 20001. `normalize`: `Dead(StepLimit)`, steps 20001, caller-chain depth 20000, with or without cycle detection (no state repeats). |
| TV-11 ‡ | `bbB` | `[3]` | F1 `[forward, null, callF1]` | `SUCCESS`, steps 3 |
| TV-12 ‡ | `bbB` | `[3]` | F1 `[forward, callF1, null]` | `SUCCESS`, steps 3 (same as TV-11: L1) |

### 24.2 Step-limit vectors (preset `steps`)

The machine starts with `steps = steps0` instead of 0.

| ID | Rows | Caps | Program | `steps0` | Expected |
|---|---|---|---|---|---|
| TV-09a | `bB` | `[1]` | F1 `[forward]` | 19999 | `SUCCESS` / `Solved`, steps 20000 |
| TV-09b | `bB` | `[1]` | F1 `[forward]` | 20000 | `STUCK` / `Dead(StepLimit)`, steps 20001, pos (0,0), star still present |
| TV-09c | `bB` | `[2]` | F1 `[red:forward, forward]` | 19999 | `STUCK` / `Dead(StepLimit)`, steps 20001, pos (0,0), star still present |

### 24.3 Frontier and stack vectors (`normalize` on partial programs)

**TV-10 (S-REBUILD, reachable middle removal).** Rows `bB`, caps
`[1, 2, 3]`, `allowedCommands = 1`. Partial program:

```text
F1: [Resolved(Any, Call F2)]                                   len 1 (closed: len = cap)
F2: [Resolved(Color(Blue), Call F3)]                           len 1, open
F3: [Resolved(Any, Paint Red), Resolved(Any, Call F2), Resolved(Any, Forward)]   len 3
```

1. `normalize` from the root returns `OpenSlot{F2, 1}` with steps 5,
   `current = F2@1`, `chain(callers) = [F2@1, F3@2]` (bottom to top).
2. Apply D-END on `(F2, 1)`. S-REBUILD gives `chain(callers) = [F3@2]`;
   `current` is still `F2@1`.
3. `normalize` returns `Solved` with steps 6.
4. `physical` = F1 `["callF2"]`, F2 `["blue:callF3", null]`, F3
   `["paintRed", "callF2", "forward"]`. `REFERENCE_RUN` returns `SUCCESS`,
   steps 6.

**TV-13 (frontiers consume nothing).**

| Case | Rows | Caps | Partial F1 | Expected |
|---|---|---|---|---|
| a | `bB` | `[2]` | empty | `OpenSlot{F1, 0}`, steps 0, pc 0 |
| b | `bB` | `[2]` | `[CondOnly(Red)]` | N-SKIP then `OpenSlot{F1, 1}`, steps 1 |
| c | `rB` | `[2]` | `[CondOnly(Red)]` | `NeedAction{F1, 0, Red}`, steps 0, pc 0 |

### 24.4 Candidate-generation vectors (root `OpenSlot{F1, 0}`, budget ≥ 1)

| ID | Rows | `allowedCommands` | Caps | Config | Expected candidate set |
|---|---|---|---|---|---|
| TV-14a | `bbB` | 0 | `[2]` | default | `Any:{forward, turnLeft, turnRight, callF1}`: 4 candidates. No condition, no D-DEFER (P-COLOR, one color). No D-END (P-EMPTYFN). |
| TV-14b | `bbB` | 0 | `[2]` | `peephole = false` | TV-14a plus D-END: 5 |
| TV-14c | `rbB` | 0 | `[2]` | default | `Any:{4 actions}` + `red:{4 actions}` + D-DEFER(Blue): 9 |
| TV-14d | `rbB` | 0 | `[2]` | `lazy_conditions = false` | `Any:{4}` + `red:{4}` + `blue:{4}`: 12 |
| TV-14e | `rbB` | 1 | `[2]` | default | `Any:{forward, turnLeft, turnRight, paintRed, callF1}` + `red:{forward, turnLeft, turnRight, callF1}` (no `red:paintRed`, P-PAINT) + D-DEFER(Blue): 10 |
| TV-14f | `bbB` | 0 | `[2]` | budget = 0 | no candidates (every cost-1 candidate exceeds the budget; D-END is excluded by P-EMPTYFN) |

**TV-15 (P-SYM).** `callable` with F1 introduced only:

| Caps | `function_symmetry` | `callable` |
|---|---|---|
| `[7, 4, 2, 4, 2]` | on | `{F1, F2, F3}`; after F2 is introduced, `{F1, F2, F3, F4}` |
| `[6, 6, 0, 6, 0]` | on | `{F1, F2}`; after F2 is introduced, `{F1, F2, F4}` |
| `[7, 4, 2, 4, 2]` | off | `{F1, F2, F3, F4, F5}` |

**TV-16 (P-TURN).** Function cells before the decision, the decision, and
whether it is accepted:

| Cells | Decision at the next index | Accepted |
|---|---|---|
| `[Any:L]` | D-PLACE `Any:R` | no (`L R`) |
| `[Any:L]` | D-PLACE `red:R` | yes (different condition) |
| `[Any:L]` | D-PLACE `Any:L` | yes (`L L` is canonical) |
| `[Any:R]` | D-PLACE `Any:R` | no (`R R`) |
| `[Any:L, Any:L]` | D-PLACE `Any:L` | no (`L L L`) |
| `[CondOnly(Red), red:R]` | D-RESOLVE index 0 with `turnLeft` | no (right neighbor) |
| `[CondOnly(Red), red:R]` | D-RESOLVE index 0 with `turnRight` | no (`R R`) |
| `[CondOnly(Red), red:R]` | D-RESOLVE index 0 with `forward` | yes |

### 24.5 Minimal-cost vectors (end to end)

Minimal costs were computed by exhaustive enumeration of all left-packed
programs. `SOLVE` MUST return exactly this cost, for every `Config`.

The example program is one minimal solution; `SOLVE` MAY return a different
program of the same cost (and therefore possibly different steps).

| ID | Rows | Start | Caps | Expected | Example minimal program |
|---|---|---|---|---|---|
| MC-01 | `bbbB` | (0,0) right | `[3]` | cost 2 | F1 `[forward, callF1, null]` (steps 5) |
| MC-02 | `Bbbb` | (0,3) right | `[4]` | `Unsolvable(Exhausted)` | — (turning around and walking needs 5 slots) |
| MC-03 | `bbb` / `b b` / `bbB` | (0,0) right | `[4]` | cost 4 | F1 `[forward, forward, turnRight, callF1]` (steps 6) |
| MC-04 | `bbr` / `  b` / `  B` | (0,0) right | `[4]` | cost 3 | F1 `[forward, red:turnRight, callF1, null]` (steps 10) |
| MC-05 | `bbbbB` | (0,0) right | `[1, 2]` | cost 3 | F1 `[callF2]`, F2 `[forward, callF1]` (steps 11) |
| MC-06 | `BbbbB` | (0,2) left | `[3, 1]` | `Unsolvable(Exhausted)` | — |

## 25. Required conformance tests

| Test | Covers |
|---|---|
| `t_level_validation` | §2.2: every rejection reason returns `Unsupported`; no panic. |
| `t_level_catalog` | All 908 catalog puzzles load and compile. |
| `t_ref_vectors` | TV-01 … TV-12 on `REFERENCE_RUN`. |
| `t_step_limit_boundary` | TV-09a/b/c on both `REFERENCE_RUN` and `normalize`. |
| `t_frontier_no_step` | TV-13. |
| `t_tail_call`, `t_non_tail_call` | S-TAIL adds no arena node (TV-01); S-PUSH suspends the caller (TV-05). |
| `t_unknown_continuation_not_tail` | A call followed by an open slot pushes the caller. |
| `t_return_is_free` | TV-05: the return from F2 consumes no step. |
| `t_rebuild_middle` | TV-10, including recomputed `depth` and `hash`. |
| `t_loop_tail`, `t_loop_nontail` | TV-07 and TV-08. |
| `t_cycle_exact_equality` | With `key_hash` forced to collide, different states are not reported as a loop. |
| `t_zobrist_incremental` | After random moves, turns, paints and star collections, the incremental hash equals a from-scratch recomputation. |
| `t_diff_random` | **T-DIFF:** ≥ 100 000 random fully resolved programs (fixed seed) on catalog puzzles; `normalize` and `REFERENCE_RUN` agree as in L4. |
| `t_candidates` | TV-14a … TV-14f. |
| `t_p_sym` | TV-15. |
| `t_p_turn` | TV-16. |
| `t_e2e_min_cost` | §24.5 vectors. |
| `t_e2e_bruteforce` | On random tiny puzzles (total capacity ≤ 4), `SOLVE` matches an exhaustive enumeration. |
| `t_config_equivalence` | Every `Config` combination yields the same minimal cost on the §24.5 set. |
| `t_determinism` | Two runs give identical results and statistics. |
| Dart `solver_solutions_test.dart` | §26. |

## 26. Output format and Dart verification

The CLI writes `solutions.json`:

```json
{
  "solver": "robozzle-solver 0.1.0",
  "maxSteps": 20000,
  "config": { "lazyConditions": true, "functionSymmetry": true, "peephole": true,
              "cycleDetection": true, "stepCut": true },
  "results": [
    { "sourceId": 195, "status": "solved", "cost": 7, "steps": 1234,
      "program": [["forward", "red:turnLeft", "callF2", null], ["forward", null], [], [], []],
      "stats": { "millis": 12, "searchNodes": 45678, "instructionsEvaluated": 912345,
                 "nodesPerBudget": [1, 1, 5, 40] } },
    { "sourceId": 53, "status": "timeout", "stats": { "millis": 10000, "searchNodes": 98765432 } },
    { "sourceId": 999, "status": "unsupported", "reason": "function capacity 13 exceeds 12" }
  ]
}
```

- `program[f]` MUST have exactly `cap[f]` entries; empty slots are `null`.
- An instruction is `"<condition>:<action>"`, with the condition part
  omitted for `Any`. Conditions: `red | green | blue`. Actions are exactly
  Dart's `ActionType` names: `forward`, `turnLeft`, `turnRight`,
  `paintRed`, `paintGreen`, `paintBlue`, `callF1` … `callF5`.
- `status` is one of `solved | unsolvable | timeout | unsupported`;
  `unsolvable` entries carry `"reason": "disconnected" | "exhausted"`.
- `stats` keys are the camelCase names of §20.

**Dart verification** (`test/solver_solutions_test.dart`): for every
`solved` entry, build a `Level` with `Level.fromJson` and a `RobotProgram`
from `program`, run `RobotInterpreter.runToCompletion()`, and require
`status == RunStatus.success` **and** `stepsExecuted == steps`. The exact
step match is the strongest evidence that §8 and the engine agree. The test
MUST be skipped when `solutions.json` is absent.

---

# Appendices

## A. CLI

```text
solver <catalog.json> [--id <sourceId>]... [--all]
       [--timeout-ms <ms>]            per puzzle, default 10000
       [--node-limit <n>]
       [--out <solutions.json>]
       [--no-lazy-conditions] [--no-function-symmetry] [--no-peephole]
       [--no-cycle-detection] [--no-step-cut]
```

One progress line per puzzle; at the end, a summary by rounded difficulty:
solved count, average time, total `search_nodes` and
`instructions_evaluated`.

## B. Module layout and implementation order

```text
solver/src/
  lib.rs         module declarations, public API (SOLVE)
  main.rs        CLI (Appendix A), JSON output (§26)
  types.rs       constants and primitive types (§1)
  puzzle.rs      input, validation, compilation, P-CONN (§2)
  program.rs     Cell, FunctionDraft, PartialProgram, ResolvedProgram (§3)
  machine.rs     PackedColors, StarSet, Machine, consume_instruction, Zobrist (§4, §7.1, §9)
  stack.rs       Frame, NodeId, StackNode, StackArena, S-CALL/S-POP/S-REBUILD (§5, §11)
  reference.rs   REFERENCE_RUN (§8)
  normalize.rs   normalize, CycleDetector (§10, §12)
  canonical.rs   P-PAINT, P-TURN, P-EMPTYFN (§15)
  search.rs      Solver, SearchState, candidates, SOLVE/SEARCH, FINALIZE (§6, §13–§18)
  stats.rs       Config, Limits, SearchStats (§16, §20)
```

Dependencies: `serde`, `serde_json`, `clap` (derive). `thiserror` MAY be
used for error types. Randomness in tests uses a hand-written `splitmix64`.

Implementation order (each step ends with its tests passing; from step 6
on, a benchmark row is appended to `BENCHMARKS.md`):

1. `types.rs`, `puzzle.rs` — `t_level_*`
2. `program.rs`
3. `reference.rs` — `t_ref_vectors`, `t_step_limit_boundary` (reference half)
4. `machine.rs`, `stack.rs` — Zobrist, S-CALL/S-POP/S-REBUILD, `t_rebuild_middle`
5. `normalize.rs` without cycle detection — `t_diff_random`, `t_frontier_no_step`
6. `search.rs` with eager conditions (`lazy_conditions = false`), IDDFS — `t_e2e_*`
7. D-DEFER / NeedAction (`lazy_conditions = true`)
8. C-OBSERVE
9. P-SYM
10. `canonical.rs`: P-PAINT, P-TURN, P-EMPTYFN
11. P-STEPCUT
12. CLI, output, `t_config_equivalence`, Dart test, full-catalog benchmark

## C. Non-goals for v1

Global transposition table; undo/trail state; path-scoped cycle cache;
parallel search within a puzzle (parallelism *across* puzzles MAY come in
v1.5); MCTS, genetic or machine-learned search; heuristic (unsound)
pruning; pushdown analysis of non-tail recursion; a secondary objective
(fewest steps at equal cost); any backend or HTTP integration.

## D. Traceability

| Rule | Section | Tests |
|---|---|---|
| R-RUN, R-STEP, R-COND, R-CALL0, R-TAIL, R-POP, R-NULL | §8 | `t_ref_vectors`, `t_step_limit_boundary`, `t_diff_random`, Dart test |
| N-* | §10 | `t_frontier_no_step`, `t_diff_random` |
| S-CALL, S-POP | §11.1, §11.3 | `t_tail_call`, `t_non_tail_call`, `t_unknown_continuation_not_tail`, `t_return_is_free` |
| S-REBUILD | §11.4 | `t_rebuild_middle` |
| C-OBSERVE | §12 | `t_loop_tail`, `t_loop_nontail`, `t_cycle_exact_equality` |
| D-* | §13 | `t_rebuild_middle`, `t_e2e_*` |
| P-CONN | §2.6 | `t_level_catalog` (none disconnected), unit test |
| P-COLOR, P-PAINT, P-DISABLED | §14.1, §15.1, §14.3 | `t_candidates` |
| P-SYM | §14.4 | `t_p_sym`, `t_config_equivalence` |
| P-TURN | §15.2 | `t_p_turn`, `t_config_equivalence` |
| P-EMPTYFN | §15.3 | `t_candidates` (TV-14a/b/f) |
| P-STEPCUT | §15.4 | unit test at `steps = MAX_STEPS`, `t_config_equivalence` |
| INV-* | §21 | see §21 |
