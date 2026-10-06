//! Training data for the learned LDS ordering (policy/README.md).
//!
//! Usage: policy_dump <catalog.json> <programs.json> <out.jsonl>
//!
//! programs.json: {"<sourceId>": [program tokens, ...]} (the solver's output
//! format). Each program must solve its puzzle (REFERENCE_RUN); its turn
//! runs are rewritten into canonical form (`canon::canonical_turns`), it is
//! shrunk (cells deleted while it still solves), canonicalized
//! (`canon::facts_of`) and replayed through the LDS tree of the default
//! configuration (`Solver::replay_dump`). One JSON line per distinct
//! canonical program: {"id", "prog", "cost", "nfun", "stars", "decisions"},
//! or {"id", "prog", "error"} when the replay leaves the tree (a program
//! that a sound pruning rule never generates).
use std::collections::BTreeMap;
use std::io::Write;

use serde_json::json;
use solver::canon::{canonical_turns, facts_of, internal_bodies};
use solver::heuristic::shrink;
use solver::program::ResolvedProgram;
use solver::puzzle::{StaticPuzzle, load_catalog};
use solver::reference::{RunStatus, reference_run};
use solver::search::Solver;
use solver::stats::{Config, Limits};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: policy_dump <catalog.json> <programs.json> <out.jsonl>");
        std::process::exit(2);
    }
    let raws = load_catalog(std::path::Path::new(&args[1])).unwrap();
    let programs: BTreeMap<String, Vec<Vec<Vec<Option<String>>>>> =
        serde_json::from_str(&std::fs::read_to_string(&args[2]).unwrap()).unwrap();
    let mut out = std::io::BufWriter::new(std::fs::File::create(&args[3]).unwrap());
    let (mut ok, mut bad, mut invalid) = (0, 0, 0);
    for raw in &raws {
        let id = raw.source_id.to_string().trim_matches('"').to_string();
        let Some(progs) = programs.get(&id) else {
            continue;
        };
        let Ok(p) = StaticPuzzle::compile(raw) else {
            continue;
        };
        let mut bodies = Vec::new();
        let mut meta = Vec::new();
        for tokens in progs {
            let Ok(prog) = ResolvedProgram::from_tokens(tokens) else {
                invalid += 1;
                continue;
            };
            if reference_run(&p, &prog).status != RunStatus::Success {
                invalid += 1;
                continue;
            }
            // The search only generates canonical turn runs (P-TURNORDER,
            // P-TURNMIN), so known programs are rewritten into that form.
            let prog = canonical_turns(&p, &prog);
            if reference_run(&p, &prog).status != RunStatus::Success {
                invalid += 1;
                continue;
            }
            // Shrinking can join two turn runs: canonicalize again.
            let (prog, _) = shrink(&p, prog);
            let prog = canonical_turns(&p, &prog);
            if let Ok(f) = facts_of(&p, &prog) {
                let b = internal_bodies(&f);
                if !bodies.contains(&b) {
                    bodies.push(b);
                    meta.push((f.cost, f.functions));
                }
            }
        }
        for (k, b) in bodies.iter().enumerate() {
            let mut solver = Solver::new(&p, Config::default(), Limits::default());
            let line = match solver.replay_dump(b) {
                Ok(decisions) => {
                    ok += 1;
                    json!({"id": id, "prog": k, "cost": meta[k].0, "nfun": meta[k].1,
                           "stars": p.initial_stars.len(), "decisions": decisions})
                }
                Err(e) => {
                    bad += 1;
                    json!({"id": id, "prog": k, "error": e})
                }
            };
            writeln!(out, "{line}").unwrap();
        }
    }
    eprintln!("dumped {ok} programs, {bad} replay errors, {invalid} invalid programs skipped");
}
