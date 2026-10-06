"""Converts the robozzle.com level archive into the catalog format, for
puzzles not in assets/levels_catalog.json (held-out data for the learned
ordering).

Source: https://github.com/lostmsu/RoboZZle.LevelArchive (levels.xml,
commit 56d4d73, 9,842 puzzles). Cropping each board to the bounding box of
its non-void tiles reproduces the catalog's rows, start and slots exactly
on the 901 puzzles both contain.

Usage: convert_archive.py levels.xml CATALOG.json OUT.json
OUT.json holds the archive puzzles not in CATALOG (8,941 at that commit),
with two extra fields: humanSolutions and inCatalog (false).
"""
import json, sys
import xml.etree.ElementTree as ET

NS = {'a': 'http://schemas.datacontract.org/2004/07/RoboCoder.GameState',
      's': 'http://schemas.microsoft.com/2003/10/Serialization/Arrays'}
DIRS = {'0': 'right', '1': 'down', '2': 'left', '3': 'up'}


def main():
    src, catalog, out_path = sys.argv[1:4]
    cat = {int(x['sourceId']) for x in json.load(open(catalog))}
    out = []
    for lv in ET.parse(src).getroot().findall('a:LevelInfo2', NS):
        def g(k):
            return lv.find('a:' + k, NS)
        i = int(g('Id').text)
        if i in cat:
            continue
        colors = [x.text for x in g('Colors').findall('s:string', NS)]
        items = [x.text for x in g('Items').findall('s:string', NS)]
        grid = [[(' ' if it == '#' else (ch.upper() if it == '*' else ch.lower())) for ch, it in zip(cr, ir)]
                for cr, ir in zip(colors, items)]
        cells = [(r, c) for r, row in enumerate(grid) for c, v in enumerate(row) if v != ' ']
        r0, r1 = min(r for r, _ in cells), max(r for r, _ in cells)
        c0, c1 = min(c for _, c in cells), max(c for _, c in cells)
        votes, vsum = int(g('DifficultyVoteCount').text), int(g('DifficultyVoteSum').text)
        out.append(dict(sourceId=i, title=g('Title').text or '', author=g('SubmittedBy').text or '',
                        difficulty=round(vsum / votes, 2) if votes else 0.0, popularity=int(g('Liked').text),
                        about=g('About').text or '', rows=[''.join(grid[r][c0:c1 + 1]) for r in range(r0, r1 + 1)],
                        startRow=int(g('RobotRow').text) - r0, startCol=int(g('RobotCol').text) - c0,
                        startDirection=DIRS[g('RobotDir').text],
                        slotsPerFunction=[int(x.text) for x in g('SubLengths').findall('s:int', NS)],
                        allowedCommands=int(g('AllowedCommands').text), humanSolutions=int(g('Solutions').text),
                        inCatalog=False))
    json.dump(out, open(out_path, 'w'))
    print(f'{len(out)} archive puzzles not in the catalog -> {out_path}')


if __name__ == '__main__':
    main()
