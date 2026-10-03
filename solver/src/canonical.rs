//! Local canonicalization rules P-PAINT and P-TURN (SPEC §15.1, §15.2).
//! P-EMPTYFN and P-STEPCUT are applied during generation in `search.rs`.

use crate::program::Cell;
use crate::types::{Action, Condition, Instruction};

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
