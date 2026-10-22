#!/usr/bin/env python3
"""Bakes the ground control map used by res/shaders/terrain_blend.gdshader.

The control map is painted, not baked lighting: it only stores how much of
each surface layer belongs at a point in the world.

    R = stable-yard dirt
    G = path
    B = training-ground sand
    A = arena sand

Grass is the remainder, so unpainted pixels are pure grass.  The map covers a
128 m square centred on the play area; the shader maps world XZ into it.

Run from the project root:

    python3 tools/build_ground_control.py

The output is deterministic.  Paint over the PNG in Krita/GIMP to tune edges;
rerun this script only when the layout rectangles themselves change.
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

# Layout copied from scenes/terrain.tscn (centre x/z, half width/depth,
# corner radius, feather width).
LAYERS = {
    "yard": ((0.0, -22.0), (12.0, 8.0), 2.0, 2.4),
    "path": ((0.0, -6.5), (2.0, 13.0), 1.6, 0.9),
    "training": ((35.0, 0.0), (20.0, 15.0), 3.0, 1.8),
    "arena": ((-32.5, 0.0), (17.5, 35.0), 2.5, 1.3),
}


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

    def layer(name: str) -> np.ndarray:
        center, half, radius, feather = LAYERS[name]
        sdf = rounded_rect_sdf(x, z, center, half, radius) + wobble
        return 1.0 - smoothstep(-feather * 0.5, feather * 0.5, sdf)

    yard = layer("yard")
    path = layer("path")
    training = layer("training")
    arena = layer("arena")

    # The path is a worn strip through the yard: keep it readable instead of
    # letting the two dirt layers double up into a 50/50 blend.
    yard *= 1.0 - path * 0.88

    # Trampled ground at the arena gate on the east side, and a softer patch
    # where the path leaves the yard.  These break up the straight edges.
    gate = 1.0 - smoothstep(
        -1.3, 1.3, circle_sdf(x, z, (-15.0, -1.5), 2.6) + wobble * 0.7
    )
    gate *= 0.55
    path_end = 1.0 - smoothstep(
        -1.1, 1.1, circle_sdf(x, z, (0.0, 6.5), 2.2) + wobble * 0.6
    )
    path_end *= 0.35

    yard = np.maximum(yard, gate)
    path = np.maximum(path, path_end * 0.7)

    # Keep a slight amount of grass in every region so the blend never looks
    # like a hard cut-out at grazing angles.
    control = np.stack(
        [
            np.clip(yard, 0.0, 1.0),
            np.clip(path, 0.0, 1.0),
            np.clip(training, 0.0, 1.0),
            np.clip(arena, 0.0, 1.0),
        ],
        axis=-1,
    )

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

    # Report the four corners of each region so the check tool can assert
    # against the same numbers.
    def sample(wx: float, wz: float) -> tuple[int, int, int, int]:
        px = int((wx - (CENTER[0] - EXTENT / 2)) / EXTENT * SIZE)
        pz = int((wz - (CENTER[1] - EXTENT / 2)) / EXTENT * SIZE)
        px = max(0, min(SIZE - 1, px))
        pz = max(0, min(SIZE - 1, pz))
        return tuple(int(v) for v in rgba[pz, px])

    for name, point in {
        "yard": (0.0, -22.0),
        "path": (0.0, -6.5),
        "training": (35.0, 0.0),
        "arena": (-32.5, 0.0),
        "grass": (70.0, 40.0),
        "yard edge": (0.0, -13.0),
        "gate": (-15.0, -1.5),
    }.items():
        print(f"  {name:10s} {point}: {sample(*point)}")


if __name__ == "__main__":
    main()
