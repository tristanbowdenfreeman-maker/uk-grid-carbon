"""Build site/map.json, the outline of the 14 regions for the Where and when page, from NESO's
GB DNO licence area boundaries (GeoJSON, British National Grid metres).

Run once; the output is committed with the site, because region boundaries don't change:
    python tools/build_map.py path/to/gb-dno-license-areas.geojson

Download: https://www.neso.energy/data-portal/gis-boundaries-gb-dno-license-areas
Each area's Name ends in its GSP group letter, the same letter Octopus prices by, so the letter
maps it to a Carbon Intensity API region (TARIFF_REGIONS).
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from grid_carbon.sources import TARIFF_REGIONS  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "site" / "map.json"
TOLERANCE = 1800        # metres: simplification error allowed
MIN_AREA = 60e6         # square metres: islands smaller than this are dropped
SCALE = 1 / 1000        # metres -> kilometres in the SVG


def simplify(points, tolerance):
    """Douglas-Peucker on a closed ring, split at the point farthest from the start (a ring's
    first and last points are the same, which leaves the plain algorithm no line to measure from)."""
    if len(points) < 4:
        return points
    sx, sy = points[0]
    far = max(range(len(points)), key=lambda i: (points[i][0] - sx) ** 2 + (points[i][1] - sy) ** 2)
    keep = [False] * len(points)
    keep[0] = keep[far] = keep[-1] = True
    stack = [(0, far), (far, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = points[a], points[b]
        dx, dy = x2 - x1, y2 - y1
        length = (dx * dx + dy * dy) ** 0.5 or 1
        best, index = 0, None
        for i in range(a + 1, b):
            x, y = points[i]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / length
            if d > best:
                best, index = d, i
        if index is not None and best > tolerance:
            keep[index] = True
            stack += [(a, index), (index, b)]
    return [p for p, k in zip(points, keep) if k]


def area(ring):
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ring, ring[1:]))) / 2


def main(source: str) -> None:
    features = json.loads(Path(source).read_text())["features"]
    rings_by_region, xs, ys = {}, [], []
    for feature in features:
        region_id = TARIFF_REGIONS[feature["properties"]["Name"].lstrip("_")]
        for polygon in feature["geometry"]["coordinates"]:
            outer = polygon[0]
            if area(outer) < MIN_AREA:
                continue
            ring = simplify(outer, TOLERANCE)
            if len(ring) >= 4:
                rings_by_region.setdefault(region_id, []).append(ring)
                xs += [x for x, _ in ring]
                ys += [y for _, y in ring]
    x0, y1 = min(xs), max(ys)
    paths = {
        region_id: "".join(
            "M" + "L".join(f"{(x - x0) * SCALE:.1f},{(y1 - y) * SCALE:.1f}" for x, y in ring[:-1]) + "Z"
            for ring in rings
        )
        for region_id, rings in sorted(rings_by_region.items())
    }
    width, height = (max(xs) - x0) * SCALE, (y1 - min(ys)) * SCALE
    OUT.write_text(json.dumps({"viewBox": f"0 0 {width:.0f} {height:.0f}", "regions": paths}, separators=(",", ":")))
    print(f"{OUT.name}: {OUT.stat().st_size / 1024:.0f} KB, {len(paths)} regions")


if __name__ == "__main__":
    main(sys.argv[1])
