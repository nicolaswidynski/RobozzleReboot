//! Candidate generation (SPEC §14–§15), SOLVE / SEARCH (§17) and
//! finalization (§18).

use arrayvec::ArrayVec;

use crate::canonical::{is_useless_paint, turns_canonical};
use crate::machine::{DeadReason, Machine};
use crate::normalize::{CycleDetector, NormalizeResult, normalize};
use crate::program::{Cell, PartialProgram, ResolvedProgram};
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::stack::{self, StackArena};
use crate::stats::{Config, Deadline, Limits, SearchStats, TimedOut};
use crate::types::{Action, Color, Condition, FnId, Instruction, MAX_FUNCTIONS, MAX_STEPS};

/// A branch's complete semantic state (SPEC §6). `Copy`, no heap.
#[derive(Debug, Clone, Copy)]
pub struct SearchState {
    pub program: PartialProgram,
    pub machine: Machine,
    pub used_slots: u8,
    /// Bit f set: F(f+1) is introduced (SPEC §14.4).
    pub introduced_functions: u8,
}

impl SearchState {
    pub fn root(puzzle: &StaticPuzzle) -> Self {
        Self {
            program: PartialProgram::new(puzzle.capacities),
            machine: Machine::new(puzzle),
            used_slots: 0,
            introduced_functions: 0b00001,
        }
    }
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Solution {
    pub program: ResolvedProgram,
    pub cost: u8,
    pub steps: u32,
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
}

pub struct Solver<'a> {
    pub puzzle: &'a StaticPuzzle,
    pub config: Config,
    pub stats: SearchStats,
    arena: StackArena,
    cycles: CycleDetector,
    deadline: Deadline,
    depth: u32,
}

/// SOLVE (SPEC §17.1).
pub fn solve(puzzle: &StaticPuzzle, config: Config, limits: Limits) -> SolveResult {
    let mut solver = Solver::new(puzzle, config, limits);
    let outcome = solver.run();
    solver.stats.millis = solver.deadline.elapsed().as_millis() as u64;
    SolveResult {
        outcome,
        stats: solver.stats,
    }
}

impl<'a> Solver<'a> {
    pub fn new(puzzle: &'a StaticPuzzle, config: Config, limits: Limits) -> Self {
        Self {
            puzzle,
            config,
            stats: SearchStats::default(),
            arena: StackArena::new(),
            cycles: CycleDetector::default(),
            deadline: Deadline::new(limits),
            depth: 0,
        }
    }

    fn run(&mut self) -> Outcome {
        if !self.puzzle.stars_connected() {
            return Outcome::Unsolvable(UnsolvableReason::Disconnected); // P-CONN
        }
        for budget in 0..=self.puzzle.total_capacity() as u8 {
            self.arena.clear();
            let before = self.stats.search_nodes;
            let result = self.search(SearchState::root(self.puzzle), budget);
            self.stats
                .nodes_per_budget
                .push(self.stats.search_nodes - before);
            match result {
                Err(TimedOut) => return Outcome::Timeout,
                Ok(Some(solution)) => return Outcome::Solved(solution),
                Ok(None) => {}
            }
        }
        Outcome::Unsolvable(UnsolvableReason::Exhausted)
    }

    /// SEARCH (SPEC §17.2).
    fn search(&mut self, state: SearchState, budget: u8) -> Result<Option<Solution>, TimedOut> {
        self.stats.search_nodes += 1;
        self.deadline.check(self.stats.search_nodes)?;
        debug_assert!(state.program.check_prefix(), "INV-PREFIX");
        debug_assert_eq!(state.used_slots, state.program.occupied_slots(), "INV-COST");
        let mut state = state;
        let result = normalize(
            self.puzzle,
            &state.program,
            &mut state.machine,
            &mut self.arena,
            &mut self.cycles,
            &self.config,
            &mut self.stats,
        );
        match result {
            NormalizeResult::Solved => Ok(Some(self.finalize(&state))),
            NormalizeResult::Dead(reason) => {
                match reason {
                    DeadReason::Crash => self.stats.dead_crash += 1,
                    DeadReason::ProgramEnded => self.stats.dead_program_ended += 1,
                    DeadReason::StepLimit => self.stats.dead_step_limit += 1,
                    DeadReason::Loop => self.stats.dead_loop += 1,
                }
                Ok(None)
            }
            NormalizeResult::OpenSlot { function, index } => {
                let candidates = self.open_candidates(&state, function, index, budget);
                self.stats.candidates_generated += candidates.len() as u64;
                for cand in candidates {
                    let mark = self.arena.mark(); // before applying: S-REBUILD allocates
                    let mut child = state;
                    self.apply_open(&mut child, function, index, cand);
                    let r = self.recurse(child, budget);
                    self.arena.truncate(mark);
                    if let Some(s) = r? {
                        return Ok(Some(s));
                    }
                }
                Ok(None)
            }
            NormalizeResult::NeedCondition { function, index } => {
                if self.config.step_cut && state.machine.steps == MAX_STEPS {
                    self.stats.prune_step_cut += 1; // P-STEPCUT: either choice consumes a step
                    return Ok(None);
                }
                let choices = self.condition_candidates(&state, function, index);
                self.stats.candidates_generated += choices.len() as u64;
                for condition in choices {
                    let mark = self.arena.mark();
                    let mut child = state;
                    child
                        .program
                        .function_mut(function)
                        .resolve_pending(index, condition);
                    self.stats.pending_resolved += 1;
                    let r = self.recurse(child, budget);
                    self.arena.truncate(mark);
                    if let Some(s) = r? {
                        return Ok(Some(s));
                    }
                }
                Ok(None)
            }
            NormalizeResult::NeedAction {
                function,
                index,
                condition,
            } => {
                if self.config.step_cut && state.machine.steps == MAX_STEPS {
                    self.stats.prune_step_cut += 1; // P-STEPCUT
                    return Ok(None);
                }
                let actions = self.need_candidates(&state, function, index, condition);
                self.stats.candidates_generated += actions.len() as u64;
                for action in actions {
                    let mark = self.arena.mark();
                    let mut child = state;
                    child
                        .program
                        .function_mut(function)
                        .resolve_cond_only(index, action);
                    if let Action::Call(g) = action {
                        child.introduced_functions |= 1 << g;
                    }
                    self.stats.condonly_resolved += 1;
                    let r = self.recurse(child, budget);
                    self.arena.truncate(mark);
                    if let Some(s) = r? {
                        return Ok(Some(s));
                    }
                }
                Ok(None)
            }
        }
    }

    fn recurse(&mut self, child: SearchState, budget: u8) -> Result<Option<Solution>, TimedOut> {
        self.stats.candidates_searched += 1;
        self.depth += 1;
        self.stats.max_search_depth = self.stats.max_search_depth.max(self.depth);
        let r = self.search(child, budget);
        self.depth -= 1;
        r
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
    }

    /// Actions available for a new cell (SPEC §14.3), in search order:
    /// Forward, calls to introduced functions, turns, calls to new
    /// functions, paints.
    fn actions(&mut self, state: &SearchState) -> Actions {
        let introduced = state.introduced_functions;
        let callable = self
            .puzzle
            .callable(introduced, self.config.function_symmetry);
        let excluded = self.puzzle.enabled_functions() & !callable;
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
        if self.config.peephole && (k == 0 || state.machine.callers.is_none()) {
            end_allowed = false;
            if k != 0 {
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
        if state.used_slots < budget {
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
                for d in pc.iter().filter(|&d| d != cur) {
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
        } else {
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
        let program = state.program.to_physical();
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
        let state = SearchState::root(p);
        solver
            .open_candidates(&state, 0, 0, budget)
            .into_iter()
            .map(|c| match c {
                Candidate::End => "END".to_string(),
                Candidate::Place(i) => instruction_token(i),
                Candidate::Defer(c) => format!("{}:?", c.name()),
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
