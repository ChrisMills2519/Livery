#!/usr/bin/env python3
"""Builds the farmhouse interior's neutral detail maps.

    python3 tools/make_interior_detail.py

Output (committed, 512x512 except the metal map at 256x256):

    Models/interior/textures/detail_wood_diff_512.jpg
    Models/interior/textures/detail_fabric_diff_512.jpg
    Models/interior/textures/detail_stone_diff_512.jpg
    Models/interior/textures/detail_metal_diff_256.jpg

The maps are deliberately *neutral luminance*, not colour: every pixel sits
around 0.90 grey, so StandardMaterial3D multiplies them over the furniture's
existing albedo colour and the farmhouse palette does not change.  That is what
lets one wood map serve the pale kit wood, the dark trim and the painted
cabinets without per-prop recolouring, and why they cost one texture fetch per
fragment instead of a full PBR set.

Sources (all CC0, recorded in Models/interior/SOURCE.txt):

  wood   Poly Haven "Angli Veneer" 1k diffuse, fine natural grain.
  fabric Poly Haven "Book Pattern" 1k colour map, coarse plain-weave cotton.
  stone  The project's own Poly Haven "Painted Plaster Wall" 1k diffuse.
  metal  High-pass of the same veneer, streaked horizontally, so fittings read
         as brushed metal rather than noise.

Poly Haven's public files API is documented at https://api.polyhaven.com/files
and the 1k JPEGs are downloaded through it.  Downloaded sources are cached in
build/tmp/interior_src (git-ignored); delete that folder to re-fetch.

Every map is resized down from the 1k source and saved as a grey JPEG at
quality 90.  They are mipmapped and lossless in Godot (see the .import files):
this machine has no VRAM and crashes on VRAM-compressed textures.

The maps are written as three-channel RGB even though every channel holds the
same value.  A single-channel JPEG imports as a luminance texture, and a
driver that samples that without a channel swizzle reads it as (grey, 0, 0) -
which paints every surface that uses the map pure red.
"""

from __future__ import annotations

import os
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Models", "interior", "textures")
CACHE_DIR = os.path.join(ROOT, "build", "tmp", "interior_src")
PLASTER = os.path.join(OUT_DIR, "painted_plaster_wall_diff_1k.jpg")

SOURCES = {
    "angli_veneer_diff_1k.jpg": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/"
        "angli_veneer/angli_veneer_diff_1k.jpg"
    ),
    "book_pattern_col1_1k.jpg": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/"
        "book_pattern/book_pattern_col1_1k.jpg"
    ),
}

# The mean every map is normalised to, and the gain the material book applies
# to the albedo colour so the multiplication keeps the kit's own tone.
DETAIL_MEAN = 0.90


def fetch(name: str) -> str:
    """Returns a cached copy of one Poly Haven 1k JPEG, downloading if needed."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, name)
    if not os.path.exists(path):
        print("fetching", SOURCES[name])
        request = urllib.request.Request(
            SOURCES[name], headers={"User-Agent": "groom-asset-fetch/1.0"}
        )
        with urllib.request.urlopen(request, timeout=180) as response:
            data = response.read()
        with open(path, "wb") as handle:
            handle.write(data)
    return path


def wrapped(image: Image.Image, build) -> Image.Image:
    """Runs `build` on a 3x3 tile and keeps the centre, so filters wrap."""
    width, height = image.size
    tiled = Image.new(image.mode, (width * 3, height * 3))
    for x in range(3):
        for y in range(3):
            tiled.paste(image, (x * width, y * height))
    result = build(tiled)
    return result.crop((width, height, width * 2, height * 2))


def grey(path: str, size: int) -> np.ndarray:
    """Loads an image as a 0..1 luminance array at `size` square."""
    image = Image.open(path).convert("L")
    if image.size != (size, size):
        image = image.resize((size, size), Image.LANCZOS)
    return np.asarray(image, dtype=np.float32) / 255.0


def normalise(values: np.ndarray, floor: float) -> np.ndarray:
    """Maps the mid-98% of the range into [floor, 1] with a mean of DETAIL_MEAN.

    Keeping 1.0 fixed means highlights never blow out, and pinning the mean
    means the material book can use one gain for every category.
    """
    low, high = np.percentile(values, (1.0, 99.0))
    spread = max(float(high - low), 1e-4)
    unit = np.clip((values - low) / spread, 0.0, 1.0)
    mapped = floor + (1.0 - floor) * unit
    mean = float(mapped.mean())
    if mean >= DETAIL_MEAN:
        return mapped
    scale = (1.0 - DETAIL_MEAN) / (1.0 - mean)
    return np.clip(1.0 - (1.0 - mapped) * scale, floor * 0.5, 1.0)


def save(values: np.ndarray, name: str) -> None:
    image = Image.fromarray(np.round(values * 255.0).clip(0, 255).astype(np.uint8), "L")
    # RGB, not L: see the note at the top of this file about luminance textures.
    image = image.convert("RGB")
    path = os.path.join(OUT_DIR, name)
    # quality 90 keeps the grain and still lands each map under ~120 KB.
    image.save(path, "JPEG", quality=90, optimize=True)
    check = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    print(
        "wrote %-32s %dx%d  mean %.3f  min %.3f  %d KB"
        % (
            name,
            image.width,
            image.height,
            check.mean(),
            check.min(),
            os.path.getsize(path) // 1024,
        )
    )


# The floors are a low floor value: the veneer's cathedral figure is strong, and
# at furniture scale a strong map reads as plywood rather than planed timber.
def wood() -> None:
    save(normalise(grey(fetch("angli_veneer_diff_1k.jpg"), 512), 0.76), "detail_wood_diff_512.jpg")


def fabric() -> None:
    save(normalise(grey(fetch("book_pattern_col1_1k.jpg"), 512), 0.70), "detail_fabric_diff_512.jpg")


def stone() -> None:
    save(normalise(grey(PLASTER, 512), 0.82), "detail_stone_diff_512.jpg")


def streak(values: np.ndarray, radius: int) -> np.ndarray:
    """A horizontal box average that wraps at the edges, so the map tiles."""
    width = values.shape[1]
    padded = np.pad(values, ((0, 0), (radius, radius)), mode="wrap")
    running = np.cumsum(padded, axis=1)
    running = np.concatenate([np.zeros((running.shape[0], 1)), running], axis=1)
    return (running[:, 2 * radius + 1:] - running[:, :-2 * radius - 1]) / float(2 * radius + 1)


def metal() -> None:
    """Brushed metal: the veneer's fine grain, high-passed and streaked."""
    base = Image.open(fetch("angli_veneer_diff_1k.jpg")).convert("L")
    base = base.resize((256, 256), Image.LANCZOS)

    def high_pass(image: Image.Image) -> Image.Image:
        blurred = image.filter(ImageFilter.GaussianBlur(3.0))
        grain = np.asarray(image, np.float32) - np.asarray(blurred, np.float32)
        return Image.fromarray(
            np.clip(128.0 + grain * 3.0, 0, 255).astype(np.uint8), "L"
        )

    grain = np.asarray(wrapped(base, high_pass), dtype=np.float32) / 255.0
    values = streak(grain, 6)
    save(normalise(values, 0.86), "detail_metal_diff_256.jpg")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    wood()
    fabric()
    stone()
    metal()
    print("detail maps normalised to a %.2f mean; albedo gain is %.3f" % (
        DETAIL_MEAN,
        1.0 / DETAIL_MEAN,
    ))


if __name__ == "__main__":
    main()
