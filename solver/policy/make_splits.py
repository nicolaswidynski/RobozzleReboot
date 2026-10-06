"""Writes the frozen family-level train / validation / test split
(splits.json) over the catalog and the archive puzzles.

Families: the union of "same author and title stem" and "identical board".
Each family goes wholly to one split by a hash of its smallest member:
70% train, 10% validation, 20% test. splits.json in this directory was made
with this script on 2026-10-06 and is frozen: never tune anything on test,
and do not regenerate it (the script refuses to overwrite it).

Usage: make_splits.py CATALOG.json ARCHIVE.json OUT.json
"""
import hashlib, json, os, re, sys


def stem(title):
    t = (title or '').lower()
    t = re.sub(r'\b(ii+|iv|v|vi+|ix|x|[0-9]+|part|level|version|the|a|an)\b', ' ', t)
    t = re.sub(r'[^a-z ]', ' ', t)
    return ' '.join(w for w in t.split() if len(w) > 2)


def main():
    catalog, archive, out = sys.argv[1:4]
    if os.path.exists(out):
        sys.exit(f'{out} exists: the split is frozen')
    puzzles = [(str(p['sourceId']), p) for p in json.load(open(catalog)) + json.load(open(archive))]
    parent = {i: i for i, _ in puzzles}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb, key=int)] = min(ra, rb, key=int)
    first = {}
    for i, p in puzzles:
        keys = ['board:' + hashlib.sha1('\n'.join(p['rows']).encode()).hexdigest()]
        s = stem(p.get('title'))
        if s:
            keys.append('fam:' + (p.get('author') or '').lower() + '|' + s)
        for k in keys:
            if k in first:
                union(i, first[k])
            else:
                first[k] = i

    def bucket(root):
        h = int(hashlib.sha256(('robozzle-split-2026-10-06:' + root).encode()).hexdigest(), 16) % 100
        return 'train' if h < 70 else 'val' if h < 80 else 'test'
    split = {i: bucket(find(i)) for i, _ in puzzles}
    doc = {'description': 'Frozen family-level split (2026-10-06). Families: same author and title stem, or identical '
                          'board. 70/10/20 by sha256 of the family root. Never tune on test.',
           'split': split}
    json.dump(doc, open(out, 'w'))
    print(f'{len(split)} puzzles -> {out}')


if __name__ == '__main__':
    main()
