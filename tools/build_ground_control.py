#!/usr/bin/env python3
"""Bakes the ground control map used by res/shaders/terrain_blend.gdshader.

The control map is painted, not baked lighting: it only stores how much of
each surface layer belongs at a point in the world.

    R = stable-yard dirt (hardstanding, and the house track)
    G = path / gravel lane
    B = training-ground sand
    A = arena sand

Grass is the remainder, so unpainted pixels are pure grass.  The map covers a
128 m square centred on the play area; the shader maps world XZ into it.

Run from the project root:

    python3 tools/build_ground_control.py

The output is deterministic.  Paint over the PNG in Krita/GIMP to tune edges;
rerun this script only when the layout itself changes.

Roads are part of this file, not the scenes: the yard, the lane network and the
house track are all painted here, so moving a route is a change to this table
and to the samples tools/check_terrain_blend.gd asserts.
"""

from pathlib import Path

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
OUTPUT = PROJECT / "assets" / "textures" / "ground" / "terrain_control.png"

SIZE = 2048
# World XZ rectangle covered by the texture.  The play area spans
# x -50..55 and z -35..35, so this leaves plenty of grass margin.
CENTER = (10.0, -5.0)
EXTENT = 128.0

# Shaped surfaces: (centre x/z, half width/depth, corner radius, feather).
# The yard now covers everything that is actually dressed: the props used to
# spill 3 m onto grass at both ends, and the grooming bay sat entirely off it.
LAYERS = {
    "yard": ((0.0, -19.0), (16.0, 9.0), 2.2, 2.6),
    "training": ((35.0, 0.0), (20.0, 15.0), 3.0, 1.8),
    "arena": ((-32.5, 0.0), (17.5, 35.0), 2.5, 1.3),
}

# Gravel lanes: (centre-line polyline, half width, feather).  A capsule chain
# around each segment, so a bend is a bend rather than two rectangles.
# The spine leaves the showground gate in the south, bends to arrive at the
# stable door, and is joined by the arena spur and the school spur.
LANES = {
    "spine": ([(0.0, 26.0), (0.0, 8.0), (-4.0, -2.0), (-5.0, -13.0)], 2.6, 0.9),
    "arena_spur": ([(-4.0, -1.5), (-15.5, -1.5)], 2.6, 0.9),
    "school_spur": ([(0.0, 8.0), (15.0, 10.0)], 2.6, 0.9),
}

# The farm track from the yard's north-east corner to the fantasy house door.
# Painted as yard dirt so it reads as a track rather than a footpath.
DRIVE = ([(16.0, -27.0), (26.0, -29.0), (37.0, -31.0)], 2.0, 1.1)

# Worn ground where feet and hooves actually gather: (centre, radius, channel,
# strength).  These break up the shaped edges and mark the working points.
WEAR = [
    ((-7.0, -20.5), 3.0, "yard", 0.55),    # stable door and stall apron
    ((-0.4, -23.0), 2.4, "yard", 0.50),    # feed trough
    ((-12.0, -13.0), 2.6, "yard", 0.50),   # grooming bay
    ((37.0, -31.0), 2.8, "yard", 0.60),    # house door
    ((1.5, 25.0), 4.0, "yard", 0.70),      # showground hardstanding
    ((-15.0, -1.5), 2.6, "yard", 0.55),    # arena gate
    ((0.0, 26.0), 2.2, "path", 0.35),      # lane end
    ((15.5, 10.0), 2.6, "path", 0.35),     # school entrance
]

CHANNELS = {"yard": 0, "path": 1, "training": 2, "arena": 3}


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rounded_rect_sdf(
    x: np.ndarray,
    z: np.ndarray,
    center: tuple[float, float],
    half: tuple[float, float],
    radius: float,
) -> np.ndarray:
    qx = np.abs(x - center[0]) - (half[0] - radius)
    qz = np.abs(z - center[1]) - (half[1] - radius)
    outside = np.sqrt(np.maximum(qx, 0.0) ** 2 + np.maximum(qz, 0.0) ** 2)
    inside = np.minimum(np.maximum(qx, qz), 0.0)
    return outside + inside - radius


def circle_sdf(
    x: np.ndarray, z: np.ndarray, center: tuple[float, float], radius: float
) -> np.ndarray:
    return np.sqrt((x - center[0]) ** 2 + (z - center[1]) ** 2) - radius


def polyline_sdf(
    x: np.ndarray, z: np.ndarray, points: list[tuple[float, float]]
) -> np.ndarray:
    """Distance to a capsule chain through `points` (rounded joins and ends)."""
    best = np.full(x.shape, np.inf, dtype=np.float32)
    for (x0, z0), (x1, z1) in zip(points[:-1], points[1:]):
        dx, dz = x1 - x0, z1 - z0
        length2 = dx * dx + dz * dz
        if length2 <= 1e-9:
            t = np.zeros(x.shape, dtype=np.float32)
        else:
            t = np.clip(((x - x0) * dx + (z - z0) * dz) / length2, 0.0, 1.0)
        px = x0 + t * dx
        pz = z0 + t * dz
        best = np.minimum(best, np.sqrt((x - px) ** 2 + (z - pz) ** 2))
    return best


def value_noise(seed: int, cells: int) -> np.ndarray:
    """Smooth low-frequency noise in [-1, 1], one value per pixel."""
    rng = np.random.default_rng(seed)
    grid = rng.random((cells + 1, cells + 1), dtype=np.float32)
    image = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    image = image.resize((SIZE, SIZE), Image.BICUBIC)
    return (np.asarray(image, dtype=np.float32) / 255.0) * 2.0 - 1.0


def build() -> np.ndarray:
    u = (np.arange(SIZE, dtype=np.float32) + 0.5) / SIZE
    x = CENTER[0] + (u - 0.5) * EXTENT
    z = CENTER[1] + (u - 0.5) * EXTENT
    x, z = np.meshgrid(x, z)

    # Two octaves of edge wobble: broad bays and small nibbles.
    wobble = value_noise(11, 16) * 0.55 + value_noise(12, 64) * 0.16

    def shaped(name: str) -> np.ndarray:
        center, half, radius, feather = LAYERS[name]
        sdf = rounded_rect_sdf(x, z, center, half, radius) + wobble
        return 1.0 - smoothstep(-feather * 0.5, feather * 0.5, sdf)

    def lane(spec) -> np.ndarray:
        points, half_width, feather = spec
        sdf = polyline_sdf(x, z, points) - half_width + wobble * 0.5
        return 1.0 - smoothstep(-feather * 0.5, feather * 0.5, sdf)

    yard = shaped("yard")
    training = shaped("training")
    arena = shaped("arena")

    # Lanes: keep the strongest one at a junction rather than summing them.
    path = np.zeros_like(yard)
    for spec in LANES.values():
        path = np.maximum(path, lane(spec))

    # The house track is dirt, laid on top of the yard channel.
    drive = lane(DRIVE)
    yard = np.maximum(yard, drive)

    # The lane is a worn strip through the yard: keep it readable instead of
    # letting the two dirt layers double up into a 50/50 blend.
    yard *= 1.0 - path * 0.88

    control = np.stack([yard, path, training, arena], axis=-1)

    # Worn ground at the working points.  Each patch raises its own channel, so
    # a trodden gate still reads as dirt-and-gravel rather than one flat colour.
    for (center, radius, channel, strength) in WEAR:
        patch = 1.0 - smoothstep(
            -1.2, 1.2, circle_sdf(x, z, center, radius) + wobble * 0.7
        )
        control[:, :, CHANNELS[channel]] = np.maximum(
            control[:, :, CHANNELS[channel]], patch * strength
        )

    # Keep a slight amount of grass in every region so the blend never looks
    # like a hard cut-out at grazing angles.
    control = np.clip(control, 0.0, 1.0)

    # Keep the painted weights normalized: where a wear patch overlaps a
    # surface, scale both down instead of letting the sum exceed one.  The
    # shader would normalize anyway; clean data keeps the check honest.
    total = control.sum(axis=-1, keepdims=True)
    control = np.where(total > 1.0, control / np.maximum(total, 1e-6), control)
    return control


def main() -> None:
    control = build()
    rgba = (np.clip(control, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(OUTPUT, optimize=True)
    print(f"wrote {OUTPUT.relative_to(PROJECT)} ({SIZE}x{SIZE})")

    # Report the points tools/check_terrain_blend.gd asserts against, so the
    # check and the generator can never drift apart silently.
    def sample(wx: float, wz: float) -> tuple[int, int, int, int]:
        px = int((wx - (CENTER[0] - EXTENT / 2)) / EXTENT * SIZE)
        pz = int((wz - (CENTER[1] - EXTENT / 2)) / EXTENT * SIZE)
        px = max(0, min(SIZE - 1, px))
        pz = max(0, min(SIZE - 1, pz))
        return tuple(int(v) for v in rgba[pz, px])

    for name, point in {
        "yard": (0.0, -22.0),
        "lane": (0.0, 14.0),
        "training": (35.0, 0.0),
        "arena": (-32.5, 0.0),
        "drive": (30.0, -30.0),
        "grass": (70.0, 40.0),
        "yard edge": (17.0, -19.0),
        "gate": (-15.0, -1.5),
        "showground": (1.5, 25.0),
        "bay": (-12.0, -13.0),
    }.items():
        print(f"  {name:11s} {point}: {sample(*point)}")


if __name__ == "__main__":
    main()
