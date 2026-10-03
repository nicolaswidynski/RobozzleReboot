//! RoboZZle solver. The normative specification is `SPEC.md`; rule IDs in
//! comments (`R-*`, `N-*`, `P-*`, …) refer to it.

pub mod canonical;
pub mod heuristic;
pub mod machine;
pub mod normalize;
pub mod program;
pub mod puzzle;
pub mod reference;
pub mod search;
pub mod stack;
pub mod stats;
pub mod types;
