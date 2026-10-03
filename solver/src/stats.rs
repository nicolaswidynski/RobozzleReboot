//! Configuration, limits and search statistics (SPEC §16, §20).

use std::time::{Duration, Instant};

use serde::Serialize;

/// Ablation flags (SPEC §16). Turning a flag off removes an optimization;
/// it never forbids a program, so every `Config` finds the same minimal cost.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub lazy_conditions: bool,
    pub lazy_active_conditions: bool,
    pub function_symmetry: bool,
    pub peephole: bool,
    pub cycle_detection: bool,
    pub step_cut: bool,
    /// After the exact phase runs out of its node share, search for any
    /// solution with LDS (heuristic phase); off = exact search only.
    pub heuristic: bool,
    /// History heuristic in the heuristic phase: rank a decision by the
    /// best progress seen anywhere in its subtrees so far (dead branches
    /// included). Ordering only.
    pub history: bool,
    /// The history entries are decaying maxima (a worse subtree pulls an
    /// entry down) instead of plain maxima. Ordering only.
    pub history_decay: bool,
    /// Anonymous auxiliary functions (D-NEWFN): F2..F5 are interchangeable
    /// whatever their capacities; bodies are matched to real functions at
    /// the end, subject to INV-FIT.
    pub anonymous_functions: bool,
    /// D-DEFER-SET: one deferred cell over all non-current colors instead
    /// of one per color (needs `lazy_conditions`).
    pub condition_sets: bool,
    /// FINDER benchmark mode: heuristic phase only, no exact search (so no
    /// optimality proofs and no lower bounds).
    pub heuristic_only: bool,
    /// Local repair in the heuristic phase (`repair.rs`): search the edit
    /// neighbourhood of the best programs seen. Uses nodes, never prunes.
    pub repair: bool,
    /// Largest share of the heuristic phase's nodes (percent) that repair
    /// may use.
    pub repair_share: u8,
}

/// Default `Config::repair_share`: repair may use a quarter of the heuristic
/// phase's nodes.
pub const DEFAULT_REPAIR_SHARE: u8 = 25;

fn is_zero(n: &u64) -> bool {
    *n == 0
}

impl Default for Config {
    fn default() -> Self {
        Self {
            lazy_conditions: true,
            lazy_active_conditions: true,
            function_symmetry: true,
            peephole: true,
            cycle_detection: true,
            step_cut: true,
            heuristic: true,
            history: true,
            history_decay: true,
            anonymous_functions: true,
            condition_sets: true,
            heuristic_only: false,
            repair: true,
            repair_share: DEFAULT_REPAIR_SHARE,
        }
    }
}

impl Config {
    /// All 256 combinations of the flags that shape the exact search, for
    /// `t_config_equivalence`.
    pub fn all_combinations() -> impl Iterator<Item = Config> {
        (0u16..256).map(|b| Config {
            lazy_conditions: b & 1 != 0,
            function_symmetry: b & 2 != 0,
            peephole: b & 4 != 0,
            cycle_detection: b & 8 != 0,
            step_cut: b & 16 != 0,
            lazy_active_conditions: b & 32 != 0,
            heuristic: true,
            history: true,
            history_decay: true,
            anonymous_functions: b & 64 != 0,
            condition_sets: b & 128 != 0,
            heuristic_only: false,
            repair: true,
            repair_share: DEFAULT_REPAIR_SHARE,
        })
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct Limits {
    pub time: Option<Duration>,
    pub nodes: Option<u64>,
}

#[derive(Debug)]
pub struct Deadline {
    start: Instant,
    limits: Limits,
    checks: u64,
    /// A tighter node cap for the current phase (deterministic).
    phase_cap: Option<u64>,
}

pub struct TimedOut;

impl Deadline {
    pub fn new(limits: Limits) -> Self {
        Self {
            start: Instant::now(),
            limits,
            checks: 0,
            phase_cap: None,
        }
    }

    pub fn set_phase_cap(&mut self, cap: Option<u64>) {
        self.phase_cap = cap;
    }

    pub fn node_limit(&self) -> Option<u64> {
        self.limits.nodes
    }

    /// Whether the global node or time limit (not a phase cap) is reached.
    pub fn limit_reached(&self, nodes: u64) -> bool {
        self.limits.nodes.is_some_and(|max| nodes >= max)
            || self.limits.time.is_some_and(|t| self.start.elapsed() > t)
    }

    /// Reads the clock only every 4096 calls (SPEC §17.2).
    #[inline]
    pub fn check(&mut self, nodes: u64) -> Result<(), TimedOut> {
        if let Some(max) = self.limits.nodes
            && nodes > max
        {
            return Err(TimedOut);
        }
        if let Some(cap) = self.phase_cap
            && nodes > cap
        {
            return Err(TimedOut);
        }
        self.checks += 1;
        if self.checks.is_multiple_of(4096)
            && let Some(t) = self.limits.time
            && self.start.elapsed() > t
        {
            return Err(TimedOut);
        }
        Ok(())
    }

    pub fn elapsed(&self) -> Duration {
        self.start.elapsed()
    }
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchStats {
    pub millis: u64,
    pub search_nodes: u64,
    pub nodes_per_budget: Vec<u64>,
    pub normalize_calls: u64,
    pub instructions_evaluated: u64,
    pub open_frontiers: u64,
    pub need_action_frontiers: u64,
    pub need_condition_frontiers: u64,
    pub candidates_generated: u64,
    pub candidates_searched: u64,
    pub dead_crash: u64,
    pub dead_program_ended: u64,
    pub dead_step_limit: u64,
    pub dead_loop: u64,
    pub prune_budget: u64,
    pub prune_step_cut: u64,
    pub prune_symmetry: u64,
    pub prune_peephole: u64,
    pub ends_selected: u64,
    pub condonly_created: u64,
    pub condonly_resolved: u64,
    pub condset_created: u64,
    /// `CondSet` cells narrowed to the colors that still skip.
    pub condset_narrowed: u64,
    pub pending_created: u64,
    pub pending_resolved: u64,
    pub prune_crash: u64,
    /// Cells not appended because the bodies would no longer fit the real
    /// function capacities (INV-FIT).
    pub prune_capacity: u64,
    /// D-END at index 1 of an auxiliary function not generated (P-SINGLE).
    pub prune_single: u64,
    /// Children cut because used slots plus P-RESERVE exceed the budget.
    pub prune_reserve: u64,
    /// Auxiliary bodies closed because INV-FIT forbids any growth.
    pub forced_closes: u64,
    /// `Pending{Paint(x)}` evaluated on an `x` tile: no decision needed.
    pub paint_same_skips: u64,
    pub prune_end_dead: u64,
    pub stack_pushes: u64,
    pub tail_calls: u64,
    pub returns: u64,
    pub stack_rebuilds: u64,
    pub stack_nodes_rebuilt: u64,
    pub max_search_depth: u32,
    pub max_call_depth: u32,
    /// Instructions per `normalize` call: 0, 1–10, 11–100, 101–1000,
    /// 1001–10000, >10000.
    pub normalize_histogram: [u64; 6],
    /// Nodes spent in the heuristic phase (included in `search_nodes`).
    pub heuristic_nodes: u64,
    pub lds_iterations: u32,
    /// Cells removed from a heuristic solution by the shrink pass.
    pub shrink_removed: u32,
    /// Heuristic-phase telemetry: how many normalized nodes had collected
    /// `i` stars (index `i`), and the best progress seen.
    pub heuristic_stars_histogram: Vec<u64>,
    pub heuristic_best_stars_alive: u32,
    pub heuristic_best_stars_dead: u32,
    /// The best live partial program (most stars, then fewest slots), with
    /// its robot position (row, col) and remaining stars; for failure
    /// analysis.
    pub heuristic_best_program: Option<Vec<Vec<String>>>,
    pub heuristic_best_position: Option<(usize, usize)>,
    pub heuristic_best_remaining: Option<Vec<(usize, usize)>>,
    /// Repair telemetry (`Config::repair`; omitted when zero). Programs
    /// repaired, nodes charged for their simulations (included in
    /// `search_nodes`), simulations and instructions simulated.
    #[serde(skip_serializing_if = "is_zero")]
    pub repairs: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_nodes: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_simulations: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_instructions: u64,
    /// Repairs that succeeded with the completed program itself, at edit
    /// distance 1, at edit distance 2.
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_found_d0: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_found_d1: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_found_d2: u64,
    /// Nodes spent on distance-1 and distance-2 neighbourhoods.
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_d1_nodes: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_d2_nodes: u64,
    /// Repaired programs that REFERENCE_RUN rejected (a simulator bug).
    #[serde(skip_serializing_if = "is_zero")]
    pub repair_rejected: u64,
}
