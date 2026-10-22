#!/usr/bin/env python3
"""Render a pair of footprint pictures from the same math the shader uses,
stacked side-by-side, so a human can read the shapes without running the game."""

import numpy as np
from PIL import Image


def ellipse_sd(p, rx, ry):
    return np.sqrt((p[0] / rx) ** 2 + (p[1] / ry) ** 2) - 1.0


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def eval_hoof(q):
    hoof_outer = ellipse_sd(q, 0.88, 0.94)
    hoof_inner = ellipse_sd((q[0], q[1] - 0.12), 0.58, 0.64)
    hoof_wall = smoothstep(0.10, -0.05, hoof_outer) * smoothstep(-0.03, 0.12, hoof_inner)
    hoof_sole = smoothstep(0.02, -0.30, hoof_outer) * 0.42
    heel_open = smoothstep(-0.30, -0.92, q[1])
    frog = 1.0 - 0.45 * smoothstep(0.22, 0.02, np.abs(q[0])) * smoothstep(0.10, -0.55, q[1])
    mask = np.maximum(hoof_wall * (1.0 - 0.80 * heel_open), hoof_sole * frog)
    return mask


def eval_boot(q, seed):
    boot_q = (q[0] * 0.94, q[1] * 1.0)
    boot_edge = ellipse_sd((boot_q[0], boot_q[1] + 0.04), 0.70, 0.95)
    boot_shape = smoothstep(0.14, -0.10, boot_edge)
    boot_shape *= np.clip(0.62 + (1.0 - 0.62) * smoothstep(-0.95, 0.25, q[1]), 0.0, 1.0)
    bands = np.abs(np.sin((q[1] + 0.08 + seed * 0.12) * 13.0))
    tread = np.clip(0.66 + (1.0 - 0.66) * smoothstep(0.25, 0.85, bands), 0.0, 1.0)
    heel_block = smoothstep(-0.45, -0.85, q[1]) * smoothstep(0.75, 0.95, np.abs(q[0]))
    mask = boot_shape * tread * (1.0 + 0.25 * heel_block)
    return mask


def render(mask, size):
    im = Image.new("RGB", (size, size), (40, 40, 48))
    px = im.load()
    # Darken where the print is, lighter near the edges.
    for y in range(size):
        for x in range(size):
            u = (x / size) * 2.0 - 1.0
            v = (y / size) * 2.0 - 1.0
            a = float(mask((u, v)))
            if a > 0.01:
                lv = int(255.0 * (1.0 - a))
                px[x, y] = (lv, lv - 6, lv - 10)
    return im


def main():
    w = 760
    hoof_mask = lambda q: eval_hoof(q)
    boot_mask = lambda q: eval_boot(q, 0.5)
    hoof = np.asarray(render(hoof_mask, w))
    boot = np.asarray(render(boot_mask, w))
    canvas = np.full((w, w * 2 + 40, 3), 32, dtype=np.uint8)
    canvas[:, :w] = hoof
    canvas[:, w + 40:] = boot
    # Thin labels baked into the picture, left side for hoof, right for boot.
    from PIL import ImageDraw, ImageFont
    img = Image.fromarray(canvas, "RGB")
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 26)
    except Exception:
        font = ImageFont.load_default()
    d.text((10, 10), "HOOF  (kind 0)", fill=(220, 210, 180), font=font)
    d.text((w + 50, 10), "BOOT  (kind 1)", fill=(220, 210, 180), font=font)
    img.save("artifacts/_dbg_fp_shapes.png")
    print("saved artifacts/_dbg_fp_shapes.png")


if __name__ == "__main__":
    main()
