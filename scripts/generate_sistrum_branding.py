#!/usr/bin/env python3
"""Derive icon inputs from the owner's logo (requires Pillow).

Run this script, then `dart run flutter_launcher_icons`. Full-colour artwork is
never recoloured/cropped. Only the Android-required white mask loses colour.
The dark background is logo2.png's top-left pixel; logo.png is the chosen mark.
"""
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = (18, 16, 14, 255)


def simplify(points, epsilon=0.45):
    """Ramer-Douglas-Peucker simplification of a traced alpha boundary."""
    if len(points) < 3:
        return points
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    maximum, index = 0, 0
    for i, (x, y) in enumerate(points[1:-1], 1):
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / length)) if length else 0
        distance = (x - ax - t * dx) ** 2 + (y - ay - t * dy) ** 2
        if distance > maximum:
            maximum, index = distance, i
    if maximum <= epsilon * epsilon:
        return [points[0], points[-1]]
    return simplify(points[:index + 1], epsilon)[:-1] + simplify(points[index:], epsilon)


def trace_mask(alpha):
    """Trace exposed pixel edges, retaining interior holes in the silhouette."""
    size = alpha.width
    pixels = alpha.load()
    edges = {}

    def filled(x, y):
        return 0 <= x < size and 0 <= y < size and pixels[x, y] >= 128

    def edge(a, b):
        edges.setdefault(a, []).append(b)

    for y in range(size):
        for x in range(size):
            if not filled(x, y):
                continue
            if not filled(x, y - 1):
                edge((x, y), (x + 1, y))
            if not filled(x + 1, y):
                edge((x + 1, y), (x + 1, y + 1))
            if not filled(x, y + 1):
                edge((x + 1, y + 1), (x, y + 1))
            if not filled(x - 1, y):
                edge((x, y + 1), (x, y))
    paths = []
    while edges:
        start = next(iter(edges))
        points = [start]
        current = start
        while True:
            following = edges[current].pop()
            if not edges[current]:
                del edges[current]
            points.append(following)
            current = following
            if current == start:
                break
        area = abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:]))) / 2
        # Drop isolated subpixel specks, not meaningful mark components.
        if area < 2:
            continue
        points = simplify(points)
        paths.append('M' + ' L'.join(f'{x},{y}' for x, y in points[:-1]) + ' Z')
    return ' '.join(paths)


def main():
    source = ROOT / 'logo/logo.png'
    logo = Image.open(source).convert('RGBA')
    if logo.width != logo.height:
        raise ValueError('The supplied mark must remain square; do not stretch it')
    for name in ['icon.png', 'icon_foreground_android.png', 'assets/images/logo.png',
                 'assets/images/logo-transparent.png']:
        shutil.copyfile(source, ROOT / name)
    # Match the adaptive 16% inset in the legacy launcher composition as well.
    legacy = Image.new('RGBA', logo.size, BACKGROUND)
    side = round(logo.width * 0.68)
    inset = (logo.width - side) // 2
    legacy.alpha_composite(logo.resize((side, side), Image.Resampling.LANCZOS), (inset, inset))
    legacy.convert('RGB').save(ROOT / 'icon_android.png')
    white = Image.new('RGBA', logo.size, 'white')
    white.putalpha(logo.getchannel('A'))
    white.save(ROOT / 'icon_monochrome_android.png')
    alpha = logo.getchannel('A').resize((192, 192), Image.Resampling.LANCZOS)
    path = trace_mask(alpha)
    vector = f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from logo/logo.png by scripts/generate_sistrum_branding.py. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="192" android:viewportHeight="192">
    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"
        android:pathData="{path}" />
</vector>
'''
    (ROOT / 'android/app/src/main/res/drawable/ic_stat_sistrum.xml').write_text(vector)


if __name__ == '__main__':
    main()
