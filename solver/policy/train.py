"""Trains the learned LDS ordering (a log-linear context model) from
`policy_dump` output and writes the weights file the solver loads with
`--policy` (policy/README.md has the exact commands).

Usage:
  train.py --dump FILE[:MULT] [--dump ...] --splits splits.json --out W.json
           [--split train] [--l2 1.0] [--vectors N --vectors-out FILE]

Each --dump is a JSONL file from `policy_dump`; MULT repeats its programs
(weighting). Only programs of puzzles in the chosen split are used. With
--vectors, N (decision, kid) rows of the training data are written with
their contexts and logits for the solver's `t_policy_vectors` test.
"""
import argparse, array, json, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import features as F  # noqa: E402


def load_design(dumps, keep, fz, grow, vectors=None, vmax=0):
    rows, cols = array.array('i'), array.array('i')
    gstart, chosen = [0], []
    nrows, nprogs, puzzles = 0, 0, set()
    for path, mult in dumps:
        with open(path) as fh:
            for line in fh:
                rec = json.loads(line)
                if 'error' in rec or not keep(rec['id']):
                    continue
                for _ in range(mult):
                    nprogs += 1
                    puzzles.add(rec['id'])
                    for dec in rec['decisions']:
                        live, rank = F.static_rank_order(dec)
                        if dec['chosen'] not in rank:
                            continue
                        for i in live:
                            k = dec['kids'][i]
                            if i == dec['chosen']:
                                chosen.append(nrows)
                            ctx = F.kid_contexts(dec, k, rank[i])
                            if vectors is not None and len(vectors) < vmax and k['kind'] != 3:
                                d = {key: dec[key] for key in ('kind', 'f', 'index', 'stars', 'total', 'dist', 'tile',
                                                               'fwd', 'depth', 'intro', 'budget', 'used', 'prev')}
                                kk = {key: k[key] for key in ('ct', 'cc', 'ac', 'newfn', 'kind', 'stars', 'dist',
                                                              'dsteps', 'moved')}
                                vectors.append({'dec': d, 'kid': kk, 'rank': rank[i], 'ctx': ctx})
                            for c in ctx:
                                j = fz.idx(c, grow)
                                if j is not None:
                                    rows.append(nrows)
                                    cols.append(j)
                            nrows += 1
                        gstart.append(nrows)
    from scipy.sparse import csr_matrix
    X = csr_matrix((np.ones(len(rows)), (np.frombuffer(rows, dtype=np.int32), np.frombuffer(cols, dtype=np.int32))),
                   shape=(nrows, len(fz.index)))
    return X, np.array(gstart), np.array(chosen), nprogs, puzzles


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dump', action='append', required=True)
    ap.add_argument('--splits', required=True)
    ap.add_argument('--split', default='train')
    ap.add_argument('--l2', type=float, default=1.0)
    ap.add_argument('--out', required=True)
    ap.add_argument('--vectors', type=int, default=0)
    ap.add_argument('--vectors-out')
    a = ap.parse_args()
    split = json.load(open(a.splits))['split']
    dumps = []
    for d in a.dump:
        path, _, mult = d.partition(':')
        dumps.append((path, int(mult or 1)))
    fz = F.Featurizer()
    vectors = [] if a.vectors else None
    X, gstart, chosen, nprogs, puzzles = load_design(
        dumps, lambda i: split.get(str(i)) == a.split, fz, True, vectors, a.vectors)
    w = F.fit(X, gstart, chosen, a.l2)
    names = fz.names()
    weights = {names[j]: float(w[j]) for j in range(len(w)) if abs(w[j]) > 1e-9}
    meta = {'dumps': [f'{os.path.basename(p)}:{m}' for p, m in dumps], 'split': a.split, 'l2': a.l2,
            'programs': nprogs, 'puzzles': len(puzzles), 'decisions': int(len(gstart) - 1),
            'contexts': len(names), 'mean_bits': float(F.bits(X @ w, gstart, chosen).mean())}
    with open(a.out, 'w') as f:
        json.dump({'meta': meta, 'weights': weights}, f, indent=0, sort_keys=True)
    print(json.dumps(meta))
    if vectors is not None:
        for v in vectors:
            v['logit'] = sum(weights.get(c, 0.0) for c in v['ctx'])
        with open(a.vectors_out, 'w') as f:
            json.dump(vectors, f)
        print(f'{len(vectors)} test vectors -> {a.vectors_out}')


if __name__ == '__main__':
    main()
