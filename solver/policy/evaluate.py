"""Offline evaluation of an LDS ordering on `policy_dump` output: how far
down the ordering the known programs' decisions are. A fast filter only;
the judge is the solver itself on held-out puzzles at equal wall-clock
(policy/README.md).

Usage: evaluate.py --dump FILE [--dump ...] --splits splits.json
                   [--split val] [--weights W.json]
Without --weights the static ranking is evaluated.

Per decision (one reference program per puzzle, the cheapest): top-1 and
top-3 rate of the program's child, its median and 90th-percentile rank.
Per puzzle (minimum over its known programs, as LDS reaches whichever
comes first): cumulative discrepancy along the path (a decision where some
child solves the puzzle ends the path), its first third, and the share of
puzzles reachable within 10 and 20 discrepancies. The replay uses an empty
history, unlike the live search.
"""
import argparse, json, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import features as F  # noqa: E402


def program_ranks(rec, weights):
    """(rank of the program's child per decision, solving decision flags)."""
    out = []
    for dec in rec['decisions']:
        live, rank = F.static_rank_order(dec)
        if dec['chosen'] not in rank:
            continue
        solved = any(dec['kids'][i]['kind'] == 3 for i in live)
        if weights is None:
            r = rank[dec['chosen']]
        else:
            z = {i: sum(weights.get(c, 0.0) for c in F.kid_contexts(dec, dec['kids'][i], rank[i])) for i in live}
            zc, rc = z[dec['chosen']], rank[dec['chosen']]
            r = sum(1 for i in live if z[i] > zc or (z[i] == zc and rank[i] < rc))
        out.append((r, solved))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dump', action='append', required=True)
    ap.add_argument('--splits', required=True)
    ap.add_argument('--split', default='val')
    ap.add_argument('--weights')
    a = ap.parse_args()
    split = json.load(open(a.splits))['split']
    weights = json.load(open(a.weights))['weights'] if a.weights else None
    puzzles = {}
    for path in a.dump:
        with open(path) as fh:
            for line in fh:
                rec = json.loads(line)
                if 'error' in rec or split.get(str(rec['id'])) != a.split:
                    continue
                ranks = program_ranks(rec, weights)
                cum = first = 0
                third = max(1, len(rec['decisions']) // 3)
                for n, (r, solved) in enumerate(ranks):
                    r = 0 if solved else r
                    cum += r
                    first += r if n < third else 0
                    if solved:
                        break
                puzzles.setdefault(rec['id'], []).append((rec['cost'], cum, first, [r for r, _ in ranks]))
    ref_ranks, cums, firsts = [], [], []
    for progs in puzzles.values():
        ref = min(progs, key=lambda p: p[0])
        best = min(progs, key=lambda p: p[1])
        ref_ranks += ref[3]
        cums.append(best[1])
        firsts.append(best[2])
    rk, c = np.array(ref_ranks), np.array(cums)
    print(json.dumps({
        'split': a.split, 'puzzles': len(puzzles), 'decisions': int(len(rk)),
        'top1': round(float(np.mean(rk == 0)), 4), 'top3': round(float(np.mean(rk <= 2)), 4),
        'rank_median': float(np.median(rk)), 'rank_p90': float(np.percentile(rk, 90)),
        'cum_median': float(np.median(c)), 'cum_p90': float(np.percentile(c, 90)),
        'first_median': float(np.median(firsts)),
        'within10': round(float(np.mean(c <= 10)), 4), 'within20': round(float(np.mean(c <= 20)), 4)}))


if __name__ == '__main__':
    main()
