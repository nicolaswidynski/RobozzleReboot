//! normalize (SPEC §10) and cycle observation (SPEC §12).

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

use crate::machine::{DeadReason, Machine, PackedColors, StarSet};
use crate::program::{Cell, PartialProgram};
use crate::puzzle::StaticPuzzle;
use crate::stack::{self, CallKind, Frame, NodeId, StackArena};
use crate::stats::{Config, SearchStats};
use crate::types::{Action, Color, Direction, FnId, TileId};

/// Geometric progress of a branch's run (low-star ranking, SPEC §17.3): a
/// side channel beside the semantic state. It is not part of `Machine`, so
/// loop detection, state equality and exact search never see it; only the
/// heuristic phase carries and updates it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Progress {
    /// Stars left when `best_distance` was last reset.
    pub stars_left: u32,
    /// Smallest walking distance to a remaining star reached since the
    /// last star was collected.
    pub best_distance: u16,
    /// Distinct (tile, direction) poses reached: bit `tile * 4 + direction`.
    pub visited: [u64; 16],
}

impl Progress {
    pub fn new(puzzle: &StaticPuzzle, m: &Machine) -> Self {
        let mut p = Progress {
            stars_left: m.stars.len(),
            best_distance: puzzle.nearest_star(m.position, &m.stars),
            visited: [0; 16],
        };
        p.mark(m);
        p
    }

    #[inline]
    fn mark(&mut self, m: &Machine) {
        let b = m.position as usize * 4 + m.direction as usize;
        self.visited[b / 64] |= 1 << (b % 64);
    }

    /// Records the machine's pose after an executed action.
    #[inline]
    pub fn observe(&mut self, puzzle: &StaticPuzzle, m: &Machine) {
        let left = m.stars.len();
        let d = puzzle.nearest_star(m.position, &m.stars);
        if left != self.stars_left {
            self.stars_left = left;
            self.best_distance = d;
        } else {
            self.best_distance = self.best_distance.min(d);
        }
        self.mark(m);
    }

    /// Number of distinct (tile, direction) poses reached.
    pub fn coverage(&self) -> u32 {
        self.visited.iter().map(|w| w.count_ones()).sum()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NormalizeResult {
    Solved,
    Dead(DeadReason),
    OpenSlot {
        function: FnId,
        index: u8,
    },
    NeedAction {
        function: FnId,
        index: u8,
        condition: Color,
    },
    /// A `Pending` cell reached on a tile whose color differs from its own:
    /// `Any` and `Color(color)` now behave differently.
    NeedCondition {
        function: FnId,
        index: u8,
    },
}

/// Keys are already well-mixed `u128` hashes; use their low bits directly.
#[derive(Default)]
pub struct PassThroughHasher(u64);

impl Hasher for PassThroughHasher {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0 << 8) ^ b as u64;
        }
    }
    fn write_u128(&mut self, v: u128) {
        self.0 = v as u64;
    }
}

#[derive(Debug, Clone, Copy)]
struct CycleSnapshot {
    position: TileId,
    direction: Direction,
    stars: StarSet,
    colors: PackedColors,
    current: Option<Frame>,
    callers: Option<NodeId>,
    depth: u16,
    /// Content hash of the caller chain (`StackArena::hash_of`): equal
    /// chains have equal hashes.
    chain_hash: u128,
    /// Position of this observation in `entries`.
    index: u32,
}

/// Observations of one key (physical state and current frame) once the
/// detector is indexed: the last `RECENT` of them, and a checkpoint that
/// moves to the newest observation whenever the key's count reaches a power
/// of two (Brent's cycle detection).
#[derive(Clone, Copy)]
struct KeyState {
    recent: [u32; RECENT],
    count: u32,
    checkpoint: u32,
}

/// C-OBSERVE and C-PUMP (SPEC §12). Cleared at the start of every
/// `normalize` call, so observations never outlive one normalization and are
/// never shared between sibling branches (SPEC §12.3).
///
/// A path-scoped detector could safely survive synthesis decisions on the
/// same DFS ancestry, because program cells are monotonically refined and a
/// completed repeated execution path only depends on cells already fixed
/// along that ancestry. V1 deliberately resets cycle detection at each
/// normalization frontier for implementation simplicity; the cost is that a
/// loop is detected at most one iteration later.
///
/// Which earlier observations a new one is compared with only decides how
/// soon a loop is detected, never the search: an undetected endless loop
/// reaches no frontier and dies at the step limit (SPEC §12.4). Short
/// normalizations compare with every earlier observation; long ones with
/// the last `RECENT` observations of the same key and a Brent checkpoint,
/// so that each observation costs O(1) comparisons.
#[derive(Default)]
pub struct CycleDetector {
    /// Observations of the current `normalize` call, keyed by the physical
    /// state and the current frame only, so that observations with different
    /// caller stacks are compared (C-PUMP).
    entries: Vec<(u128, CycleSnapshot)>,
    /// Built only once a normalization makes many calls; most make few, and
    /// a linear scan of a short `Vec` is cheaper than hashing and clearing.
    index: HashMap<u128, KeyState, BuildHasherDefault<PassThroughHasher>>,
    indexed: bool,
    /// Low-water marks of the caller depth: segments (first observation,
    /// lowest depth since then), with strictly increasing depths. An earlier
    /// caller chain is still the bottom of the current one if and only if
    /// the depth never fell below its depth since (nodes are immutable and
    /// only `pop` lowers the depth), which makes C-PUMP O(log n).
    lows: Vec<(u32, u16)>,
}

const LINEAR_LIMIT: usize = 32;
const RECENT: usize = 8;

impl CycleDetector {
    pub fn clear(&mut self) {
        self.entries.clear();
        self.lows.clear();
        if self.indexed {
            self.index.clear();
            self.indexed = false;
        }
    }

    /// Records that a `pop` lowered the caller depth to `depth`.
    #[inline]
    pub fn on_pop(&mut self, depth: u16) {
        let mut start = None;
        while let Some(&(first, low)) = self.lows.last() {
            if low <= depth {
                break;
            }
            start = Some(first);
            self.lows.pop();
        }
        if let Some(first) = start
            && self.lows.last().is_none_or(|&(_, low)| low < depth)
        {
            self.lows.push((first, depth));
        }
    }

    /// The lowest caller depth since observation `index` (u16::MAX if the
    /// depth has not fallen since).
    fn low_since(&self, index: u32) -> u16 {
        let pos = self.lows.partition_point(|&(first, _)| first <= index);
        self.lows[pos - 1].1
    }

    /// Records the state; returns true if execution provably never ends.
    fn observe(&mut self, m: &Machine, arena: &StackArena) -> bool {
        let current = m.current.unwrap_or(Frame {
            function: 255,
            pc: 255,
        });
        let key = stack::mix(m.physical_hash, current);
        let i = self.entries.len() as u32;
        let snap = CycleSnapshot {
            position: m.position,
            direction: m.direction,
            stars: m.stars,
            colors: m.colors,
            current: m.current,
            callers: m.callers,
            depth: arena.depth_of(m.callers),
            chain_hash: arena.hash_of(m.callers),
            index: i,
        };
        if self.indexed {
            if let Some(ks) = self.index.get(&key) {
                let n = (ks.count as usize).min(RECENT);
                let older = ks.count as usize > RECENT;
                if ks.recent[..n]
                    .iter()
                    .chain(older.then_some(&ks.checkpoint))
                    .any(|&j| self.repeats(&self.entries[j as usize].1, &snap, arena))
                {
                    return true;
                }
            }
        } else if self
            .entries
            .iter()
            .any(|(k, s)| *k == key && self.repeats(s, &snap, arena))
        {
            return true;
        }
        self.entries.push((key, snap));
        if self.lows.last().is_none_or(|&(_, low)| low < u16::MAX) {
            self.lows.push((i, u16::MAX));
        }
        if self.indexed {
            Self::record(&mut self.index, key, i);
        } else if self.entries.len() > LINEAR_LIMIT {
            for (j, (k, _)) in self.entries.iter().enumerate() {
                Self::record(&mut self.index, *k, j as u32);
            }
            self.indexed = true;
        }
        false
    }

    fn record(
        index: &mut HashMap<u128, KeyState, BuildHasherDefault<PassThroughHasher>>,
        key: u128,
        i: u32,
    ) {
        let ks = index.entry(key).or_insert(KeyState {
            recent: [0; RECENT],
            count: 0,
            checkpoint: i,
        });
        ks.recent[ks.count as usize % RECENT] = i;
        ks.count += 1;
        if ks.count.is_power_of_two() {
            ks.checkpoint = i;
        }
    }

    /// Whether reaching `now` after `before` proves the execution never ends.
    #[inline]
    fn repeats(&self, before: &CycleSnapshot, now: &CycleSnapshot, arena: &StackArena) -> bool {
        if before.position != now.position
            || before.direction != now.direction
            || before.current != now.current
            || before.stars != now.stars
            || before.colors != now.colors
        {
            return false;
        }
        // C-PUMP: the earlier caller chain is still the bottom of the current
        // one (same node: it was never popped), so everything between the
        // observations ran above it and repeats forever. Also covers the
        // exact repeat with the same node.
        let still_bottom =
            now.depth >= before.depth && self.low_since(before.index) >= before.depth;
        if cfg!(test) {
            assert_eq!(
                still_bottom,
                is_ancestor_or_self(arena, before.callers, before.depth, now.callers, now.depth),
                "low-water mark disagrees with the chain walk"
            );
        }
        if still_bottom {
            return true;
        }
        // C-OBSERVE: an exact repeat whose chain was rebuilt with different
        // nodes but identical contents.
        before.depth == now.depth
            && before.chain_hash == now.chain_hash
            && arena.chains_equal(before.callers, now.callers)
    }
}

/// Whether node `a` (at depth `a_depth`) lies on the chain ending at `b`
/// (the reference for the low-water mark, checked in tests).
fn is_ancestor_or_self(
    arena: &StackArena,
    a: Option<NodeId>,
    a_depth: u16,
    b: Option<NodeId>,
    b_depth: u16,
) -> bool {
    if b_depth < a_depth {
        return false;
    }
    let mut cursor = b;
    for _ in 0..(b_depth - a_depth) {
        cursor = cursor.and_then(|id| arena.get(id).parent);
    }
    cursor == a
}

/// Executes the partial program from `machine` until a frontier or a
/// terminal outcome (SPEC §10.1). Takes the program by shared reference:
/// it can never change it (INV-PURE).
pub fn normalize(
    puzzle: &StaticPuzzle,
    program: &PartialProgram,
    machine: &mut Machine,
    arena: &mut StackArena,
    cycles: &mut CycleDetector,
    config: &Config,
    stats: &mut SearchStats,
) -> NormalizeResult {
    normalize_with(puzzle, program, machine, arena, cycles, config, stats, None)
}

/// `normalize` that also records the run's geometric progress (the
/// heuristic phase in low-star mode, SPEC §17.3). Same result as
/// `normalize`.
#[allow(clippy::too_many_arguments)]
pub fn normalize_tracked(
    puzzle: &StaticPuzzle,
    program: &PartialProgram,
    machine: &mut Machine,
    arena: &mut StackArena,
    cycles: &mut CycleDetector,
    config: &Config,
    stats: &mut SearchStats,
    progress: &mut Progress,
) -> NormalizeResult {
    normalize_with(
        puzzle,
        program,
        machine,
        arena,
        cycles,
        config,
        stats,
        Some(progress),
    )
}

#[allow(clippy::too_many_arguments)]
fn normalize_with(
    puzzle: &StaticPuzzle,
    program: &PartialProgram,
    machine: &mut Machine,
    arena: &mut StackArena,
    cycles: &mut CycleDetector,
    config: &Config,
    stats: &mut SearchStats,
    progress: Option<&mut Progress>,
) -> NormalizeResult {
    let before = stats.instructions_evaluated;
    let result = normalize_inner(
        puzzle, program, machine, arena, cycles, config, stats, progress,
    );
    let n = stats.instructions_evaluated - before;
    let bucket = match n {
        0 => 0,
        1..=10 => 1,
        11..=100 => 2,
        101..=1000 => 3,
        1001..=10000 => 4,
        _ => 5,
    };
    stats.normalize_histogram[bucket] += 1;
    result
}

#[allow(clippy::too_many_arguments)]
fn normalize_inner(
    puzzle: &StaticPuzzle,
    program: &PartialProgram,
    machine: &mut Machine,
    arena: &mut StackArena,
    cycles: &mut CycleDetector,
    config: &Config,
    stats: &mut SearchStats,
    mut progress: Option<&mut Progress>,
) -> NormalizeResult {
    stats.normalize_calls += 1;
    cycles.clear();
    loop {
        // N-SOLVED
        if machine.stars.is_empty() {
            return NormalizeResult::Solved;
        }
        // N-NOFRAME
        let Some(frame) = machine.current else {
            return NormalizeResult::Dead(DeadReason::ProgramEnded);
        };
        let d = program.function(frame.function);
        if frame.pc == d.len {
            if d.closed() {
                // N-RETURN
                stack::pop(machine, arena);
                cycles.on_pop(arena.depth_of(machine.callers));
                stats.returns += 1;
                continue;
            }
            // N-OPEN: no step consumed, pc not advanced (INV-FRONTIER)
            stats.open_frontiers += 1;
            return NormalizeResult::OpenSlot {
                function: frame.function,
                index: frame.pc,
            };
        }
        let advance = |m: &mut Machine| {
            m.current = Some(Frame {
                function: frame.function,
                pc: frame.pc + 1,
            })
        };
        match d.cells[frame.pc as usize] {
            Cell::CondSet(mask) => {
                let tile = machine.tile_color();
                if mask.contains(tile) {
                    // N-NEEDSET: the member conditioned on `tile` would run;
                    // no step consumed, pc not advanced.
                    stats.need_action_frontiers += 1;
                    return NormalizeResult::NeedAction {
                        function: frame.function,
                        index: frame.pc,
                        condition: tile,
                    };
                }
                // Every member skips.
                stats.instructions_evaluated += 1;
                if let Err(e) = machine.consume_instruction() {
                    return NormalizeResult::Dead(e);
                }
                advance(machine);
            }
            Cell::CondOnly(c) => {
                if machine.tile_color() == c {
                    // N-NEED
                    stats.need_action_frontiers += 1;
                    return NormalizeResult::NeedAction {
                        function: frame.function,
                        index: frame.pc,
                        condition: c,
                    };
                }
                // N-SKIP
                stats.instructions_evaluated += 1;
                if let Err(e) = machine.consume_instruction() {
                    return NormalizeResult::Dead(e);
                }
                advance(machine);
            }
            Cell::Pending { action, color } => {
                let tile = machine.tile_color();
                if tile != color && action == Action::Paint(tile) {
                    // N-PAINTSAME: `Any` repaints the tile with its own color
                    // and `Color(color)` skips; both consume one step and
                    // change nothing, so the choice stays deferred.
                    stats.paint_same_skips += 1;
                    stats.instructions_evaluated += 1;
                    if let Err(e) = machine.consume_instruction() {
                        return NormalizeResult::Dead(e);
                    }
                    advance(machine);
                    continue;
                }
                if tile != color {
                    // N-NEEDCOND: no step consumed, pc not advanced.
                    stats.need_condition_frontiers += 1;
                    return NormalizeResult::NeedCondition {
                        function: frame.function,
                        index: frame.pc,
                    };
                }
                // On its own color the condition is irrelevant: it runs.
                stats.instructions_evaluated += 1;
                if let Err(e) = machine.consume_instruction() {
                    return NormalizeResult::Dead(e);
                }
                advance(machine);
                if let Some(dead) = execute(
                    puzzle, program, machine, arena, cycles, config, stats, action,
                ) {
                    return dead;
                }
                if let Some(p) = progress.as_deref_mut() {
                    p.observe(puzzle, machine);
                }
            }
            Cell::Resolved(instr) => {
                // N-EXEC: step first (R-STEP), then pc, then the condition.
                stats.instructions_evaluated += 1;
                if let Err(e) = machine.consume_instruction() {
                    return NormalizeResult::Dead(e);
                }
                advance(machine);
                if !instr.condition.matches(machine.tile_color()) {
                    continue;
                }
                if let Some(dead) = execute(
                    puzzle,
                    program,
                    machine,
                    arena,
                    cycles,
                    config,
                    stats,
                    instr.action,
                ) {
                    return dead;
                }
                if let Some(p) = progress.as_deref_mut() {
                    p.observe(puzzle, machine);
                }
            }
            Cell::Unused => unreachable!("Unused cell inside a function prefix"),
        }
    }
}

/// The X-rules (SPEC §10.2). Returns `Some(result)` if execution ends.
#[allow(clippy::too_many_arguments)]
#[inline]
fn execute(
    puzzle: &StaticPuzzle,
    program: &PartialProgram,
    machine: &mut Machine,
    arena: &mut StackArena,
    cycles: &mut CycleDetector,
    config: &Config,
    stats: &mut SearchStats,
    action: Action,
) -> Option<NormalizeResult> {
    match action {
        Action::Forward => match puzzle.forward_target(machine.position, machine.direction) {
            None => return Some(NormalizeResult::Dead(DeadReason::Crash)),
            Some(n) => machine.move_to(n),
        },
        Action::TurnLeft => machine.turn(false),
        Action::TurnRight => machine.turn(true),
        Action::Paint(c) => machine.paint(c),
        Action::Call(g) => {
            match stack::call(machine, program, arena, g) {
                CallKind::Tail => stats.tail_calls += 1,
                CallKind::Push => {
                    stats.stack_pushes += 1;
                    let depth = arena.depth_of(machine.callers) as u32 + 1;
                    stats.max_call_depth = stats.max_call_depth.max(depth);
                }
            }
            if config.cycle_detection && cycles.observe(machine, arena) {
                return Some(NormalizeResult::Dead(DeadReason::Loop));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::{FunctionDraft, ResolvedProgram, program_from};
    use crate::puzzle::tests::puzzle;
    use crate::puzzle::{StaticPuzzle, load_catalog};
    use crate::reference::{RunStatus, reference_run_from};
    use crate::types::{Condition, Instruction, MAX_FUNCTIONS};

    fn run(
        p: &StaticPuzzle,
        prog: &PartialProgram,
        steps0: u32,
        cycle: bool,
    ) -> (NormalizeResult, Machine, StackArena) {
        let mut m = Machine::new(p);
        m.steps = steps0;
        let mut arena = StackArena::new();
        let config = Config {
            cycle_detection: cycle,
            ..Config::default()
        };
        let r = normalize(
            p,
            prog,
            &mut m,
            &mut arena,
            &mut CycleDetector::default(),
            &config,
            &mut SearchStats::default(),
        );
        (r, m, arena)
    }

    /// Left-packs a physical program into a fully decided partial program (L1).
    fn packed(prog: &ResolvedProgram) -> PartialProgram {
        let caps: [u8; MAX_FUNCTIONS] = std::array::from_fn(|f| prog.functions[f].len() as u8);
        let mut p = PartialProgram::new(caps);
        for f in 0..MAX_FUNCTIONS {
            let d: &mut FunctionDraft = &mut p.functions[f];
            for i in prog.functions[f].iter().flatten() {
                d.push(Cell::Resolved(*i));
            }
            if !d.closed() {
                d.end();
            }
        }
        p
    }

    fn caps(c: &[u8]) -> [u8; 5] {
        let mut out = [0; 5];
        out[..c.len()].copy_from_slice(c);
        out
    }

    #[test]
    fn t_normalize_loop_vectors() {
        // TV-07: tail self-loop.
        let p = puzzle(&["bB"], (0, 0), "right", &[1], 0);
        let prog = packed(&program_from(&[&[Some("callF1")]], caps(&[1])));
        let (r, m, _) = run(&p, &prog, 0, true);
        assert_eq!((r, m.steps), (NormalizeResult::Dead(DeadReason::Loop), 2));
        let (r, m, _) = run(&p, &prog, 0, false);
        assert_eq!(
            (r, m.steps),
            (NormalizeResult::Dead(DeadReason::StepLimit), 20001)
        );
        // TV-08: non-tail recursion never repeats a state exactly, but the
        // stack pumps (C-PUMP).
        let p = puzzle(&["bbB"], (0, 0), "right", &[2], 0);
        let prog = packed(&program_from(
            &[&[Some("callF1"), Some("forward")]],
            caps(&[2]),
        ));
        let (r, m, _) = run(&p, &prog, 0, true);
        assert_eq!((r, m.steps), (NormalizeResult::Dead(DeadReason::Loop), 2));
        let (r, m, arena) = run(&p, &prog, 0, false);
        assert_eq!(
            (r, m.steps),
            (NormalizeResult::Dead(DeadReason::StepLimit), 20001)
        );
        assert_eq!(arena.depth_of(m.callers), 20000);
        // Counting recursion that pops back down is not a loop:
        // F1 = [callF2, forward, forward], F2 = [red:callF2, turnLeft, turnLeft]
        // would be; here the stack shrinks back, so the run must finish.
        let p = puzzle(&["bbbB"], (0, 0), "right", &[3, 1], 0);
        let prog = packed(&program_from(
            &[
                &[Some("callF2"), Some("forward"), Some("callF1")],
                &[Some("forward")],
            ],
            caps(&[3, 1]),
        ));
        let (r, _, _) = run(&p, &prog, 0, true);
        assert_eq!(r, NormalizeResult::Solved);
    }

    #[test]
    fn t_step_limit_boundary_normalize() {
        let p = puzzle(&["bB"], (0, 0), "right", &[2], 0);
        let fwd = packed(&program_from(&[&[Some("forward")]], caps(&[1])));
        let (r, m, _) = run(&p, &fwd, 19_999, true);
        assert_eq!((r, m.steps), (NormalizeResult::Solved, 20_000));
        let (r, m, _) = run(&p, &fwd, 20_000, true);
        assert_eq!(
            (r, m.steps),
            (NormalizeResult::Dead(DeadReason::StepLimit), 20_001)
        );
        assert_eq!(m.position, p.start_tile);
        assert!(!m.stars.is_empty());
        let skip = packed(&program_from(
            &[&[Some("red:forward"), Some("forward")]],
            caps(&[2]),
        ));
        let (r, m, _) = run(&p, &skip, 19_999, true);
        assert_eq!(
            (r, m.steps),
            (NormalizeResult::Dead(DeadReason::StepLimit), 20_001)
        );
        assert!(!m.stars.is_empty());
        // A skipped CondOnly also consumes the step.
        let mut cond_only = PartialProgram::new(caps(&[2]));
        cond_only.function_mut(0).push(Cell::CondOnly(Color::Red));
        cond_only
            .function_mut(0)
            .push(Cell::Resolved(Instruction::any(Action::Forward)));
        let (r, _, _) = run(&p, &cond_only, 19_999, true);
        assert_eq!(r, NormalizeResult::Dead(DeadReason::StepLimit));
    }

    #[test]
    fn t_frontier_no_step() {
        // TV-13
        let p = puzzle(&["bB"], (0, 0), "right", &[2], 0);
        let empty = PartialProgram::new(caps(&[2]));
        let (r, m, _) = run(&p, &empty, 0, true);
        assert_eq!(
            r,
            NormalizeResult::OpenSlot {
                function: 0,
                index: 0
            }
        );
        assert_eq!(
            (m.steps, m.current),
            (0, Some(Frame { function: 0, pc: 0 }))
        );

        let mut co = PartialProgram::new(caps(&[2]));
        co.function_mut(0).push(Cell::CondOnly(Color::Red));
        let (r, m, _) = run(&p, &co, 0, true);
        assert_eq!(
            r,
            NormalizeResult::OpenSlot {
                function: 0,
                index: 1
            }
        );
        assert_eq!(m.steps, 1);

        let red = puzzle(&["rB"], (0, 0), "right", &[2], 0);
        let (r, m, _) = run(&red, &co, 0, true);
        assert_eq!(
            r,
            NormalizeResult::NeedAction {
                function: 0,
                index: 0,
                condition: Color::Red
            }
        );
        assert_eq!(
            (m.steps, m.current),
            (0, Some(Frame { function: 0, pc: 0 }))
        );

        // CondSet: stops on a member color without consuming anything,
        // skips (one step) on a color outside the set.
        let set = |m: u8| {
            let mut prog = PartialProgram::new(caps(&[2]));
            prog.function_mut(0)
                .push(Cell::CondSet(crate::types::ColorMask(m)));
            prog
        };
        let (r, m, _) = run(&red, &set(0b011), 0, true); // {red, green} on red
        assert_eq!(
            r,
            NormalizeResult::NeedAction {
                function: 0,
                index: 0,
                condition: Color::Red
            }
        );
        assert_eq!(m.steps, 0);
        let (r, m, _) = run(&p, &set(0b011), 0, true); // {red, green} on blue
        assert_eq!(
            r,
            NormalizeResult::OpenSlot {
                function: 0,
                index: 1
            }
        );
        assert_eq!(m.steps, 1);

        // Pending on another color: NeedCondition, nothing consumed.
        let mut pend = PartialProgram::new(caps(&[2]));
        pend.function_mut(0).push(Cell::Pending {
            action: Action::Forward,
            color: Color::Red,
        });
        let (r, m, _) = run(&p, &pend, 0, true);
        assert_eq!(
            r,
            NormalizeResult::NeedCondition {
                function: 0,
                index: 0
            }
        );
        assert_eq!(
            (m.steps, m.current),
            (0, Some(Frame { function: 0, pc: 0 }))
        );
        // Pending on its own color runs without a decision.
        let (r, m, _) = run(&red, &pend, 0, true);
        assert_eq!((r, m.steps), (NormalizeResult::Solved, 1));
    }

    #[test]
    fn t_rebuild_middle_end_to_end() {
        // TV-10
        let p = puzzle(&["bB"], (0, 0), "right", &[1, 2, 3], 1);
        let mut prog = PartialProgram::new(caps(&[1, 2, 3]));
        let r = |c, a| Cell::Resolved(Instruction::new(c, a));
        prog.function_mut(0)
            .push(r(Condition::Any, Action::Call(1)));
        prog.function_mut(1)
            .push(r(Condition::Color(Color::Blue), Action::Call(2)));
        prog.function_mut(2)
            .push(r(Condition::Any, Action::Paint(Color::Red)));
        prog.function_mut(2)
            .push(r(Condition::Any, Action::Call(1)));
        prog.function_mut(2)
            .push(r(Condition::Any, Action::Forward));
        let (res, mut m, mut arena) = run(&p, &prog, 0, true);
        assert_eq!(
            res,
            NormalizeResult::OpenSlot {
                function: 1,
                index: 1
            }
        );
        assert_eq!(m.steps, 5);
        assert_eq!(m.current, Some(Frame { function: 1, pc: 1 }));
        let f = |function, pc| Frame { function, pc };
        assert_eq!(arena.chain(m.callers), vec![f(1, 1), f(2, 2)]);
        // D-END on (F2, 1), then S-REBUILD.
        prog.function_mut(1).end();
        stack::rebuild_after_end(&mut m, &mut arena, 1, 1);
        assert_eq!(arena.chain(m.callers), vec![f(2, 2)]);
        assert_eq!(m.current, Some(f(1, 1)));
        let res = normalize(
            &p,
            &prog,
            &mut m,
            &mut arena,
            &mut CycleDetector::default(),
            &Config::default(),
            &mut SearchStats::default(),
        );
        assert_eq!((res, m.steps), (NormalizeResult::Solved, 6));
    }

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            z ^ (z >> 31)
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    fn random_program(p: &StaticPuzzle, rng: &mut Rng) -> ResolvedProgram {
        let enabled: Vec<u8> = (0..5).filter(|&f| p.capacities[f as usize] > 0).collect();
        let functions = std::array::from_fn(|f| {
            (0..p.capacities[f])
                .map(|_| {
                    if rng.below(4) == 0 {
                        return None;
                    }
                    let condition = match rng.below(5) {
                        0 => Condition::Color(Color::Red),
                        1 => Condition::Color(Color::Green),
                        2 => Condition::Color(Color::Blue),
                        _ => Condition::Any,
                    };
                    let action = match rng.below(9) {
                        0..=2 => Action::Forward,
                        3 => Action::TurnLeft,
                        4 => Action::TurnRight,
                        5 => Action::Paint(Color::from_index(rng.below(3) as u8)),
                        _ => Action::Call(enabled[rng.below(enabled.len() as u64) as usize]),
                    };
                    Some(Instruction::new(condition, action))
                })
                .collect()
        });
        ResolvedProgram { functions }
    }

    /// The low-water marks answer "lowest caller depth since observation
    /// i" exactly like a brute-force minimum, under random pushes, pops and
    /// observations.
    #[test]
    fn t_low_water_marks() {
        let mut rng = Rng(77);
        for _ in 0..2000 {
            let mut d = CycleDetector::default();
            let mut depth: u16 = rng.below(5) as u16;
            // (observation index, depths seen since it)
            let mut obs: Vec<u16> = Vec::new();
            let mut lows_since: Vec<u16> = Vec::new();
            for _ in 0..rng.below(200) {
                match rng.below(3) {
                    0 => depth += 1,
                    1 if depth > 0 => {
                        depth -= 1;
                        d.on_pop(depth);
                        for l in lows_since.iter_mut() {
                            *l = (*l).min(depth);
                        }
                    }
                    _ => {
                        let i = obs.len() as u32;
                        obs.push(depth);
                        lows_since.push(u16::MAX);
                        if d.lows.last().is_none_or(|&(_, low)| low < u16::MAX) {
                            d.lows.push((i, u16::MAX));
                        }
                    }
                }
                for (i, &l) in lows_since.iter().enumerate() {
                    assert_eq!(d.low_since(i as u32), l);
                }
            }
        }
    }

    /// T-DIFF (SPEC §25, L4): normalize on the left-packed program agrees
    /// with REFERENCE_RUN on the physical one.
    #[test]
    fn t_diff_random() {
        let path =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/levels_catalog.json");
        let puzzles: Vec<StaticPuzzle> = load_catalog(&path)
            .unwrap()
            .iter()
            .map(|r| StaticPuzzle::compile(r).unwrap())
            .collect();
        // Small puzzles succeed more often under random programs; pick one
        // a third of the time so every outcome is well exercised.
        let small = [
            puzzle(&["bB"], (0, 0), "right", &[3, 2], 7),
            puzzle(&["rgB", "bRg"], (0, 0), "right", &[4, 3, 2], 7),
            puzzle(&["bbB", "rBb"], (0, 0), "right", &[3, 3], 7),
        ];
        let mut rng = Rng(2026);
        let mut seen = std::collections::HashMap::new();
        for _ in 0..100_000 {
            let p = if rng.below(3) == 0 {
                &small[rng.below(small.len() as u64) as usize]
            } else {
                &puzzles[rng.below(puzzles.len() as u64) as usize]
            };
            let phys = random_program(p, &mut rng);
            let steps0 = if rng.below(10) == 0 { 19_990 } else { 0 };
            let reference = reference_run_from(p, &phys, steps0);
            for cycle in [false, true] {
                let (res, m, _) = run(p, &packed(&phys), steps0, cycle);
                let expected = match reference.status {
                    RunStatus::Success => NormalizeResult::Solved,
                    RunStatus::Crashed => NormalizeResult::Dead(DeadReason::Crash),
                    RunStatus::Stuck => NormalizeResult::Dead(DeadReason::StepLimit),
                    RunStatus::OutOfInstructions => NormalizeResult::Dead(DeadReason::ProgramEnded),
                };
                if res == NormalizeResult::Dead(DeadReason::Loop) {
                    assert!(
                        cycle && reference.status == RunStatus::Stuck,
                        "Loop but reference {:?}",
                        reference.status
                    );
                    *seen.entry("loop".to_string()).or_insert(0) += 1;
                    continue;
                }
                assert_eq!(res, expected, "program {:?}", phys.to_tokens());
                assert_eq!(m.steps, reference.steps);
                assert_eq!(p.row_col(m.position), (reference.row, reference.col));
                assert_eq!(m.direction, reference.direction);
                for t in 0..p.tile_count as usize {
                    if p.is_tile[t] {
                        assert_eq!(Some(m.colors.get(t as TileId)), reference.colors[t]);
                        assert_eq!(m.stars.contains(t as TileId), reference.stars[t]);
                    }
                }
                *seen.entry(format!("{:?}", reference.status)).or_insert(0) += 1;
            }
        }
        // Every outcome must actually be exercised.
        for k in ["Success", "Crashed", "Stuck", "OutOfInstructions", "loop"] {
            assert!(
                seen.get(k).copied().unwrap_or(0) > 100,
                "too few {k}: {seen:?}"
            );
        }
    }
}
