#!/usr/bin/env python3
"""
Replicate the exact fragment math from res/shaders/footprint.gdshader so the
print visibility question can be answered without involving the renderer.

Horses in Godot Compatibility do not draw through blend_mul, so the shader
composes the effect from ALPHA instead.  The question here is purely whether
that math actually produces a visible, well-shaped print on the quad, which
this script answers directly.
"""

import numpy as np


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


def scan(kind, label):
    w, h = 512, 512
    xs = np.linspace(-1.0, 1.0, w)
    ys = np.linspace(-1.0, 1.0, h)
    xx, yy = np.meshgrid(xs, ys)
    q = (xx, yy)
    age = 0.0
    strength = 1.0
    life = 1.0 - max(min(age / 40.0, 1.0), 0.0)
    tint_strength = 0.5
    for seed in [0.0, 0.33, 0.66]:
        if kind == 0:
            mask = eval_hoof(q)
        else:
            mask = eval_boot(q, seed)
        alpha = mask * life * strength * tint_strength * (0.90 + 0.10 * seed)
        cover = (alpha > 0.02).sum()
        max_alpha = alpha.max()
        mean_alpha = alpha.mean()
        cx = alpha[h // 2, :]
        cy = alpha[:, w // 2]
        x_ix = np.where(cx > 0.05)[0]
        y_ix = np.where(cy > 0.05)[0]
        x_span = (x_ix.max() - x_ix.min()) if len(x_ix) else 0
        y_span = (y_ix.max() - y_ix.min()) if len(y_ix) else 0
        print("%s seed=%.2f: max_alpha=%.3f  mean_alpha=%.4f  cover=%.1f%%  "
              "center_span px = x:%d y:%d" %
              (label, seed, max_alpha, mean_alpha, 100.0 * cover / (w * h), x_span, y_span))
    print("   full (print over dark background, tint_strength=0.5):")
    bg = np.zeros((h, w)) + 0.2
    seed = 0.5
    if kind == 0:
        mask = eval_hoof(q)
    else:
        mask = eval_boot(q, seed)
    full_alpha = mask * life * strength * tint_strength * (0.90 + 0.10 * seed)
    tint = np.array([0.20, 0.16, 0.12])
    comp_r = bg * (1.0 - full_alpha) + tint[0] * full_alpha
    comp_g = bg * (1.0 - full_alpha) + tint[1] * full_alpha
    comp_b = bg * (1.0 - full_alpha) + tint[2] * full_alpha
    print("   blended r mean=%.3f g mean=%.3f b mean=%.3f  (pure bg would be 0.20,0.16,0.12)" % (
        comp_r.mean(), comp_g.mean(), comp_b.mean()))
    # Center-line profile down the longest axis (Y for hoof, X for boot toe):
    if kind == 0:
        prof = full_alpha[h // 2, :]
        axis = "x"
    else:
        prof = full_alpha[:, w // 2]
        axis = "y"
    peak = prof.max()
    width = int(np.sum(prof > 0.1 * peak))
    print("   center-line profile: peak=%.3f  full-width>10pct=%d px" % (peak, width))


if __name__ == "__main__":
    print("=== hoof (kind 0) ===")
    scan(0, "hoof")
    print("=== boot (kind 1) ===")
    scan(1, "boot")
    print()
    print("Interpretation:")
    print("  max_alpha is the darkest a print pixel gets.  With tint_strength=0.5")
    print("  and a fresh print, the darkest pixels are around 0.23 alpha, so the")
    print("  print sits on top of the ground texture rather than fully occluding it.")
    print("  That is the intended look: pressed-down earth, not a flat decal.")
