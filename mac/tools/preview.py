#!/usr/bin/env python3
"""Render a pet's frames in the terminal so you can eyeball pixel art without building.

    python3 tools/preview.py Dog          # body + standing legs
    python3 tools/preview.py Dog --all    # base, alt, walk, air frames
    python3 tools/preview.py --check      # validate every pet's row widths

Reads Design/Pets/<Name>.swift directly; no Swift toolchain needed.
"""
import re, sys, glob, os

HERE = os.path.dirname(os.path.abspath(__file__))
PETS_DIR = os.path.join(HERE, '..', 'Design', 'Pets')
GLYPH = {'.': '  ', 'o': '██', 'e': '●●', 'w': '○○'}
FALLBACK = ['▒▒', '░░', '▓▓', '▚▚', '♥♥', '▞▞', '▙▙', '▟▟']

def load(name):
    src = open(os.path.join(PETS_DIR, name + '.swift')).read()
    def field(key):
        m = re.search(r'\b' + key + r':\s*\[(.*?)\]', src, re.S)
        return re.findall(r'"([^"]*)"', m.group(1)) if m else []
    return {k: field(k) for k in ['body', 'bodyAlt', 'legsStand', 'legsWalk', 'legsAir']}

def show(rows):
    glyphs = dict(GLYPH); i = 0
    for r in rows:
        out = ''
        for c in r:
            if c not in glyphs:
                glyphs[c] = FALLBACK[i % len(FALLBACK)]; i += 1
            out += glyphs[c]
        print(out)

def check(name, f):
    widths = {len(r) for k in f for r in f[k]}
    probs = []
    if len(widths) != 1: probs.append(f'{name}: mixed row widths {sorted(widths)}')
    if len(f['body']) != len(f['bodyAlt']): probs.append(f'{name}: body/bodyAlt row counts differ')
    if not (len(f['legsStand']) == len(f['legsWalk']) == len(f['legsAir'])): probs.append(f'{name}: legs row counts differ')
    return probs

args = sys.argv[1:]
if '--check' in args:
    bad = []
    for path in sorted(glob.glob(os.path.join(PETS_DIR, '*.swift'))):
        n = os.path.basename(path)[:-6]
        bad += check(n, load(n))
    print('\n'.join(bad) if bad else 'all pets OK')
    sys.exit(1 if bad else 0)

name = next((a for a in args if not a.startswith('-')), None)
if not name:
    print(__doc__); sys.exit(1)
f = load(name)
for p in check(name, f): print('WARNING:', p)
frames = [('base + stand', f['body'] + f['legsStand'])]
if '--all' in args:
    frames += [('alt + stand', f['bodyAlt'] + f['legsStand']),
               ('base + walk', f['body'] + f['legsWalk']),
               ('alt + air', f['bodyAlt'] + f['legsAir'])]
for title, rows in frames:
    print(f'--- {name}: {title} ---'); show(rows); print()
