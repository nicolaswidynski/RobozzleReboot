//! Candidate generation (SPEC §14–§15), SOLVE / SEARCH (§17) and
//! finalization (§18).

use arrayvec::ArrayVec;

use crate::canonical::{is_useless_paint, turns_canonical};
use crate::heuristic::HeuristicCursor;
use crate::machine::{DeadReason, Machine};
use crate::normalize::{CycleDetector, NormalizeResult, normalize};
use crate::program::{Cell, PartialProgram, ResolvedProgram};
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::repair::RepairPool;
use crate::stack::{self, StackArena};
use crate::stats::{Config, Deadline, Limits, SearchStats};
use crate::types::{
    Action, Color, ColorMask, Condition, FnId, Instruction, MAX_FUNCTIONS, MAX_STEPS,
};

/// A branch's complete semantic state (SPEC §6). `Copy`, no heap.
#[derive(Debug, Clone, Copy)]
pub struct SearchState {
    pub program: PartialProgram,
    pub machine: Machine,
    pub used_slots: u8,
    /// Bit f set: F(f+1) is introduced (SPEC §14.4).
    pub introduced_functions: u8,
}

/// At most 3 moves + 3 paints + 5 calls.
pub type Actions = ArrayVec<Action, 11>;
/// At most (2 active + 2 deferred conditions) × 11 actions + END.
pub type Candidates = ArrayVec<Candidate, 48>;

/// An open-slot decision (SPEC §13).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Candidate {
    End,
    Place(Instruction),
    Defer(Color),
    /// `Pending { action, color: current tile color }` (D-PENDING).
    Pending(Action, Color),
    /// `CondSet(colors)` (D-DEFER-SET).
    DeferSet(ColorMask),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FoundBy {
    Exact,
    Heuristic,
    /// Local repair of a near-solution (`Config::repair`).
    Repair,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Solution {
    pub program: ResolvedProgram,
    pub cost: u8,
    pub steps: u32,
    /// Proven minimal: every smaller budget was searched exhaustively.
    pub optimal: bool,
    pub found_by: FoundBy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnsolvableReason {
    Disconnected,
    Exhausted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Solved(Solution),
    Unsolvable(UnsolvableReason),
    Timeout,
}

#[derive(Debug, Clone)]
pub struct SolveResult {
    pub outcome: Outcome,
    pub stats: SearchStats,
    /// Every program with fewer occupied slots is proven not to solve the
    /// puzzle (budgets `0..lower_bound` were searched exhaustively).
    pub lower_bound: u8,
}

pub struct Solver<'a> {
    pub puzzle: &'a StaticPuzzle,
    pub config: Config,
    pub stats: SearchStats,
    /// The stack arena of the running phase; the other phase's is parked so
    /// that each paused search keeps its stack nodes.
    pub(crate) arena: StackArena,
    parked_arena: StackArena,
    pub(crate) cycles: CycleDetector,
    pub(crate) deadline: Deadline,
    exact: ExactCursor,
    pub(crate) heuristic: HeuristicCursor,
    pub(crate) repair: RepairPool,
    /// Capacities the search uses. With anonymous functions, every enabled
    /// auxiliary function gets the largest auxiliary capacity, at indices
    /// 1..=n in order of introduction; otherwise the real capacities.
    capacities: [u8; MAX_FUNCTIONS],
    /// Real auxiliary capacities, largest first (INV-FIT).
    aux_capacities: ArrayVec<u8, 4>,
}

/// Result of running a resumable search until it stops.
pub(crate) enum Step {
    Found(Solution),
    /// Nothing left to search within the requested scope.
    Exhausted,
    /// The phase's node cap (or the global limit) was reached.
    Paused,
}

/// Resumable exact iterative deepening (SPEC §17.2) on an explicit stack,
/// so that the portfolio (§17.1) can pause it and later continue exactly
/// where it stopped.
#[derive(Default)]
struct ExactCursor {
    /// The budget being searched; every smaller budget is exhausted.
    budget: u8,
    started: bool,
    iteration_start: u64,
    stack: Vec<ExactFrame>,
}

struct ExactFrame {
    kids: Vec<SearchState>,
    next: usize,
    /// Arena length after the kids were created; restored before each kid.
    mark: usize,
}

/// SOLVE (SPEC §17.1).
pub fn solve(puzzle: &StaticPuzzle, config: Config, limits: Limits) -> SolveResult {
    let mut solver = Solver::new(puzzle, config, limits);
    let outcome = solver.run();
    solver.stats.millis = solver.deadline.elapsed().as_millis() as u64;
    let lower_bound = match &outcome {
        Outcome::Solved(s) if s.optimal => s.cost,
        _ => solver.exact.budget,
    };
    SolveResult {
        outcome,
        stats: solver.stats,
        lower_bound,
    }
}

impl<'a> Solver<'a> {
    pub fn new(puzzle: &'a StaticPuzzle, config: Config, limits: Limits) -> Self {
        Self {
            puzzle,
            config,
            stats: SearchStats::default(),
            arena: StackArena::new(),
            parked_arena: StackArena::new(),
            cycles: CycleDetector::default(),
            deadline: Deadline::new(limits),
            exact: ExactCursor::default(),
            heuristic: HeuristicCursor::default(),
            repair: RepairPool::default(),
            capacities: puzzle.capacities,
            aux_capacities: ArrayVec::new(),
        }
        .with_capacities()
    }

    fn with_capacities(mut self) -> Self {
        // P-SINGLE: an auxiliary function of capacity 1 could only hold one
        // cell, which a minimal solution never has; treat it as disabled.
        let min_aux = if self.config.peephole { 2 } else { 1 };
        for f in 1..MAX_FUNCTIONS {
            if self.capacities[f] < min_aux {
                self.capacities[f] = 0;
            }
        }
        let mut aux: ArrayVec<u8, 4> = self.capacities[1..]
            .iter()
            .copied()
            .filter(|&c| c > 0)
            .collect();
        aux.sort_unstable_by(|a, b| b.cmp(a));
        if self.config.anonymous_functions {
            let largest = aux.first().copied().unwrap_or(0);
            for f in 1..MAX_FUNCTIONS {
                self.capacities[f] = if f <= aux.len() { largest } else { 0 };
            }
        }
        self.aux_capacities = aux;
        self
    }

    /// The root state of every iteration (SPEC §17.1).
    pub fn root(&self) -> SearchState {
        SearchState {
            program: PartialProgram::new(self.capacities),
            machine: Machine::new(self.puzzle),
            used_slots: 0,
            introduced_functions: 0b00001,
        }
    }

    fn enabled_functions(&self) -> u8 {
        (0..MAX_FUNCTIONS)
            .filter(|&f| self.capacities[f] > 0)
            .fold(0, |m, f| m | (1 << f))
    }

    /// Functions a new `Call` may target (P-DISABLED, P-SYM, D-NEWFN).
    fn callable(&self, introduced: u8) -> u8 {
        let enabled = self.enabled_functions();
        if !self.config.function_symmetry {
            return enabled;
        }
        // One class per capacity among the auxiliary functions (a single
        // class with anonymous functions); the lowest-index fresh member of
        // each class is callable.
        let mut callable = introduced & enabled;
        for f in 1..MAX_FUNCTIONS {
            let cap = self.capacities[f];
            if cap == 0 || introduced & (1 << f) != 0 {
                continue;
            }
            let lower_fresh_same_class =
                (1..f).any(|g| self.capacities[g] == cap && introduced & (1 << g) == 0);
            if !lower_fresh_same_class {
                callable |= 1 << f;
            }
        }
        callable
    }

    /// Whether a child already needs more slots than the budget once the
    /// P-RESERVE slots are counted.
    fn over_reserve(&mut self, child: &SearchState, budget: u8) -> bool {
        let over = self.config.peephole && child.used_slots + self.reserved_slots(child) > budget;
        if over {
            self.stats.prune_reserve += 1;
        }
        over
    }

    /// P-RESERVE (SPEC §15.5): every introduced auxiliary body that is not
    /// closed still needs `2 − len` cells in any minimal solution (P-EMPTYFN
    /// and P-SINGLE), so this many slots are reserved on top of `used`.
    fn reserved_slots(&self, s: &SearchState) -> u8 {
        (1..MAX_FUNCTIONS)
            .filter(|&g| s.introduced_functions & (1 << g) != 0)
            .map(|g| &s.program.functions[g])
            .filter(|d| !d.closed())
            .map(|d| 2u8.saturating_sub(d.len))
            .sum()
    }

    /// INV-FIT: the auxiliary bodies, with function `f` at length `len`,
    /// can still be matched to distinct real functions of sufficient
    /// capacity (sorted greedy matching is exact for threshold constraints).
    fn aux_fits(&self, program: &PartialProgram, f: FnId, len: u8) -> bool {
        let mut lens: ArrayVec<u8, 4> = (1..=self.aux_capacities.len())
            .map(|g| {
                if g == f as usize {
                    len
                } else {
                    program.functions[g].len
                }
            })
            .collect();
        lens.sort_unstable_by(|a, b| b.cmp(a));
        lens.iter().zip(&self.aux_capacities).all(|(l, c)| l <= c)
    }

    /// Maps an internal program to real function names and capacities:
    /// the longest body goes to the largest real capacity (ties by index),
    /// and every call is renamed accordingly.
    pub(crate) fn realize(&self, program: &PartialProgram) -> PartialProgram {
        let mut name: [u8; MAX_FUNCTIONS] = [0, 1, 2, 3, 4];
        let n = if self.config.anonymous_functions {
            let n = self.aux_capacities.len();
            let mut internal: ArrayVec<usize, 4> = (1..=n).collect();
            internal.sort_by_key(|&g| (std::cmp::Reverse(program.functions[g].len), g));
            // The real functions the search may use: those not disabled by
            // P-SINGLE (exactly the ones counted in `aux_capacities`).
            let min_aux = if self.config.peephole { 2 } else { 1 };
            let mut real: ArrayVec<usize, 4> = (1..MAX_FUNCTIONS)
                .filter(|&f| self.puzzle.capacities[f] >= min_aux)
                .collect();
            real.sort_by_key(|&f| (std::cmp::Reverse(self.puzzle.capacities[f]), f));
            for (&g, &f) in internal.iter().zip(&real) {
                name[g] = f as u8;
            }
            n
        } else {
            MAX_FUNCTIONS - 1
        };
        let rename = |a: Action| match a {
            Action::Call(g) => Action::Call(name[g as usize]),
            other => other,
        };
        let mut out = PartialProgram::new(self.puzzle.capacities);
        for (src, &target) in program.functions.iter().zip(&name).take(n + 1) {
            if src.len == 0 {
                continue;
            }
            let dst = &mut out.functions[target as usize];
            assert!(
                src.len <= dst.capacity,
                "INV-FIT violated: body does not fit"
            );
            for (k, cell) in src.decided().iter().enumerate() {
                dst.cells[k] = match *cell {
                    Cell::Resolved(i) => {
                        Cell::Resolved(Instruction::new(i.condition, rename(i.action)))
                    }
                    Cell::Pending { action, color } => Cell::Pending {
                        action: rename(action),
                        color,
                    },
                    other => other,
                };
            }
            dst.len = src.len;
            dst.ended = true;
        }
        out
    }

    /// The deterministic portfolio (SPEC §17.1). Exact and heuristic search
    /// alternate in equal slices that double every round; both resume where
    /// they stopped. Once the heuristic finds a solution, all remaining
    /// nodes go to exact search below its cost, which either finds a shorter
    /// solution or proves this one minimal.
    fn run(&mut self) -> Outcome {
        if !self.puzzle.stars_connected() {
            return Outcome::Unsolvable(UnsolvableReason::Disconnected); // P-CONN
        }
        let max_budget = self.puzzle.total_capacity() as u8;
        if self.config.heuristic_only {
            // FINDER benchmark mode (BENCHMARKS.md): no exact search at all.
            return match self.heuristic_resume() {
                Step::Found(s) => Outcome::Solved(s),
                Step::Exhausted => Outcome::Unsolvable(UnsolvableReason::Exhausted),
                Step::Paused => Outcome::Timeout,
            };
        }
        if !self.config.heuristic {
            return match self.exact_resume(max_budget) {
                Step::Found(s) => Outcome::Solved(s),
                Step::Exhausted => Outcome::Unsolvable(UnsolvableReason::Exhausted),
                Step::Paused => Outcome::Timeout,
            };
        }
        let mut slice = self
            .deadline
            .node_limit()
            .map_or(1_000_000, |n| (n / 60).max(1));
        let mut best = loop {
            let cap = self.stats.search_nodes.saturating_add(slice);
            self.deadline.set_phase_cap(Some(cap));
            match self.exact_resume(max_budget) {
                Step::Found(s) => return Outcome::Solved(s),
                Step::Exhausted => return Outcome::Unsolvable(UnsolvableReason::Exhausted),
                Step::Paused if self.deadline.limit_reached(self.stats.search_nodes) => {
                    return Outcome::Timeout;
                }
                Step::Paused => {}
            }
            let cap = self.stats.search_nodes.saturating_add(slice);
            self.deadline.set_phase_cap(Some(cap));
            std::mem::swap(&mut self.arena, &mut self.parked_arena);
            let step = self.heuristic_resume();
            std::mem::swap(&mut self.arena, &mut self.parked_arena);
            match step {
                Step::Found(s) => break s,
                Step::Exhausted => return Outcome::Unsolvable(UnsolvableReason::Exhausted),
                Step::Paused if self.deadline.limit_reached(self.stats.search_nodes) => {
                    return Outcome::Timeout;
                }
                Step::Paused => {}
            }
            slice = slice.saturating_mul(2);
        };
        self.deadline.set_phase_cap(None);
        if best.cost > 0 {
            match self.exact_resume(best.cost - 1) {
                Step::Found(s) => return Outcome::Solved(s),
                Step::Exhausted => best.optimal = true,
                Step::Paused => {}
            }
        }
        Outcome::Solved(best)
    }

    /// Continues exact IDDFS until a solution, until every budget up to
    /// `max_budget` is exhausted, or until the node cap.
    fn exact_resume(&mut self, max_budget: u8) -> Step {
        loop {
            if self.exact.budget > max_budget {
                return Step::Exhausted;
            }
            match self.exact_iteration() {
                Step::Exhausted => {
                    self.stats
                        .nodes_per_budget
                        .push(self.stats.search_nodes - self.exact.iteration_start);
                    self.exact.budget += 1;
                    self.exact.started = false;
                }
                other => return other,
            }
        }
    }

    /// One budget of SEARCH (SPEC §17.2), resumable.
    fn exact_iteration(&mut self) -> Step {
        let budget = self.exact.budget;
        if !self.exact.started {
            if self.deadline.check(self.stats.search_nodes + 1).is_err() {
                return Step::Paused;
            }
            self.arena.clear();
            self.exact.stack.clear();
            self.exact.iteration_start = self.stats.search_nodes;
            self.exact.started = true;
            let mut root = self.root();
            match self.normalize_counted(&mut root) {
                NormalizeResult::Solved => return Step::Found(self.finalize(&root)),
                NormalizeResult::Dead(_) => return Step::Exhausted,
                r => self.push_exact_frame(&root, r, budget),
            }
        }
        loop {
            let Some(top) = self.exact.stack.last_mut() else {
                return Step::Exhausted;
            };
            if top.next == top.kids.len() {
                self.exact.stack.pop();
                continue;
            }
            if self.deadline.check(self.stats.search_nodes + 1).is_err() {
                return Step::Paused;
            }
            let mut kid = top.kids[top.next];
            top.next += 1;
            let mark = top.mark;
            self.arena.truncate(mark);
            self.stats.candidates_searched += 1;
            match self.normalize_counted(&mut kid) {
                NormalizeResult::Solved => return Step::Found(self.finalize(&kid)),
                NormalizeResult::Dead(_) => {}
                r => self.push_exact_frame(&kid, r, budget),
            }
        }
    }

    fn push_exact_frame(&mut self, state: &SearchState, result: NormalizeResult, budget: u8) {
        let kids = self.children(state, result, budget);
        let mark = self.arena.mark();
        self.exact.stack.push(ExactFrame {
            kids,
            next: 0,
            mark,
        });
        let depth = self.exact.stack.len() as u32;
        self.stats.max_search_depth = self.stats.max_search_depth.max(depth);
    }

    /// Normalizes one search node (SPEC §10), counting it.
    pub(crate) fn normalize_counted(&mut self, s: &mut SearchState) -> NormalizeResult {
        self.stats.search_nodes += 1;
        debug_assert!(s.program.check_prefix(), "INV-PREFIX");
        debug_assert_eq!(s.used_slots, s.program.occupied_slots(), "INV-COST");
        let r = normalize(
            self.puzzle,
            &s.program,
            &mut s.machine,
            &mut self.arena,
            &mut self.cycles,
            &self.config,
            &mut self.stats,
        );
        if let NormalizeResult::Dead(reason) = r {
            self.count_dead(reason);
        }
        r
    }

    pub(crate) fn count_dead(&mut self, reason: DeadReason) {
        match reason {
            DeadReason::Crash => self.stats.dead_crash += 1,
            DeadReason::ProgramEnded => self.stats.dead_program_ended += 1,
            DeadReason::StepLimit => self.stats.dead_step_limit += 1,
            DeadReason::Loop => self.stats.dead_loop += 1,
        }
    }

    /// Every child of a frontier, decisions applied (SPEC §13), in
    /// generation order. Used by the heuristic phase.
    pub(crate) fn children(
        &mut self,
        state: &SearchState,
        result: NormalizeResult,
        budget: u8,
    ) -> Vec<SearchState> {
        let mut out = Vec::new();
        match result {
            NormalizeResult::OpenSlot { function, index } => {
                for cand in self.open_candidates(state, function, index, budget) {
                    let mut child = *state;
                    self.apply_open(&mut child, function, index, cand);
                    if self.over_reserve(&child, budget) {
                        continue;
                    }
                    out.push(child);
                }
            }
            NormalizeResult::NeedCondition { function, index } => {
                if self.config.step_cut && state.machine.steps == MAX_STEPS {
                    self.stats.prune_step_cut += 1;
                    return out;
                }
                for condition in self.condition_candidates(state, function, index) {
                    let mut child = *state;
                    child
                        .program
                        .function_mut(function)
                        .resolve_pending(index, condition);
                    self.stats.pending_resolved += 1;
                    out.push(child);
                }
            }
            NormalizeResult::NeedAction {
                function,
                index,
                condition,
            } => {
                if self.config.step_cut && state.machine.steps == MAX_STEPS {
                    self.stats.prune_step_cut += 1;
                    return out;
                }
                // D-RESOLVE: the member conditioned on `condition` runs now.
                for action in self.need_candidates(state, function, index, condition) {
                    let mut child = *state;
                    child
                        .program
                        .function_mut(function)
                        .resolve_deferred(index, condition, action);
                    if let Action::Call(g) = action {
                        child.introduced_functions |= 1 << g;
                    }
                    self.stats.condonly_resolved += 1;
                    if self.over_reserve(&child, budget) {
                        continue;
                    }
                    out.push(child);
                }
                // D-NARROW: the members of a CondSet that still skip on
                // `condition`; normalize then skips the cell (one step).
                if let Cell::CondSet(mask) = state.program.function(function).cell(index) {
                    let rest = ColorMask(mask.0 & !(1 << condition as u8));
                    let mut child = *state;
                    child.program.function_mut(function).cells[index as usize] =
                        if rest.count() == 1 {
                            Cell::CondOnly(rest.iter().next().expect("one color"))
                        } else {
                            Cell::CondSet(rest)
                        };
                    self.stats.condset_narrowed += 1;
                    out.push(child);
                }
            }
            NormalizeResult::Solved | NormalizeResult::Dead(_) => {}
        }
        self.stats.candidates_generated += out.len() as u64;
        out
    }

    /// D-END, D-PLACE, D-DEFER (SPEC §13).
    fn apply_open(&mut self, s: &mut SearchState, f: FnId, k: u8, cand: Candidate) {
        match cand {
            Candidate::End => {
                s.program.function_mut(f).end();
                self.stats.ends_selected += 1;
                let rebuilt = stack::rebuild_after_end(&mut s.machine, &mut self.arena, f, k);
                if rebuilt > 0 {
                    self.stats.stack_rebuilds += 1;
                    self.stats.stack_nodes_rebuilt += rebuilt as u64;
                }
            }
            Candidate::Place(i) => {
                s.program.function_mut(f).push(Cell::Resolved(i));
                s.used_slots += 1;
                if let Action::Call(g) = i.action {
                    s.introduced_functions |= 1 << g;
                }
            }
            Candidate::Defer(c) => {
                s.program.function_mut(f).push(Cell::CondOnly(c));
                s.used_slots += 1;
                self.stats.condonly_created += 1;
            }
            Candidate::DeferSet(mask) => {
                s.program.function_mut(f).push(Cell::CondSet(mask));
                s.used_slots += 1;
                self.stats.condset_created += 1;
            }
            Candidate::Pending(action, color) => {
                s.program
                    .function_mut(f)
                    .push(Cell::Pending { action, color });
                s.used_slots += 1;
                if let Action::Call(g) = action {
                    s.introduced_functions |= 1 << g;
                }
                self.stats.pending_created += 1;
            }
        }
        if self.config.anonymous_functions && f != 0 && cand != Candidate::End {
            self.close_unfittable(s);
        }
    }

    /// INV-FIT deduction (SPEC §14.5): once an auxiliary body can no longer
    /// grow, no completion can grow it (lengths only increase), so it is
    /// closed at once, as the engine's capacity would close it. This is not
    /// a decision and costs nothing; it restores tail calls and spares a
    /// node whose only child would be END.
    fn close_unfittable(&mut self, s: &mut SearchState) {
        for h in 1..=self.aux_capacities.len() as FnId {
            let d = s.program.function(h);
            if d.closed() || d.len == 0 || self.aux_fits(&s.program, h, d.len + 1) {
                continue;
            }
            let len = d.len;
            s.program.function_mut(h).end();
            self.stats.forced_closes += 1;
            let rebuilt = stack::rebuild_after_end(&mut s.machine, &mut self.arena, h, len);
            if rebuilt > 0 {
                self.stats.stack_rebuilds += 1;
                self.stats.stack_nodes_rebuilt += rebuilt as u64;
            }
        }
    }

    /// P-ENDDEAD (SPEC §15.3a): END at `(f, k)` ends the program if every
    /// suspended frame is `(f, k)` too, because S-REBUILD removes them all.
    fn end_leaves_no_caller(&self, state: &SearchState, f: FnId, k: u8) -> bool {
        let target = stack::Frame { function: f, pc: k };
        let mut cursor = state.machine.callers;
        while let Some(id) = cursor {
            let node = self.arena.get(id);
            if node.frame != target {
                return false;
            }
            cursor = node.parent;
        }
        true
    }

    /// The output shape the game requires (SPEC §18): exactly `cap[f]` slots
    /// per function, calls only to enabled functions, paints only in allowed
    /// colors. The reference interpreter cannot see capacities, so this is
    /// checked separately.
    pub(crate) fn assert_shape(&self, program: &ResolvedProgram) {
        for (f, slots) in program.functions.iter().enumerate() {
            assert_eq!(
                slots.len(),
                self.puzzle.capacities[f] as usize,
                "F{} slot count",
                f + 1
            );
            for i in slots.iter().flatten() {
                match i.action {
                    Action::Call(g) => assert!(
                        self.puzzle.capacities[g as usize] > 0,
                        "call to disabled F{}",
                        g + 1
                    ),
                    Action::Paint(c) => {
                        assert!(self.puzzle.allowed_paints.contains(c), "paint not allowed")
                    }
                    _ => {}
                }
            }
        }
    }

    /// Actions available for a new cell (SPEC §14.3), in search order:
    /// Forward, calls to introduced functions, turns, calls to new
    /// functions, paints.
    fn actions(&mut self, state: &SearchState) -> Actions {
        let introduced = state.introduced_functions;
        let callable = self.callable(introduced);
        let excluded = self.enabled_functions() & !callable;
        self.stats.prune_symmetry += excluded.count_ones() as u64;
        let mut out = Actions::new();
        out.push(Action::Forward);
        out.extend(
            (0..MAX_FUNCTIONS as u8)
                .filter(|g| callable & introduced & (1 << g) != 0)
                .map(Action::Call),
        );
        out.push(Action::TurnLeft);
        out.push(Action::TurnRight);
        out.extend(
            (0..MAX_FUNCTIONS as u8)
                .filter(|g| callable & !introduced & (1 << g) != 0)
                .map(Action::Call),
        );
        out.extend(self.puzzle.allowed_paints.iter().map(Action::Paint));
        out
    }

    /// Whether placing `cell` at index `k` of function `f` passes P-PAINT
    /// and P-TURN.
    fn canonical(
        &mut self,
        state: &SearchState,
        f: FnId,
        k: u8,
        cell: Cell,
        resolving: bool,
    ) -> bool {
        if !self.config.peephole {
            return true;
        }
        let ok = match cell {
            Cell::Resolved(i) if is_useless_paint(i) => false,
            Cell::Resolved(_) => {
                let d = state.program.function(f);
                let mut cells = d.cells;
                cells[k as usize] = cell;
                let len = if resolving {
                    d.len as usize
                } else {
                    k as usize + 1
                };
                turns_canonical(&cells[..len], k as usize)
            }
            _ => true,
        };
        if !ok {
            self.stats.prune_peephole += 1;
        }
        ok
    }

    /// P-CRASH: an action that runs immediately in this state and drives the
    /// robot off the board can only lead to `Dead(Crash)`.
    fn crashes_now(&mut self, state: &SearchState, action: Action) -> bool {
        let dead = self.config.peephole
            && action == Action::Forward
            && self
                .puzzle
                .forward_target(state.machine.position, state.machine.direction)
                .is_none();
        if dead {
            self.stats.prune_crash += 1;
        }
        dead
    }

    /// Candidates at `OpenSlot{f, k}` (SPEC §14.1), in search order.
    pub fn open_candidates(
        &mut self,
        state: &SearchState,
        f: FnId,
        k: u8,
        budget: u8,
    ) -> Candidates {
        // P-EMPTYFN; P-ENDDEAD: with no suspended caller, END ends the
        // program while stars remain.
        let mut end_allowed = true;
        if self.config.peephole {
            if k == 0 {
                end_allowed = false; // P-EMPTYFN
            } else if f != 0 && k == 1 {
                end_allowed = false; // P-SINGLE: an auxiliary body never has exactly one cell
                self.stats.prune_single += 1;
            } else if self.end_leaves_no_caller(state, f, k) {
                end_allowed = false; // P-ENDDEAD
                self.stats.prune_end_dead += 1;
            }
        }
        if self.config.step_cut && state.machine.steps == MAX_STEPS {
            self.stats.prune_step_cut += 1; // P-STEPCUT: only END survives
            let mut out = Candidates::new();
            if end_allowed {
                out.push(Candidate::End);
            }
            return out;
        }
        let mut out = Candidates::new();
        // INV-FIT: with anonymous functions, appending to an auxiliary body
        // must keep the bodies matchable to the real capacities.
        let fits =
            !self.config.anonymous_functions || f == 0 || self.aux_fits(&state.program, f, k + 1);
        if !fits {
            self.stats.prune_capacity += 1;
        }
        if state.used_slots < budget && fits {
            let actions = self.actions(state);
            let pc = self.puzzle.possible_colors;
            let cur = state.machine.tile_color();
            if pc.count() >= 2 && self.config.lazy_active_conditions {
                // D-PENDING: `Any` and `Color(cur)` merged until observable.
                for &action in &actions {
                    if self.crashes_now(state, action) {
                        continue;
                    }
                    if self.config.peephole && action == Action::Paint(cur) {
                        // `Color(cur): Paint(cur)` is forbidden (P-PAINT), so
                        // only `Any` is left.
                        out.push(Candidate::Place(Instruction::any(action)));
                    } else {
                        out.push(Candidate::Pending(action, cur));
                    }
                }
            } else {
                let mut conditions: ArrayVec<Condition, 2> = ArrayVec::new();
                conditions.push(Condition::Any);
                if pc.count() >= 2 {
                    conditions.push(Condition::Color(cur)); // P-COLOR
                }
                for &condition in &conditions {
                    for &action in &actions {
                        if self.crashes_now(state, action) {
                            continue;
                        }
                        let i = Instruction::new(condition, action);
                        if self.canonical(state, f, k, Cell::Resolved(i), false) {
                            out.push(Candidate::Place(i));
                        }
                    }
                }
            }
            if pc.count() >= 2 {
                let deferred = ColorMask(pc.0 & !(1 << cur as u8));
                let as_set = self.config.lazy_conditions
                    && self.config.condition_sets
                    && deferred.count() >= 2;
                if as_set {
                    out.push(Candidate::DeferSet(deferred)); // D-DEFER-SET
                }
                for d in deferred.iter() {
                    if as_set {
                        continue;
                    }
                    if self.config.lazy_conditions {
                        out.push(Candidate::Defer(d));
                    } else {
                        for &action in &actions {
                            let i = Instruction::new(Condition::Color(d), action);
                            if self.canonical(state, f, k, Cell::Resolved(i), false) {
                                out.push(Candidate::Place(i));
                            }
                        }
                    }
                }
            }
        } else if fits {
            self.stats.prune_budget += 1;
        }
        if end_allowed {
            out.push(Candidate::End);
        }
        out
    }

    /// Choices at `NeedCondition{f, k}` (D-CHOOSE): `Any` runs the action
    /// now, `Color(c)` skips it.
    pub fn condition_candidates(
        &mut self,
        state: &SearchState,
        f: FnId,
        k: u8,
    ) -> ArrayVec<Condition, 2> {
        let Cell::Pending { action, color } = state.program.function(f).cell(k) else {
            unreachable!("NeedCondition on a non-Pending cell");
        };
        let mut out = ArrayVec::new();
        if !self.crashes_now(state, action) {
            let cell = Cell::Resolved(Instruction::any(action));
            if self.canonical(state, f, k, cell, true) {
                out.push(Condition::Any);
            }
        }
        let cell = Cell::Resolved(Instruction::new(Condition::Color(color), action));
        if self.canonical(state, f, k, cell, true) {
            out.push(Condition::Color(color));
        }
        out
    }

    /// Actions at `NeedAction{f, k, c}` (SPEC §14.2).
    pub fn need_candidates(&mut self, state: &SearchState, f: FnId, k: u8, c: Color) -> Actions {
        self.actions(state)
            .into_iter()
            .filter(|&a| {
                if self.crashes_now(state, a) {
                    return false;
                }
                let cell = Cell::Resolved(Instruction::new(Condition::Color(c), a));
                self.canonical(state, f, k, cell, true)
            })
            .collect()
    }

    /// FINALIZE (SPEC §18).
    fn finalize(&self, state: &SearchState) -> Solution {
        debug_assert!(!state.program.has_cond_only(), "INV-FIN");
        let program = self.realize(&state.program).to_physical();
        self.assert_shape(&program);
        let run = reference_run(self.puzzle, &program);
        assert_eq!(
            run.status,
            RunStatus::Success,
            "INV-VERIFY: {:?}",
            program.to_tokens()
        );
        Solution {
            program,
            cost: state.used_slots,
            steps: run.steps,
            optimal: true,
            found_by: FoundBy::Exact,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::instruction_token;
    use crate::puzzle::tests::puzzle;

    fn root_candidates(p: &StaticPuzzle, config: Config, budget: u8) -> Vec<String> {
        let mut solver = Solver::new(p, config, Limits::default());
        let state = solver.root();
        solver
            .open_candidates(&state, 0, 0, budget)
            .into_iter()
            .map(|c| match c {
                Candidate::End => "END".to_string(),
                Candidate::Place(i) => instruction_token(i),
                Candidate::Defer(c) => format!("{}:?", c.name()),
                Candidate::DeferSet(m) => format!(
                    "{{{}}}:?",
                    m.iter().map(Color::name).collect::<Vec<_>>().join(",")
                ),
                Candidate::Pending(a, c) => format!(
                    "{}|any:{}",
                    c.name(),
                    instruction_token(Instruction::any(a))
                ),
            })
            .collect()
    }

    fn sorted(mut v: Vec<String>) -> Vec<String> {
        v.sort();
        v
    }

    fn strs(v: &[&str]) -> Vec<String> {
        sorted(v.iter().map(|s| s.to_string()).collect())
    }

    /// TV-14 (SPEC §24.4)
    #[test]
    fn t_candidates() {
        let d = Config::default();
        let one_color = puzzle(&["bbB"], (0, 0), "right", &[2], 0);
        assert_eq!(
            sorted(root_candidates(&one_color, d, 1)),
            strs(&["forward", "turnLeft", "turnRight", "callF1"])
        );
        let no_peep = Config {
            peephole: false,
            ..d
        };
        assert_eq!(root_candidates(&one_color, no_peep, 1).len(), 5);
        assert!(root_candidates(&one_color, no_peep, 1).contains(&"END".to_string()));

        // SPEC TV-14c..e describe the candidate sets without D-PENDING.
        let d = Config {
            lazy_active_conditions: false,
            ..d
        };
        let two = puzzle(&["rbB"], (0, 0), "right", &[2], 0);
        let c = root_candidates(&two, d, 1);
        assert_eq!(c.len(), 9);
        assert!(c.contains(&"blue:?".to_string()) && c.contains(&"red:callF1".to_string()));
        let eager = root_candidates(
            &two,
            Config {
                lazy_conditions: false,
                ..d
            },
            1,
        );
        assert_eq!(eager.len(), 12);
        assert!(eager.contains(&"blue:turnLeft".to_string()));

        let paint = puzzle(&["rbB"], (0, 0), "right", &[2], 1);
        let c = root_candidates(&paint, d, 1);
        assert_eq!(c.len(), 10);
        assert!(c.contains(&"paintRed".to_string()) && !c.contains(&"red:paintRed".to_string()));

        assert!(root_candidates(&one_color, d, 0).is_empty());

        // With D-PENDING: one candidate per action instead of two.
        let lazy = Config::default();
        assert_eq!(
            sorted(root_candidates(&two, lazy, 1)),
            strs(&[
                "red|any:forward",
                "red|any:turnLeft",
                "red|any:turnRight",
                "red|any:callF1",
                "blue:?"
            ])
        );
        assert_eq!(
            sorted(root_candidates(&paint, lazy, 1)),
            strs(&[
                "red|any:forward",
                "red|any:turnLeft",
                "red|any:turnRight",
                "red|any:callF1",
                "paintRed",
                "blue:?"
            ])
        );
        // D-DEFER-SET: with three possible colors, one deferred set instead
        // of one CondOnly per other color.
        let three = puzzle(&["rgbB"], (0, 0), "right", &[2], 0);
        let c = root_candidates(&three, lazy, 1);
        assert!(c.contains(&"{green,blue}:?".to_string()), "{c:?}");
        assert!(!c.iter().any(|x| x == "green:?" || x == "blue:?"));
        let per_color = root_candidates(
            &three,
            Config {
                condition_sets: false,
                ..lazy
            },
            1,
        );
        assert!(
            per_color.contains(&"green:?".to_string()) && per_color.contains(&"blue:?".to_string())
        );
        assert_eq!(per_color.len(), c.len() + 1);
        // P-CRASH: facing a gap, no Forward is generated.
        let wall = puzzle(&["rbB"], (0, 0), "left", &[2], 0);
        assert!(
            !root_candidates(&wall, lazy, 1)
                .iter()
                .any(|c| c.contains("forward"))
        );
    }

    fn solve_default(p: &StaticPuzzle, config: Config) -> SolveResult {
        solve(p, config, Limits::default())
    }

    /// (rows, start, dir, caps, paints, expected cost or None = Exhausted)
    type Mc = (
        &'static [&'static str],
        (i64, i64),
        &'static str,
        &'static [i64],
        i64,
        Option<u8>,
    );
    const MC: &[Mc] = &[
        (&["bbbB"], (0, 0), "right", &[3], 0, Some(2)),
        (&["Bbbb"], (0, 3), "right", &[4], 0, None),
        (&["bbb", "b b", "bbB"], (0, 0), "right", &[4], 0, Some(4)),
        (&["bbr", "  b", "  B"], (0, 0), "right", &[4], 0, Some(3)),
        (&["bbbbB"], (0, 0), "right", &[1, 2], 0, Some(3)),
        (&["BbbbB"], (0, 2), "left", &[3, 1], 0, None),
    ];

    /// §24.5 under every Config (t_e2e_min_cost + t_config_equivalence).
    #[test]
    fn t_e2e_min_cost_all_configs() {
        for (n, &(rows, start, dir, caps, paints, expected)) in MC.iter().enumerate() {
            let p = puzzle(rows, start, dir, caps, paints);
            for config in Config::all_combinations() {
                let r = solve_default(&p, config);
                match (expected, &r.outcome) {
                    (Some(cost), Outcome::Solved(s)) => {
                        assert_eq!(s.cost, cost, "MC-0{} {config:?}", n + 1);
                        assert_eq!(s.program.occupied_slots(), cost as usize);
                    }
                    (None, Outcome::Unsolvable(UnsolvableReason::Exhausted)) => {}
                    other => panic!("MC-0{} {config:?}: {other:?}", n + 1),
                }
            }
        }
    }

    #[test]
    fn t_tv10_puzzle_minimal() {
        // The TV-10 puzzle is solved trivially; the point is that the search
        // copes with three functions and paint.
        let p = puzzle(&["bB"], (0, 0), "right", &[1, 2, 3], 1);
        let r = solve_default(&p, Config::default());
        assert!(matches!(
            r.outcome,
            Outcome::Solved(Solution { cost: 1, .. })
        ));
    }

    #[test]
    fn t_determinism() {
        let p = puzzle(&["bbr", "  b", "  B"], (0, 0), "right", &[4], 0);
        let a = solve_default(&p, Config::default());
        let b = solve_default(&p, Config::default());
        assert_eq!(a.outcome, b.outcome);
        assert_eq!(a.stats.search_nodes, b.stats.search_nodes);
        assert_eq!(
            a.stats.instructions_evaluated,
            b.stats.instructions_evaluated
        );
    }

    struct Rng(u64);
    impl Rng {
        fn below(&mut self, n: u64) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            (z ^ (z >> 31)) % n
        }
    }

    /// Minimal cost by exhaustive enumeration of every left-packed physical
    /// program (L1), checked with REFERENCE_RUN only. `None`: no solution.
    fn brute_force_min(p: &StaticPuzzle) -> Option<u8> {
        let mut conditions = vec![Condition::Any];
        conditions.extend(p.possible_colors.iter().map(Condition::Color));
        let mut actions = vec![Action::Forward, Action::TurnLeft, Action::TurnRight];
        actions.extend(p.allowed_paints.iter().map(Action::Paint));
        actions.extend(
            (0..5u8)
                .filter(|&g| p.capacities[g as usize] > 0)
                .map(Action::Call),
        );
        let options: Vec<Instruction> = conditions
            .iter()
            .flat_map(|&c| actions.iter().map(move |&a| Instruction::new(c, a)))
            .collect();
        let caps = p.capacities;
        for k in 0..=p.total_capacity() as usize {
            // Every split of k cells over the functions.
            let mut splits = vec![vec![]];
            for &cap in &caps {
                splits = splits
                    .into_iter()
                    .flat_map(|s: Vec<usize>| {
                        (0..=cap as usize).map(move |n| [s.clone(), vec![n]].concat())
                    })
                    .collect();
            }
            for split in splits.into_iter().filter(|s| s.iter().sum::<usize>() == k) {
                let mut idx = vec![0usize; k];
                loop {
                    let mut functions: [Vec<Option<Instruction>>; 5] = Default::default();
                    let mut cell = 0;
                    for f in 0..5 {
                        for _ in 0..split[f] {
                            functions[f].push(Some(options[idx[cell]]));
                            cell += 1;
                        }
                        functions[f].resize(caps[f] as usize, None);
                    }
                    if reference_run(p, &ResolvedProgram { functions }).status == RunStatus::Success
                    {
                        return Some(k as u8);
                    }
                    // Next combination (odometer).
                    let mut pos = 0;
                    while pos < k {
                        idx[pos] += 1;
                        if idx[pos] < options.len() {
                            break;
                        }
                        idx[pos] = 0;
                        pos += 1;
                    }
                    if pos == k {
                        break;
                    }
                }
            }
        }
        None
    }

    fn random_tiny_puzzle(rng: &mut Rng) -> Option<StaticPuzzle> {
        let (rows, cols) = (1 + rng.below(3) as usize, 2 + rng.below(3) as usize);
        let colors = 1 + rng.below(2) as usize;
        let palette = ['b', 'r', 'g'];
        let mut grid: Vec<Vec<char>> = (0..rows)
            .map(|_| {
                (0..cols)
                    .map(|_| {
                        if rng.below(4) == 0 {
                            ' '
                        } else {
                            palette[rng.below(colors as u64) as usize]
                        }
                    })
                    .collect()
            })
            .collect();
        let start = (0usize, 0usize);
        grid[0][0] = palette[0];
        let tiles: Vec<(usize, usize)> = (0..rows)
            .flat_map(|r| (0..cols).map(move |c| (r, c)))
            .filter(|&(r, c)| grid[r][c] != ' ' && (r, c) != start)
            .collect();
        if tiles.is_empty() {
            return None;
        }
        for _ in 0..1 + rng.below(2) {
            let (r, c) = tiles[rng.below(tiles.len() as u64) as usize];
            grid[r][c] = grid[r][c].to_ascii_uppercase();
        }
        let caps: Vec<i64> = match rng.below(3) {
            0 => vec![3],
            1 => vec![2, 1],
            _ => vec![1, 1, 1],
        };
        let paints = if rng.below(3) == 0 {
            1 << rng.below(colors as u64)
        } else {
            0
        };
        let dirs = ["up", "right", "down", "left"];
        let rows_s: Vec<String> = grid.iter().map(|r| r.iter().collect()).collect();
        let rows_ref: Vec<&str> = rows_s.iter().map(|s| s.as_str()).collect();
        let p = puzzle(
            &rows_ref,
            (0, 0),
            dirs[rng.below(4) as usize],
            &caps,
            paints,
        );
        p.stars_connected().then_some(p)
    }

    /// t_e2e_bruteforce (SPEC §25): SOLVE's minimal cost equals exhaustive
    /// enumeration on random tiny puzzles, for several configurations.
    #[test]
    fn t_e2e_bruteforce() {
        let mut rng = Rng(42);
        let configs = [
            Config::default(),
            Config {
                lazy_conditions: false,
                ..Config::default()
            },
            Config {
                function_symmetry: false,
                peephole: false,
                ..Config::default()
            },
        ];
        let (mut solved, mut unsolvable, mut checked) = (0, 0, 0);
        while checked < 60 {
            let Some(p) = random_tiny_puzzle(&mut rng) else {
                continue;
            };
            checked += 1;
            let expected = brute_force_min(&p);
            for config in configs {
                let got = match solve_default(&p, config).outcome {
                    Outcome::Solved(s) => Some(s.cost),
                    Outcome::Unsolvable(UnsolvableReason::Exhausted) => None,
                    other => panic!("{other:?}"),
                };
                assert_eq!(
                    got, expected,
                    "puzzle {:?} caps {:?} config {config:?}",
                    p.source_id, p.capacities
                );
            }
            if expected.is_some() {
                solved += 1
            } else {
                unsolvable += 1
            }
        }
        assert!(
            solved > 10 && unsolvable > 5,
            "solved {solved}, unsolvable {unsolvable}"
        );
    }

    /// Pausing the exact search every few nodes and resuming it gives the
    /// same solution after the same number of nodes as one uninterrupted run.
    #[test]
    fn t_exact_resume_is_lossless() {
        let p = puzzle(&["bbr", "  b", "rbB"], (0, 0), "right", &[3, 2], 1);
        let mut whole = Solver::new(&p, Config::default(), Limits::default());
        let Step::Found(expected) = whole.exact_resume(10) else {
            panic!("no solution")
        };
        for slice in [1u64, 7, 100] {
            let mut sliced = Solver::new(&p, Config::default(), Limits::default());
            let found = loop {
                let cap = sliced.stats.search_nodes + slice;
                sliced.deadline.set_phase_cap(Some(cap));
                match sliced.exact_resume(10) {
                    Step::Found(s) => break s,
                    Step::Paused => {}
                    Step::Exhausted => panic!("exhausted"),
                }
            };
            assert_eq!(found, expected, "slice {slice}");
            assert_eq!(
                sliced.stats.search_nodes, whole.stats.search_nodes,
                "slice {slice}"
            );
        }
    }

    /// INV-FIT and the final renaming (D-NEWFN).
    #[test]
    fn t_anonymous_functions_fit_and_realize() {
        // Real auxiliary capacities: F2 = 1, F3 = 3, F5 = 2 (F4 disabled).
        let p = puzzle(&["bbbbB"], (0, 0), "right", &[2, 1, 3, 0, 2], 0);
        // With peephole on, P-SINGLE disables the capacity-1 function.
        let pruned = Solver::new(&p, Config::default(), Limits::default());
        assert_eq!(pruned.capacities, [2, 3, 3, 0, 0]);
        assert_eq!(pruned.aux_capacities.as_slice(), &[3, 2]);
        // The rest of this test exercises INV-FIT with three capacities.
        let config = Config {
            peephole: false,
            ..Config::default()
        };
        let solver = Solver::new(&p, config, Limits::default());
        assert_eq!(solver.capacities, [2, 3, 3, 3, 0]);
        assert_eq!(solver.aux_capacities.as_slice(), &[3, 2, 1]);
        let mut prog = solver.root().program;
        let fwd = Cell::Resolved(Instruction::any(Action::Forward));
        prog.function_mut(1).push(fwd);
        prog.function_mut(2).push(fwd);
        assert!(solver.aux_fits(&prog, 1, 3)); // lengths 3, 1, 0 fit 3, 2, 1
        prog.function_mut(1).push(fwd);
        prog.function_mut(1).push(fwd);
        assert!(solver.aux_fits(&prog, 2, 2)); // 3, 2, 0
        assert!(!solver.aux_fits(&prog, 2, 3)); // 3, 3, 0: two bodies need 3
        prog.function_mut(2).push(fwd);
        prog.function_mut(3).push(fwd);
        assert!(!solver.aux_fits(&prog, 3, 2)); // 3, 2, 2: the third gets 1

        // Realize: the longest body goes to F3, the next to F5, the shortest
        // to F2, and calls follow.
        prog.function_mut(0)
            .push(Cell::Resolved(Instruction::any(Action::Call(2))));
        prog.function_mut(0).push(Cell::Pending {
            action: Action::Call(3),
            color: Color::Blue,
        });
        let real = solver.realize(&prog);
        assert_eq!(real.functions[2].len, 3); // internal 1 -> F3
        assert_eq!(real.functions[4].len, 2); // internal 2 -> F5
        assert_eq!(real.functions[1].len, 1); // internal 3 -> F2
        assert_eq!(real.functions[3].len, 0);
        assert_eq!(
            real.functions[0].decided(),
            &[
                Cell::Resolved(Instruction::any(Action::Call(4))),
                Cell::Pending {
                    action: Action::Call(1),
                    color: Color::Blue
                },
            ]
        );
        let tokens = real.to_physical().to_tokens();
        assert_eq!(
            tokens.iter().map(Vec::len).collect::<Vec<_>>(),
            vec![2, 1, 3, 0, 2]
        );
    }

    /// Anonymous functions against exhaustive enumeration on tiny puzzles
    /// whose auxiliary functions have different capacities (one color, no
    /// paint, so the brute force stays small).
    #[test]
    fn t_anonymous_functions_bruteforce() {
        let mut rng = Rng(7);
        let mut checked = 0;
        let mut solved = 0;
        while checked < 25 {
            let (rows, cols) = (1 + rng.below(3) as usize, 2 + rng.below(3) as usize);
            let mut grid: Vec<Vec<char>> = (0..rows)
                .map(|_| {
                    (0..cols)
                        .map(|_| if rng.below(4) == 0 { ' ' } else { 'b' })
                        .collect()
                })
                .collect();
            grid[0][0] = 'b';
            let tiles: Vec<(usize, usize)> = (0..rows)
                .flat_map(|r| (0..cols).map(move |c| (r, c)))
                .filter(|&(r, c)| grid[r][c] != ' ' && (r, c) != (0, 0))
                .collect();
            if tiles.is_empty() {
                continue;
            }
            for _ in 0..1 + rng.below(2) {
                let (r, c) = tiles[rng.below(tiles.len() as u64) as usize];
                grid[r][c] = 'B';
            }
            let caps: &[i64] = if rng.below(2) == 0 {
                &[1, 2, 1]
            } else {
                &[1, 1, 2]
            };
            let rows_s: Vec<String> = grid.iter().map(|r| r.iter().collect()).collect();
            let rows_ref: Vec<&str> = rows_s.iter().map(|s| s.as_str()).collect();
            let dirs = ["up", "right", "down", "left"];
            let p = puzzle(&rows_ref, (0, 0), dirs[rng.below(4) as usize], caps, 0);
            if !p.stars_connected() {
                continue;
            }
            checked += 1;
            let expected = brute_force_min(&p);
            for anonymous_functions in [true, false] {
                let config = Config {
                    anonymous_functions,
                    heuristic: false,
                    ..Config::default()
                };
                let got = match solve_default(&p, config).outcome {
                    Outcome::Solved(s) => Some(s.cost),
                    Outcome::Unsolvable(UnsolvableReason::Exhausted) => None,
                    other => panic!("{other:?}"),
                };
                assert_eq!(
                    got, expected,
                    "{rows_s:?} caps {caps:?} anonymous={anonymous_functions}"
                );
            }
            solved += expected.is_some() as u32;
        }
        assert!(solved >= 5, "only {solved} solvable cases");
    }

    /// D-DEFER-SET against exhaustive enumeration on tiny three-color
    /// puzzles (the other brute-force tests use at most two colors).
    #[test]
    fn t_condition_sets_bruteforce() {
        let mut rng = Rng(99);
        let palette = ['r', 'g', 'b'];
        let (mut checked, mut solved) = (0, 0);
        while checked < 30 {
            let (rows, cols) = (1 + rng.below(3) as usize, 2 + rng.below(3) as usize);
            let mut grid: Vec<Vec<char>> = (0..rows)
                .map(|_| {
                    (0..cols)
                        .map(|_| {
                            if rng.below(5) == 0 {
                                ' '
                            } else {
                                palette[rng.below(3) as usize]
                            }
                        })
                        .collect()
                })
                .collect();
            grid[0][0] = palette[rng.below(3) as usize];
            let tiles: Vec<(usize, usize)> = (0..rows)
                .flat_map(|r| (0..cols).map(move |c| (r, c)))
                .filter(|&(r, c)| grid[r][c] != ' ' && (r, c) != (0, 0))
                .collect();
            if tiles.is_empty() {
                continue;
            }
            for _ in 0..1 + rng.below(2) {
                let (r, c) = tiles[rng.below(tiles.len() as u64) as usize];
                grid[r][c] = grid[r][c].to_ascii_uppercase();
            }
            let rows_s: Vec<String> = grid.iter().map(|r| r.iter().collect()).collect();
            let rows_ref: Vec<&str> = rows_s.iter().map(|s| s.as_str()).collect();
            let dirs = ["up", "right", "down", "left"];
            let caps: &[i64] = if rng.below(2) == 0 { &[3] } else { &[2, 2] };
            let p = puzzle(&rows_ref, (0, 0), dirs[rng.below(4) as usize], caps, 0);
            if !p.stars_connected() || p.possible_colors.count() < 3 {
                continue;
            }
            checked += 1;
            let expected = brute_force_min(&p);
            for condition_sets in [true, false] {
                let config = Config {
                    condition_sets,
                    heuristic: false,
                    ..Config::default()
                };
                let got = match solve_default(&p, config).outcome {
                    Outcome::Solved(s) => Some(s.cost),
                    Outcome::Unsolvable(UnsolvableReason::Exhausted) => None,
                    other => panic!("{other:?}"),
                };
                assert_eq!(
                    got, expected,
                    "{rows_s:?} caps {caps:?} condition_sets={condition_sets}"
                );
            }
            solved += expected.is_some() as u32;
        }
        assert!(solved >= 5, "only {solved} solvable cases");
    }

    #[test]
    fn disconnected_is_unsolvable() {
        let p = puzzle(&["b B"], (0, 0), "right", &[2], 0);
        assert_eq!(
            solve_default(&p, Config::default()).outcome,
            Outcome::Unsolvable(UnsolvableReason::Disconnected)
        );
    }

    #[test]
    fn star_less_puzzle_is_solved_by_the_empty_program() {
        let p = puzzle(&["bb"], (0, 0), "right", &[2], 0);
        let r = solve_default(&p, Config::default());
        assert!(matches!(
            r.outcome,
            Outcome::Solved(Solution { cost: 0, .. })
        ));
    }
}
