//! CLI (SPEC Appendix A) writing `solutions.json` (SPEC §26).

use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use clap::Parser;
use serde_json::{Value, json};

use solver::puzzle::{RawPuzzle, StaticPuzzle, load_catalog};
use solver::search::{FoundBy, Outcome, UnsolvableReason, solve};
use solver::stats::{Config, Limits};
use solver::types::MAX_STEPS;

#[derive(Parser)]
#[command(about = "Solves RoboZZle puzzles, minimal-slot when provable (see SPEC.md)")]
struct Args {
    /// Catalog JSON file (an array of puzzles).
    catalog: PathBuf,
    /// Solve only these sourceIds (repeatable).
    #[arg(long = "id")]
    ids: Vec<String>,
    /// Solve every puzzle in the catalog.
    #[arg(long)]
    all: bool,
    /// Per-puzzle search-node limit. Results depend only on this, not on
    /// the machine's speed (deterministic).
    #[arg(long, default_value_t = 20_000_000)]
    node_limit: u64,
    /// Optional per-puzzle wall-clock safety limit in milliseconds. When it
    /// triggers, the result depends on machine speed.
    #[arg(long)]
    timeout_ms: Option<u64>,
    /// Exact (optimal) search only; no heuristic phase.
    #[arg(long)]
    exact_only: bool,
    /// Output file (default: print to stdout).
    #[arg(long)]
    out: Option<PathBuf>,
    /// Puzzles solved in parallel (default: available CPUs).
    #[arg(long)]
    jobs: Option<usize>,
    #[arg(long)]
    no_lazy_conditions: bool,
    #[arg(long)]
    no_lazy_active_conditions: bool,
    #[arg(long)]
    no_function_symmetry: bool,
    #[arg(long)]
    no_peephole: bool,
    #[arg(long)]
    no_cycle_detection: bool,
    #[arg(long)]
    no_step_cut: bool,
    /// Heuristic phase without the history heuristic.
    #[arg(long)]
    no_history: bool,
    /// Auxiliary functions keep their identities (P-SYM only).
    #[arg(long)]
    no_anonymous_functions: bool,
}

fn id_string(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

fn solve_one(raw: &RawPuzzle, config: Config, limits: Limits) -> (Value, String) {
    let id = raw.source_id.clone();
    let puzzle = match StaticPuzzle::compile(raw) {
        Ok(p) => p,
        Err(reason) => {
            let line = format!("{:>6}  unsupported  {reason}", id_string(&id));
            return (
                json!({ "sourceId": id, "status": "unsupported", "reason": reason }),
                line,
            );
        }
    };
    let result = solve(&puzzle, config, limits);
    let stats = serde_json::to_value(&result.stats).unwrap();
    let ms = result.stats.millis;
    match result.outcome {
        Outcome::Solved(s) => {
            let found_by = match s.found_by {
                FoundBy::Exact => "exact",
                FoundBy::Heuristic => "heuristic",
            };
            let line = format!(
                "{:>6}  solved       cost {:>2}{}  steps {:>5}  {:>7} ms  {found_by}",
                id_string(&id),
                s.cost,
                if s.optimal { "*" } else { " " },
                s.steps,
                ms
            );
            (
                json!({ "sourceId": id, "status": "solved", "cost": s.cost, "optimal": s.optimal,
                        "lowerBound": result.lower_bound, "foundBy": found_by, "steps": s.steps,
                        "program": s.program.to_tokens(), "stats": stats }),
                line,
            )
        }
        Outcome::Unsolvable(reason) => {
            let reason = match reason {
                UnsolvableReason::Disconnected => "disconnected",
                UnsolvableReason::Exhausted => "exhausted",
            };
            let line = format!("{:>6}  unsolvable   {reason}  {ms:>7} ms", id_string(&id));
            (
                json!({ "sourceId": id, "status": "unsolvable", "reason": reason, "stats": stats }),
                line,
            )
        }
        Outcome::Timeout => {
            let line = format!(
                "{:>6}  timeout      cost >= {:>2}               {ms:>7} ms",
                id_string(&id),
                result.lower_bound
            );
            (
                json!({ "sourceId": id, "status": "timeout", "lowerBound": result.lower_bound,
                        "stats": stats }),
                line,
            )
        }
    }
}

fn main() {
    let args = Args::parse();
    let catalog = load_catalog(&args.catalog).unwrap_or_else(|e| {
        eprintln!("error: {e}");
        std::process::exit(2);
    });
    let selected: Vec<RawPuzzle> = if args.all {
        catalog
    } else if !args.ids.is_empty() {
        let found: Vec<RawPuzzle> = catalog
            .into_iter()
            .filter(|r| args.ids.contains(&id_string(&r.source_id)))
            .collect();
        if found.len() != args.ids.len() {
            eprintln!(
                "warning: {} of {} ids were not found",
                args.ids.len() - found.len(),
                args.ids.len()
            );
        }
        found
    } else {
        eprintln!("error: pass --all or at least one --id");
        std::process::exit(2);
    };

    let config = Config {
        lazy_conditions: !args.no_lazy_conditions,
        lazy_active_conditions: !args.no_lazy_active_conditions,
        function_symmetry: !args.no_function_symmetry,
        peephole: !args.no_peephole,
        cycle_detection: !args.no_cycle_detection,
        step_cut: !args.no_step_cut,
        heuristic: !args.exact_only,
        history: !args.no_history,
        anonymous_functions: !args.no_anonymous_functions,
    };
    let limits = Limits {
        time: args.timeout_ms.map(Duration::from_millis),
        nodes: Some(args.node_limit),
    };
    let jobs = args
        .jobs
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()))
        .max(1);

    // Work-stealing over an index; results keep catalog order (determinism).
    let next = AtomicUsize::new(0);
    let results: Mutex<Vec<Option<Value>>> = Mutex::new(vec![None; selected.len()]);
    let done = AtomicUsize::new(0);
    std::thread::scope(|scope| {
        for _ in 0..jobs.min(selected.len().max(1)) {
            scope.spawn(|| {
                loop {
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    if i >= selected.len() {
                        break;
                    }
                    let (value, line) = solve_one(&selected[i], config, limits);
                    let n = done.fetch_add(1, Ordering::Relaxed) + 1;
                    eprintln!("[{n:>4}/{}] {line}", selected.len());
                    results.lock().unwrap()[i] = Some(value);
                }
            });
        }
    });
    let results: Vec<Value> = results
        .into_inner()
        .unwrap()
        .into_iter()
        .map(Option::unwrap)
        .collect();

    print_summary(&selected, &results);

    let output = json!({
        "solver": concat!("robozzle-solver ", env!("CARGO_PKG_VERSION")),
        "maxSteps": MAX_STEPS,
        "config": config,
        "results": results,
    });
    let text = serde_json::to_string_pretty(&output).unwrap() + "\n";
    match &args.out {
        Some(path) => std::fs::write(path, text).unwrap_or_else(|e| {
            eprintln!("error: {}: {e}", path.display());
            std::process::exit(2);
        }),
        None => print!("{text}"),
    }
}

/// Summary by rounded difficulty (stderr).
fn print_summary(puzzles: &[RawPuzzle], results: &[Value]) {
    let mut rows: std::collections::BTreeMap<i64, (usize, usize, u64, u64, u64)> =
        Default::default();
    for (raw, r) in puzzles.iter().zip(results) {
        let stars = raw
            .difficulty
            .map_or(0, |d| d.round().clamp(1.0, 5.0) as i64);
        let e = rows.entry(stars).or_default();
        e.0 += 1;
        if r["status"] == "solved" {
            e.1 += 1;
        }
        e.2 += r["stats"]["millis"].as_u64().unwrap_or(0);
        e.3 += r["stats"]["searchNodes"].as_u64().unwrap_or(0);
        e.4 += r["stats"]["instructionsEvaluated"].as_u64().unwrap_or(0);
    }
    eprintln!("\ndifficulty  solved/total   avg ms   search nodes   instructions");
    let mut total = (0, 0, 0u64, 0u64, 0u64);
    for (stars, (n, solved, ms, nodes, instr)) in &rows {
        let label = if *stars == 0 {
            "?".to_string()
        } else {
            "★".repeat(*stars as usize)
        };
        eprintln!(
            "{label:<11} {solved:>5}/{n:<6} {:>8} {nodes:>14} {instr:>14}",
            ms / *n as u64
        );
        total = (
            total.0 + n,
            total.1 + solved,
            total.2 + ms,
            total.3 + nodes,
            total.4 + instr,
        );
    }
    if total.0 > 0 {
        eprintln!(
            "{:<11} {:>5}/{:<6} {:>8} {:>14} {:>14}",
            "all",
            total.1,
            total.0,
            total.2 / total.0 as u64,
            total.3,
            total.4
        );
    }
}
