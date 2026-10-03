//! Near-solution local repair (`Config::repair`, SPEC §17.5).
//!
//! The heuristic phase keeps a small pool of the best distinct programs it
//! has normalized (most stars collected, dead programs included, then the
//! shortest walk to the nearest remaining star). A pooled program is
//! completed deterministically: open slots become END, `Pending` becomes
//! `Any`, `CondOnly` / `CondSet` cells are dropped. While the repair share
//! of the node budget allows, the best unrepaired pool entry is repaired by
//! searching its edit neighbourhood:
//!
//! - distance 1: replace one executed cell (condition and/or action), delete
//!   it, or insert one cell where the function has a free slot;
//! - distance 2: two such edits, at least one of them an insertion, both at
//!   the few slots executed last before the failure.
//!
//! Every candidate is simulated from a snapshot taken just before the first
//! fetch of the first slot whose content (or tail-call status) differs from
//! the base program, so the shared prefix of the run is not re-executed.
//! Every simulation is charged `max(1, steps / 8)` search nodes and checks
//! the deadline; repair uses at most `repair_share` percent of the
//! heuristic phase's nodes. A repaired program is only a candidate: like any heuristic
//! solution it is verified by `REFERENCE_RUN`, shape-checked and shrunk.
//!
//! Nothing here is random or time-dependent; every order is fixed (sets are
//! `BTreeSet`), so the result is deterministic for a given node limit.

use std::cmp::Reverse;
use std::collections::BTreeSet;

use crate::machine::{PackedColors, StarSet};
use crate::program::ResolvedProgram;
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::search::{FoundBy, SearchState, Solution, Solver};
use crate::types::{
    Action, Condition, Direction, Instruction, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS, MAX_STEPS, TileId,
};

/// Pool size (distinct programs waiting for repair).
const POOL: usize = 4;
/// Distance 2 uses the edits at this many slots executed last.
const TAIL_SLOTS: usize = 3;

type Key = (u32, Reverse<u16>);

/// A complete physical program in fixed-size storage (cheap to copy and
/// edit). Every function is left-packed.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct Prog {
    cells: [[Option<Instruction>; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
    cap: [u8; MAX_FUNCTIONS],
}

impl Prog {
    fn from_resolved(p: &ResolvedProgram) -> Self {
        let mut cells = [[None; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS];
        let mut cap = [0u8; MAX_FUNCTIONS];
        for f in 0..MAX_FUNCTIONS {
            cap[f] = p.functions[f].len() as u8;
            // Left-pack (the completion already is; this keeps it an invariant).
            for (k, i) in p.functions[f].iter().flatten().enumerate() {
                cells[f][k] = Some(*i);
            }
        }
        Self { cells, cap }
    }

    fn to_resolved(self) -> ResolvedProgram {
        ResolvedProgram {
            functions: std::array::from_fn(|f| self.cells[f][..self.cap[f] as usize].to_vec()),
        }
    }

    fn len(&self, f: usize) -> usize {
        self.cells[f][..self.cap[f] as usize]
            .iter()
            .take_while(|c| c.is_some())
            .count()
    }

    /// Index of the last occupied slot of each function (`-1` if empty).
    fn last_occupied(&self) -> [i8; MAX_FUNCTIONS] {
        std::array::from_fn(|f| {
            (0..self.cap[f] as usize)
                .rev()
                .find(|&k| self.cells[f][k].is_some())
                .map_or(-1, |k| k as i8)
        })
    }

    /// FNV-1a over every slot (deterministic).
    fn hash(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut eat = |b: u8| {
            h ^= b as u64;
            h = h.wrapping_mul(0x0000_0100_0000_01b3);
        };
        for f in 0..MAX_FUNCTIONS {
            eat(0xf0 | f as u8);
            for k in 0..self.cap[f] as usize {
                eat(match self.cells[f][k] {
                    None => 0xff,
                    Some(i) => instruction_code(i),
                });
            }
        }
        h
    }
}

fn is_call(cell: Option<Instruction>) -> bool {
    matches!(
        cell,
        Some(Instruction {
            action: Action::Call(_),
            ..
        })
    )
}

fn instruction_code(i: Instruction) -> u8 {
    let c = match i.condition {
        Condition::Any => 0,
        Condition::Color(c) => 1 + c as u8,
    };
    let a = match i.action {
        Action::Forward => 0,
        Action::TurnLeft => 1,
        Action::TurnRight => 2,
        Action::Paint(p) => 3 + p as u8,
        Action::Call(g) => 6 + g,
    };
    c * 16 + a
}

#[derive(Clone, Copy, Debug)]
enum Edit {
    Replace(u8, u8, Instruction),
    Delete(u8, u8),
    Insert(u8, u8, Instruction),
}

impl Edit {
    /// (function, slot index) the edit is anchored at.
    fn slot(self) -> (usize, usize) {
        match self {
            Edit::Replace(f, i, _) | Edit::Delete(f, i) | Edit::Insert(f, i, _) => {
                (f as usize, i as usize)
            }
        }
    }

    fn is_insert(self) -> bool {
        matches!(self, Edit::Insert(..))
    }

    /// Applies the edit; false if it does not fit (no free slot).
    fn apply(self, p: &mut Prog) -> bool {
        match self {
            Edit::Replace(f, i, ins) => {
                p.cells[f as usize][i as usize] = Some(ins);
                true
            }
            Edit::Delete(f, i) => {
                let (f, i) = (f as usize, i as usize);
                let cap = p.cap[f] as usize;
                p.cells[f].copy_within(i + 1..cap, i);
                p.cells[f][cap - 1] = None;
                true
            }
            Edit::Insert(f, j, ins) => {
                let (f, j) = (f as usize, j as usize);
                let cap = p.cap[f] as usize;
                if cap == 0 || p.cells[f][cap - 1].is_some() {
                    return false;
                }
                p.cells[f].copy_within(j..cap - 1, j + 1);
                p.cells[f][j] = Some(ins);
                true
            }
        }
    }
}

/// Simulator state (mirrors `REFERENCE_RUN`, with packed board storage).
#[derive(Clone)]
struct SimState {
    colors: PackedColors,
    stars: StarSet,
    stars_left: u32,
    pos: TileId,
    dir: Direction,
    steps: u32,
    last_pickup: u32,
    /// (function, next slot index)
    stack: Vec<(u8, u8)>,
}

impl SimState {
    fn initial(p: &StaticPuzzle) -> Self {
        Self {
            colors: p.initial_colors,
            stars: p.initial_stars,
            stars_left: p.initial_stars.len(),
            pos: p.start_tile,
            dir: p.start_direction,
            steps: 0,
            last_pickup: 0,
            stack: if p.capacities[0] > 0 {
                vec![(0, 0)]
            } else {
                vec![]
            },
        }
    }
}

/// Fetch log of the base run: when each slot was first and last fetched,
/// and the state just before its first fetch.
struct Trace {
    fetches: u32,
    first: [[u32; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
    last: [[u32; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
    snap: [[u16; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
    snaps: Vec<SimState>,
    pickups: Vec<u32>,
}

impl Trace {
    fn new() -> Self {
        Self {
            fetches: 0,
            first: [[0; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
            last: [[0; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
            snap: [[0; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
            snaps: Vec::new(),
            pickups: Vec::new(),
        }
    }

    #[inline]
    fn fetch(&mut self, f: usize, i: usize, st: &SimState) {
        self.fetches += 1;
        if self.first[f][i] == 0 {
            self.first[f][i] = self.fetches;
            self.snap[f][i] = self.snaps.len() as u16;
            self.snaps.push(st.clone());
        }
        self.last[f][i] = self.fetches;
    }
}

/// Runs `prog` from `st` with `REFERENCE_RUN` semantics. Returns true on
/// success. Gives up (false) after `gap_cap` steps without a new star.
fn simulate(
    puzzle: &StaticPuzzle,
    prog: &Prog,
    st: &mut SimState,
    mut trace: Option<&mut Trace>,
    gap_cap: u32,
) -> bool {
    if st.stars_left == 0 {
        return true;
    }
    let last_occ = prog.last_occupied();
    loop {
        let Some(&(f, i)) = st.stack.last() else {
            return st.stars_left == 0;
        };
        let (fu, iu) = (f as usize, i as usize);
        if iu >= prog.cap[fu] as usize {
            st.stack.pop(); // R-POP
            continue;
        }
        if let Some(t) = trace.as_deref_mut() {
            t.fetch(fu, iu, st);
        }
        st.stack.last_mut().expect("a frame").1 += 1;
        let Some(ins) = prog.cells[fu][iu] else {
            continue; // R-NULL
        };
        st.steps += 1;
        if st.steps > MAX_STEPS || st.steps - st.last_pickup > gap_cap {
            return false;
        }
        if !ins.condition.matches(st.colors.get(st.pos)) {
            continue;
        }
        match ins.action {
            Action::Call(g) => {
                if prog.cap[g as usize] == 0 {
                    continue; // R-CALL0
                }
                if last_occ[fu] == i as i8 {
                    st.stack.pop(); // R-TAIL
                }
                st.stack.push((g, 0));
            }
            Action::TurnLeft => st.dir = st.dir.left(),
            Action::TurnRight => st.dir = st.dir.right(),
            Action::Paint(c) => st.colors.set(st.pos, c),
            Action::Forward => match puzzle.forward_target(st.pos, st.dir) {
                None => return false,
                Some(t) => {
                    st.pos = t;
                    if st.stars.remove(t) {
                        st.stars_left -= 1;
                        st.last_pickup = st.steps;
                        if let Some(tr) = trace.as_deref_mut() {
                            tr.pickups.push(st.steps);
                        }
                        if st.stars_left == 0 {
                            return true;
                        }
                    }
                }
            },
        }
    }
}

/// The earliest point where `p` can behave differently from `base`: the
/// first fetch of the first slot (per function) whose content differs or
/// whose call changes tail-call status. `None` if no such slot was ever
/// fetched (then `p` fails exactly like `base`).
fn divergence(base: &Prog, p: &Prog, trace: &Trace) -> Option<(usize, usize)> {
    let bl = base.last_occupied();
    let pl = p.last_occupied();
    let mut best: Option<(u32, usize, usize)> = None;
    for f in 0..MAX_FUNCTIONS {
        for k in 0..base.cap[f] as usize {
            let tail_changed =
                is_call(base.cells[f][k]) && ((bl[f] == k as i8) != (pl[f] == k as i8));
            if base.cells[f][k] != p.cells[f][k] || tail_changed {
                // Frames run their slots in order from 0, so no later slot
                // of `f` was fetched before this one.
                let t = trace.first[f][k];
                if t != 0 && best.is_none_or(|(b, _, _)| t < b) {
                    best = Some((t, f, k));
                }
                break;
            }
        }
    }
    best.map(|(_, f, k)| (f, k))
}

#[derive(Clone)]
struct PoolEntry {
    key: Key,
    prog: Prog,
    hash: u64,
}

/// Repair state of one solve.
#[derive(Default)]
pub(crate) struct RepairPool {
    /// Most stars collected by any normalized heuristic node.
    best: u32,
    /// Waiting programs, best first (key descending, then arrival).
    entries: Vec<PoolEntry>,
    /// Programs already admitted (repaired or waiting).
    seen: BTreeSet<u64>,
}

enum Outcome {
    Found(Prog),
    NotFound,
    /// Deadline (node or time limit) reached.
    Stopped,
}

impl Solver<'_> {
    /// Offers a normalized heuristic node (alive or dead) to the pool.
    pub(crate) fn repair_observe(&mut self, kid: &SearchState, collected: u32) {
        if collected < self.repair.best {
            return;
        }
        self.repair.best = collected;
        let dist = self
            .puzzle
            .nearest_star(kid.machine.position, &kid.machine.stars);
        let key: Key = (collected, Reverse(dist));
        if self.repair.entries.len() >= POOL
            && self.repair.entries.last().is_some_and(|e| e.key >= key)
        {
            return;
        }
        let prog =
            Prog::from_resolved(&self.realize(&kid.program).to_physical_dropping_cond_only());
        let hash = prog.hash();
        if !self.repair.seen.insert(hash) {
            return;
        }
        let entry = PoolEntry { key, prog, hash };
        let at = self
            .repair
            .entries
            .iter()
            .position(|e| e.key < key)
            .unwrap_or(self.repair.entries.len());
        self.repair.entries.insert(at, entry);
        if self.repair.entries.len() > POOL {
            let dropped = self.repair.entries.pop().expect("an entry");
            // A dropped program may be offered again later.
            self.repair.seen.remove(&dropped.hash);
        }
    }

    /// Repairs the best waiting program if the repair share allows it.
    pub(crate) fn repair_tick(&mut self) -> Option<Solution> {
        if self.repair.entries.is_empty() {
            return None;
        }
        // The share is of the heuristic phase's nodes, so that the exact
        // phase's half of the budget does not count (PRODUCT = FINDER).
        let share = self.config.repair_share as u64;
        if self.stats.repair_nodes * 100 > share * self.heuristic_nodes_so_far() {
            return None;
        }
        let entry = self.repair.entries.remove(0);
        self.stats.repairs += 1;
        match self.repair_program(entry.prog) {
            Outcome::Found(p) => {
                let program = p.to_resolved();
                // The simulator only proposes; REFERENCE_RUN decides (and
                // `finalize_physical` verifies again, shrinks and checks the
                // shape). A disagreement would be a simulator bug.
                if reference_run(self.puzzle, &program).status != RunStatus::Success {
                    debug_assert!(false, "repair simulator disagrees with REFERENCE_RUN");
                    self.stats.repair_rejected += 1;
                    return None;
                }
                Some(self.finalize_physical(program, FoundBy::Repair))
            }
            Outcome::NotFound | Outcome::Stopped => None,
        }
    }

    /// Charges one simulation of `steps` instructions to the node budget.
    fn repair_charge(&mut self, steps: u32) {
        let nodes = (steps as u64 / 8).max(1);
        self.stats.search_nodes += nodes;
        self.stats.repair_nodes += nodes;
        self.stats.repair_simulations += 1;
        self.stats.repair_instructions += steps as u64;
    }

    fn repair_alphabet(&self) -> Vec<Instruction> {
        let mut conditions = vec![Condition::Any];
        if self.puzzle.possible_colors.count() >= 2 {
            conditions.extend(self.puzzle.possible_colors.iter().map(Condition::Color));
        }
        let mut actions = vec![Action::Forward, Action::TurnLeft, Action::TurnRight];
        actions.extend(self.puzzle.allowed_paints.iter().map(Action::Paint));
        // P-SINGLE: functions of capacity 1 are never needed.
        actions.extend(
            (0..MAX_FUNCTIONS as u8)
                .filter(|&g| self.puzzle.capacities[g as usize] >= 2)
                .map(Action::Call),
        );
        let mut out = Vec::new();
        for &c in &conditions {
            for &a in &actions {
                if let (Condition::Color(x), Action::Paint(y)) = (c, a)
                    && x == y
                {
                    continue; // P-PAINT
                }
                out.push(Instruction::new(c, a));
            }
        }
        out
    }

    /// Searches the edit neighbourhood of `base` (distance 1, then 2).
    fn repair_program(&mut self, base: Prog) -> Outcome {
        let mut trace = Trace::new();
        if self.deadline.check(self.stats.search_nodes + 1).is_err() {
            return Outcome::Stopped;
        }
        let mut st = SimState::initial(self.puzzle);
        let ok = simulate(self.puzzle, &base, &mut st, Some(&mut trace), u32::MAX);
        self.repair_charge(st.steps);
        if ok {
            self.stats.repair_found_d0 += 1;
            return Outcome::Found(base);
        }
        let base_steps = st.steps;
        // Give up on a candidate after this many steps without a new star.
        let mut max_gap = 0;
        let mut prev = 0;
        for &t in &trace.pickups {
            max_gap = max_gap.max(t - prev);
            prev = t;
        }
        if trace.pickups.is_empty() {
            max_gap = base_steps.min(1000);
        }
        let gap_cap = (2 * max_gap).max(max_gap + 256);

        let alphabet = self.repair_alphabet();
        // Distance-1 edits whose anchor slot was fetched, most recently
        // fetched first (the cells executed just before the failure).
        let mut edits: Vec<(u32, Edit)> = Vec::new();
        for f in 0..MAX_FUNCTIONS {
            let cap = base.cap[f] as usize;
            let len = base.len(f);
            for i in 0..len {
                let t = trace.last[f][i];
                if t == 0 {
                    continue;
                }
                for &ins in &alphabet {
                    if Some(ins) != base.cells[f][i] {
                        edits.push((t, Edit::Replace(f as u8, i as u8, ins)));
                    }
                }
                edits.push((t, Edit::Delete(f as u8, i as u8)));
            }
            if len < cap {
                for j in 0..=len {
                    // Appending after a tail call changes it at the call.
                    let anchor = if j == len && j > 0 && is_call(base.cells[f][j - 1]) {
                        j - 1
                    } else {
                        j
                    };
                    let t = trace.last[f][anchor];
                    if t == 0 {
                        continue;
                    }
                    for &ins in &alphabet {
                        edits.push((t, Edit::Insert(f as u8, j as u8, ins)));
                    }
                }
            }
        }
        // Stable sort: ties keep generation order.
        edits.sort_by_key(|&(t, _)| Reverse(t));
        let mut tried: BTreeSet<u64> = BTreeSet::new();
        tried.insert(base.hash());

        let nodes_before = self.stats.repair_nodes;
        for &(_, e) in &edits {
            match self.repair_try(&base, &trace, &[e], gap_cap, &mut tried) {
                Some(true) => {
                    self.stats.repair_found_d1 += 1;
                    self.stats.repair_d1_nodes += self.stats.repair_nodes - nodes_before;
                    let p = applied(&base, &[e]).expect("applied once already");
                    return Outcome::Found(p);
                }
                Some(false) => {}
                None => return Outcome::Stopped,
            }
        }
        self.stats.repair_d1_nodes += self.stats.repair_nodes - nodes_before;

        // Distance 2: pairs of edits anchored at the TAIL_SLOTS slots fetched
        // last before the failure.
        let mut slots: Vec<(u32, usize, usize)> = Vec::new();
        for f in 0..MAX_FUNCTIONS {
            for k in 0..base.cap[f] as usize {
                if trace.last[f][k] != 0 && k <= base.len(f) {
                    slots.push((trace.last[f][k], f, k));
                }
            }
        }
        slots.sort_by_key(|&(t, _, _)| Reverse(t));
        slots.truncate(TAIL_SLOTS);
        let tail: Vec<Edit> = edits
            .iter()
            .map(|&(_, e)| e)
            .filter(|e| slots.iter().any(|&(_, f, k)| (f, k) == e.slot()))
            .collect();
        let nodes_before = self.stats.repair_nodes;
        for a in 0..tail.len() {
            for b in a + 1..tail.len() {
                let (ea, eb) = (tail[a], tail[b]);
                // At least one insertion: the measured distance-2 repairs
                // all grow a function the search had closed early (END);
                // pairs of in-place changes cost most of the distance-2
                // budget and never succeeded on the dev set (v1).
                if !ea.is_insert() && !eb.is_insert() {
                    continue;
                }
                match self.repair_try(&base, &trace, &[ea, eb], gap_cap, &mut tried) {
                    Some(true) => {
                        self.stats.repair_found_d2 += 1;
                        self.stats.repair_d2_nodes += self.stats.repair_nodes - nodes_before;
                        let p = applied(&base, &[ea, eb]).expect("applied once already");
                        return Outcome::Found(p);
                    }
                    Some(false) => {}
                    None => return Outcome::Stopped,
                }
            }
        }
        self.stats.repair_d2_nodes += self.stats.repair_nodes - nodes_before;
        Outcome::NotFound
    }

    /// Simulates `base` with `edits` applied. `Some(success)`, or `None`
    /// when the deadline is reached.
    fn repair_try(
        &mut self,
        base: &Prog,
        trace: &Trace,
        edits: &[Edit],
        gap_cap: u32,
        tried: &mut BTreeSet<u64>,
    ) -> Option<bool> {
        let Some(p) = applied(base, edits) else {
            return Some(false);
        };
        if !tried.insert(p.hash()) {
            return Some(false);
        }
        let Some((f, k)) = divergence(base, &p, trace) else {
            return Some(false); // behaves exactly like the base program
        };
        if self.deadline.check(self.stats.search_nodes + 1).is_err() {
            return None;
        }
        let mut st = trace.snaps[trace.snap[f][k] as usize].clone();
        let start = st.steps;
        let ok = simulate(self.puzzle, &p, &mut st, None, gap_cap);
        self.repair_charge(st.steps - start);
        Some(ok)
    }
}

/// `base` with `edits` applied, highest anchor first so that earlier
/// anchors keep their meaning. `None` if an insertion does not fit.
fn applied(base: &Prog, edits: &[Edit]) -> Option<Prog> {
    let mut order: Vec<Edit> = edits.to_vec();
    order.sort_by_key(|e| Reverse(e.slot()));
    let mut p = *base;
    for e in order {
        if !e.apply(&mut p) {
            return None;
        }
    }
    Some(p)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::program_from;
    use crate::puzzle::tests::puzzle;
    use crate::search::Solver;
    use crate::types::Color;

    /// Validation on the catalog (run with `--ignored --nocapture`): break
    /// every known solution by one edit (replace or delete one executed
    /// cell) and check that repair finds a solution again.
    #[test]
    #[ignore]
    fn t_repair_recovers_broken_solutions() {
        use crate::puzzle::load_catalog;
        use crate::stats::{Config, Limits};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let raws = load_catalog(&root.join("../assets/levels_catalog.json")).unwrap();
        let text = std::fs::read_to_string(root.join("solutions.json")).unwrap();
        let sols: serde_json::Value = serde_json::from_str(&text).unwrap();
        let (mut broken, mut fixed, mut d1, mut d2, mut nodes) = (0u64, 0u64, 0u64, 0u64, 0u64);
        for r in sols["results"].as_array().unwrap() {
            if r["status"] != "solved" {
                continue;
            }
            let raw = raws.iter().find(|x| x.source_id == r["sourceId"]).unwrap();
            let p = StaticPuzzle::compile(raw).unwrap();
            let tokens: Vec<Vec<Option<String>>> =
                serde_json::from_value(r["program"].clone()).unwrap();
            let good = Prog::from_resolved(&ResolvedProgram::from_tokens(&tokens).unwrap());
            let config = Config {
                repair: true,
                ..Config::default()
            };
            // One deterministic mutation per puzzle: the middle occupied
            // cell of F1 is replaced by `forward` (or deleted if it is one).
            let len = good.len(0);
            let i = len / 2;
            let mut bad = good;
            if good.cells[0][i] == Some(Instruction::any(Action::Forward)) {
                Edit::Delete(0, i as u8).apply(&mut bad);
            } else {
                Edit::Replace(0, i as u8, Instruction::any(Action::Forward)).apply(&mut bad);
            }
            if reference_run(&p, &bad.to_resolved()).status == RunStatus::Success {
                continue;
            }
            broken += 1;
            let mut solver = Solver::new(&p, config, Limits::default());
            if let Outcome::Found(q) = solver.repair_program(bad) {
                assert_eq!(
                    reference_run(&p, &q.to_resolved()).status,
                    RunStatus::Success
                );
                fixed += 1;
            }
            d1 += solver.stats.repair_found_d1;
            d2 += solver.stats.repair_found_d2;
            nodes += solver.stats.repair_nodes;
        }
        eprintln!("broken {broken} fixed {fixed} (d1 {d1}, d2 {d2}) nodes {nodes}");
        assert!(fixed * 10 >= broken * 9);
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

    fn random_instruction(p: &StaticPuzzle, rng: &mut Rng) -> Instruction {
        let enabled: Vec<u8> = (0..5).filter(|&f| p.capacities[f as usize] > 0).collect();
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
        Instruction::new(condition, action)
    }

    /// A random physical program, holes included (`from_resolved` packs it).
    fn random_program(p: &StaticPuzzle, rng: &mut Rng) -> ResolvedProgram {
        ResolvedProgram {
            functions: std::array::from_fn(|f| {
                (0..p.capacities[f])
                    .map(|_| (rng.below(4) != 0).then(|| random_instruction(p, rng)))
                    .collect()
            }),
        }
    }

    fn random_edit(p: &StaticPuzzle, base: &Prog, rng: &mut Rng) -> Option<Edit> {
        let enabled: Vec<usize> = (0..MAX_FUNCTIONS).filter(|&f| base.cap[f] > 0).collect();
        let f = enabled[rng.below(enabled.len() as u64) as usize];
        let len = base.len(f) as u64;
        match rng.below(3) {
            0 if len > 0 => Some(Edit::Replace(
                f as u8,
                rng.below(len) as u8,
                random_instruction(p, rng),
            )),
            1 if len > 0 => Some(Edit::Delete(f as u8, rng.below(len) as u8)),
            2 if len < base.cap[f] as u64 => Some(Edit::Insert(
                f as u8,
                rng.below(len + 1) as u8,
                random_instruction(p, rng),
            )),
            _ => None,
        }
    }

    /// The simulator agrees with REFERENCE_RUN (success and step count) on
    /// random programs, packing them keeps their meaning, and an edited
    /// program resumed from the base run's divergence snapshot behaves
    /// exactly as when it runs from the start.
    #[test]
    fn t_simulate_diff_random() {
        use crate::puzzle::load_catalog;
        let path =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/levels_catalog.json");
        let puzzles: Vec<StaticPuzzle> = load_catalog(&path)
            .unwrap()
            .iter()
            .map(|r| StaticPuzzle::compile(r).unwrap())
            .collect();
        // Small puzzles succeed more often under random programs.
        let small = [
            puzzle(&["bB"], (0, 0), "right", &[3, 2], 7),
            puzzle(&["rgB", "bRg"], (0, 0), "right", &[4, 3, 2], 7),
            puzzle(&["bbB", "rBb"], (0, 0), "right", &[3, 3], 7),
        ];
        let mut rng = Rng(2026);
        let (mut successes, mut resumed, mut repaired) = (0, 0, 0);
        for _ in 0..20_000 {
            let p = if rng.below(2) == 0 {
                &small[rng.below(small.len() as u64) as usize]
            } else {
                &puzzles[rng.below(puzzles.len() as u64) as usize]
            };
            let r = random_program(p, &mut rng);
            let base = Prog::from_resolved(&r);
            let reference = reference_run(p, &r);
            let mut trace = Trace::new();
            let mut st = SimState::initial(p);
            let ok = simulate(p, &base, &mut st, Some(&mut trace), u32::MAX);
            assert_eq!(ok, reference.status == RunStatus::Success);
            if ok {
                assert_eq!(st.steps, reference.steps);
                successes += 1;
                continue;
            }
            let Some(q) = random_edit(p, &base, &mut rng).and_then(|e| applied(&base, &[e])) else {
                continue;
            };
            let q_reference = reference_run(p, &q.to_resolved());
            let mut fresh = SimState::initial(p);
            let ok = simulate(p, &q, &mut fresh, None, u32::MAX);
            assert_eq!(ok, q_reference.status == RunStatus::Success);
            if ok {
                assert_eq!(fresh.steps, q_reference.steps);
                repaired += 1;
            }
            match divergence(&base, &q, &trace) {
                None => assert!(!ok, "a run that never reaches the edit fails like the base"),
                Some((f, k)) => {
                    let mut st = trace.snaps[trace.snap[f][k] as usize].clone();
                    assert_eq!(simulate(p, &q, &mut st, None, u32::MAX), ok);
                    if ok {
                        assert_eq!(st.steps, fresh.steps);
                    }
                    resumed += 1;
                }
            }
        }
        assert!(
            successes > 100 && repaired > 100 && resumed > 1000,
            "too few cases: {successes} {repaired} {resumed}"
        );
    }

    /// With repair given every node it asks for, the heuristic phase still
    /// returns only valid solutions and proves exhaustion when there is no
    /// solution, and a node-limited solve is deterministic.
    #[test]
    fn t_repair_only_adds_valid_solutions() {
        use crate::search::{Step, solve};
        use crate::stats::{Config, Limits};
        type Mc = (
            &'static [&'static str],
            (i64, i64),
            &'static str,
            &'static [i64],
            Option<u8>,
        );
        let cases: &[Mc] = &[
            (&["bbbB"], (0, 0), "right", &[3], Some(2)),
            (&["Bbbb"], (0, 3), "right", &[4], None),
            (&["bbb", "b b", "bbB"], (0, 0), "right", &[4], Some(4)),
            (&["bbr", "  b", "  B"], (0, 0), "right", &[4], Some(3)),
            (&["bbbbB"], (0, 0), "right", &[1, 2], Some(3)),
            (&["BbbbB"], (0, 2), "left", &[3, 1], None),
        ];
        let config = Config {
            repair: true,
            repair_share: 100,
            ..Config::default()
        };
        for (rows, start, dir, caps, optimum) in cases {
            let p = puzzle(rows, *start, dir, caps, 0);
            let mut solver = Solver::new(&p, config, Limits::default());
            match (solver.heuristic_resume(), optimum) {
                (Step::Found(s), Some(opt)) => {
                    assert!(s.cost >= *opt);
                    assert_eq!(reference_run(&p, &s.program).status, RunStatus::Success);
                }
                (Step::Exhausted, None) => {}
                _ => panic!("{rows:?}: unexpected heuristic outcome"),
            }
        }
        let p = puzzle(&["bbr", "  b", "rbB"], (0, 0), "right", &[3, 2], 1);
        let limits = Limits {
            nodes: Some(500),
            time: None,
        };
        let a = solve(&p, config, limits);
        let b = solve(&p, config, limits);
        assert_eq!(a.outcome, b.outcome);
        assert_eq!(a.stats.search_nodes, b.stats.search_nodes);
        assert_eq!(a.stats.repair_nodes, b.stats.repair_nodes);
    }

    /// The simulator agrees with REFERENCE_RUN on success.
    #[test]
    fn t_simulate_matches_reference() {
        let p = puzzle(&["bbbB"], (0, 0), "right", &[3, 2], 0);
        for prog in [
            vec![vec![Some("forward"), Some("callF1")]],
            vec![vec![Some("forward"), Some("turnLeft")]],
            vec![
                vec![Some("callF2"), Some("callF1")],
                vec![Some("forward"), None],
            ],
        ] {
            let slices: Vec<Vec<Option<&str>>> = prog.clone();
            let refs: Vec<&[Option<&str>]> = slices.iter().map(|v| v.as_slice()).collect();
            let r = program_from(&refs, [3, 2, 0, 0, 0]);
            let mut st = SimState::initial(&p);
            let ok = simulate(&p, &Prog::from_resolved(&r), &mut st, None, u32::MAX);
            assert_eq!(ok, reference_run(&p, &r).status == RunStatus::Success);
        }
    }
}
