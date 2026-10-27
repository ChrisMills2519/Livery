#!/usr/bin/env python3
"""Turn the loading screen's raw art into the two images the shell ships.

    python3 tools/prepare_splash_art.py

In:   tools/web_shell/art/ginger-games-logo-source.png   the studio wordmark
      tools/web_shell/art/livery-render.png             tools/render_splash.gd

Out:  tools/web_shell/art/ginger-games-logo.png          the wordmark, trimmed
      tools/web_shell/art/livery-splash.png              the horse, trimmed

Both outputs are transparent PNGs that tools/export_web_mobile.py copies into
the export as `branding-ginger-games.png` and `branding-livery.png`, and that
tools/deploy_r2.py then publishes.  Re-run this whenever the sources change;
tools/check_web_shell.py asserts the exported copies exist.

Two things this is doing deliberately:

* Trimming to the alpha bounding box, with a small margin, so the CSS decides
  the size and the empty pixels are not paid for on a phone's first visit.
* Filling the RGB under transparent pixels from their nearest opaque neighbour.
  The sources carry black under alpha, which is invisible until the browser
  scales the image down and blends it in — and then it shows up as a dark halo
  around the wordmark.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ART = Path(__file__).resolve().parent / "web_shell" / "art"
LOGO_SOURCE = ART / "ginger-games-logo-source.png"
LOGO_OUT = ART / "ginger-games-logo.png"
HORSE_SOURCE = ART / "livery-render.png"
HORSE_OUT = ART / "livery-splash.png"

# Breathing room around the mark and the horse: the trim is tight, and a
# couple of source pixels of nothing keeps the muzzle off the frame edge.
MARGIN = 14
# The splash draws the horse up to about 32 rem wide on a tablet, which is
# 1100 device pixels at a 2x ratio: that is the size the source should be, and
# more would only cost a phone the bytes.
HORSE_MAX_WIDTH = 1100
# Enough passes to fill the margin and the soft edge, no more.
DEHALO_PASSES = 14
ALPHA_THRESHOLD = 8


def dehalo(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Give every transparent pixel the colour of the nearest opaque pixel.

    Scaling blends RGB with no regard for alpha, so black under a transparent
    pixel becomes a dark edge the moment the image is drawn smaller.
    """
    filled = rgb.copy()
    known = alpha > ALPHA_THRESHOLD
    for _ in range(DEHALO_PASSES):
        if known.all():
            break
        # The mean of the known pixels in each 3x3 neighbourhood: for a flat
        # mark this is the mark's own colour, and for anything else it is the
        # nearest edge's colour rather than a hard copy of one neighbour.
        total = np.zeros_like(filled, dtype=np.float64)
        count = np.zeros(known.shape, dtype=np.float64)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                shifted = np.roll(np.roll(filled, dy, axis=0), dx, axis=1)
                shifted_known = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
                total += shifted * shifted_known[..., None]
                count += shifted_known
        grow = (~known) & (count > 0)
        filled[grow] = (total[grow] / count[grow][..., None]).round()
        known = known | grow
    return filled


def trim(image: Image.Image, margin: int) -> Image.Image:
    box = image.getchannel("A").point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    if box is None:
        raise SystemExit("the image is fully transparent")
    left, top, right, bottom = box
    return image.crop(
        (
            max(0, left - margin),
            max(0, top - margin),
            min(image.width, right + margin),
            min(image.height, bottom + margin),
        )
    )


def process(source: Path, target: Path, max_width: int | None) -> tuple[int, int]:
    if not source.exists():
        raise SystemExit(f"missing {source}; it is this tool's input")
    image = Image.open(source).convert("RGBA")
    array = np.asarray(image)
    alpha = array[..., 3]
    if alpha.max() == 0:
        raise SystemExit(f"{source.name} has no opaque pixels")
    fixed = np.dstack([dehalo(array[..., :3], alpha), alpha])
    image = Image.fromarray(fixed.astype(np.uint8), "RGBA")
    image = trim(image, MARGIN)
    if max_width is not None and image.width > max_width:
        height = round(image.height * max_width / image.width)
        image = image.resize((max_width, height), Image.LANCZOS)
    image.save(target, optimize=True)
    return image.size


def main() -> int:
    for source, target, limit in (
        (LOGO_SOURCE, LOGO_OUT, None),
        (HORSE_SOURCE, HORSE_OUT, HORSE_MAX_WIDTH),
    ):
        width, height = process(source, target, limit)
        size = target.stat().st_size
        print(f"[splash-art] {target.name}  {width}x{height}  {size / 1024:.0f} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
