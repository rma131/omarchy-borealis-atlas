# The globe's coastlines

`coastline.js` is the only bundled data in this repository that is not code, so
here is where it came from and how to make it again. It is 925 coordinate
pairs — about 10 KB of source — and it exists so that the small globe beside
the place name shows continents you can recognise rather than a bare grid.

## Source

**Natural Earth 1:110m physical coastline**, public domain (CC0), from the
canonical mirror:

```
https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_coastline.geojson
```

Natural Earth asks for no attribution and imposes no conditions — *"you may use
the maps in any manner, including modifying the content and design"* — so it is
compatible with this repository's MIT licence and with the marketplace's
requirement that bundled assets be ours to ship. It is credited here because
that is the decent thing, not because it is required.

## Method

5128 vertices in, 925 out:

1. **Douglas–Peucker** simplification at a **0.9°** tolerance, in lon/lat
   degrees. No projection first — the globe is orthographic and re-projects
   every vertex at paint time anyway, so simplifying in the source coordinate
   system is both simpler and closer to what is drawn.
2. **Quantise to tenths of a degree**, as integers, and drop consecutive
   duplicates.
3. **Drop any stroke left with fewer than 4 vertices** — specks that would draw
   as a dot or not at all.

## Why 0.9° and a tenth of a degree

The globe is drawn about a hundred pixels across and shows one hemisphere, so
180° of arc maps to roughly 100 px: **one pixel is about 1.8°**, or 200 km.

- A tenth of a degree is already an order of magnitude finer than a pixel, so
  the quantisation is free.
- Below about 400 vertices the continents stop being recognisable, and the
  first shapes to go are Italy, the Red Sea, Hudson Bay and the Baltic — which
  are exactly the ones people use to orient themselves.
- Above about 1500 you are paying source size for detail finer than a pixel.

925 sits in the middle of that, and was checked by rendering the globe centred
on Toronto, Amsterdam, Quito and Cyprus at the real drawn size.

## Regenerate

Save as `mkcoast.py` beside a downloaded `ne110.geojson`:

```python
#!/usr/bin/env python3
import json, math, sys

TOL = float(sys.argv[1]) if len(sys.argv) > 1 else 0.9   # degrees
MINPTS = 4

def perp(p, a, b):
    (x, y), (x1, y1), (x2, y2) = p, a, b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(x - x1, y - y1)
    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (x1 + t * dx), y - (y1 + t * dy))

def dp(pts, tol):
    if len(pts) < 3:
        return pts
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = perp(pts[i], pts[0], pts[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax > tol:
        return dp(pts[:idx + 1], tol)[:-1] + dp(pts[idx:], tol)
    return [pts[0], pts[-1]]

j = json.load(open("ne110.geojson"))
paths = []
for f in j["features"]:
    g = f["geometry"]
    segs = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
    for seg in segs:
        s = dp([(float(a), float(b)) for a, b in seg], TOL)
        q, prev = [], None
        for x, y in s:
            v = (int(round(x * 10)), int(round(y * 10)))
            if v != prev:
                q.append(v); prev = v
        if len(q) >= MINPTS:
            paths.append(q)
print("%d paths, %d vertices" % (len(paths), sum(len(p) for p in paths)))
print(",\n    ".join("[" + ",".join("%d,%d" % v for v in p) + "]" for p in paths))
```

```sh
curl -fsSLO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_coastline.geojson
mv ne_110m_coastline.geojson ne110.geojson
python3 mkcoast.py 0.9
```

Paste the output into `coastline.js`'s `paths` array and update the vertex
count in its header comment. Tolerances of 0.6 and 1.3 give 1382 and 667
vertices respectively, if you want it finer or lighter.

## Removing the globe

`Globe.qml` and `coastline.js` are the whole feature. Delete both, and delete
the `Globe { … }` block in `BorealisAtlas.qml`, and nothing else changes.
