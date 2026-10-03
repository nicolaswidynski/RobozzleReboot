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
        }
    }
}

impl Config {
    /// All 64 combinations, for `t_config_equivalence`.
    pub fn all_combinations() -> impl Iterator<Item = Config> {
        (0u8..64).map(|b| Config {
            lazy_conditions: b & 1 != 0,
            function_symmetry: b & 2 != 0,
            peephole: b & 4 != 0,
            cycle_detection: b & 8 != 0,
            step_cut: b & 16 != 0,
            lazy_active_conditions: b & 32 != 0,
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
}

pub struct TimedOut;

impl Deadline {
    pub fn new(limits: Limits) -> Self {
        Self {
            start: Instant::now(),
            limits,
            checks: 0,
        }
    }

    /// Reads the clock only every 4096 calls (SPEC §17.2).
    #[inline]
    pub fn check(&mut self, nodes: u64) -> Result<(), TimedOut> {
        if let Some(max) = self.limits.nodes
            && nodes > max
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
    pub pending_created: u64,
    pub pending_resolved: u64,
    pub prune_crash: u64,
    pub prune_end_dead: u64,
    pub stack_pushes: u64,
    pub tail_calls: u64,
    pub returns: u64,
    pub stack_rebuilds: u64,
    pub stack_nodes_rebuilt: u64,
    pub max_search_depth: u32,
    pub max_call_depth: u32,
}
