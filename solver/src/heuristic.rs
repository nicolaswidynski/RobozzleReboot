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
//! The first solution found is not necessarily minimal. It is verified on
//! the reference interpreter, then shrunk by deleting cells while it still
//! solves the puzzle.

use crate::normalize::NormalizeResult;
use crate::program::Cell;
use crate::program::ResolvedProgram;
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::search::{FoundBy, SearchState, Solution, Solver, Step};
use crate::types::{Action, Condition, FnId, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS};

type Score = (u32, u16, u8, usize);

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
    started: bool,
    stack: Vec<HeuristicFrame>,
    /// Best stars collected anywhere below each decision (history heuristic).
    history: Vec<u32>,
}

struct HeuristicFrame {
    /// Normalized kids in rank order, with their decision's history key.
    kids: Vec<(SearchState, NormalizeResult, u16)>,
    next: usize,
    allowance: u32,
    mark: usize,
    /// Best stars collected in this frame's subtree so far.
    best: u32,
    /// The parent's decision that led here.
    parent_key: Option<u16>,
}

impl Solver<'_> {
    /// Continues LDS until a solution, until an iteration finishes without
    /// cutting anything (the whole space is searched), or until the node cap.
    pub(crate) fn heuristic_resume(&mut self) -> Step {
        let before = self.stats.search_nodes;
        let step = self.heuristic_steps();
        self.stats.heuristic_nodes += self.stats.search_nodes - before;
        step
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
                match self.normalize_counted(&mut root) {
                    NormalizeResult::Solved => return Step::Found(self.finalize_heuristic(&root)),
                    NormalizeResult::Dead(_) => return Step::Exhausted,
                    r => {
                        let allowance = self.heuristic.allowance;
                        if let Some(s) =
                            self.push_heuristic_frame(&root, r, allowance, budget, None)
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
                let (kid, result, key) = top.kids[top.next];
                top.next += 1;
                let allowance = top.allowance - rank;
                let mark = top.mark;
                self.arena.truncate(mark);
                self.stats.candidates_searched += 1;
                if let Some(s) =
                    self.push_heuristic_frame(&kid, result, allowance, budget, Some(key))
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
        let kids = self.children(state, result, budget);
        let mut best = 0;
        let mut ranked: Vec<(Score, SearchState, NormalizeResult, u16)> =
            Vec::with_capacity(kids.len());
        for (i, mut kid) in kids.into_iter().enumerate() {
            let key = history_key(f, index, decision_code(&kid, f, index));
            let r = self.normalize_counted(&mut kid);
            let collected = total - kid.machine.stars.len();
            best = best.max(collected);
            let h = &mut self.heuristic.history[key as usize];
            *h = (*h).max(collected);
            match r {
                NormalizeResult::Solved => return Some(self.finalize_heuristic(&kid)),
                NormalizeResult::Dead(_) => self.record_progress(&kid, false),
                r => {
                    self.record_progress(&kid, true);
                    ranked.push((self.score(&kid, i, key), kid, r, key));
                }
            }
        }
        ranked.sort_by_key(|(score, _, _, _)| *score);
        let mark = self.arena.mark();
        self.heuristic.stack.push(HeuristicFrame {
            kids: ranked
                .into_iter()
                .map(|(_, k, r, key)| (k, r, key))
                .collect(),
            next: 0,
            allowance,
            mark,
            best,
            parent_key,
        });
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
            *h = (*h).max(frame.best);
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

    fn score(&self, kid: &SearchState, index: usize, key: u16) -> Score {
        let m = &kid.machine;
        let total = self.puzzle.initial_stars.len();
        let mut collected = total - m.stars.len();
        if self.config.history {
            collected = collected.max(self.heuristic.history[key as usize]);
        }
        (
            total - collected,
            self.puzzle.nearest_star(m.position, &m.stars),
            kid.used_slots,
            index,
        )
    }

    fn finalize_heuristic(&mut self, state: &SearchState) -> Solution {
        let program = self.realize(&state.program).to_physical_dropping_cond_only();
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
            found_by: FoundBy::Heuristic,
        }
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
                    assert_eq!(s.found_by, FoundBy::Heuristic);
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
