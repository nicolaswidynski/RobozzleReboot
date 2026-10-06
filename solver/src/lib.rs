//! RoboZZle solver. The normative specification is `SPEC.md`; rule IDs in
//! comments (`R-*`, `N-*`, `P-*`, …) refer to it.

pub mod canon;
pub mod canonical;
pub mod heuristic;
pub mod machine;
pub mod normalize;
pub mod policy;
pub mod program;
pub mod puzzle;
pub mod reference;
pub mod repair;
pub mod search;
pub mod stack;
pub mod stats;
pub mod types;
