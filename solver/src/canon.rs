//! Canonical form of a known solution, and the consistency test used to
//! replay it through the search tree (`Solver::replay_dump`, the training
//! data of the learned ordering; not used by the search itself).
//!
//! Facts are expressed in the solver's internal labels. With anonymous
//! auxiliary functions (D-NEWFN), the search numbers aux functions 1..n in
//! the order their first call is decided, which in lazy synthesis is the
//! order in which execution first runs a call to each of them. The known
//! program is therefore first canonicalized: holes are removed, the suffix
//! of each function that execution never reaches is dropped (it can never
//! be decided), and the aux functions are renumbered by first executed call.

use serde::{Deserialize, Serialize};

use crate::normalize::NormalizeResult;
use crate::program::{Cell, ResolvedProgram};
use crate::puzzle::StaticPuzzle;
use crate::reference::{RunStatus, reference_run};
use crate::search::SearchState;
use crate::types::{Action, Condition, Instruction, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS, MAX_STEPS};

/// Structure of a canonical known solution, in internal labels.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Facts {
    /// Occupied slots of the canonical program (the exact budget to search).
    pub cost: u8,
    /// Functions used (F1 plus the aux functions it reaches).
    pub functions: u8,
    /// Body length per internal function (0 for unused labels).
    pub lengths: [u8; MAX_FUNCTIONS],
    /// Per internal function, the bit set of internal functions it calls.
    pub edges: [u8; MAX_FUNCTIONS],
    /// Per internal function and slot: the called internal function, or
    /// -1 for a non-call instruction (slots beyond the length: -1).
    pub sites: [[i8; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
    /// The canonical program in internal labels (tokens), for reference.
    pub program: Vec<Vec<Option<String>>>,
    /// An aux function with exactly one cell (P-SINGLE never generates it).
    pub single_cell_aux: bool,
}

/// What one run of a resolved program reveals about its structure.
struct Trace {
    /// Highest slot index fetched per function (-1: never entered).
    reached: [i32; MAX_FUNCTIONS],
    /// Functions in the order their first call executed.
    call_order: Vec<usize>,
}

/// REFERENCE_RUN semantics (SPEC §8) with a trace; `None` if the program
/// does not solve the puzzle.
fn traced_run(puzzle: &StaticPuzzle, program: &ResolvedProgram) -> Option<Trace> {
    let caps: [usize; MAX_FUNCTIONS] = std::array::from_fn(|f| program.functions[f].len());
    let mut colors = puzzle.initial_colors;
    let mut stars = puzzle.initial_stars;
    let mut position = puzzle.start_tile;
    let mut direction = puzzle.start_direction;
    let mut steps = 0u32;
    let mut stack: Vec<(usize, usize)> = if caps[0] > 0 { vec![(0, 0)] } else { vec![] };
    let mut trace = Trace {
        reached: [-1; MAX_FUNCTIONS],
        call_order: Vec::new(),
    };
    if stars.is_empty() {
        return Some(trace);
    }
    loop {
        let &(f, i) = stack.last()?;
        if i >= caps[f] {
            stack.pop();
            continue;
        }
        trace.reached[f] = trace.reached[f].max(i as i32);
        stack.last_mut().unwrap().1 += 1;
        let Some(instr) = program.functions[f][i] else {
            continue;
        };
        steps += 1;
        if steps > MAX_STEPS {
            return None;
        }
        if !instr.condition.matches(colors.get(position)) {
            continue;
        }
        match instr.action {
            Action::Call(g) => {
                let g = g as usize;
                if caps[g] == 0 {
                    continue;
                }
                if !trace.call_order.contains(&g) && g != 0 {
                    trace.call_order.push(g);
                }
                let next = stack.last().unwrap().1;
                if program.functions[f][next..].iter().all(|s| s.is_none()) {
                    stack.pop();
                }
                stack.push((g, 0));
            }
            Action::TurnLeft => direction = direction.left(),
            Action::TurnRight => direction = direction.right(),
            Action::Paint(c) => colors.set(position, c),
            Action::Forward => {
                position = puzzle.forward_target(position, direction)?;
                stars.remove(position);
                if stars.is_empty() {
                    return Some(trace);
                }
            }
        }
    }
}

/// Rewrites every maximal run of turn cells into the canonical block the
/// search generates (P-TURN, P-TURNORDER, P-TURNMIN, SPEC §15.2, §15.2a):
/// `Any` turns rotating by the best base `b`, then for each possible color
/// in the order red < green < blue the turns rotating that color by the
/// rest, each written `L`, `L L` or `R`. Holes are removed first (R-NULL
/// costs nothing; tail calls keep their status). A run is evaluated on one
/// tile, so its effect is a rotation per possible color, which the block
/// reproduces with no more cells or steps; turns conditioned on colors the
/// puzzle cannot show are dropped (they never fire).
pub fn canonical_turns(puzzle: &StaticPuzzle, program: &ResolvedProgram) -> ResolvedProgram {
    const Q: [u8; 4] = [0, 1, 2, 1];
    let quarter = |q: u8, condition: Condition, out: &mut Vec<Option<Instruction>>| {
        let mut push = |action| out.push(Some(Instruction { condition, action }));
        match q % 4 {
            1 => push(Action::TurnLeft),
            2 => {
                push(Action::TurnLeft);
                push(Action::TurnLeft);
            }
            3 => push(Action::TurnRight),
            _ => {}
        }
    };
    let pc = puzzle.possible_colors;
    let functions = std::array::from_fn(|f| {
        let cells: Vec<Instruction> = program.functions[f].iter().flatten().copied().collect();
        let mut out: Vec<Option<Instruction>> = Vec::with_capacity(cells.len());
        let mut i = 0;
        while i < cells.len() {
            let is_turn =
                |c: &Instruction| matches!(c.action, Action::TurnLeft | Action::TurnRight);
            if !is_turn(&cells[i]) {
                out.push(Some(cells[i]));
                i += 1;
                continue;
            }
            let mut j = i;
            let mut rot = [0u8; 3];
            while j < cells.len() && is_turn(&cells[j]) {
                let q = if cells[j].action == Action::TurnLeft {
                    1
                } else {
                    3
                };
                for x in pc.iter() {
                    if cells[j].condition.matches(x) {
                        rot[x as usize] = (rot[x as usize] + q) % 4;
                    }
                }
                j += 1;
            }
            let cost = |b: u8| {
                Q[b as usize]
                    + pc.iter()
                        .map(|x| Q[((rot[x as usize] + 4 - b) % 4) as usize])
                        .sum::<u8>()
            };
            let base = (0..4u8).min_by_key(|&b| (cost(b), b)).expect("four bases");
            quarter(base, Condition::Any, &mut out);
            for x in pc.iter() {
                quarter(
                    (rot[x as usize] + 4 - base) % 4,
                    Condition::Color(x),
                    &mut out,
                );
            }
            i = j;
        }
        out.resize(program.functions[f].len(), None);
        out
    });
    ResolvedProgram { functions }
}

/// Canonicalizes a valid program and extracts its facts (see the module
/// documentation). Errors if the program does not solve the puzzle, before
/// or after canonicalization.
pub fn facts_of(puzzle: &StaticPuzzle, program: &ResolvedProgram) -> Result<Facts, String> {
    // Remove holes (R-NULL costs nothing; the last occupied slot is kept).
    let packed: [Vec<Instruction>; MAX_FUNCTIONS] =
        std::array::from_fn(|f| program.functions[f].iter().flatten().copied().collect());
    let as_resolved = |bodies: &[Vec<Instruction>; MAX_FUNCTIONS]| ResolvedProgram {
        functions: std::array::from_fn(|f| {
            let mut v: Vec<Option<Instruction>> = bodies[f].iter().copied().map(Some).collect();
            v.resize(puzzle.capacities[f] as usize, None);
            v
        }),
    };
    let trace = traced_run(puzzle, &as_resolved(&packed)).ok_or("does not solve the puzzle")?;
    // Drop the never-reached suffix of every function (and unreached
    // functions entirely).
    let mut bodies = packed.clone();
    for (body, &reached) in bodies.iter_mut().zip(&trace.reached) {
        body.truncate((reached + 1) as usize);
    }
    if reference_run(puzzle, &as_resolved(&bodies)).status != RunStatus::Success {
        return Err("canonical program does not solve the puzzle".into());
    }
    // Internal labels: F1 = 0, then aux functions by first executed call.
    let mut label = [u8::MAX; MAX_FUNCTIONS];
    label[0] = 0;
    for (k, &g) in trace.call_order.iter().enumerate() {
        label[g] = k as u8 + 1;
    }
    let mut facts = Facts {
        cost: 0,
        functions: trace.call_order.len() as u8 + 1,
        lengths: [0; MAX_FUNCTIONS],
        edges: [0; MAX_FUNCTIONS],
        sites: [[-1; MAX_FUNCTION_SLOTS]; MAX_FUNCTIONS],
        program: vec![Vec::new(); MAX_FUNCTIONS],
        single_cell_aux: false,
    };
    let mut internal: [Vec<Instruction>; MAX_FUNCTIONS] = Default::default();
    for f in 0..MAX_FUNCTIONS {
        if label[f] == u8::MAX {
            continue; // never called: never decided
        }
        let l = label[f] as usize;
        for &ins in &bodies[f] {
            let action = match ins.action {
                // A call that never executes may target an unused function;
                // it is still a call cell (its target is irrelevant).
                Action::Call(g) if label[g as usize] != u8::MAX => Action::Call(label[g as usize]),
                other => other,
            };
            internal[l].push(Instruction::new(ins.condition, action));
        }
    }
    for (l, body) in internal.iter().enumerate() {
        facts.lengths[l] = body.len() as u8;
        facts.cost += body.len() as u8;
        if l > 0 && body.len() == 1 {
            facts.single_cell_aux = true;
        }
        for (i, ins) in body.iter().enumerate() {
            if let Action::Call(g) = ins.action {
                facts.edges[l] |= 1 << g;
                facts.sites[l][i] = g as i8;
            }
        }
        facts.program[l] = body
            .iter()
            .map(|&i| Some(crate::program::instruction_token(i)))
            .collect();
    }
    Ok(facts)
}

/// Whether `kid`, a child at frontier `r`, made the decision the known
/// program (internal labels, left-packed bodies) makes at that slot.
pub fn consistent(kid: &SearchState, r: NormalizeResult, known: &[Vec<Instruction>]) -> bool {
    let (f, index) = match r {
        NormalizeResult::OpenSlot { function, index } => (function, index),
        NormalizeResult::NeedAction {
            function, index, ..
        } => (function, index),
        NormalizeResult::NeedCondition { function, index } => (function, index),
        _ => return false,
    };
    let body = &known[f as usize];
    let d = kid.program.function(f);
    if matches!(r, NormalizeResult::OpenSlot { .. }) && d.len == index {
        return body.len() == index as usize;
    }
    let Some(want) = body.get(index as usize) else {
        return false;
    };
    match d.cell(index) {
        Cell::Resolved(i) => i == *want,
        Cell::Pending { action, color } => {
            action == want.action
                && (want.condition == Condition::Any || want.condition == Condition::Color(color))
        }
        Cell::CondOnly(c) => want.condition == Condition::Color(c),
        Cell::CondSet(m) => matches!(want.condition, Condition::Color(c) if m.contains(c)),
        Cell::Unused => false,
    }
}

/// The canonical known program (internal labels) as instruction bodies.
pub fn internal_bodies(facts: &Facts) -> Vec<Vec<Instruction>> {
    facts
        .program
        .iter()
        .map(|b| {
            b.iter()
                .map(|t| crate::program::parse_instruction(t.as_ref().unwrap()).unwrap())
                .collect()
        })
        .collect()
}
