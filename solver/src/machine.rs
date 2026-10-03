//! Board state, the runtime machine and Zobrist hashing (SPEC §4, §7.1, §9).

use std::sync::OnceLock;

use crate::puzzle::StaticPuzzle;
use crate::stack::{Frame, NodeId};
use crate::types::{Color, Direction, MAX_STEPS, MAX_TILES, TileId};

const COLOR_WORDS: usize = (MAX_TILES * 2).div_ceil(64);
const STAR_WORDS: usize = MAX_TILES.div_ceil(64);

/// 2 bits per tile (`Red = 0`, `Green = 1`, `Blue = 2`). 64 is divisible by
/// 2, so a tile's bits never straddle a word boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct PackedColors {
    words: [u64; COLOR_WORDS],
}

impl PackedColors {
    pub const fn zeroed() -> Self {
        Self {
            words: [0; COLOR_WORDS],
        }
    }

    #[inline]
    pub fn get(&self, tile: TileId) -> Color {
        let bit = tile as usize * 2;
        Color::from_index(((self.words[bit / 64] >> (bit % 64)) & 0b11) as u8)
    }

    #[inline]
    pub fn set(&mut self, tile: TileId, color: Color) {
        let bit = tile as usize * 2;
        let shift = bit % 64;
        let word = &mut self.words[bit / 64];
        *word = (*word & !(0b11u64 << shift)) | ((color as u64) << shift);
    }
}

/// One bit per tile.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct StarSet {
    words: [u64; STAR_WORDS],
}

impl StarSet {
    pub const fn empty() -> Self {
        Self {
            words: [0; STAR_WORDS],
        }
    }

    #[inline]
    pub fn contains(&self, tile: TileId) -> bool {
        let t = tile as usize;
        self.words[t / 64] & (1u64 << (t % 64)) != 0
    }

    #[inline]
    pub fn insert(&mut self, tile: TileId) {
        let t = tile as usize;
        self.words[t / 64] |= 1u64 << (t % 64);
    }

    /// Returns whether the tile had a star.
    #[inline]
    pub fn remove(&mut self, tile: TileId) -> bool {
        let t = tile as usize;
        let mask = 1u64 << (t % 64);
        let word = &mut self.words[t / 64];
        let had = *word & mask != 0;
        *word &= !mask;
        had
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.words.iter().all(|&w| w == 0)
    }

    pub fn len(&self) -> u32 {
        self.words.iter().map(|w| w.count_ones()).sum()
    }

    pub fn iter(&self) -> impl Iterator<Item = TileId> + '_ {
        (0..MAX_TILES)
            .filter(|&t| self.contains(t as TileId))
            .map(|t| t as TileId)
    }
}

/// Fixed-seed Zobrist tables (SPEC §7.1).
pub struct Zobrist {
    robot: [[u128; 4]; MAX_TILES],
    star: [u128; MAX_TILES],
    color: [[u128; 3]; MAX_TILES],
}

fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9e37_79b9_7f4a_7c15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

impl Zobrist {
    pub fn get() -> &'static Zobrist {
        static TABLES: OnceLock<Zobrist> = OnceLock::new();
        TABLES.get_or_init(|| {
            let mut seed = 0x5eed_0f20_26ab_u64;
            let mut next =
                || ((splitmix64(&mut seed) as u128) << 64) | splitmix64(&mut seed) as u128;
            let mut z = Zobrist {
                robot: [[0; 4]; MAX_TILES],
                star: [0; MAX_TILES],
                color: [[0; 3]; MAX_TILES],
            };
            for t in 0..MAX_TILES {
                for d in 0..4 {
                    z.robot[t][d] = next();
                }
                z.star[t] = next();
                for c in 0..3 {
                    z.color[t][c] = next();
                }
            }
            z
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeadReason {
    Crash,
    ProgramEnded,
    StepLimit,
    Loop,
}

/// The runtime machine (SPEC §4.2). `Copy`, no heap: the suspended callers
/// live in the `StackArena`, referenced by `callers`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Machine {
    pub position: TileId,
    pub direction: Direction,
    pub colors: PackedColors,
    pub stars: StarSet,
    pub current: Option<Frame>,
    pub callers: Option<NodeId>,
    pub steps: u32,
    pub physical_hash: u128,
}

impl Machine {
    /// The root machine: start state, `current = F1@0`, hash from scratch.
    pub fn new(puzzle: &StaticPuzzle) -> Self {
        let mut m = Machine {
            position: puzzle.start_tile,
            direction: puzzle.start_direction,
            colors: puzzle.initial_colors,
            stars: puzzle.initial_stars,
            current: (puzzle.capacities[0] > 0).then_some(Frame { function: 0, pc: 0 }),
            callers: None,
            steps: 0,
            physical_hash: 0,
        };
        m.physical_hash = m.hash_from_scratch(puzzle);
        m
    }

    pub fn hash_from_scratch(&self, puzzle: &StaticPuzzle) -> u128 {
        let z = Zobrist::get();
        let mut h = z.robot[self.position as usize][self.direction as usize];
        for t in self.stars.iter() {
            h ^= z.star[t as usize];
        }
        for t in 0..puzzle.tile_count as usize {
            if puzzle.is_tile[t] {
                h ^= z.color[t][self.colors.get(t as TileId) as usize];
            }
        }
        h
    }

    /// SPEC §9: the only code that advances `steps`.
    #[inline]
    pub fn consume_instruction(&mut self) -> Result<(), DeadReason> {
        self.steps += 1;
        if self.steps > MAX_STEPS {
            Err(DeadReason::StepLimit)
        } else {
            Ok(())
        }
    }

    #[inline]
    pub fn tile_color(&self) -> Color {
        self.colors.get(self.position)
    }

    /// X-FORWARD after the target is known to be a tile.
    #[inline]
    pub fn move_to(&mut self, target: TileId) {
        let z = Zobrist::get();
        let d = self.direction as usize;
        self.physical_hash ^= z.robot[self.position as usize][d] ^ z.robot[target as usize][d];
        self.position = target;
        if self.stars.remove(target) {
            self.physical_hash ^= z.star[target as usize];
        }
    }

    #[inline]
    pub fn turn(&mut self, right: bool) {
        let z = Zobrist::get();
        let p = self.position as usize;
        let new = if right {
            self.direction.right()
        } else {
            self.direction.left()
        };
        self.physical_hash ^= z.robot[p][self.direction as usize] ^ z.robot[p][new as usize];
        self.direction = new;
    }

    #[inline]
    pub fn paint(&mut self, color: Color) {
        let z = Zobrist::get();
        let p = self.position as usize;
        let old = self.colors.get(self.position);
        self.physical_hash ^= z.color[p][old as usize] ^ z.color[p][color as usize];
        self.colors.set(self.position, color);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packed_colors_round_trip_every_tile() {
        let mut c = PackedColors::zeroed();
        for t in 0..MAX_TILES {
            c.set(t as TileId, Color::from_index((t % 3) as u8));
        }
        for t in 0..MAX_TILES {
            assert_eq!(c.get(t as TileId), Color::from_index((t % 3) as u8));
        }
        c.set(37, Color::Blue);
        assert_eq!(c.get(36), Color::Red);
        assert_eq!(c.get(37), Color::Blue);
        assert_eq!(c.get(38), Color::Blue);
    }

    #[test]
    fn t_zobrist_incremental() {
        use crate::puzzle::tests::puzzle;
        let p = puzzle(&["rgbr", "gbrG", "bRgb"], (0, 0), "right", &[1], 0b111);
        let mut m = Machine::new(&p);
        let mut seed = 7u64;
        for _ in 0..10_000 {
            match splitmix64(&mut seed) % 4 {
                0 => m.turn(true),
                1 => m.turn(false),
                2 => m.paint(Color::from_index((splitmix64(&mut seed) % 3) as u8)),
                _ => {
                    if let Some(n) = p.forward_target(m.position, m.direction) {
                        m.move_to(n);
                    }
                }
            }
            assert_eq!(m.physical_hash, m.hash_from_scratch(&p));
        }
        // Painting back restores the hash.
        let before = m.physical_hash;
        let c = m.tile_color();
        m.paint(if c == Color::Red {
            Color::Blue
        } else {
            Color::Red
        });
        assert_ne!(m.physical_hash, before);
        m.paint(c);
        assert_eq!(m.physical_hash, before);
    }

    #[test]
    fn consume_instruction_boundary() {
        use crate::puzzle::tests::puzzle;
        let mut m = Machine::new(&puzzle(&["bB"], (0, 0), "right", &[1], 0));
        m.steps = 19_999;
        assert_eq!(m.consume_instruction(), Ok(()));
        assert_eq!(m.steps, 20_000);
        assert_eq!(m.consume_instruction(), Err(DeadReason::StepLimit));
        assert_eq!(m.steps, 20_001);
    }

    #[test]
    fn star_set_basics() {
        let mut s = StarSet::empty();
        assert!(s.is_empty());
        s.insert(0);
        s.insert(255);
        assert!(s.contains(255) && s.contains(0) && !s.contains(64));
        assert_eq!(s.len(), 2);
        assert!(s.remove(255));
        assert!(!s.remove(255));
        assert_eq!(s.iter().collect::<Vec<_>>(), vec![0]);
    }
}
