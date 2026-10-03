//! Persistent caller stack and the stack transitions S-CALL, S-POP and
//! S-REBUILD (SPEC §5, §11).

use crate::machine::Machine;
use crate::program::PartialProgram;
use crate::types::FnId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Frame {
    pub function: FnId,
    pub pc: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct NodeId(pub u32);

/// An immutable suspended frame. `hash` covers the whole chain ending here.
#[derive(Debug, Clone, Copy)]
pub struct StackNode {
    pub frame: Frame,
    pub parent: Option<NodeId>,
    pub depth: u16,
    pub hash: u128,
}

#[inline]
pub fn mix(parent: u128, frame: Frame) -> u128 {
    let x = (((frame.function as u128) << 8) | frame.pc as u128) + 1;
    let mut h = parent ^ x.wrapping_mul(0x9e37_79b9_7f4a_7c15_6a09_e667_f3bc_c909);
    h ^= h >> 67;
    h = h.wrapping_mul(0xbf58_476d_1ce4_e5b9_94d0_49bb_1331_11eb);
    h ^ (h >> 59)
}

#[derive(Debug, Default)]
pub struct StackArena {
    nodes: Vec<StackNode>,
}

impl StackArena {
    pub fn new() -> Self {
        Self::default()
    }

    #[inline]
    pub fn mark(&self) -> usize {
        self.nodes.len()
    }

    #[inline]
    pub fn truncate(&mut self, mark: usize) {
        self.nodes.truncate(mark);
    }

    pub fn clear(&mut self) {
        self.nodes.clear();
    }

    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    #[inline]
    pub fn get(&self, id: NodeId) -> &StackNode {
        &self.nodes[id.0 as usize]
    }

    #[inline]
    pub fn hash_of(&self, id: Option<NodeId>) -> u128 {
        id.map_or(0, |id| self.get(id).hash)
    }

    #[inline]
    pub fn depth_of(&self, id: Option<NodeId>) -> u16 {
        id.map_or(0, |id| self.get(id).depth)
    }

    #[inline]
    pub fn push(&mut self, parent: Option<NodeId>, frame: Frame) -> NodeId {
        let (parent_hash, parent_depth) = match parent {
            Some(p) => (self.get(p).hash, self.get(p).depth),
            None => (0, 0),
        };
        let id = NodeId(u32::try_from(self.nodes.len()).expect("stack arena exceeded u32"));
        self.nodes.push(StackNode {
            frame,
            parent,
            depth: parent_depth + 1,
            hash: mix(parent_hash, frame),
        });
        id
    }

    /// `chain(id)`, bottom to top.
    pub fn chain(&self, mut id: Option<NodeId>) -> Vec<Frame> {
        let mut out = Vec::new();
        while let Some(n) = id {
            out.push(self.get(n).frame);
            id = self.get(n).parent;
        }
        out.reverse();
        out
    }

    /// Exact equality of two caller chains (SPEC §12.2).
    pub fn chains_equal(&self, mut a: Option<NodeId>, mut b: Option<NodeId>) -> bool {
        loop {
            match (a, b) {
                (None, None) => return true,
                (Some(x), Some(y)) => {
                    if x == y {
                        return true; // immutable nodes: the rest is shared
                    }
                    let (nx, ny) = (self.get(x), self.get(y));
                    if nx.depth != ny.depth || nx.frame != ny.frame {
                        return false;
                    }
                    a = nx.parent;
                    b = ny.parent;
                }
                _ => return false,
            }
        }
    }
}

/// How S-CALL handled the caller.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallKind {
    Tail,
    Push,
}

/// S-CALL (SPEC §11.1). `current.pc` must already point past the call cell.
#[inline]
pub fn call(
    machine: &mut Machine,
    program: &PartialProgram,
    arena: &mut StackArena,
    target: FnId,
) -> CallKind {
    let caller = machine.current.expect("call without a current frame");
    let kind = if program.function(caller.function).exhausted(caller.pc) {
        CallKind::Tail // S-TAIL
    } else {
        machine.callers = Some(arena.push(machine.callers, caller)); // S-PUSH
        CallKind::Push
    };
    machine.current = Some(Frame {
        function: target,
        pc: 0,
    });
    kind
}

/// S-POP (SPEC §11.3). Consumes no step.
#[inline]
pub fn pop(machine: &mut Machine, arena: &StackArena) {
    match machine.callers {
        Some(id) => {
            let node = arena.get(id);
            machine.current = Some(node.frame);
            machine.callers = node.parent;
        }
        None => machine.current = None,
    }
}

/// S-REBUILD (SPEC §11.4) after D-END on `(function, end_pc)`: removes every
/// suspended frame equal to it, keeping the others in order. Does not touch
/// `current`; N-RETURN pops it. Reuses the unchanged part of the chain below
/// the deepest removed frame. Returns the number of frames re-pushed.
pub fn rebuild_after_end(
    machine: &mut Machine,
    arena: &mut StackArena,
    function: FnId,
    end_pc: u8,
) -> usize {
    let target = Frame {
        function,
        pc: end_pc,
    };
    // Walk top to bottom, remembering the frames above the deepest match.
    let mut above: Vec<Frame> = Vec::new(); // top to bottom
    let mut keep_until = 0; // frames of `above` (from the top) to keep
    let mut base: Option<Option<NodeId>> = None; // parent of the deepest match
    let mut cursor = machine.callers;
    while let Some(id) = cursor {
        let node = *arena.get(id);
        if node.frame == target {
            base = Some(node.parent);
            keep_until = above.len();
        }
        above.push(node.frame);
        cursor = node.parent;
    }
    let Some(base) = base else {
        return 0; // nothing to remove: no allocation
    };
    let mut parent = base;
    let mut rebuilt = 0;
    for &frame in above[..keep_until].iter().rev() {
        if frame != target {
            parent = Some(arena.push(parent, frame));
            rebuilt += 1;
        }
    }
    machine.callers = parent;
    rebuilt
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::Cell;
    use crate::puzzle::tests::puzzle;
    use crate::types::{Action, Instruction};

    fn f(function: u8, pc: u8) -> Frame {
        Frame { function, pc }
    }

    fn machine_with_chain(arena: &mut StackArena, frames: &[Frame], current: Frame) -> Machine {
        let mut m = Machine::new(&puzzle(&["bB"], (0, 0), "right", &[2, 2, 3], 0));
        let mut parent = None;
        for &fr in frames {
            parent = Some(arena.push(parent, fr));
        }
        m.callers = parent;
        m.current = Some(current);
        m
    }

    #[test]
    fn t_tail_call_and_unknown_continuation() {
        let mut arena = StackArena::new();
        let mut prog = PartialProgram::new([2, 0, 0, 0, 0]);
        let call = Cell::Resolved(Instruction::any(Action::Call(0)));
        prog.function_mut(0)
            .push(Cell::Resolved(Instruction::any(Action::Forward)));
        prog.function_mut(0).push(call);
        let mut m = Machine::new(&puzzle(&["bB"], (0, 0), "right", &[2], 0));
        m.current = Some(f(0, 2)); // past the call; len == cap: exhausted
        assert_eq!(call_kind(&mut m, &prog, &mut arena), CallKind::Tail);
        assert_eq!(arena.len(), 0);

        // t_unknown_continuation_not_tail: F1 = [call], slot 1 still open.
        let mut prog = PartialProgram::new([2, 0, 0, 0, 0]);
        prog.function_mut(0).push(call);
        m.current = Some(f(0, 1));
        assert_eq!(call_kind(&mut m, &prog, &mut arena), CallKind::Push);
        assert_eq!(arena.chain(m.callers), vec![f(0, 1)]);
        // Once slot 1 is END, the same call is a tail call.
        prog.function_mut(0).end();
        m.callers = None;
        m.current = Some(f(0, 1));
        assert_eq!(call_kind(&mut m, &prog, &mut arena), CallKind::Tail);
    }

    fn call_kind(m: &mut Machine, prog: &PartialProgram, arena: &mut StackArena) -> CallKind {
        call(m, prog, arena, 0)
    }

    #[test]
    fn pop_restores_caller() {
        let mut arena = StackArena::new();
        let mut m = machine_with_chain(&mut arena, &[f(0, 1)], f(1, 3));
        pop(&mut m, &arena);
        assert_eq!((m.current, m.callers), (Some(f(0, 1)), None));
        pop(&mut m, &arena);
        assert_eq!(m.current, None);
    }

    #[test]
    fn t_rebuild_middle() {
        // TV-10 shape: [B@k, C@j] suspended, B@k current; END(B, k).
        let (b, c) = (1, 2);
        let mut arena = StackArena::new();
        let mut m = machine_with_chain(&mut arena, &[f(0, 1), f(b, 1), f(c, 2)], f(b, 1));
        let rebuilt = rebuild_after_end(&mut m, &mut arena, b, 1);
        assert_eq!(rebuilt, 1); // only C@j re-pushed; F1@1 below is reused
        assert_eq!(arena.chain(m.callers), vec![f(0, 1), f(c, 2)]);
        assert_eq!(m.current, Some(f(b, 1)), "S-REBUILD must not pop current");
        assert_eq!(arena.depth_of(m.callers), 2);
        // Hash equals that of a freshly built identical chain.
        let mut fresh = StackArena::new();
        let bottom = fresh.push(None, f(0, 1));
        let id = fresh.push(Some(bottom), f(c, 2));
        assert_eq!(arena.hash_of(m.callers), fresh.hash_of(Some(id)));
    }

    #[test]
    fn rebuild_without_match_allocates_nothing() {
        let mut arena = StackArena::new();
        let mut m = machine_with_chain(&mut arena, &[f(0, 1), f(2, 2)], f(1, 1));
        let before = (arena.len(), m.callers);
        assert_eq!(rebuild_after_end(&mut m, &mut arena, 1, 1), 0);
        assert_eq!((arena.len(), m.callers), before);
    }

    #[test]
    fn rebuild_removes_every_match() {
        let mut arena = StackArena::new();
        let mut m = machine_with_chain(
            &mut arena,
            &[f(1, 1), f(2, 2), f(1, 1), f(3, 0), f(1, 1)],
            f(1, 1),
        );
        rebuild_after_end(&mut m, &mut arena, 1, 1);
        assert_eq!(arena.chain(m.callers), vec![f(2, 2), f(3, 0)]);
    }

    #[test]
    fn chains_equal_compares_contents() {
        let mut arena = StackArena::new();
        let mut chain = |top: Frame| {
            let bottom = arena.push(None, f(0, 1));
            arena.push(Some(bottom), top)
        };
        let (a, b, c) = (chain(f(2, 2)), chain(f(2, 2)), chain(f(2, 3)));
        assert_ne!(a, b);
        assert!(arena.chains_equal(Some(a), Some(b)));
        assert!(!arena.chains_equal(Some(a), Some(c)));
        assert!(!arena.chains_equal(Some(a), None));
    }
}
