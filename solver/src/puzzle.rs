//! Puzzle input, validation and compilation (SPEC §2).

use std::collections::VecDeque;

use serde::Deserialize;

use crate::machine::{PackedColors, StarSet};
use crate::types::{
    Color, ColorMask, Direction, FnId, MAX_FUNCTION_SLOTS, MAX_FUNCTIONS, MAX_TILES, TileId,
};

/// A catalog entry or an editor puzzle, as stored in JSON (SPEC §2.1).
/// Unknown fields are ignored.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawPuzzle {
    /// An integer in the catalog, a string for editor puzzles; echoed back
    /// unchanged in the output.
    pub source_id: serde_json::Value,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub difficulty: Option<f64>,
    pub rows: Vec<String>,
    pub start_row: i64,
    pub start_col: i64,
    pub start_direction: String,
    pub slots_per_function: Vec<i64>,
    #[serde(default)]
    pub allowed_commands: i64,
}

/// Immutable, solver-oriented form of a puzzle (SPEC §2.3).
#[derive(Debug, Clone)]
pub struct StaticPuzzle {
    pub source_id: serde_json::Value,
    pub difficulty: Option<f64>,
    pub rows: usize,
    pub cols: usize,
    pub tile_count: u16,
    pub is_tile: Vec<bool>,
    /// `neighbors[tile][direction]`: `None` when off the grid or a gap.
    pub neighbors: Vec<[Option<TileId>; 4]>,
    pub initial_colors: PackedColors,
    pub initial_stars: StarSet,
    pub start_tile: TileId,
    pub start_direction: Direction,
    pub capacities: [u8; MAX_FUNCTIONS],
    pub allowed_paints: ColorMask,
    pub possible_colors: ColorMask,
    pub function_classes: FunctionClasses,
}

/// Capacity classes of F2..F5 (SPEC §2.5): each class is a bitmask of
/// functions with the same non-zero capacity. F1 is in no class.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FunctionClasses {
    pub classes: Vec<u8>,
}

impl FunctionClasses {
    fn new(capacities: &[u8; MAX_FUNCTIONS]) -> Self {
        let mut classes: Vec<(u8, u8)> = Vec::new(); // (capacity, mask)
        for (f, &cap) in capacities.iter().enumerate().skip(1) {
            if cap == 0 {
                continue;
            }
            match classes.iter_mut().find(|(c, _)| *c == cap) {
                Some((_, mask)) => *mask |= 1 << f,
                None => classes.push((cap, 1 << f)),
            }
        }
        Self {
            classes: classes.into_iter().map(|(_, m)| m).collect(),
        }
    }
}

pub type Unsupported = String;

impl StaticPuzzle {
    /// Validates (SPEC §2.2) and compiles a puzzle. Never panics on bad input.
    pub fn compile(raw: &RawPuzzle) -> Result<StaticPuzzle, Unsupported> {
        let rows = raw.rows.len();
        if rows == 0 {
            return Err("grid has no rows".into());
        }
        let row_chars: Vec<Vec<char>> = raw.rows.iter().map(|r| r.chars().collect()).collect();
        let cols = row_chars[0].len();
        if cols == 0 || row_chars.iter().any(|r| r.len() != cols) {
            return Err("grid rows have different or zero lengths".into());
        }
        if rows * cols > MAX_TILES {
            return Err(format!(
                "grid has {} tiles, more than {MAX_TILES}",
                rows * cols
            ));
        }

        let tile_count = rows * cols;
        let mut is_tile = vec![false; tile_count];
        let mut initial_colors = PackedColors::zeroed();
        let mut initial_stars = StarSet::empty();
        let mut board_colors = ColorMask::EMPTY;
        for (r, row) in row_chars.iter().enumerate() {
            for (c, &ch) in row.iter().enumerate() {
                let t = r * cols + c;
                let color = match ch {
                    ' ' | '.' => continue,
                    'r' | 'R' => Color::Red,
                    'g' | 'G' => Color::Green,
                    'b' | 'B' => Color::Blue,
                    other => return Err(format!("unknown tile character {other:?}")),
                };
                is_tile[t] = true;
                initial_colors.set(t as TileId, color);
                board_colors.insert(color);
                if ch.is_ascii_uppercase() {
                    initial_stars.insert(t as TileId);
                }
            }
        }

        let (sr, sc) = (raw.start_row, raw.start_col);
        if sr < 0 || sc < 0 || sr as usize >= rows || sc as usize >= cols {
            return Err(format!("start ({sr}, {sc}) is outside the grid"));
        }
        let start_tile = sr as usize * cols + sc as usize;
        if !is_tile[start_tile] {
            return Err(format!("start ({sr}, {sc}) is a gap"));
        }
        let start_direction = Direction::from_name(&raw.start_direction)
            .ok_or_else(|| format!("unknown start direction {:?}", raw.start_direction))?;

        if raw.slots_per_function.len() != MAX_FUNCTIONS {
            return Err(format!(
                "slotsPerFunction has {} entries, expected {MAX_FUNCTIONS}",
                raw.slots_per_function.len()
            ));
        }
        let mut capacities = [0u8; MAX_FUNCTIONS];
        for (f, &cap) in raw.slots_per_function.iter().enumerate() {
            if cap < 0 || cap as usize > MAX_FUNCTION_SLOTS {
                return Err(format!(
                    "function capacity {cap} is outside 0..={MAX_FUNCTION_SLOTS}"
                ));
            }
            capacities[f] = cap as u8;
        }
        if capacities[0] == 0 {
            return Err("F1 has no slots".into());
        }

        let mut neighbors = vec![[None; 4]; tile_count];
        for r in 0..rows {
            for c in 0..cols {
                for d in Direction::ALL {
                    let (dr, dc) = d.delta();
                    let (nr, nc) = (r as i32 + dr, c as i32 + dc);
                    if nr < 0 || nc < 0 || nr as usize >= rows || nc as usize >= cols {
                        continue;
                    }
                    let n = nr as usize * cols + nc as usize;
                    if is_tile[n] {
                        neighbors[r * cols + c][d as usize] = Some(n as TileId);
                    }
                }
            }
        }

        let allowed_paints = ColorMask((raw.allowed_commands & 0b111) as u8);
        let possible_colors = ColorMask(board_colors.0 | allowed_paints.0);

        Ok(StaticPuzzle {
            source_id: raw.source_id.clone(),
            difficulty: raw.difficulty,
            rows,
            cols,
            tile_count: tile_count as u16,
            is_tile,
            neighbors,
            initial_colors,
            initial_stars,
            start_tile: start_tile as TileId,
            start_direction,
            capacities,
            allowed_paints,
            possible_colors,
            function_classes: FunctionClasses::new(&capacities),
        })
    }

    #[inline]
    pub fn forward_target(&self, tile: TileId, direction: Direction) -> Option<TileId> {
        self.neighbors[tile as usize][direction as usize]
    }

    /// P-CONN (SPEC §2.6): every star is reachable from the start tile.
    pub fn stars_connected(&self) -> bool {
        let mut seen = vec![false; self.tile_count as usize];
        let mut queue = VecDeque::from([self.start_tile]);
        seen[self.start_tile as usize] = true;
        while let Some(t) = queue.pop_front() {
            for n in self.neighbors[t as usize].iter().flatten() {
                if !seen[*n as usize] {
                    seen[*n as usize] = true;
                    queue.push_back(*n);
                }
            }
        }
        self.initial_stars.iter().all(|t| seen[t as usize])
    }

    /// The set of functions a new `Call` may target (SPEC §14.3, §14.4),
    /// as a bitmask. `introduced` always contains F1.
    pub fn callable(&self, introduced: u8, symmetry: bool) -> u8 {
        let enabled = self.enabled_functions();
        if !symmetry {
            return enabled;
        }
        let mut mask = introduced & enabled;
        for &class in &self.function_classes.classes {
            let fresh = class & !introduced;
            if fresh != 0 {
                mask |= fresh & fresh.wrapping_neg(); // lowest-index member
            }
        }
        mask
    }

    pub fn enabled_functions(&self) -> u8 {
        (0..MAX_FUNCTIONS)
            .filter(|&f| self.capacities[f] > 0)
            .fold(0u8, |m, f| m | (1 << f))
    }

    pub fn total_capacity(&self) -> u32 {
        self.capacities.iter().map(|&c| c as u32).sum()
    }

    pub fn tile_of(&self, row: usize, col: usize) -> TileId {
        (row * self.cols + col) as TileId
    }

    pub fn row_col(&self, tile: TileId) -> (usize, usize) {
        (tile as usize / self.cols, tile as usize % self.cols)
    }
}

pub fn fn_bit(f: FnId) -> u8 {
    1 << f
}

/// Reads a catalog file (a JSON array of puzzles).
pub fn load_catalog(path: &std::path::Path) -> Result<Vec<RawPuzzle>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// Builds a puzzle from rows; start defaults to (0, 0).
    pub fn raw(
        rows: &[&str],
        start: (i64, i64),
        dir: &str,
        caps: &[i64],
        paints: i64,
    ) -> RawPuzzle {
        let mut slots = caps.to_vec();
        slots.resize(5, 0);
        RawPuzzle {
            source_id: serde_json::json!(0),
            title: None,
            difficulty: None,
            rows: rows.iter().map(|s| s.to_string()).collect(),
            start_row: start.0,
            start_col: start.1,
            start_direction: dir.into(),
            slots_per_function: slots,
            allowed_commands: paints,
        }
    }

    pub fn puzzle(
        rows: &[&str],
        start: (i64, i64),
        dir: &str,
        caps: &[i64],
        paints: i64,
    ) -> StaticPuzzle {
        StaticPuzzle::compile(&raw(rows, start, dir, caps, paints)).expect("valid test puzzle")
    }

    fn catalog_path() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/levels_catalog.json")
    }

    #[test]
    fn t_level_catalog() {
        let raws = load_catalog(&catalog_path()).unwrap();
        assert_eq!(raws.len(), 908);
        let mut single_color = 0;
        for r in &raws {
            let p = StaticPuzzle::compile(r).unwrap_or_else(|e| panic!("{}: {e}", r.source_id));
            assert!(
                p.stars_connected(),
                "{} has an unreachable star",
                r.source_id
            );
            if p.possible_colors.count() == 1 {
                single_color += 1;
            }
        }
        assert_eq!(single_color, 18);
    }

    #[test]
    fn t_level_validation() {
        let ok = raw(&["bB"], (0, 0), "right", &[2], 0);
        assert!(StaticPuzzle::compile(&ok).is_ok());

        let cases: Vec<(&str, RawPuzzle)> = vec![
            (
                "no rows",
                RawPuzzle {
                    rows: vec![],
                    ..ok.clone()
                },
            ),
            (
                "ragged",
                RawPuzzle {
                    rows: vec!["bB".into(), "b".into()],
                    ..ok.clone()
                },
            ),
            (
                "too big",
                RawPuzzle {
                    rows: vec!["b".repeat(17); 16],
                    ..ok.clone()
                },
            ),
            (
                "bad char",
                RawPuzzle {
                    rows: vec!["bX".into()],
                    ..ok.clone()
                },
            ),
            (
                "start outside",
                RawPuzzle {
                    start_col: 5,
                    ..ok.clone()
                },
            ),
            (
                "start negative",
                RawPuzzle {
                    start_row: -1,
                    ..ok.clone()
                },
            ),
            (
                "start on gap",
                RawPuzzle {
                    rows: vec![" B".into()],
                    ..ok.clone()
                },
            ),
            (
                "bad direction",
                RawPuzzle {
                    start_direction: "north".into(),
                    ..ok.clone()
                },
            ),
            (
                "4 functions",
                RawPuzzle {
                    slots_per_function: vec![2, 0, 0, 0],
                    ..ok.clone()
                },
            ),
            (
                "capacity 13",
                RawPuzzle {
                    slots_per_function: vec![13, 0, 0, 0, 0],
                    ..ok.clone()
                },
            ),
            (
                "negative cap",
                RawPuzzle {
                    slots_per_function: vec![2, -1, 0, 0, 0],
                    ..ok.clone()
                },
            ),
            (
                "no F1",
                RawPuzzle {
                    slots_per_function: vec![0, 3, 0, 0, 0],
                    ..ok.clone()
                },
            ),
        ];
        for (name, r) in cases {
            assert!(
                StaticPuzzle::compile(&r).is_err(),
                "{name} should be rejected"
            );
        }

        // The editor's limits are accepted: 14×14 grid, 12 slots.
        let big = RawPuzzle {
            rows: vec!["b".repeat(14); 14],
            slots_per_function: vec![12, 12, 12, 12, 12],
            ..ok
        };
        assert!(StaticPuzzle::compile(&big).is_ok());
    }

    #[test]
    fn compiles_neighbors_colors_and_stars() {
        let p = puzzle(&["rb ", " G "], (0, 0), "right", &[3], 0b001);
        assert_eq!(p.tile_count, 6);
        assert_eq!(p.forward_target(0, Direction::Right), Some(1));
        assert_eq!(p.forward_target(1, Direction::Right), None); // gap
        assert_eq!(p.forward_target(0, Direction::Up), None); // off grid
        assert_eq!(p.forward_target(1, Direction::Down), Some(4));
        assert_eq!(p.initial_colors.get(4), Color::Green);
        assert!(p.initial_stars.contains(4));
        assert!(p.allowed_paints.contains(Color::Red));
        assert_eq!(p.possible_colors.count(), 3);
    }

    #[test]
    fn disconnected_star_is_detected() {
        let p = puzzle(&["b B"], (0, 0), "right", &[2], 0);
        assert!(!p.stars_connected());
    }

    #[test]
    fn t_p_sym_callable_sets() {
        // TV-15
        let p = puzzle(&["bB"], (0, 0), "right", &[7, 4, 2, 4, 2], 0);
        assert_eq!(p.callable(0b00001, true), 0b00111);
        assert_eq!(p.callable(0b00011, true), 0b01111);
        assert_eq!(p.callable(0b00001, false), 0b11111);
        let p = puzzle(&["bB"], (0, 0), "right", &[6, 6, 0, 6, 0], 0);
        assert_eq!(p.callable(0b00001, true), 0b00011);
        assert_eq!(p.callable(0b00011, true), 0b01011);
    }
}
