//! Program model (SPEC §3) and the instruction syntax of the output (SPEC §26).

use crate::types::{
    Action, Color, Condition, FnId, Instruction, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Cell {
    /// Storage filler only; has no program meaning.
    #[default]
    Unused,
    Resolved(Instruction),
    /// An occupied slot whose condition is chosen and whose action is not.
    CondOnly(Color),
    /// An occupied slot whose action is chosen and whose condition is known
    /// to be either `Any` or `Color(color)`: the two only differ once the
    /// slot runs on a tile of another color (SPEC §13, D-CHOOSE).
    Pending {
        action: Action,
        color: Color,
    },
}

/// A left-packed function prefix (SPEC §3.1). `cells[0..len)` are decided;
/// if `ended`, every slot from `len` on is empty, otherwise slot `len` is open.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FunctionDraft {
    pub cells: [Cell; MAX_FUNCTION_SLOTS],
    pub len: u8,
    pub capacity: u8,
    pub ended: bool,
}

impl FunctionDraft {
    pub fn new(capacity: u8) -> Self {
        assert!(capacity as usize <= MAX_FUNCTION_SLOTS);
        Self {
            cells: [Cell::Unused; MAX_FUNCTION_SLOTS],
            len: 0,
            capacity,
            ended: capacity == 0,
        }
    }

    /// `closed(f)`: nothing can be appended any more.
    #[inline]
    pub fn closed(&self) -> bool {
        self.ended || self.len == self.capacity
    }

    /// `exhausted(f, pc)`: a frame at `pc` definitely has nothing left to run.
    #[inline]
    pub fn exhausted(&self, pc: u8) -> bool {
        pc == self.len && self.closed()
    }

    #[inline]
    pub fn cell(&self, index: u8) -> Cell {
        debug_assert!(index < self.len);
        self.cells[index as usize]
    }

    pub fn decided(&self) -> &[Cell] {
        &self.cells[..self.len as usize]
    }

    pub fn push(&mut self, cell: Cell) {
        debug_assert!(!self.closed());
        debug_assert!(cell != Cell::Unused);
        self.cells[self.len as usize] = cell;
        self.len += 1;
    }

    pub fn end(&mut self) {
        debug_assert!(!self.closed());
        self.ended = true;
    }

    pub fn resolve_cond_only(&mut self, index: u8, action: Action) {
        match self.cells[index as usize] {
            Cell::CondOnly(color) => {
                self.cells[index as usize] =
                    Cell::Resolved(Instruction::new(Condition::Color(color), action));
            }
            other => panic!("slot {index} is {other:?}, not CondOnly"),
        }
    }

    pub fn resolve_pending(&mut self, index: u8, condition: Condition) {
        match self.cells[index as usize] {
            Cell::Pending { action, color } => {
                debug_assert!(condition == Condition::Any || condition == Condition::Color(color));
                self.cells[index as usize] = Cell::Resolved(Instruction::new(condition, action));
            }
            other => panic!("slot {index} is {other:?}, not Pending"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PartialProgram {
    pub functions: [FunctionDraft; MAX_FUNCTIONS],
}

impl PartialProgram {
    pub fn new(capacities: [u8; MAX_FUNCTIONS]) -> Self {
        Self {
            functions: capacities.map(FunctionDraft::new),
        }
    }

    #[inline]
    pub fn function(&self, f: FnId) -> &FunctionDraft {
        &self.functions[f as usize]
    }

    #[inline]
    pub fn function_mut(&mut self, f: FnId) -> &mut FunctionDraft {
        &mut self.functions[f as usize]
    }

    /// Number of occupied cells (INV-COST).
    pub fn occupied_slots(&self) -> u8 {
        self.functions.iter().map(|f| f.len).sum()
    }

    pub fn has_cond_only(&self) -> bool {
        self.functions
            .iter()
            .any(|f| f.decided().iter().any(|c| matches!(c, Cell::CondOnly(_))))
    }

    /// INV-PREFIX (SPEC §3.1).
    pub fn check_prefix(&self) -> bool {
        self.functions.iter().all(|f| {
            f.len <= f.capacity
                && (f.capacity != 0 || f.ended)
                && f.decided().iter().all(|c| *c != Cell::Unused)
                && f.cells[f.len as usize..].iter().all(|c| *c == Cell::Unused)
        })
    }

    /// The physical program (SPEC §3.3): undecided tails become `None`, and a
    /// `Pending` cell becomes `Any` (it never ran on another color, so `Any`
    /// and `Color(c)` behaved identically). Panics if a `CondOnly` remains.
    pub fn to_physical(&self) -> ResolvedProgram {
        ResolvedProgram {
            functions: std::array::from_fn(|f| {
                let d = &self.functions[f];
                let mut slots: Vec<Option<Instruction>> = d
                    .decided()
                    .iter()
                    .map(|c| match c {
                        Cell::Resolved(i) => Some(*i),
                        Cell::Pending { action, .. } => Some(Instruction::any(*action)),
                        other => panic!("cannot make a physical program with {other:?}"),
                    })
                    .collect();
                slots.resize(d.capacity as usize, None);
                slots
            }),
        }
    }
}

/// The game's program representation: `functions[f].len() == cap[f]`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedProgram {
    pub functions: [Vec<Option<Instruction>>; MAX_FUNCTIONS],
}

impl ResolvedProgram {
    pub fn occupied_slots(&self) -> usize {
        self.functions
            .iter()
            .flatten()
            .filter(|s| s.is_some())
            .count()
    }

    /// Output form (SPEC §26): one array per function, `null` for empty.
    pub fn to_tokens(&self) -> Vec<Vec<Option<String>>> {
        self.functions
            .iter()
            .map(|f| f.iter().map(|s| s.map(instruction_token)).collect())
            .collect()
    }

    /// Parses the output form back. `capacities` fixes the array lengths.
    pub fn from_tokens(tokens: &[Vec<Option<String>>]) -> Result<Self, String> {
        if tokens.len() != MAX_FUNCTIONS {
            return Err(format!("expected {MAX_FUNCTIONS} functions"));
        }
        let mut functions: [Vec<Option<Instruction>>; MAX_FUNCTIONS] = Default::default();
        for (f, slots) in tokens.iter().enumerate() {
            for s in slots {
                functions[f].push(match s {
                    None => None,
                    Some(t) => Some(parse_instruction(t)?),
                });
            }
        }
        Ok(Self { functions })
    }
}

/// `"<condition>:<action>"`, the condition omitted for `Any`. Action names
/// are exactly Dart's `ActionType` names.
pub fn instruction_token(i: Instruction) -> String {
    let action = match i.action {
        Action::Forward => "forward".to_string(),
        Action::TurnLeft => "turnLeft".to_string(),
        Action::TurnRight => "turnRight".to_string(),
        Action::Paint(Color::Red) => "paintRed".to_string(),
        Action::Paint(Color::Green) => "paintGreen".to_string(),
        Action::Paint(Color::Blue) => "paintBlue".to_string(),
        Action::Call(f) => format!("callF{}", f + 1),
    };
    match i.condition {
        Condition::Any => action,
        Condition::Color(c) => format!("{}:{action}", c.name()),
    }
}

pub fn parse_instruction(token: &str) -> Result<Instruction, String> {
    let (cond, action) = match token.split_once(':') {
        Some((c, a)) => (
            Condition::Color(match c {
                "red" => Color::Red,
                "green" => Color::Green,
                "blue" => Color::Blue,
                _ => return Err(format!("unknown condition in {token:?}")),
            }),
            a,
        ),
        None => (Condition::Any, token),
    };
    let action = match action {
        "forward" => Action::Forward,
        "turnLeft" => Action::TurnLeft,
        "turnRight" => Action::TurnRight,
        "paintRed" => Action::Paint(Color::Red),
        "paintGreen" => Action::Paint(Color::Green),
        "paintBlue" => Action::Paint(Color::Blue),
        a => match a.strip_prefix("callF").and_then(|n| n.parse::<u8>().ok()) {
            Some(n @ 1..=5) => Action::Call(n - 1),
            _ => return Err(format!("unknown action in {token:?}")),
        },
    };
    Ok(Instruction::new(cond, action))
}

/// Test helper: builds a `ResolvedProgram` from token arrays.
pub fn program_from(
    functions: &[&[Option<&str>]],
    capacities: [u8; MAX_FUNCTIONS],
) -> ResolvedProgram {
    let mut out: [Vec<Option<Instruction>>; MAX_FUNCTIONS] = Default::default();
    for f in 0..MAX_FUNCTIONS {
        let given = functions.get(f).copied().unwrap_or(&[]);
        assert!(
            given.len() <= capacities[f] as usize,
            "F{} has too many slots",
            f + 1
        );
        out[f] = given
            .iter()
            .map(|t| t.map(|t| parse_instruction(t).unwrap()))
            .collect();
        out[f].resize(capacities[f] as usize, None);
    }
    ResolvedProgram { functions: out }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_round_trip() {
        let all = [
            "forward",
            "turnLeft",
            "turnRight",
            "paintRed",
            "paintGreen",
            "paintBlue",
            "callF1",
            "callF5",
            "red:forward",
            "green:callF3",
            "blue:paintRed",
        ];
        for t in all {
            assert_eq!(instruction_token(parse_instruction(t).unwrap()), t);
        }
        for bad in ["callF0", "callF6", "purple:forward", "jump", "red:"] {
            assert!(parse_instruction(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn draft_predicates() {
        let mut d = FunctionDraft::new(2);
        assert!(!d.closed() && !d.exhausted(0));
        d.push(Cell::Resolved(Instruction::any(Action::Forward)));
        assert!(!d.exhausted(1)); // slot 1 is still open
        d.end();
        assert!(d.exhausted(1) && !d.exhausted(0));
        let zero = FunctionDraft::new(0);
        assert!(zero.ended && zero.exhausted(0));
    }

    #[test]
    fn physical_form_pads_with_none() {
        let mut p = PartialProgram::new([3, 1, 0, 0, 0]);
        p.function_mut(0)
            .push(Cell::Resolved(Instruction::any(Action::Forward)));
        p.function_mut(0).push(Cell::CondOnly(Color::Red));
        assert!(p.check_prefix());
        assert_eq!(p.occupied_slots(), 2);
        assert!(p.has_cond_only());
        p.function_mut(0).resolve_cond_only(1, Action::Call(0));
        assert!(!p.has_cond_only());
        let phys = p.to_physical();
        assert_eq!(
            phys.to_tokens()[0],
            vec![Some("forward".into()), Some("red:callF1".into()), None]
        );
        assert_eq!(phys.functions[1], vec![None]);
        assert_eq!(
            ResolvedProgram::from_tokens(&phys.to_tokens()).unwrap(),
            phys
        );
    }
}
