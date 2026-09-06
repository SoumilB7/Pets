#!/usr/bin/env python3
"""Render Design/Pets/Dog.swift into build/AppIcon.icns (pure Python + macOS iconutil)."""
import re, os, zlib, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
src = open(os.path.join(ROOT, 'Design', 'Pets', 'Dog.swift')).read()
pal = {}
for m in re.finditer(r'"(.)":\s*rgb\(([\d.]+),\s*([\d.]+),\s*([\d.]+)\)', src):
    pal[m.group(1)] = tuple(int(float(m.group(i)) * 255) for i in (2, 3, 4))
pal.setdefault('o', (59, 41, 59))
for m in re.finditer(r'"(.)":\s*OUT', src): pal[m.group(1)] = (59, 41, 59)
def field(key):
    m = re.search(r'\b' + key + r':\s*\[(.*?)\]', src, re.S)
    return re.findall(r'"([^"]*)"', m.group(1))
rows = field('body') + field('legsStand')
W = len(rows[0]); H = len(rows)
SIZE = 1024; cell = SIZE // (max(W, H) + 2)
ox = (SIZE - W * cell) // 2; oy = (SIZE - H * cell) // 2
img = bytearray(SIZE * SIZE * 4)
# rounded orange background tile like a macOS icon
bg = (255, 232, 200)
r = SIZE // 5
for yy in range(SIZE):
    for xx in range(SIZE):
        dx = max(r - xx, 0, xx - (SIZE - 1 - r)); dy = max(r - yy, 0, yy - (SIZE - 1 - r))
        if dx * dx + dy * dy <= r * r and 60 <= xx < SIZE - 60 and 60 <= yy < SIZE - 60:
            i = (yy * SIZE + xx) * 4; img[i:i+4] = bytes(bg) + b'\xff'
for ry, row in enumerate(rows):
    for rx, c in enumerate(row):
        if c == '.': continue
        col = pal.get(c, (0, 0, 0))
        for yy in range(oy + ry * cell, oy + (ry + 1) * cell):
            for xx in range(ox + rx * cell, ox + (rx + 1) * cell):
                i = (yy * SIZE + xx) * 4; img[i:i+4] = bytes(col) + b'\xff'
raw = b''.join(b'\x00' + bytes(img[y*SIZE*4:(y+1)*SIZE*4]) for y in range(SIZE))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
out = os.path.join(ROOT, 'build'); os.makedirs(out, exist_ok=True)
iconset = os.path.join(out, 'AppIcon.iconset'); os.makedirs(iconset, exist_ok=True)
big = os.path.join(out, 'icon1024.png'); open(big, 'wb').write(png)
for s in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon_{s}x{s}' + ('@2x' if scale == 2 else '') + '.png'
        subprocess.run(['sips', '-z', str(s*scale), str(s*scale), big, '--out', os.path.join(iconset, name)], check=True, capture_output=True)
subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', os.path.join(out, 'AppIcon.icns')], check=True)
print('icon ok')
