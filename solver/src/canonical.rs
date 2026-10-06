//! Local canonicalization rules P-PAINT and P-TURN (SPEC §15.1, §15.2),
//! P-TURNORDER, P-TURNMIN and P-PAINTKNOWN (§15.2a, §15.1a). P-EMPTYFN
//! and P-STEPCUT are applied during generation in `search.rs`.
//!
//! **Canonical key.** Some rewrites below keep the cost and the steps (P-TURN
//! `R R` -> `L L`, P-TURNORDER, P-PAINTKNOWN `Color(d): a` -> `Any: a`).
//! They are sound together because each one strictly lowers one key: the
//! cells in (function, index) order, each compared by (condition: Any <
//! red < green < blue, then action: turnLeft < turnRight). None of them
//! touches a call cell or changes the order of executed calls, so the P-SYM
//! naming is unchanged. Among the minimal-cost solutions take those with
//! the fewest steps, and among them the one with the smallest key: every
//! rewrite that lowers cost or steps contradicts the choice, and every
//! other one lowers the key, so that solution passes all rules at once.
//! The search applies the rules only to `Resolved` cells, which never
//! change afterwards, so every window it rejects is in every completion
//! (with `Pending` cells, physically `Any`, the rules simply check less).

use crate::program::Cell;
use crate::types::{Action, Color, ColorMask, Condition, Instruction};

/// P-PAINT: `Color(c): Paint(c)` never changes state.
#[inline]
pub fn is_useless_paint(i: Instruction) -> bool {
    matches!((i.condition, i.action), (Condition::Color(c), Action::Paint(p)) if c == p)
}

/// `Some((condition, is_right))` for a resolved turn.
#[inline]
fn turn(cell: Cell) -> Option<(Condition, bool)> {
    match cell {
        Cell::Resolved(Instruction {
            condition,
            action: Action::TurnLeft,
        }) => Some((condition, false)),
        Cell::Resolved(Instruction {
            condition,
            action: Action::TurnRight,
        }) => Some((condition, true)),
        _ => None,
    }
}

/// P-TURN: checks every window of same-condition adjacent turns that
/// contains `index`. Forbidden: `L R`, `R L`, `R R`, `L L L` (and `R R R`).
pub fn turns_canonical(cells: &[Cell], index: usize) -> bool {
    let at = |j: isize| -> Option<(Condition, bool)> {
        if j < 0 || j as usize >= cells.len() {
            None
        } else {
            turn(cells[j as usize])
        }
    };
    let i = index as isize;
    // Pairs containing `index`.
    for j in [i - 1, i] {
        if let (Some((c1, r1)), Some((c2, r2))) = (at(j), at(j + 1))
            && c1 == c2
            && (r1 != r2 || (r1 && r2))
        {
            return false;
        }
    }
    // Triples containing `index`.
    for j in [i - 2, i - 1, i] {
        if let (Some(a), Some(b), Some(c)) = (at(j), at(j + 1), at(j + 2))
            && a == b
            && b == c
        {
            return false;
        }
    }
    true
}

/// Condition order of P-TURNORDER: Any < red < green < blue.
#[inline]
fn condition_key(c: Condition) -> u8 {
    match c {
        Condition::Any => 0,
        Condition::Color(x) => 1 + x as u8,
    }
}

/// P-TURNORDER: adjacent `Resolved` turns with different conditions must
/// appear in `condition_key` order. Checks the pairs containing `index`.
///
/// *Proof.* A body is entered only at index 0 and its cells run in order,
/// so cell `i + 1` is evaluated right after cell `i`; a turn neither moves
/// the robot nor paints. So two adjacent turns are evaluated on the same
/// tile color, each fires exactly when its condition matches it, and
/// rotations commute: swapping them keeps behavior, cost and steps and
/// lowers the canonical key (module comment).
pub fn turns_ordered(cells: &[Cell], index: usize) -> bool {
    for j in [index.wrapping_sub(1), index] {
        if j >= cells.len() || j + 1 >= cells.len() {
            continue;
        }
        if let (Some((c1, _)), Some((c2, _))) = (turn(cells[j]), turn(cells[j + 1]))
            && c1 != c2
            && condition_key(c1) > condition_key(c2)
        {
            return false;
        }
    }
    true
}

/// P-TURNMIN: the maximal run of `Resolved` turns containing `index` must
/// not be longer than the shortest block with the same rotation on every
/// possible color.
///
/// *Proof.* As for P-TURNORDER, a run of turns is evaluated on one tile
/// color, so its effect is a rotation `rot(x)` (quarter turns mod 4) per
/// possible color `x`, at one cell and one step per turn. `Any` turns
/// rotating by `b` followed by `Color(x)` turns rotating by `rot(x) - b`
/// have the same effect with `q(b) + Σ_x q(rot(x) - b)` cells, where
/// `q = [0, 1, 2, 1]` (`L`, `L L`, `R`). A longer run can be replaced by
/// this block with fewer cells and steps, so no minimal solution contains
/// it. The run checked here is a contiguous part of a turn run of every
/// completion, and shortening a part shortens the whole.
pub fn turns_minimal(cells: &[Cell], index: usize, possible: ColorMask) -> bool {
    if turn(cells[index]).is_none() {
        return true;
    }
    let (mut a, mut b) = (index, index);
    while a > 0 && turn(cells[a - 1]).is_some() {
        a -= 1;
    }
    while b + 1 < cells.len() && turn(cells[b + 1]).is_some() {
        b += 1;
    }
    let len = b - a + 1;
    if len < 2 {
        return true;
    }
    let mut rot = [0u8; 3];
    for &cell in &cells[a..=b] {
        let (condition, right) = turn(cell).expect("a turn");
        let q = if right { 3 } else { 1 };
        for x in possible.iter() {
            if condition.matches(x) {
                rot[x as usize] = (rot[x as usize] + q) % 4;
            }
        }
    }
    const Q: [usize; 4] = [0, 1, 2, 1];
    let best = (0..4u8)
        .map(|base| {
            Q[base as usize]
                + possible
                    .iter()
                    .map(|x| Q[((rot[x as usize] + 4 - base) % 4) as usize])
                    .sum::<usize>()
        })
        .min()
        .expect("four bases");
    len <= best
}

/// P-PAINTKNOWN: the tile color whenever cell `index` is evaluated, if the
/// cells before it fix it: a `Resolved` `Any: Paint(d)` followed only by
/// turns (`Resolved` or `Pending`). The flag says whether every turn in
/// between is unconditional (`Resolved` `Any` or `Pending`).
///
/// *Why it is known.* A body is entered only at index 0 and no call lies
/// between the paint and `index`, so every evaluation of `index` follows,
/// in the same frame, the paint (which always fires) and turns (which
/// neither move nor paint): the robot stands on a tile of color `d`. A
/// `Pending` turn in between was created after the paint ran, so on color
/// `d`; it can never split and stays `Any` in every completion.
pub fn known_color(cells: &[Cell], index: usize) -> Option<(Color, bool)> {
    let mut all_any = true;
    for &cell in cells[..index].iter().rev() {
        match cell {
            Cell::Resolved(Instruction {
                condition: Condition::Any,
                action: Action::Paint(d),
            }) => return Some((d, all_any)),
            Cell::Resolved(Instruction {
                condition,
                action: Action::TurnLeft | Action::TurnRight,
            }) => all_any &= condition == Condition::Any,
            Cell::Pending {
                action: Action::TurnLeft | Action::TurnRight,
                ..
            } => {}
            _ => return None,
        }
    }
    None
}

/// P-PAINTKNOWN (overwritten paint): a `Resolved` paint immediately
/// followed by a `Resolved` `Any: Paint` (checked on the pairs containing
/// `index`). *Proof:* the second cell runs right after the first and
/// repaints the same tile without reading it, so the first paint is never
/// observed; removing it saves a cell and steps.
pub fn paint_overwritten(cells: &[Cell], index: usize) -> bool {
    let paint = |j: usize| {
        matches!(
            cells.get(j),
            Some(Cell::Resolved(Instruction {
                action: Action::Paint(_),
                ..
            }))
        )
    };
    let any_paint = |j: usize| {
        matches!(
            cells.get(j),
            Some(Cell::Resolved(Instruction {
                condition: Condition::Any,
                action: Action::Paint(_),
            }))
        )
    };
    (index > 0 && paint(index - 1) && any_paint(index)) || (paint(index) && any_paint(index + 1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Color;

    fn r(c: Condition, a: Action) -> Cell {
        Cell::Resolved(Instruction::new(c, a))
    }
    const ANY: Condition = Condition::Any;
    const RED: Condition = Condition::Color(Color::Red);
    use Action::{Forward as F, TurnLeft as L, TurnRight as R};

    /// TV-16
    #[test]
    fn t_p_turn() {
        // (cells after the decision, index of the decided cell, accepted)
        let cases: &[(&[Cell], usize, bool)] = &[
            (&[r(ANY, L), r(ANY, R)], 1, false),
            (&[r(ANY, L), r(RED, R)], 1, true),
            (&[r(ANY, L), r(ANY, L)], 1, true),
            (&[r(ANY, R), r(ANY, R)], 1, false),
            (&[r(ANY, L), r(ANY, L), r(ANY, L)], 2, false),
            (&[r(RED, L), r(RED, R)], 0, false), // D-RESOLVE, right neighbor
            (&[r(RED, R), r(RED, R)], 0, false),
            (&[r(RED, F), r(RED, R)], 0, true),
            (&[r(ANY, L), Cell::CondOnly(Color::Red), r(ANY, R)], 2, true),
        ];
        for (n, (cells, i, ok)) in cases.iter().enumerate() {
            assert_eq!(turns_canonical(cells, *i), *ok, "case {n}");
        }
    }

    const GREEN: Condition = Condition::Color(Color::Green);
    const RG: ColorMask = ColorMask(0b011);

    #[test]
    fn t_p_turnorder() {
        let cases: &[(&[Cell], usize, bool)] = &[
            (&[r(ANY, L), r(RED, R)], 1, true),
            (&[r(RED, R), r(ANY, L)], 1, false),
            (&[r(RED, R), r(ANY, L)], 0, false), // D-RESOLVE, right neighbor
            (&[r(GREEN, L), r(RED, L)], 1, false),
            (&[r(RED, L), r(GREEN, L)], 1, true),
            (&[r(RED, L), r(RED, L)], 1, true), // same condition: P-TURN
            (&[r(RED, L), r(ANY, F)], 1, true),
            (&[r(RED, L), Cell::CondOnly(Color::Red), r(ANY, R)], 2, true),
        ];
        for (n, (cells, i, ok)) in cases.iter().enumerate() {
            assert_eq!(turns_ordered(cells, *i), *ok, "case {n}");
        }
    }

    #[test]
    fn t_p_turnmin() {
        // Two colors (red, green).
        let cases: &[(&[Cell], usize, bool)] = &[
            (&[r(ANY, L), r(ANY, L)], 1, true),
            // Any L, red R: red 0, green 1 = green L (1 cell).
            (&[r(ANY, L), r(RED, R)], 1, false),
            // red L, green L = Any L.
            (&[r(RED, L), r(GREEN, L)], 1, false),
            // red L, green R: needs 2 cells.
            (&[r(RED, L), r(GREEN, R)], 1, true),
            // Any L L, red R: red 1, green 2 = Any L, green L.
            (&[r(ANY, L), r(ANY, L), r(RED, R)], 2, false),
            // Any L L, red L: red 3, green 2 = Any R, green R.
            (&[r(ANY, L), r(ANY, L), r(RED, L)], 2, false),
            (&[r(ANY, F), r(RED, L)], 1, true),
        ];
        for (n, (cells, i, ok)) in cases.iter().enumerate() {
            assert_eq!(turns_minimal(cells, *i, RG), *ok, "case {n}");
        }
        // Three colors: red 1, green 2, blue 0 needs 3 cells.
        let rgb = ColorMask(0b111);
        let cells = [r(RED, L), r(GREEN, L), r(GREEN, L)];
        assert!(turns_minimal(&cells, 2, rgb));
        // red L, green L, blue L = Any L.
        let cells = [r(RED, L), r(GREEN, L), r(Condition::Color(Color::Blue), L)];
        assert!(!turns_minimal(&cells, 2, rgb));
    }

    #[test]
    fn t_p_paintknown() {
        let paint = |c: Condition, x: Color| r(c, Action::Paint(x));
        let pend = Cell::Pending {
            action: L,
            color: Color::Red,
        };
        let cells = [paint(ANY, Color::Red), r(ANY, L), pend, r(ANY, F)];
        assert_eq!(known_color(&cells, 3), Some((Color::Red, true)));
        assert_eq!(known_color(&cells, 1), Some((Color::Red, true)));
        assert_eq!(known_color(&cells, 0), None);
        let cells = [paint(ANY, Color::Red), r(GREEN, L), r(ANY, F)];
        assert_eq!(known_color(&cells, 2), Some((Color::Red, false)));
        let cells = [paint(RED, Color::Green), r(ANY, F)];
        assert_eq!(known_color(&cells, 1), None);
        let cells = [r(ANY, F), paint(ANY, Color::Red), r(ANY, Action::Forward)];
        assert_eq!(known_color(&cells, 2), Some((Color::Red, true)));
        assert_eq!(known_color(&cells, 1), None);

        assert!(paint_overwritten(
            &[paint(RED, Color::Green), paint(ANY, Color::Blue)],
            1
        ));
        assert!(paint_overwritten(
            &[paint(RED, Color::Green), paint(ANY, Color::Blue)],
            0
        ));
        assert!(!paint_overwritten(
            &[paint(ANY, Color::Green), paint(RED, Color::Blue)],
            1
        ));
        assert!(!paint_overwritten(
            &[paint(ANY, Color::Green), r(ANY, L), paint(ANY, Color::Blue)],
            2
        ));
    }

    #[test]
    fn t_p_paint() {
        assert!(is_useless_paint(Instruction::new(
            RED,
            Action::Paint(Color::Red)
        )));
        assert!(!is_useless_paint(Instruction::new(
            RED,
            Action::Paint(Color::Blue)
        )));
        assert!(!is_useless_paint(Instruction::new(
            ANY,
            Action::Paint(Color::Red)
        )));
    }
}
