//! Constants and primitive types (SPEC §1).

pub const MAX_FUNCTIONS: usize = 5;
/// The app's editor allows 12 slots per function (editor_screen.dart:45).
pub const MAX_FUNCTION_SLOTS: usize = 12;
/// rows × cols; the editor allows 14×14 = 196, the catalog uses up to 12×16.
pub const MAX_TILES: usize = 256;
/// interpreter.dart:93
pub const MAX_STEPS: u32 = 20_000;

/// `row * cols + col`. `MAX_TILES = 256` makes `u8` an exact fit.
pub type TileId = u8;
/// 0..=4, F1 = 0.
pub type FnId = u8;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Color {
    Red = 0,
    Green = 1,
    Blue = 2,
}

impl Color {
    pub const ALL: [Color; 3] = [Color::Red, Color::Green, Color::Blue];

    pub fn name(self) -> &'static str {
        match self {
            Color::Red => "red",
            Color::Green => "green",
            Color::Blue => "blue",
        }
    }

    pub fn from_index(i: u8) -> Color {
        match i {
            0 => Color::Red,
            1 => Color::Green,
            2 => Color::Blue,
            _ => panic!("invalid color index {i}"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Direction {
    Up = 0,
    Right = 1,
    Down = 2,
    Left = 3,
}

impl Direction {
    #[inline]
    pub fn left(self) -> Self {
        match self {
            Self::Up => Self::Left,
            Self::Left => Self::Down,
            Self::Down => Self::Right,
            Self::Right => Self::Up,
        }
    }

    #[inline]
    pub fn right(self) -> Self {
        match self {
            Self::Up => Self::Right,
            Self::Right => Self::Down,
            Self::Down => Self::Left,
            Self::Left => Self::Up,
        }
    }

    /// `(dRow, dCol)`; row 0 is the top row.
    pub fn delta(self) -> (i32, i32) {
        match self {
            Self::Up => (-1, 0),
            Self::Right => (0, 1),
            Self::Down => (1, 0),
            Self::Left => (0, -1),
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "up" => Some(Self::Up),
            "right" => Some(Self::Right),
            "down" => Some(Self::Down),
            "left" => Some(Self::Left),
            _ => None,
        }
    }

    pub const ALL: [Direction; 4] = [Self::Up, Self::Right, Self::Down, Self::Left];
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Condition {
    Any,
    Color(Color),
}

impl Condition {
    #[inline]
    pub fn matches(self, tile: Color) -> bool {
        match self {
            Condition::Any => true,
            Condition::Color(c) => c == tile,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Action {
    Forward,
    TurnLeft,
    TurnRight,
    Paint(Color),
    Call(FnId),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Instruction {
    pub condition: Condition,
    pub action: Action,
}

impl Instruction {
    pub const fn new(condition: Condition, action: Action) -> Self {
        Self { condition, action }
    }

    pub const fn any(action: Action) -> Self {
        Self {
            condition: Condition::Any,
            action,
        }
    }
}

/// Bit `1 << (color as u8)`: the same layout as the catalog's
/// `allowedCommands` (1 = red, 2 = green, 4 = blue).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ColorMask(pub u8);

impl ColorMask {
    pub const EMPTY: ColorMask = ColorMask(0);

    #[inline]
    pub fn contains(self, color: Color) -> bool {
        self.0 & (1 << color as u8) != 0
    }

    #[inline]
    pub fn insert(&mut self, color: Color) {
        self.0 |= 1 << color as u8;
    }

    pub fn count(self) -> u32 {
        self.0.count_ones()
    }

    pub fn iter(self) -> impl Iterator<Item = Color> {
        Color::ALL.into_iter().filter(move |&c| self.contains(c))
    }
}
