"""Collects the solved programs of solver output files into the
`policy_dump` input format {"<sourceId>": [program, ...]} (deduplicated).

Usage: build_corpus.py --catalog CATALOG.json --out programs.json FILE_OR_GLOB...

Every input is a solver output (`{"results": [...]}`, as written by
`solver --out` or `solver/ledger.json`); rows with status "solved" for
puzzles of CATALOG are kept. `policy_dump` re-verifies every program.
"""
import argparse, glob, json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--catalog', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('inputs', nargs='+')
    a = ap.parse_args()
    ids = {str(p['sourceId']) for p in json.load(open(a.catalog))}
    progs, seen, files = {}, set(), 0
    for pattern in a.inputs:
        for path in sorted(glob.glob(pattern)):
            try:
                rows = json.load(open(path)).get('results') or []
            except (OSError, ValueError, AttributeError):
                continue
            files += 1
            for r in rows:
                i = str(r.get('sourceId'))
                if r.get('status') != 'solved' or i not in ids:
                    continue
                key = (i, json.dumps(r['program']))
                if key not in seen:
                    seen.add(key)
                    progs.setdefault(i, []).append(r['program'])
    json.dump(progs, open(a.out, 'w'))
    print(f'{files} files: {len(progs)} puzzles, {len(seen)} distinct programs -> {a.out}')


if __name__ == '__main__':
    main()
