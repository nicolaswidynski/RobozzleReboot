"""Feature schema and model of the learned LDS ordering (SPEC §17.3).

The model is log-linear over the live children ("kids") of a frontier: each
kid has a set of binary contexts, its logit is the sum of their weights, and
the policy is the softmax over the live kids. `kid_contexts` defines the 14
context templates; `src/policy.rs` computes exactly the same strings in the
solver (checked by `t_policy_vectors` on `test_vectors.json`).

Input rows come from `policy_dump` (src/bin/policy_dump.rs): one JSON line
per known program, with its decisions. A decision holds the frontier's
features and every child's features; `chosen` is the child that follows the
program. Child kinds: 0 open slot, 1 need-condition, 2 need-action,
3 solved, 4 dead (not live).
"""
import math

import numpy as np

ACT = {0: 'F', 1: 'L', 2: 'R', 3: 'Pr', 4: 'Pg', 5: 'Pb', 15: '?'}


def act_cat(k, dec):
    a = k['ac']
    ct = k['ct']
    if ct == 0:
        return 'END'
    if a == 15:
        return 'DEF'
    if a >= 6:
        g = a - 6
        if k['newfn']:
            return 'Cnew'
        if g == dec['f']:
            return 'Cself'
        if g == 0:
            return 'C1'
        return 'Cold'
    if 3 <= a <= 5:
        return 'P' + ('same' if (a - 3) == dec['tile'] else 'oth')
    return ACT[a]


def cond_cat(k, dec):
    ct, cc = k['ct'], k['cc']
    if ct == 0:
        return '-'
    if cc == 0:
        return 'any'
    if cc >= 4:
        return 'set'
    c = cc - 1
    if ct == 3:
        return 'pend'  # Any-or-current-color, undecided
    return 'cur' if c == dec['tile'] else 'oth'


def prev_cat(dec):
    p = dec['prev']
    if not p:
        return 'start'
    ct, cc, ac = p
    a = ACT.get(ac, 'C') if ac < 6 or ac == 15 else ('C%d' % (ac - 6) if (ac - 6) != dec['f'] else 'Cself')
    return '%d/%s/%s' % (ct, 'a' if cc == 0 else ('s' if cc >= 4 else 'c'), a)


def bucket(x, edges):
    for i, e in enumerate(edges):
        if x <= e:
            return i
    return len(edges)


def kid_contexts(dec, k, rank):
    """The 14 active contexts (feature keys) of one live child; `rank` is its
    rank under the static ordering."""
    fk = dec['kind']
    C = act_cat(k, dec) + '|' + cond_cat(k, dec) + '|' + str(k['ct'])
    dstar = k['stars'] - dec['stars']
    if k['kind'] == 3:
        out = 'SOLVED'
    else:
        dd = k['dist'] - dec['dist'] if dstar == 0 else 0
        out = 'k%d|s%d|d%d|m%d|t%d' % (k['kind'], min(dstar, 2), (dd > 0) - (dd < 0),
                                       int(k['moved']), bucket(k['dsteps'], [1, 4, 30, 300, 3000]))
    o_short = 'k%d|s%d|t%d' % (k['kind'], min(dstar, 2), bucket(k['dsteps'], [1, 4, 30, 300, 3000]))
    f0 = int(dec['f'] == 0)
    idx = min(dec['index'], 3)
    sf = dec['stars'] / max(dec['total'], 1)
    sfb = 0 if dec['stars'] == 0 else (1 if sf < 0.5 else 2)
    fwd = dec['fwd']
    fwdc = 'void' if fwd == 0 else ('same' if fwd - 1 == dec['tile'] else 'oth')
    return [
        'C:' + C,
        'CK:%s:%d' % (C, fk),
        'CP:%s:%s' % (C, prev_cat(dec)),
        'CI:%s:%d:%d' % (C, idx, f0),
        'O:' + out,
        'OC:%s:%s' % (o_short, C),
        'CW:%s:%s' % (C, fwdc),
        'CD:%s:%d' % (C, min(dec['depth'], 2)),
        'CS:%s:%d' % (C, sfb),
        'CN:%s:%d:%d' % (C, dec['intro'], int(k['newfn'])),
        'CB:%s:%d' % (C, bucket(dec['budget'] - dec['used'], [2, 5, 9])),
        'OK:%s:%d' % (out, fk),
        'rank%d' % min(rank, 12),
        'rankK%d:%d' % (min(rank, 6), fk),
    ]


def static_rank_order(dec):
    """Live kids sorted by the static score; returns (live indices, rank of
    each). A solved kid ends LDS at once, so it ranks first."""
    live = [i for i, k in enumerate(dec['kids']) if k['kind'] != 4]
    keyed = []
    for i in live:
        k = dec['kids'][i]
        keyed.append(((0,) if k['kind'] == 3 else (1,) + tuple(k['score']), i))
    keyed.sort()
    rank = {i: r for r, (_, i) in enumerate(keyed)}
    return live, rank


class Featurizer:
    """Maps context strings to column indices (grows only when training)."""

    def __init__(self):
        self.index = {}

    def idx(self, key, grow):
        j = self.index.get(key)
        if j is None and grow:
            j = self.index[key] = len(self.index)
        return j

    def names(self):
        out = [None] * len(self.index)
        for k, j in self.index.items():
            out[j] = k
        return out


def group_logsoftmax(z, gstart):
    n = len(gstart) - 1
    sizes = np.diff(gstart)
    gid = np.repeat(np.arange(n), sizes)
    mx = np.maximum.reduceat(z, gstart[:-1])
    e = np.exp(z - mx[gid])
    s = np.add.reduceat(e, gstart[:-1])
    return z - mx[gid] - np.log(s)[gid], gid, e / s[gid]


def fit(X, gstart, chosen, l2=1.0, maxiter=500):
    """Maximum likelihood of the chosen kids with an L2 penalty (convex)."""
    from scipy.optimize import minimize
    m = X.shape[1]

    def f(w):
        z = X @ w
        lp, gid, p = group_logsoftmax(z, gstart)
        loss = -lp[chosen].sum() + 0.5 * l2 * (w @ w)
        g = X.T @ p - np.asarray(X[chosen].sum(axis=0)).ravel() + l2 * w
        return loss, g

    res = minimize(f, np.zeros(m), jac=True, method='L-BFGS-B', options={'maxiter': maxiter})
    return res.x


def bits(z, gstart, chosen):
    lp, _, _ = group_logsoftmax(z, gstart)
    return -lp[chosen] / math.log(2)
