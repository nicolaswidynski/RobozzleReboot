//! Learned LDS ordering (experimental, `--policy`; SPEC §17.3): a log-linear
//! context model over the live kids of a frontier, in the style of Levin
//! tree search with context models. A kid's logit is the sum of the weights
//! of its active contexts; kids are tried in decreasing logit order, ties
//! by the static rank.
//!
//! The 14 context templates are those of `policy/features.py`
//! (`kid_contexts`), computed from the frontier (`DecFeat`) and the kid
//! before and after its lookahead (`KidFeat`). Training data comes from
//! `Solver::replay_dump`, which calls the same feature functions as the
//! search. The weights file maps context strings to weights; at run time
//! each context gets an integer key and the weight is memoized per key, so
//! the strings are only built on the first occurrence.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::hash::{BuildHasherDefault, Hasher};
use std::sync::OnceLock;

/// The loaded weights (set once by the CLI with `--policy`).
pub static POLICY: OnceLock<Policy> = OnceLock::new();

pub struct Policy {
    weights: HashMap<String, f64>,
}

impl Policy {
    /// Loads `{"weights": {"<context>": w, ...}}`.
    pub fn load(path: &std::path::Path) -> Result<Policy, String> {
        let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
        let v: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let obj = v["weights"].as_object().ok_or("no \"weights\" object")?;
        let weights = obj
            .iter()
            .map(|(k, w)| (k.clone(), w.as_f64().unwrap_or(0.0)))
            .collect();
        Ok(Policy { weights })
    }

    /// The kid's logit (sum of its contexts' weights), memoized by key.
    pub fn logit(&self, memo: &mut Memo, dec: &DecFeat, kid: &KidFeat, rank: usize) -> f64 {
        let keys = keys(dec, kid, rank);
        let mut z = 0.0;
        for (t, key) in keys.iter().enumerate() {
            let w = match memo.get(key) {
                Some(w) => *w,
                None => {
                    let s = context_string(t, dec, kid, rank);
                    let w = self.weights.get(&s).copied().unwrap_or(0.0);
                    memo.insert(*key, w);
                    w
                }
            };
            z += w;
        }
        z
    }
}

/// A multiplicative hasher for the integer context keys.
#[derive(Default)]
pub struct KeyHasher(u64);

impl Hasher for KeyHasher {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = (self.0.rotate_left(8) ^ *b as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
    }
    fn write_u64(&mut self, n: u64) {
        self.0 = (n ^ (n >> 29)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
}

pub type Memo = HashMap<u64, f64, BuildHasherDefault<KeyHasher>>;

/// The frontier a decision is made at (the parent, normalized).
#[derive(Debug, Clone, Copy, Default)]
pub struct DecFeat {
    /// 0 open slot, 1 need-condition, 2 need-action.
    pub fk: u8,
    pub f: u8,
    pub index: u8,
    pub stars: u32,
    pub total: u32,
    pub dist: u16,
    pub tile: u8,
    /// 0 void, else 1 + the forward tile's color.
    pub fwd: u8,
    pub depth: u32,
    pub intro: u32,
    pub budget: u32,
    pub used: u32,
    /// (cell type, condition code, action code) of the previous cell.
    pub prev: Option<(u8, u8, u8)>,
}

/// One live kid: its new cell (before the lookahead) and its lookahead.
#[derive(Debug, Clone, Copy, Default)]
pub struct KidFeat {
    pub ct: u8,
    pub cc: u8,
    pub ac: u8,
    pub newfn: bool,
    /// Lookahead result: 0 open, 1 need-condition, 2 need-action, 3 solved.
    pub kind: u8,
    pub stars: u32,
    pub dist: u16,
    pub dsteps: u32,
    pub moved: bool,
}

const ACT_STR: [&str; 11] = [
    "F", "L", "R", "Psame", "Poth", "Cnew", "Cself", "C1", "Cold", "END", "DEF",
];
const COND_STR: [&str; 6] = ["-", "any", "set", "pend", "cur", "oth"];
/// `features.py` ACT labels for the previous cell.
const PREV_ACT_STR: [&str; 13] = [
    "F", "L", "R", "Pr", "Pg", "Pb", "?", "C0", "C1", "C2", "C3", "C4", "Cself",
];
const FWD_STR: [&str; 3] = ["void", "same", "oth"];

fn act_cat(k: &KidFeat, d: &DecFeat) -> u8 {
    let a = k.ac;
    if k.ct == 0 {
        return 9;
    }
    if a == 15 {
        return 10;
    }
    if a >= 6 {
        let g = a - 6;
        return if k.newfn {
            5
        } else if g == d.f {
            6
        } else if g == 0 {
            7
        } else {
            8
        };
    }
    if (3..=5).contains(&a) {
        return if a - 3 == d.tile { 3 } else { 4 };
    }
    a // 0 F, 1 L, 2 R
}

fn cond_cat(k: &KidFeat, d: &DecFeat) -> u8 {
    let (ct, cc) = (k.ct, k.cc);
    if ct == 0 {
        return 0;
    }
    if cc == 0 {
        return 1;
    }
    if cc >= 4 {
        return 2;
    }
    if ct == 3 {
        return 3;
    }
    if cc - 1 == d.tile { 4 } else { 5 }
}

/// (cell type, a/s/c, action label) of the previous cell, or None (start).
fn prev_parts(d: &DecFeat) -> Option<(u8, u8, u8)> {
    let (ct, cc, ac) = d.prev?;
    let cls = if cc == 0 {
        0
    } else if cc >= 4 {
        1
    } else {
        2
    };
    let a = if ac < 6 {
        ac
    } else if ac == 15 {
        6
    } else if ac - 6 != d.f {
        7 + (ac - 6)
    } else {
        12
    };
    Some((ct, cls, a))
}

fn bucket(x: i64, edges: &[i64]) -> u8 {
    for (i, e) in edges.iter().enumerate() {
        if x <= *e {
            return i as u8;
        }
    }
    edges.len() as u8
}

const STEP_EDGES: [i64; 5] = [1, 4, 30, 300, 3000];
const BUDGET_EDGES: [i64; 3] = [2, 5, 9];

/// A kid's lookahead outcome: (kind, min(dstar, 2), sign of the distance
/// change + 1, moved); `None` for a solved kid ("SOLVED").
type Outcome = Option<(u8, u8, u8, u8)>;

/// (outcome, min(dstar, 2), steps bucket).
fn out_parts(d: &DecFeat, k: &KidFeat) -> (Outcome, u8, u8) {
    let dstar = k.stars.saturating_sub(d.stars).min(2) as u8;
    let tb = bucket(k.dsteps as i64, &STEP_EDGES);
    if k.kind == 3 {
        return (None, dstar, tb);
    }
    let dd = if dstar == 0 {
        k.dist as i64 - d.dist as i64
    } else {
        0
    };
    let sign = ((dd > 0) as i8 - (dd < 0) as i8 + 1) as u8;
    (Some((k.kind, dstar, sign, k.moved as u8)), dstar, tb)
}

fn sfb(d: &DecFeat) -> u8 {
    if d.stars == 0 {
        0
    } else if 2 * d.stars < d.total.max(1) {
        1
    } else {
        2
    }
}

fn fwdc(d: &DecFeat) -> u8 {
    if d.fwd == 0 {
        0
    } else if d.fwd - 1 == d.tile {
        1
    } else {
        2
    }
}

fn out_code(d: &DecFeat, k: &KidFeat) -> u64 {
    match out_parts(d, k) {
        (None, ..) => 0xFFFF,
        (Some((kind, s, sign, m)), _, tb) => {
            kind as u64 | (s as u64) << 3 | (sign as u64) << 5 | (m as u64) << 7 | (tb as u64) << 8
        }
    }
}

/// Integer keys of the 14 contexts, in `kid_contexts` order; each encodes
/// every component of its context string.
fn keys(d: &DecFeat, k: &KidFeat, rank: usize) -> [u64; 14] {
    let c = act_cat(k, d) as u64 | (cond_cat(k, d) as u64) << 4 | (k.ct as u64) << 7;
    let prev = match prev_parts(d) {
        None => 0u64,
        Some((ct, cls, a)) => 1 | (ct as u64) << 1 | (cls as u64) << 5 | (a as u64) << 7,
    };
    let out = out_code(d, k);
    let (_, dstar, tb) = out_parts(d, k);
    let oshort = k.kind as u64 | (dstar as u64) << 3 | (tb as u64) << 5;
    let idx = d.index.min(3) as u64;
    let f0 = (d.f == 0) as u64;
    let bb = bucket(d.budget as i64 - d.used as i64, &BUDGET_EDGES) as u64;
    let fk = d.fk as u64;
    let t = |n: u64, payload: u64| n << 56 | payload;
    [
        t(0, c),
        t(1, c | fk << 11),
        t(2, c | prev << 11),
        t(3, c | idx << 11 | f0 << 13),
        t(4, out),
        t(5, c | oshort << 11),
        t(6, c | (fwdc(d) as u64) << 11),
        t(7, c | (d.depth.min(2) as u64) << 11),
        t(8, c | (sfb(d) as u64) << 11),
        t(
            9,
            c | (d.intro.min(7) as u64) << 11 | (k.newfn as u64) << 14,
        ),
        t(10, c | bb << 11),
        t(11, out | fk << 16),
        t(12, rank.min(12) as u64),
        t(13, rank.min(6) as u64 | fk << 4),
    ]
}

/// The context string of template `t` (exactly as `features.py`).
pub fn context_string(t: usize, d: &DecFeat, k: &KidFeat, rank: usize) -> String {
    let mut c = String::new();
    let _ = write!(
        c,
        "{}|{}|{}",
        ACT_STR[act_cat(k, d) as usize],
        COND_STR[cond_cat(k, d) as usize],
        k.ct
    );
    let (op, dstar, tb) = out_parts(d, k);
    let out = match op {
        None => "SOLVED".to_string(),
        Some((kind, s, sign, m)) => {
            format!("k{kind}|s{s}|d{}|m{m}|t{tb}", sign as i8 - 1)
        }
    };
    let fk = d.fk;
    match t {
        0 => format!("C:{c}"),
        1 => format!("CK:{c}:{fk}"),
        2 => {
            let p = match prev_parts(d) {
                None => "start".to_string(),
                Some((ct, cls, a)) => {
                    format!(
                        "{ct}/{}/{}",
                        ["a", "s", "c"][cls as usize],
                        PREV_ACT_STR[a as usize]
                    )
                }
            };
            format!("CP:{c}:{p}")
        }
        3 => format!("CI:{c}:{}:{}", d.index.min(3), (d.f == 0) as u8),
        4 => format!("O:{out}"),
        5 => format!("OC:k{}|s{dstar}|t{tb}:{c}", k.kind),
        6 => format!("CW:{c}:{}", FWD_STR[fwdc(d) as usize]),
        7 => format!("CD:{c}:{}", d.depth.min(2)),
        8 => format!("CS:{c}:{}", sfb(d)),
        9 => format!("CN:{c}:{}:{}", d.intro, k.newfn as u8),
        10 => format!(
            "CB:{c}:{}",
            bucket(d.budget as i64 - d.used as i64, &BUDGET_EDGES)
        ),
        11 => format!("OK:{out}:{fk}"),
        12 => format!("rank{}", rank.min(12)),
        13 => format!("rankK{}:{fk}", rank.min(6)),
        _ => unreachable!(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The Rust contexts and logits equal `features.py`'s on real dump rows
    /// (vectors written by `policy/train.py --vectors`).
    #[test]
    fn t_policy_vectors() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("policy");
        let text = std::fs::read_to_string(dir.join("test_vectors.json")).unwrap();
        let policy = Policy::load(&dir.join("linear_b.json")).unwrap();
        let vecs: Vec<serde_json::Value> = serde_json::from_str(&text).unwrap();
        let mut memo = Memo::default();
        let mut seen: HashMap<u64, String> = HashMap::new();
        let u = |v: &serde_json::Value| v.as_u64().unwrap();
        for v in &vecs {
            let dv = &v["dec"];
            let kv = &v["kid"];
            let prev = dv["prev"].as_array().unwrap();
            let d = DecFeat {
                fk: u(&dv["kind"]) as u8,
                f: u(&dv["f"]) as u8,
                index: u(&dv["index"]) as u8,
                stars: u(&dv["stars"]) as u32,
                total: u(&dv["total"]) as u32,
                dist: u(&dv["dist"]) as u16,
                tile: u(&dv["tile"]) as u8,
                fwd: u(&dv["fwd"]) as u8,
                depth: u(&dv["depth"]) as u32,
                intro: u(&dv["intro"]) as u32,
                budget: u(&dv["budget"]) as u32,
                used: u(&dv["used"]) as u32,
                prev: if prev.is_empty() {
                    None
                } else {
                    Some((u(&prev[0]) as u8, u(&prev[1]) as u8, u(&prev[2]) as u8))
                },
            };
            let k = KidFeat {
                ct: u(&kv["ct"]) as u8,
                cc: u(&kv["cc"]) as u8,
                ac: u(&kv["ac"]) as u8,
                newfn: kv["newfn"].as_bool().unwrap(),
                kind: u(&kv["kind"]) as u8,
                stars: u(&kv["stars"]) as u32,
                dist: u(&kv["dist"]) as u16,
                dsteps: u(&kv["dsteps"]) as u32,
                moved: kv["moved"].as_bool().unwrap(),
            };
            let rank = u(&v["rank"]) as usize;
            let want: Vec<String> = v["ctx"]
                .as_array()
                .unwrap()
                .iter()
                .map(|s| s.as_str().unwrap().to_string())
                .collect();
            let got: Vec<String> = (0..14).map(|t| context_string(t, &d, &k, rank)).collect();
            assert_eq!(got, want);
            // Distinct contexts have distinct keys (the memo is sound).
            for (key, s) in keys(&d, &k, rank).iter().zip(&got) {
                if let Some(o) = seen.insert(*key, s.clone()) {
                    assert_eq!(&o, s);
                }
            }
            let z = policy.logit(&mut memo, &d, &k, rank);
            assert!((z - v["logit"].as_f64().unwrap()).abs() < 1e-9, "{z} {v}");
        }
        assert!(seen.len() > 100);
    }
}
