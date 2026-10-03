//! REFERENCE_RUN (SPEC §8): a deliberately plain, unoptimized mirror of
//! `lib/engine/interpreter.dart`. It knows nothing about synthesis and shares
//! no execution code with `normalize`, so the two can check each other.

use crate::program::ResolvedProgram;
use crate::puzzle::StaticPuzzle;
use crate::types::{Action, Color, Direction, MAX_FUNCTIONS, MAX_STEPS};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunStatus {
    Success,
    Crashed,
    OutOfInstructions,
    Stuck,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunResult {
    pub status: RunStatus,
    pub steps: u32,
    pub row: usize,
    pub col: usize,
    pub direction: Direction,
    /// Per tile (row-major); `None` for gaps.
    pub colors: Vec<Option<Color>>,
    pub stars: Vec<bool>,
    pub max_stack_depth: usize,
}

pub fn reference_run(puzzle: &StaticPuzzle, program: &ResolvedProgram) -> RunResult {
    reference_run_from(puzzle, program, 0)
}

/// Runs with the step counter preset to `steps0` (test vectors TV-09).
pub fn reference_run_from(
    puzzle: &StaticPuzzle,
    program: &ResolvedProgram,
    steps0: u32,
) -> RunResult {
    let caps: [usize; MAX_FUNCTIONS] = std::array::from_fn(|f| program.functions[f].len());
    let (rows, cols) = (puzzle.rows, puzzle.cols);
    let mut colors: Vec<Option<Color>> = (0..rows * cols)
        .map(|t| puzzle.is_tile[t].then(|| puzzle.initial_colors.get(t as u8)))
        .collect();
    let mut stars: Vec<bool> = (0..rows * cols)
        .map(|t| puzzle.initial_stars.contains(t as u8))
        .collect();
    let mut stars_left = stars.iter().filter(|&&s| s).count();
    let (mut row, mut col) = puzzle.row_col(puzzle.start_tile);
    let mut direction = puzzle.start_direction;
    let mut steps = steps0;
    // (function, next slot index)
    let mut stack: Vec<(usize, usize)> = if caps[0] > 0 { vec![(0, 0)] } else { vec![] };
    let mut max_stack_depth = stack.len();

    macro_rules! finish {
        ($status:expr) => {
            return RunResult {
                status: $status,
                steps,
                row,
                col,
                direction,
                colors,
                stars,
                max_stack_depth,
            }
        };
    }

    if stars_left == 0 {
        finish!(RunStatus::Success); // (111)
    }
    loop {
        let Some(&(f, i)) = stack.last() else {
            // (185)
            finish!(if stars_left == 0 {
                RunStatus::Success
            } else {
                RunStatus::OutOfInstructions
            });
        };
        if i >= caps[f] {
            stack.pop(); // (193) R-POP: free
            continue;
        }
        let slot = program.functions[f][i];
        stack.last_mut().unwrap().1 += 1;
        let Some(instr) = slot else {
            continue; // (202) R-NULL: free
        };
        steps += 1; // (206) R-STEP
        if steps > MAX_STEPS {
            finish!(RunStatus::Stuck); // (207)
        }
        let here = colors[row * cols + col].expect("robot stands on a tile");
        if !instr.condition.matches(here) {
            continue; // (221) R-COND
        }
        match instr.action {
            Action::Call(g) => {
                let g = g as usize;
                if caps[g] == 0 {
                    continue; // (232) R-CALL0
                }
                let next = stack.last().unwrap().1;
                if program.functions[f][next..].iter().all(|s| s.is_none()) {
                    stack.pop(); // (240) R-TAIL
                }
                stack.push((g, 0));
                max_stack_depth = max_stack_depth.max(stack.len());
            }
            Action::TurnLeft => direction = direction.left(),
            Action::TurnRight => direction = direction.right(),
            Action::Paint(c) => colors[row * cols + col] = Some(c),
            Action::Forward => {
                // (271)
                let (dr, dc) = direction.delta();
                let (nr, nc) = (row as i64 + dr as i64, col as i64 + dc as i64);
                if nr < 0 || nc < 0 || nr as usize >= rows || nc as usize >= cols {
                    finish!(RunStatus::Crashed);
                }
                let (nr, nc) = (nr as usize, nc as usize);
                if colors[nr * cols + nc].is_none() {
                    finish!(RunStatus::Crashed); // (279)
                }
                row = nr;
                col = nc;
                if stars[nr * cols + nc] {
                    stars[nr * cols + nc] = false;
                    stars_left -= 1;
                }
                if stars_left == 0 {
                    finish!(RunStatus::Success); // (288)
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::program_from;
    use crate::puzzle::tests::puzzle;

    fn caps(c: &[u8]) -> [u8; 5] {
        let mut out = [0; 5];
        out[..c.len()].copy_from_slice(c);
        out
    }

    struct Tv {
        id: &'static str,
        rows: &'static [&'static str],
        dir: &'static str,
        caps: &'static [u8],
        paints: i64,
        program: &'static [&'static [Option<&'static str>]],
        steps0: u32,
        status: RunStatus,
        steps: u32,
        pos: (usize, usize),
    }

    const S: RunStatus = RunStatus::Success;

    /// SPEC §24.1 and §24.2.
    const VECTORS: &[Tv] = &[
        Tv {
            id: "TV-01",
            rows: &["bbbB"],
            dir: "right",
            caps: &[2],
            paints: 0,
            program: &[&[Some("forward"), Some("callF1")]],
            steps0: 0,
            status: S,
            steps: 5,
            pos: (0, 3),
        },
        Tv {
            id: "TV-02",
            rows: &["bB"],
            dir: "right",
            caps: &[2],
            paints: 0,
            program: &[&[Some("turnLeft"), Some("forward")]],
            steps0: 0,
            status: RunStatus::Crashed,
            steps: 2,
            pos: (0, 0),
        },
        Tv {
            id: "TV-03",
            rows: &["bB"],
            dir: "right",
            caps: &[2],
            paints: 0,
            program: &[&[Some("red:forward"), Some("forward")]],
            steps0: 0,
            status: S,
            steps: 2,
            pos: (0, 1),
        },
        Tv {
            id: "TV-04",
            rows: &["bB"],
            dir: "right",
            caps: &[2],
            paints: 1,
            program: &[&[Some("paintRed"), Some("red:forward")]],
            steps0: 0,
            status: S,
            steps: 2,
            pos: (0, 1),
        },
        Tv {
            id: "TV-05",
            rows: &["bB"],
            dir: "up",
            caps: &[2, 1],
            paints: 0,
            program: &[&[Some("callF2"), Some("forward")], &[Some("turnRight")]],
            steps0: 0,
            status: S,
            steps: 3,
            pos: (0, 1),
        },
        Tv {
            id: "TV-06",
            rows: &["bB"],
            dir: "right",
            caps: &[2, 0],
            paints: 0,
            program: &[&[Some("callF2"), Some("forward")]],
            steps0: 0,
            status: S,
            steps: 2,
            pos: (0, 1),
        },
        Tv {
            id: "TV-07",
            rows: &["bB"],
            dir: "right",
            caps: &[1],
            paints: 0,
            program: &[&[Some("callF1")]],
            steps0: 0,
            status: RunStatus::Stuck,
            steps: 20001,
            pos: (0, 0),
        },
        Tv {
            id: "TV-08",
            rows: &["bbB"],
            dir: "right",
            caps: &[2],
            paints: 0,
            program: &[&[Some("callF1"), Some("forward")]],
            steps0: 0,
            status: RunStatus::Stuck,
            steps: 20001,
            pos: (0, 0),
        },
        Tv {
            id: "TV-09a",
            rows: &["bB"],
            dir: "right",
            caps: &[1],
            paints: 0,
            program: &[&[Some("forward")]],
            steps0: 19999,
            status: S,
            steps: 20000,
            pos: (0, 1),
        },
        Tv {
            id: "TV-09b",
            rows: &["bB"],
            dir: "right",
            caps: &[1],
            paints: 0,
            program: &[&[Some("forward")]],
            steps0: 20000,
            status: RunStatus::Stuck,
            steps: 20001,
            pos: (0, 0),
        },
        Tv {
            id: "TV-09c",
            rows: &["bB"],
            dir: "right",
            caps: &[2],
            paints: 0,
            program: &[&[Some("red:forward"), Some("forward")]],
            steps0: 19999,
            status: RunStatus::Stuck,
            steps: 20001,
            pos: (0, 0),
        },
        Tv {
            id: "TV-10",
            rows: &["bB"],
            dir: "right",
            caps: &[1, 2, 3],
            paints: 1,
            program: &[
                &[Some("callF2")],
                &[Some("blue:callF3"), None],
                &[Some("paintRed"), Some("callF2"), Some("forward")],
            ],
            steps0: 0,
            status: S,
            steps: 6,
            pos: (0, 1),
        },
        Tv {
            id: "TV-11",
            rows: &["bbB"],
            dir: "right",
            caps: &[3],
            paints: 0,
            program: &[&[Some("forward"), None, Some("callF1")]],
            steps0: 0,
            status: S,
            steps: 3,
            pos: (0, 2),
        },
        Tv {
            id: "TV-12",
            rows: &["bbB"],
            dir: "right",
            caps: &[3],
            paints: 0,
            program: &[&[Some("forward"), Some("callF1"), None]],
            steps0: 0,
            status: S,
            steps: 3,
            pos: (0, 2),
        },
    ];

    #[test]
    fn t_ref_vectors() {
        for tv in VECTORS {
            let p = puzzle(
                tv.rows,
                (0, 0),
                tv.dir,
                &tv.caps.iter().map(|&c| c as i64).collect::<Vec<_>>(),
                tv.paints,
            );
            let prog = program_from(tv.program, caps(tv.caps));
            let r = reference_run_from(&p, &prog, tv.steps0);
            assert_eq!(
                (r.status, r.steps, (r.row, r.col)),
                (tv.status, tv.steps, tv.pos),
                "{}",
                tv.id
            );
            if tv.status == RunStatus::Stuck || tv.status == RunStatus::Crashed {
                assert!(
                    r.stars.iter().any(|&s| s),
                    "{}: the star must still be there",
                    tv.id
                );
            }
        }
    }

    #[test]
    fn t_ref_depths() {
        let p = puzzle(&["bB"], (0, 0), "up", &[2, 1], 0);
        let r = reference_run(
            &p,
            &program_from(
                &[&[Some("callF2"), Some("forward")], &[Some("turnRight")]],
                caps(&[2, 1]),
            ),
        );
        assert_eq!(r.max_stack_depth, 2); // TV-05
        let p = puzzle(&["bbB"], (0, 0), "right", &[2], 0);
        let r = reference_run(
            &p,
            &program_from(&[&[Some("callF1"), Some("forward")]], caps(&[2])),
        );
        assert_eq!(r.max_stack_depth, 20001); // TV-08
    }
}
