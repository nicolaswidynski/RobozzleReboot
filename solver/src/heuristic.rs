//! Heuristic phase: limited discrepancy search (LDS) over the same lazy
//! synthesis tree as the exact search, with the same sound pruning.
//!
//! At every frontier each child is normalized once (one-step lookahead) and
//! the children are ranked by: fewest stars left, shortest walk to the
//! nearest star, fewest occupied slots, then generation order. Taking the
//! child of rank `r` costs `r` discrepancies; iteration `d` explores every
//! path whose total discrepancy is at most `d`. Nothing is random and ties
//! are broken by generation order, so the result is deterministic for a
//! given node limit.
//!
//! With `config.history`, a child is ranked by the best progress seen so far
//! anywhere below the same decision (same function, slot and cell), dead
//! branches included, if that beats its own immediate progress. This is the
//! analogue of a chess engine's history heuristic: a near-solution that died
//! late keeps pulling the search back to its prefix. It only reorders.
//!
//! With `config.history_decay`, a history entry is a decaying maximum
//! instead of a plain one: a subtree that does better than the entry raises
//! it at once (a bonus), a subtree that does worse pulls it a quarter of the
//! way down (a malus). A decision that once led far but keeps failing
//! slowly loses its pull, so the search moves on to other prefixes.
//!
//! With `config.low_star` on puzzles with at most 2 stars, the star count
//! is nearly always 0, so it cannot tell branches apart. Progress is then
//! measured geometrically: a branch's value is its stars, then the smallest
//! walking distance to a remaining star its run has reached since the last
//! star (a side channel, `Progress`, not part of the semantic state). The
//! history stores that value, so a dead branch that came close still pulls
//! the search back. Level 2 also breaks ties by the number of distinct
//! (tile, direction) poses the run has reached, more first. Ordering only.
//!
//! With `config.repair`, local repair (`repair.rs`) runs after every frame
//! push: it tries small edits of the best programs seen so far, within a
//! share of this phase's nodes.
//!
//! The first solution found is not necessarily minimal. It is verified on
//! the reference interpreter, then shrunk by deleting cells while it still
//! solves the puzzle.

use crate::normalize::{NormalizeResult, Progress};
use crate::policy::{DecFeat, KidFeat};
use crate::program::Cell;
use crate::program::ResolvedProgram;
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::search::{FoundBy, SearchState, Solution, Solver, Step};
use crate::types::{Action, Condition, FnId, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS};

/// (−progress, −poses reached (low-star level 2, else 0), walking distance,
/// used slots, generation order); smaller ranks first.
type Score = (u32, u16, u16, u8, usize);

/// History entries count stars × 16, so that a decaying entry keeps a
/// fraction of a star.
const HISTORY_SCALE: u32 = 16;
/// In low-star mode a star is worth more than any distance improvement.
const LOW_STAR_SCALE: u32 = 1 << 16;
/// Low-star mode applies to puzzles with at most this many stars.
const LOW_STAR_MAX_STARS: u32 = 2;
/// A worse subtree pulls a decaying entry `1 / 2^DECAY_SHIFT` of the way
/// down.
const DECAY_SHIFT: u32 = 2;

/// One decaying history entry: a better result is taken at once (bonus), a
/// worse one pulls the entry toward it (malus).
fn decay_toward(h: &mut u32, v: u32) {
    if v > *h {
        *h = v;
    } else {
        *h -= (*h - v) >> DECAY_SHIFT;
    }
}

/// Distinct decision codes per slot (see `decision_code`).
const CODES: usize = 128;
const HISTORY_SIZE: usize = MAX_FUNCTIONS * MAX_FUNCTION_SLOTS * CODES;

fn action_code(a: Action) -> usize {
    match a {
        Action::Forward => 0,
        Action::TurnLeft => 1,
        Action::TurnRight => 2,
        Action::Paint(c) => 3 + c as usize,
        Action::Call(g) => 6 + g as usize,
    }
}

/// A code for the decision a child made at slot `index` of function `f`.
fn decision_code(kid: &SearchState, f: FnId, index: u8) -> usize {
    let d = kid.program.function(f);
    if index >= d.len {
        return 0; // END
    }
    match d.cell(index) {
        Cell::Resolved(i) => {
            let c = match i.condition {
                Condition::Any => 0,
                Condition::Color(c) => 1 + c as usize,
            };
            1 + c * 11 + action_code(i.action)
        }
        Cell::CondOnly(c) => 45 + c as usize,
        Cell::Pending { action, color } => 48 + color as usize * 11 + action_code(action),
        Cell::CondSet(mask) => 81 + mask.0 as usize, // 84, 86 or 87
        Cell::Unused => unreachable!(),
    }
}

fn history_key(f: FnId, index: u8, code: usize) -> u16 {
    ((f as usize * MAX_FUNCTION_SLOTS + index as usize) * CODES + code) as u16
}

fn frontier_slot(result: NormalizeResult) -> (FnId, u8) {
    match result {
        NormalizeResult::OpenSlot { function, index }
        | NormalizeResult::NeedCondition { function, index }
        | NormalizeResult::NeedAction {
            function, index, ..
        } => (function, index),
        NormalizeResult::Solved | NormalizeResult::Dead(_) => unreachable!(),
    }
}

/// Resumable LDS state (an explicit stack), so that the portfolio can pause
/// the heuristic phase and continue it later without losing work.
#[derive(Default)]
pub(crate) struct HeuristicCursor {
    /// Discrepancy allowance of the current iteration.
    allowance: u32,
    /// Whether the current iteration skipped a kid because of the allowance.
    cut: bool,
    /// `search_nodes` when the current slice started.
    slice_start: u64,
    started: bool,
    stack: Vec<HeuristicFrame>,
    /// Best progress (`history_value`) reached anywhere below each decision
    /// (history heuristic); a decaying maximum with `config.history_decay`.
    history: Vec<u32>,
    /// Memoized context weights of the learned ordering (`config.policy`).
    policy_memo: crate::policy::Memo,
}

struct HeuristicFrame {
    /// Normalized kids in rank order, with their run's progress and their
    /// decision's history key.
    kids: Vec<(SearchState, Progress, NormalizeResult, u16)>,
    next: usize,
    allowance: u32,
    mark: usize,
    /// Best progress (`history_value`) in this frame's subtree so far.
    best: u32,
    /// The parent's decision that led here.
    parent_key: Option<u16>,
}

impl Solver<'_> {
    /// Continues LDS until a solution, until an iteration finishes without
    /// cutting anything (the whole space is searched), or until the node cap.
    pub(crate) fn heuristic_resume(&mut self) -> Step {
        self.heuristic.slice_start = self.stats.search_nodes;
        let step = self.heuristic_steps();
        self.stats.heuristic_nodes += self.stats.search_nodes - self.heuristic.slice_start;
        step
    }

    /// Nodes used by the heuristic phase so far (repair included), also in
    /// the middle of a slice.
    pub(crate) fn heuristic_nodes_so_far(&self) -> u64 {
        self.stats.heuristic_nodes + self.stats.search_nodes - self.heuristic.slice_start
    }

    fn heuristic_steps(&mut self) -> Step {
        let budget = self.puzzle.total_capacity() as u8;
        loop {
            if !self.heuristic.started {
                if self.deadline.check(self.stats.search_nodes + 1).is_err() {
                    return Step::Paused;
                }
                self.stats.lds_iterations += 1;
                self.arena.clear();
                self.heuristic.stack.clear();
                self.heuristic.cut = false;
                self.heuristic.started = true;
                let mut root = self.root();
                let mut progress = Progress::new(self.puzzle, &root.machine);
                match self.lds_normalize(&mut root, &mut progress) {
                    NormalizeResult::Solved => return Step::Found(self.finalize_heuristic(&root)),
                    NormalizeResult::Dead(_) => return Step::Exhausted,
                    r => {
                        let allowance = self.heuristic.allowance;
                        if let Some(s) =
                            self.push_heuristic_frame(&root, &progress, r, allowance, budget, None)
                        {
                            return Step::Found(s);
                        }
                    }
                }
            }
            loop {
                let Some(top) = self.heuristic.stack.last_mut() else {
                    if !self.heuristic.cut {
                        return Step::Exhausted;
                    }
                    self.heuristic.allowance += 1;
                    self.heuristic.started = false;
                    break;
                };
                if top.next == top.kids.len() {
                    self.pop_heuristic_frame();
                    continue;
                }
                let rank = top.next as u32;
                if rank > top.allowance {
                    // Kids are in rank order: the rest are cut as well.
                    self.heuristic.cut = true;
                    self.pop_heuristic_frame();
                    continue;
                }
                if self.deadline.check(self.stats.search_nodes + 1).is_err() {
                    return Step::Paused;
                }
                let (kid, progress, result, key) = top.kids[top.next];
                top.next += 1;
                let allowance = top.allowance - rank;
                let mark = top.mark;
                self.arena.truncate(mark);
                self.stats.candidates_searched += 1;
                if let Some(s) =
                    self.push_heuristic_frame(&kid, &progress, result, allowance, budget, Some(key))
                {
                    return Step::Found(s);
                }
            }
        }
    }

    /// Expands a normalized frontier: every child is normalized once
    /// (lookahead) and ranked. Returns a solution if a child solves it.
    fn push_heuristic_frame(
        &mut self,
        state: &SearchState,
        progress: &Progress,
        result: NormalizeResult,
        allowance: u32,
        budget: u8,
        parent_key: Option<u16>,
    ) -> Option<Solution> {
        if self.heuristic.history.is_empty() {
            self.heuristic.history = vec![0; HISTORY_SIZE];
        }
        let (f, index) = frontier_slot(result);
        let total = self.puzzle.initial_stars.len();
        let policy = if self.config.policy {
            Some(
                crate::policy::POLICY
                    .get()
                    .expect("--policy weights loaded"),
            )
        } else {
            None
        };
        let dec = policy.map(|_| self.policy_dec(state, result, f, index, budget));
        let kids = self.children(state, result, budget);
        let mut best = 0;
        let mut ranked: Vec<(Score, SearchState, Progress, NormalizeResult, u16, KidFeat)> =
            Vec::with_capacity(kids.len());
        for (i, mut kid) in kids.into_iter().enumerate() {
            let key = history_key(f, index, decision_code(&kid, f, index));
            let pre = dec.map(|_| {
                let (ct, cc, ac) = cell_parts(&kid, f, index);
                let newfn = (kid.introduced_functions & !state.introduced_functions) != 0;
                (ct, cc, ac, newfn)
            });
            let mut kid_progress = *progress;
            let r = self.lds_normalize(&mut kid, &mut kid_progress);
            let collected = total - kid.machine.stars.len();
            let value = self.history_value(&kid, &kid_progress);
            best = best.max(value);
            let h = &mut self.heuristic.history[key as usize];
            *h = (*h).max(value);
            if self.config.repair && r != NormalizeResult::Solved {
                self.repair_observe(&kid, collected);
            }
            match r {
                NormalizeResult::Solved => return Some(self.finalize_heuristic(&kid)),
                NormalizeResult::Dead(_) => self.record_progress(&kid, false),
                r => {
                    self.record_progress(&kid, true);
                    let score = self.score(&kid, &kid_progress, i, key);
                    let feat = match pre {
                        Some(pre) => self.policy_kid(state, &kid, r, pre),
                        None => KidFeat::default(),
                    };
                    ranked.push((score, kid, kid_progress, r, key, feat));
                }
            }
        }
        ranked.sort_by_key(|(score, ..)| *score);
        if let (Some(policy), Some(dec)) = (policy, dec)
            && ranked.len() > 1
        {
            ranked = self.policy_order(policy, &dec, ranked);
        }
        let mark = self.arena.mark();
        self.heuristic.stack.push(HeuristicFrame {
            kids: ranked
                .into_iter()
                .map(|(_, k, p, r, key, _)| (k, p, r, key))
                .collect(),
            next: 0,
            allowance,
            mark,
            best,
            parent_key,
        });
        if self.config.repair
            && let Some(s) = self.repair_tick()
        {
            return Some(s);
        }
        None
    }

    /// Pops a finished (or cut) frame, crediting its best progress to the
    /// decision that led to it and to its parent frame.
    fn pop_heuristic_frame(&mut self) {
        let frame = self.heuristic.stack.pop().expect("a frame to pop");
        if let Some(parent) = self.heuristic.stack.last_mut() {
            parent.best = parent.best.max(frame.best);
        }
        if let Some(key) = frame.parent_key {
            let h = &mut self.heuristic.history[key as usize];
            let v = frame.best;
            if self.config.history_decay {
                decay_toward(h, v);
            } else {
                *h = (*h).max(v);
            }
        }
    }

    /// Telemetry only; never influences the search.
    fn record_progress(&mut self, kid: &SearchState, alive: bool) {
        let total = self.puzzle.initial_stars.len();
        let collected = total - kid.machine.stars.len();
        let stats = &mut self.stats;
        if stats.heuristic_stars_histogram.len() <= total as usize {
            stats
                .heuristic_stars_histogram
                .resize(total as usize + 1, 0);
        }
        stats.heuristic_stars_histogram[collected as usize] += 1;
        if !alive {
            stats.heuristic_best_stars_dead = stats.heuristic_best_stars_dead.max(collected);
            return;
        }
        let better = stats.heuristic_best_program.is_none()
            || collected > stats.heuristic_best_stars_alive
            || (collected == stats.heuristic_best_stars_alive
                && (kid.used_slots as usize)
                    < stats
                        .heuristic_best_program
                        .as_ref()
                        .map_or(usize::MAX, |p| p.iter().map(Vec::len).sum()));
        if better {
            stats.heuristic_best_stars_alive = collected;
            stats.heuristic_best_program = Some(kid.program.to_partial_tokens());
            stats.heuristic_best_position = Some(self.puzzle.row_col(kid.machine.position));
            stats.heuristic_best_remaining = Some(
                kid.machine
                    .stars
                    .iter()
                    .map(|t| self.puzzle.row_col(t))
                    .collect(),
            );
        }
    }

    /// Normalizes an LDS node, recording its run's progress in low-star
    /// mode.
    fn lds_normalize(&mut self, s: &mut SearchState, progress: &mut Progress) -> NormalizeResult {
        if self.low_star_on() {
            self.normalize_tracked_counted(s, progress)
        } else {
            self.normalize_counted(s)
        }
    }

    /// Low-star mode (SPEC §17.3): on, and the puzzle has at most
    /// `LOW_STAR_MAX_STARS` stars.
    fn low_star_on(&self) -> bool {
        self.config.low_star > 0 && self.puzzle.initial_stars.len() <= LOW_STAR_MAX_STARS
    }

    /// The progress a node has made, as ranked and stored in the history:
    /// stars × `HISTORY_SCALE`; in low-star mode, stars first, then the
    /// smallest walking distance to a remaining star its run has reached.
    fn history_value(&self, kid: &SearchState, progress: &Progress) -> u32 {
        let collected = self.puzzle.initial_stars.len() - kid.machine.stars.len();
        if self.low_star_on() {
            collected * LOW_STAR_SCALE + (u16::MAX - progress.best_distance) as u32
        } else {
            collected * HISTORY_SCALE
        }
    }

    fn score(&self, kid: &SearchState, progress: &Progress, index: usize, key: u16) -> Score {
        let m = &kid.machine;
        let mut value = self.history_value(kid, progress);
        if self.config.history {
            value = value.max(self.heuristic.history[key as usize]);
        }
        let poses = if self.low_star_on() && self.config.low_star >= 2 {
            u16::MAX - progress.coverage() as u16
        } else {
            0
        };
        (
            u32::MAX - value,
            poses,
            self.puzzle.nearest_star(m.position, &m.stars),
            kid.used_slots,
            index,
        )
    }

    fn finalize_heuristic(&mut self, state: &SearchState) -> Solution {
        let program = self
            .realize(&state.program)
            .to_physical_dropping_cond_only();
        self.finalize_physical(program, FoundBy::Heuristic)
    }

    /// Verifies a complete physical program with `REFERENCE_RUN` (MUST
    /// succeed), shrinks it, checks its shape and verifies it again.
    pub(crate) fn finalize_physical(
        &mut self,
        program: ResolvedProgram,
        found_by: FoundBy,
    ) -> Solution {
        let run = reference_run(self.puzzle, &program);
        assert_eq!(
            run.status,
            RunStatus::Success,
            "INV-VERIFY: {:?}",
            program.to_tokens()
        );
        let (program, removed) = shrink(self.puzzle, program);
        self.stats.shrink_removed += removed;
        self.assert_shape(&program);
        let run = reference_run(self.puzzle, &program);
        assert_eq!(run.status, RunStatus::Success, "INV-VERIFY after shrink");
        Solution {
            cost: program.occupied_slots() as u8,
            steps: run.steps,
            program,
            optimal: false,
            found_by,
        }
    }
}

/// One live kid of a frontier as `push_heuristic_frame` ranks it.
type RankedKid = (Score, SearchState, Progress, NormalizeResult, u16, KidFeat);

/// Kind code of a normalize result: 0 open, 1 need-condition, 2
/// need-action, 3 solved, 4 dead.
fn result_kind(r: NormalizeResult) -> u8 {
    match r {
        NormalizeResult::OpenSlot { .. } => 0,
        NormalizeResult::NeedCondition { .. } => 1,
        NormalizeResult::NeedAction { .. } => 2,
        NormalizeResult::Solved => 3,
        NormalizeResult::Dead(_) => 4,
    }
}

/// (cell type, condition code, action code) of the cell at (f, index), as
/// the training dump: cell type 0 END, 1 resolved, 2 cond-only, 3 pending,
/// 4 cond-set; condition 0 any / 1+c color / 4+mask set; action
/// `action_code` or 15 unknown.
fn cell_parts(s: &SearchState, f: FnId, index: u8) -> (u8, u8, u8) {
    let d = s.program.function(f);
    if index >= d.len {
        return (0, 0, 15);
    }
    match d.cell(index) {
        Cell::Resolved(i) => {
            let c = match i.condition {
                Condition::Any => 0,
                Condition::Color(c) => 1 + c as u8,
            };
            (1, c, action_code(i.action) as u8)
        }
        Cell::CondOnly(c) => (2, 1 + c as u8, 15),
        Cell::Pending { action, color } => (3, 1 + color as u8, action_code(action) as u8),
        Cell::CondSet(m) => (4, 4 + m.0, 15),
        Cell::Unused => (9, 0, 15),
    }
}

impl Solver<'_> {
    /// The learned ordering (`config.policy`): the frontier's context
    /// features (also written by `replay_dump` for training).
    fn policy_dec(
        &self,
        state: &SearchState,
        result: NormalizeResult,
        f: FnId,
        index: u8,
        budget: u8,
    ) -> DecFeat {
        let pm = &state.machine;
        let total = self.puzzle.initial_stars.len();
        let mut depth = 0u32;
        let mut cursor = pm.callers;
        while let Some(id) = cursor {
            depth += 1;
            if depth >= 2 {
                break; // the model only sees min(depth, 2)
            }
            cursor = self.arena.get(id).parent;
        }
        DecFeat {
            fk: result_kind(result),
            f,
            index,
            stars: total - pm.stars.len(),
            total,
            dist: if !pm.stars.is_empty() {
                self.puzzle.nearest_star(pm.position, &pm.stars)
            } else {
                0
            },
            tile: pm.tile_color() as u8,
            fwd: match self.puzzle.forward_target(pm.position, pm.direction) {
                None => 0,
                Some(t) => 1 + pm.colors.get(t) as u8,
            },
            depth,
            intro: state.introduced_functions.count_ones(),
            budget: budget as u32,
            used: state.used_slots as u32,
            prev: if index > 0 {
                Some(cell_parts(state, f, index - 1))
            } else {
                None
            },
        }
    }

    /// The learned ordering: a live kid's context features (`pre`: its new
    /// cell and whether it introduced a function, taken before the
    /// lookahead).
    fn policy_kid(
        &self,
        parent: &SearchState,
        kid: &SearchState,
        r: NormalizeResult,
        pre: (u8, u8, u8, bool),
    ) -> KidFeat {
        let (pm, km) = (&parent.machine, &kid.machine);
        let total = self.puzzle.initial_stars.len();
        KidFeat {
            ct: pre.0,
            cc: pre.1,
            ac: pre.2,
            newfn: pre.3,
            kind: result_kind(r),
            stars: total - km.stars.len(),
            dist: if !km.stars.is_empty() {
                self.puzzle.nearest_star(km.position, &km.stars)
            } else {
                0
            },
            dsteps: km.steps.saturating_sub(pm.steps),
            moved: km.position != pm.position,
        }
    }

    /// Reorders the live kids (given in static rank order) by learned
    /// probability, most probable first, ties by static rank.
    fn policy_order(
        &mut self,
        policy: &crate::policy::Policy,
        dec: &DecFeat,
        ranked: Vec<RankedKid>,
    ) -> Vec<RankedKid> {
        let memo = &mut self.heuristic.policy_memo;
        let z: Vec<f64> = ranked
            .iter()
            .enumerate()
            .map(|(rank, e)| policy.logit(memo, dec, &e.5, rank))
            .collect();
        let mut order: Vec<usize> = (0..ranked.len()).collect();
        order.sort_by(|&a, &b| z[b].total_cmp(&z[a]).then(a.cmp(&b)));
        let mut slots: Vec<Option<RankedKid>> = ranked.into_iter().map(Some).collect();
        order
            .iter()
            .map(|&i| slots[i].take().expect("each kid once"))
            .collect()
    }

    /// Training data for the learned ordering: replays a known program
    /// (internal labels, `canon::internal_bodies`) through the LDS tree
    /// under the static ranking (empty history) and returns, for every
    /// decision on its path, the frontier's context features, every child's
    /// features and static score (live children), and the child that
    /// follows the program. The features come from `policy_dec` and
    /// `policy_kid`, the functions the search itself uses.
    pub fn replay_dump(
        &mut self,
        known: &[Vec<crate::types::Instruction>],
    ) -> Result<Vec<serde_json::Value>, String> {
        use serde_json::json;
        self.heuristic.history = vec![0; HISTORY_SIZE];
        let budget = self.puzzle.total_capacity() as u8;
        let mut state = self.root();
        let mut progress = Progress::new(self.puzzle, &state.machine);
        let mut r = self.lds_normalize(&mut state, &mut progress);
        let mut out = Vec::new();
        for _ in 0..5000 {
            match r {
                NormalizeResult::Solved => return Ok(out),
                NormalizeResult::Dead(x) => return Err(format!("the known path died: {x:?}")),
                _ => {}
            }
            let (f, index) = frontier_slot(r);
            let dec = self.policy_dec(&state, r, f, index, budget);
            let kids = self.children(&state, r, budget);
            let mut rows = Vec::with_capacity(kids.len());
            let mut next = None;
            for (i, mut kid) in kids.into_iter().enumerate() {
                let follows = crate::canon::consistent(&kid, r, known);
                let key = history_key(f, index, decision_code(&kid, f, index));
                let (ct, cc, ac) = cell_parts(&kid, f, index);
                let newfn = (kid.introduced_functions & !state.introduced_functions) != 0;
                let mut kid_progress = progress;
                let kr = self.lds_normalize(&mut kid, &mut kid_progress);
                let k = self.policy_kid(&state, &kid, kr, (ct, cc, ac, newfn));
                let score = (k.kind <= 2).then(|| {
                    let s = self.score(&kid, &kid_progress, i, key);
                    vec![s.0 as u64, s.1 as u64, s.2 as u64, s.3 as u64, s.4 as u64]
                });
                rows.push(json!({
                    "ct": k.ct, "cc": k.cc, "ac": k.ac, "newfn": k.newfn, "kind": k.kind,
                    "stars": k.stars, "dist": k.dist, "dsteps": k.dsteps, "moved": k.moved,
                    "score": score, "follows": follows,
                }));
                if follows && next.is_none() {
                    next = Some((i, kid, kid_progress, kr));
                }
            }
            let Some((chosen, kid, kid_progress, kr)) = next else {
                return Err(format!("no child follows the known program at {r:?}"));
            };
            out.push(json!({
                "kind": dec.fk, "f": dec.f, "index": dec.index, "stars": dec.stars,
                "total": dec.total, "dist": dec.dist, "tile": dec.tile, "fwd": dec.fwd,
                "depth": dec.depth, "intro": dec.intro, "budget": dec.budget, "used": dec.used,
                "prev": dec.prev.map(|(a, b, c)| vec![a, b, c]).unwrap_or_default(),
                "chosen": chosen, "kids": rows,
            }));
            match kr {
                NormalizeResult::Solved => return Ok(out),
                NormalizeResult::Dead(_) => return Err("the known path's child dies".into()),
                _ => {}
            }
            state = kid;
            progress = kid_progress;
            r = kr;
        }
        Err("too long".into())
    }
}

/// Deletes cells while the program still solves the puzzle: single cells
/// first, then adjacent pairs (e.g. a `L R` that cancels out), first to
/// last, repeating until nothing more can be deleted. Deterministic.
pub fn shrink(puzzle: &StaticPuzzle, mut program: ResolvedProgram) -> (ResolvedProgram, u32) {
    let mut removed = 0;
    'pass: loop {
        for width in [1usize, 2] {
            for f in 0..program.functions.len() {
                let len = program.functions[f].len();
                for i in 0..len.saturating_sub(width - 1) {
                    if program.functions[f][i..i + width]
                        .iter()
                        .any(|s| s.is_none())
                    {
                        continue;
                    }
                    let mut candidate = program.clone();
                    candidate.functions[f].drain(i..i + width);
                    candidate.functions[f].resize(len, None);
                    if reference_run(puzzle, &candidate).status == RunStatus::Success {
                        program = candidate;
                        removed += width as u32;
                        continue 'pass;
                    }
                }
            }
        }
        return (program, removed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::program_from;
    use crate::puzzle::tests::puzzle;
    use crate::search::{Outcome, UnsolvableReason, solve};
    use crate::stats::{Config, Limits};

    #[test]
    fn t_shrink_removes_redundant_cells() {
        let p = puzzle(&["bbbB"], (0, 0), "right", &[4], 0);
        let prog = program_from(
            &[&[
                Some("forward"),
                Some("turnLeft"),
                Some("turnRight"),
                Some("callF1"),
            ]],
            [4, 0, 0, 0, 0],
        );
        let (shrunk, removed) = shrink(&p, prog);
        assert_eq!(removed, 2);
        assert_eq!(
            shrunk.to_tokens()[0],
            vec![Some("forward".into()), Some("callF1".into()), None, None]
        );
    }

    /// FIND returns the first solution and claims no minimality it has not
    /// proven; `prove_minimal` returns the proven shortest program.
    #[test]
    fn t_find_and_prove_modes() {
        type Case = (
            &'static [&'static str],
            (i64, i64),
            &'static str,
            &'static [i64],
            u8,
        );
        let cases: &[Case] = &[
            (&["bbbB"], (0, 0), "right", &[3], 2),
            (&["bbb", "b b", "bbB"], (0, 0), "right", &[4], 4),
            (&["bbr", "  b", "  B"], (0, 0), "right", &[4], 3),
            (&["bbbbB"], (0, 0), "right", &[1, 2], 3),
        ];
        for (rows, start, dir, caps, optimum) in cases {
            let p = puzzle(rows, *start, dir, caps, 0);
            let find = Config {
                exact_share: 0,
                ..Config::default()
            };
            match solve(&p, find, Limits::default()).outcome {
                Outcome::Solved(s) => {
                    assert!(s.cost >= *optimum);
                    assert!(
                        !s.optimal,
                        "{rows:?}: FIND without exact search proved nothing"
                    );
                    assert_ne!(s.found_by, FoundBy::Exact);
                }
                other => panic!("{rows:?}: {other:?}"),
            }
            let prove = Config {
                exact_share: 0,
                prove_minimal: true,
                ..Config::default()
            };
            match solve(&p, prove, Limits::default()).outcome {
                Outcome::Solved(s) => assert!(s.optimal && s.cost == *optimum, "{rows:?}"),
                other => panic!("{rows:?}: {other:?}"),
            }
        }
    }

    /// Heuristic phase alone (exact phase given no nodes): finds a verified
    /// solution whenever one exists, proves exhaustion otherwise.
    #[test]
    fn t_heuristic_phase_alone() {
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
        for (rows, start, dir, caps, optimum) in cases {
            let p = puzzle(rows, *start, dir, caps, 0);
            let mut solver = Solver::new(&p, Config::default(), Limits::default());
            match (solver.heuristic_resume(), optimum) {
                (Step::Found(s), Some(opt)) => {
                    assert!(s.cost >= *opt);
                    assert!(matches!(s.found_by, FoundBy::Heuristic | FoundBy::Repair));
                }
                (Step::Exhausted, None) => {}
                _ => panic!("{rows:?}: unexpected heuristic outcome"),
            }
            // Full solve with a tiny node budget still reports the optimum
            // or a valid heuristic solution, never a wrong one.
            let r = solve(
                &p,
                Config::default(),
                Limits {
                    nodes: Some(20),
                    time: None,
                },
            );
            match (r.outcome, optimum) {
                (Outcome::Solved(s), Some(opt)) => {
                    assert!(s.cost >= *opt && (!s.optimal || s.cost == *opt));
                    assert!(r.lower_bound <= *opt);
                }
                (Outcome::Unsolvable(UnsolvableReason::Exhausted), None)
                | (Outcome::Timeout, _) => {}
                (other, _) => panic!("{rows:?}: {other:?}"),
            }
        }
    }

    /// The history heuristic only reorders: with a decaying, a plain or no
    /// history, LDS still finds a valid solution when one exists and proves
    /// exhaustion otherwise, and a node-limited run is deterministic.
    #[test]
    fn t_history_variants() {
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
        for (history, history_decay) in [(true, true), (true, false), (false, false)] {
            let config = Config {
                history,
                history_decay,
                ..Config::default()
            };
            for (rows, start, dir, caps, optimum) in cases {
                let p = puzzle(rows, *start, dir, caps, 0);
                let mut solver = Solver::new(&p, config, Limits::default());
                match (solver.heuristic_resume(), optimum) {
                    (Step::Found(s), Some(opt)) => assert!(s.cost >= *opt),
                    (Step::Exhausted, None) => {}
                    _ => panic!("{rows:?} {history} {history_decay}: unexpected outcome"),
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
        }
    }

    /// The learned ordering (`--policy`) only reorders: LDS still finds a
    /// valid solution when one exists, proves exhaustion otherwise, and is
    /// deterministic.
    #[test]
    fn t_policy_ordering() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("policy/linear_b.json");
        let policy = crate::policy::Policy::load(&path).expect("policy/linear_b.json");
        let _ = crate::policy::POLICY.set(policy);
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
            policy: true,
            ..Config::default()
        };
        for (rows, start, dir, caps, optimum) in cases {
            let p = puzzle(rows, *start, dir, caps, 0);
            let mut solver = Solver::new(&p, config, Limits::default());
            match (solver.heuristic_resume(), optimum) {
                (Step::Found(s), Some(opt)) => assert!(s.cost >= *opt),
                (Step::Exhausted, None) => {}
                _ => panic!("{rows:?}: unexpected outcome"),
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
    }

    #[test]
    fn t_node_limited_solve_is_deterministic() {
        let p = puzzle(&["bbr", "  b", "rbB"], (0, 0), "right", &[3, 2], 1);
        let limits = Limits {
            nodes: Some(500),
            time: None,
        };
        let a = solve(&p, Config::default(), limits);
        let b = solve(&p, Config::default(), limits);
        assert_eq!(a.outcome, b.outcome);
        assert_eq!(a.lower_bound, b.lower_bound);
        assert_eq!(a.stats.search_nodes, b.stats.search_nodes);
        assert_eq!(
            a.stats.instructions_evaluated,
            b.stats.instructions_evaluated
        );
    }
}
