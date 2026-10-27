"""Build the low-poly prop library for Groom.

Every prop is generated procedurally, flat shaded and built from solid
materials only (no textures, no UVs needed), so the whole library stays cheap
enough for the Compatibility renderer and the tablet build.

Usage:
    blender --background --factory-startup --python tools/build_props.py -- [--stage trees|all]

Outputs:
    Models/props/<category>/<name>.glb   one prop per file, origin on the ground
    artifacts/props_library.blend        every prop laid out in a labelled grid
    artifacts/props_<category>.png       contact sheet per category
    artifacts/props_overview.png         scene render of a dozen props together
    Models/props/props_manifest.json     size / triangle count per prop

The Blender scene is the source of truth while this runs; the .blend is saved
after the GLBs are exported so the exports stay at the origin.
"""

import bpy
import bmesh
import json
import math
import os
import random
import sys
from mathutils import Euler, Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Models", "props")
ART_DIR = os.path.join(ROOT, "artifacts")
LIB_BLEND = os.path.join(ART_DIR, "props_library.blend")
TAU = math.tau

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
STAGE = ARGS[ARGS.index("--stage") + 1] if "--stage" in ARGS else "all"

# ---------------------------------------------------------------------------
# palette: name -> (linear rgb, roughness, metallic, emission strength)
# ---------------------------------------------------------------------------

PALETTE = {
    "bark":        ((0.215, 0.135, 0.082), 0.92, 0.0, 0.0),
    "bark_light":  ((0.360, 0.255, 0.165), 0.92, 0.0, 0.0),
    "bark_dark":   ((0.130, 0.085, 0.055), 0.95, 0.0, 0.0),
    "birch":       ((0.760, 0.735, 0.660), 0.88, 0.0, 0.0),
    "leaf_deep":   ((0.048, 0.140, 0.058), 0.90, 0.0, 0.0),
    "leaf_mid":    ((0.105, 0.260, 0.080), 0.90, 0.0, 0.0),
    "leaf_light":  ((0.215, 0.385, 0.115), 0.88, 0.0, 0.0),
    "leaf_olive":  ((0.300, 0.380, 0.115), 0.88, 0.0, 0.0),
    "leaf_rust":   ((0.560, 0.245, 0.070), 0.90, 0.0, 0.0),
    "leaf_amber":  ((0.700, 0.430, 0.100), 0.90, 0.0, 0.0),
    "leaf_red":    ((0.520, 0.140, 0.060), 0.90, 0.0, 0.0),
    "pine_deep":   ((0.045, 0.135, 0.080), 0.92, 0.0, 0.0),
    "pine_mid":    ((0.070, 0.215, 0.115), 0.92, 0.0, 0.0),
    "pine_light":  ((0.120, 0.300, 0.150), 0.90, 0.0, 0.0),
    "moss":        ((0.255, 0.390, 0.105), 0.95, 0.0, 0.0),
    "berry":       ((0.400, 0.035, 0.055), 0.55, 0.0, 0.0),
    "apple":       ((0.620, 0.100, 0.070), 0.50, 0.0, 0.0),
    "blossom":     ((0.840, 0.500, 0.560), 0.80, 0.0, 0.0),
    "blossom_pale": ((0.900, 0.780, 0.700), 0.80, 0.0, 0.0),
    "flower_white": ((0.880, 0.870, 0.780), 0.80, 0.0, 0.0),
    "flower_yellow": ((0.870, 0.700, 0.160), 0.80, 0.0, 0.0),
    "stone":       ((0.395, 0.400, 0.385), 0.94, 0.0, 0.0),
    "stone_light": ((0.520, 0.525, 0.500), 0.94, 0.0, 0.0),
    "stone_dark":  ((0.245, 0.255, 0.250), 0.95, 0.0, 0.0),
    "wood":        ((0.440, 0.300, 0.170), 0.88, 0.0, 0.0),
    "wood_light":  ((0.600, 0.450, 0.270), 0.88, 0.0, 0.0),
    "wood_pale":   ((0.680, 0.540, 0.340), 0.88, 0.0, 0.0),
    "wood_dark":   ((0.245, 0.165, 0.100), 0.92, 0.0, 0.0),
    "wood_red":    ((0.420, 0.170, 0.110), 0.85, 0.0, 0.0),
    "wood_grey":   ((0.420, 0.370, 0.300), 0.92, 0.0, 0.0),
    "metal":       ((0.330, 0.340, 0.355), 0.42, 0.75, 0.0),
    "metal_dark":  ((0.155, 0.165, 0.175), 0.50, 0.70, 0.0),
    "hay":         ((0.720, 0.600, 0.265), 0.95, 0.0, 0.0),
    "hay_dark":    ((0.550, 0.440, 0.175), 0.95, 0.0, 0.0),
    "rope":        ((0.600, 0.505, 0.335), 0.95, 0.0, 0.0),
    "water":       ((0.150, 0.360, 0.430), 0.12, 0.0, 0.0),
    "terracotta":  ((0.500, 0.220, 0.130), 0.88, 0.0, 0.0),
    "soil":        ((0.165, 0.110, 0.070), 0.98, 0.0, 0.0),
    "roof":        ((0.240, 0.175, 0.140), 0.90, 0.0, 0.0),
    "roof_red":    ((0.360, 0.155, 0.110), 0.90, 0.0, 0.0),
    "plaster":     ((0.700, 0.640, 0.530), 0.92, 0.0, 0.0),
    "glass_warm":  ((0.900, 0.680, 0.280), 0.35, 0.0, 3.0),
    "churn":       ((0.520, 0.530, 0.520), 0.38, 0.60, 0.0),
    "feed":        ((0.430, 0.330, 0.160), 0.95, 0.0, 0.0),
    "paint_red":   ((0.550, 0.120, 0.085), 0.55, 0.0, 0.0),
    "paint_white": ((0.820, 0.800, 0.740), 0.60, 0.0, 0.0),
    "sack":        ((0.560, 0.490, 0.335), 0.98, 0.0, 0.0),
    "apple_green": ((0.330, 0.470, 0.120), 0.50, 0.0, 0.0),
    "rubber":      ((0.055, 0.058, 0.062), 0.80, 0.0, 0.0),
    "bristle_dark": ((0.115, 0.090, 0.070), 0.95, 0.0, 0.0),
    "bristle_pale": ((0.640, 0.570, 0.430), 0.95, 0.0, 0.0),
    "bristle_grey": ((0.360, 0.340, 0.300), 0.95, 0.0, 0.0),
    "leather":     ((0.240, 0.135, 0.080), 0.72, 0.0, 0.0),
    "sponge":      ((0.610, 0.480, 0.230), 0.98, 0.0, 0.0),
    "carrot":      ((0.660, 0.260, 0.045), 0.80, 0.0, 0.0),
    "skin":        ((0.560, 0.370, 0.250), 0.75, 0.0, 0.0),
    "hair":        ((0.115, 0.078, 0.050), 0.90, 0.0, 0.0),
    "coat_red":    ((0.330, 0.090, 0.070), 0.92, 0.0, 0.0),
    "coat_green":  ((0.130, 0.240, 0.140), 0.92, 0.0, 0.0),
    "coat_blue":   ((0.100, 0.170, 0.290), 0.92, 0.0, 0.0),
    "coat_mustard": ((0.480, 0.330, 0.090), 0.92, 0.0, 0.0),
    "coat_grey":   ((0.290, 0.295, 0.280), 0.92, 0.0, 0.0),
    "denim":       ((0.140, 0.190, 0.265), 0.92, 0.0, 0.0),
    "boot":        ((0.070, 0.058, 0.050), 0.85, 0.0, 0.0),
    "straw":       ((0.690, 0.560, 0.290), 0.95, 0.0, 0.0),
    "brass":       ((0.600, 0.440, 0.140), 0.35, 0.80, 0.0),
    "rosette_red": ((0.520, 0.080, 0.070), 0.60, 0.0, 0.0),
    "rosette_blue": ((0.080, 0.170, 0.480), 0.60, 0.0, 0.0),
    "rosette_yellow": ((0.780, 0.560, 0.080), 0.60, 0.0, 0.0),
}

LEAF = ("leaf_deep", "leaf_mid", "leaf_mid", "leaf_light", "leaf_mid")
LEAF_LIGHT = ("leaf_mid", "leaf_light", "leaf_light", "leaf_olive")
LEAF_PINE = ("pine_deep", "pine_mid", "pine_mid", "pine_light")
AUTUMN = ("leaf_rust", "leaf_amber", "leaf_amber", "leaf_red", "leaf_rust")
STONE = ("stone", "stone", "stone_light", "stone_dark")
BARK = ("bark", "bark", "bark_light")
WOOD = ("wood", "wood", "wood_light")
HAY = ("hay", "hay", "hay_dark")

MAT_CACHE = {}


def palette(key):
    return PALETTE[key]


def material(key):
    if key in MAT_CACHE:
        return MAT_CACHE[key]
    rgb, rough, metal, emit = PALETTE[key]
    m = bpy.data.materials.new("P_" + key)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        bsdf.inputs["Emission"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, 1.0)
    MAT_CACHE[key] = m
    return m


def mtx(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    return (Matrix.Translation(Vector(loc))
            @ Euler(rot, "XYZ").to_matrix().to_4x4()
            @ Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0))))


CATEGORY_COLLECTIONS = {}


def category_collection(cat):
    if cat not in CATEGORY_COLLECTIONS:
        c = bpy.data.collections.new("props_" + cat)
        bpy.context.scene.collection.children.link(c)
        CATEGORY_COLLECTIONS[cat] = c
    return CATEGORY_COLLECTIONS[cat]


ALL_PROPS = []


class Prop:
    """One flat-shaded multi-material object, built in local space."""

    def __init__(self, name, category, seed):
        self.name = name
        self.category = category
        self.rng = random.Random(seed)
        self.bm = bmesh.new()
        self.slots = []
        self.obj = None

    # -- materials ---------------------------------------------------------

    def _slot(self, key):
        if key in self.slots:
            return self.slots.index(key)
        self.slots.append(key)
        return len(self.slots) - 1

    def _paint(self, faces, shades):
        if isinstance(shades, str):
            shades = (shades,)
        idx = [self._slot(k) for k in shades]
        for f in faces:
            f.material_index = idx[0] if len(idx) == 1 else self.rng.choice(idx)

    def _new_faces(self, before):
        return [f for f in self.bm.faces if f not in before]

    # -- primitives --------------------------------------------------------

    def ico(self, loc, radius, subdiv=2, scale=(1, 1, 1), rot=(0, 0, 0), shades=("leaf_mid",)):
        before = set(self.bm.faces)
        bmesh.ops.create_icosphere(
            self.bm, subdivisions=subdiv, radius=radius,
            matrix=mtx(loc, rot, scale))
        self._paint(self._new_faces(before), shades)

    def box(self, loc, size, rot=(0, 0, 0), shades=("wood",)):
        before = set(self.bm.faces)
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=mtx(loc, rot, size))
        self._paint(self._new_faces(before), shades)

    def cone(self, loc, r1, r2, depth, seg=8, rot=(0, 0, 0), shades=("wood",), cap=None):
        before = set(self.bm.faces)
        bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg,
            radius1=r1, radius2=r2, depth=depth, matrix=mtx(loc, rot))
        faces = self._new_faces(before)
        self._paint(faces, shades)
        if cap is not None:
            ci = self._slot(cap)
            for f in faces:
                if len(f.verts) > 4:
                    f.material_index = ci

    def cyl(self, loc, radius, depth, axis="Z", seg=10, shades=("wood",), cap=None, r2=None):
        rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
        self.cone(loc, radius, radius if r2 is None else r2, depth, seg, rot, shades, cap)

    def stick(self, a, b, r1, r2=None, seg=6, shades=("bark",), cap=None):
        a = Vector(a)
        b = Vector(b)
        d = b - a
        length = d.length
        if length < 1e-6:
            return
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        before = set(self.bm.faces)
        bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg,
            radius1=r1, radius2=(r1 * 0.7 if r2 is None else r2),
            depth=length, matrix=Matrix.Translation((a + b) * 0.5) @ rot)
        faces = self._new_faces(before)
        self._paint(faces, shades)
        if cap is not None:
            ci = self._slot(cap)
            for f in faces:
                if len(f.verts) > 4:
                    f.material_index = ci

    def warp(self, fn, zmin=-1e9, zmax=1e9):
        for v in self.bm.verts:
            if zmin <= v.co.z <= zmax:
                fn(v)

    # -- finish ------------------------------------------------------------

    def finish(self):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for key in self.slots:
            me.materials.append(material(key))
        for poly in me.polygons:
            poly.use_smooth = False
        obj = bpy.data.objects.new(self.name, me)
        category_collection(self.category).objects.link(obj)
        self.obj = obj
        ALL_PROPS.append(self)
        return obj


def arc_points(a, b, lift, n=7):
    a, b = Vector(a), Vector(b)
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        p.z += math.sin(t * math.pi) * lift
        pts.append(p)
    return pts


# ---------------------------------------------------------------------------
# trees
# ---------------------------------------------------------------------------

def tree_oak(name, seed, height=5.6, spread=1.85, shades=LEAF, apples=False):
    p = Prop(name, "trees", seed)
    r = p.rng

    for i in range(5):
        a = TAU * i / 5 + r.uniform(-0.35, 0.35)
        p.stick((math.cos(a) * 0.10, math.sin(a) * 0.10, 0.22),
                (math.cos(a) * r.uniform(0.38, 0.52), math.sin(a) * r.uniform(0.38, 0.52), 0.015),
                0.095, 0.018, 5, ("bark_dark",))

    mid = Vector((r.uniform(-0.10, 0.10), r.uniform(-0.10, 0.10), 1.75))
    top = Vector((mid.x + r.uniform(0.02, 0.20), mid.y + r.uniform(-0.16, 0.16), 3.55))
    p.stick((0, 0, 0), mid, 0.42, 0.25, 7, BARK)
    p.stick(mid, top, 0.25, 0.11, 7, BARK)

    cz = height * 0.775
    lobes = []
    p.ico((top.x, top.y, cz + 0.20), spread * 0.80, 2, (1, 1, 0.92),
          (0, 0, r.uniform(0, TAU)), shades)
    lobes.append((top.x, top.y, cz + 0.20, spread * 0.8))
    count = 6
    for i in range(count):
        a = TAU * i / count + r.uniform(-0.30, 0.30)
        rad = spread * r.uniform(0.52, 0.72)
        z = cz + r.uniform(-0.55, 0.55)
        rr = spread * r.uniform(0.42, 0.58)
        loc = (top.x + math.cos(a) * rad, top.y + math.sin(a) * rad, z)
        p.ico(loc, rr, 2, (1, 1, 0.86), (0, 0, r.uniform(0, TAU)),
              shades if z > cz - 0.2 else ("leaf_deep", "leaf_mid", "leaf_mid"))
        lobes.append((loc[0], loc[1], z, rr))
    p.ico((top.x + 0.10, top.y - 0.06, cz + r.uniform(0.90, 1.08)), spread * 0.50,
          2, (1, 1, 0.78), (0, 0, r.uniform(0, TAU)), shades)

    for i in range(3):
        lx, ly, lz, _ = lobes[1 + i * 2]
        p.stick((top.x, top.y, 2.9), (lx * 0.72, ly * 0.72, lz - 0.2), 0.09, 0.025, 5, ("bark",))

    if apples:
        for i in range(10):
            a = TAU * i / 10 + r.uniform(-0.2, 0.2)
            rad = spread * r.uniform(0.82, 1.0)
            z = cz + r.uniform(-0.65, -0.1)
            p.ico((top.x + math.cos(a) * rad, top.y + math.sin(a) * rad, z),
                  r.uniform(0.08, 0.11), 1, (1, 1, 1), (0, 0, 0), ("apple",))

    return p.finish()


def tree_birch(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    base = Vector((0, 0, 0))
    mid = Vector((r.uniform(-0.10, 0.10), r.uniform(-0.08, 0.08), 2.4))
    top = Vector((mid.x + r.uniform(0.05, 0.20), mid.y + r.uniform(-0.12, 0.12), 4.75))
    p.stick(base, mid, 0.17, 0.12, 7, ("birch",))
    p.stick(mid, top, 0.12, 0.055, 7, ("birch",))

    for i in range(8):
        z = r.uniform(0.45, 4.3)
        a = r.uniform(0, TAU)
        rad = 0.145 if z < 2.4 else 0.095
        p.box((math.cos(a) * rad, math.sin(a) * rad, z),
              (0.025, r.uniform(0.06, 0.11), r.uniform(0.018, 0.04)),
              (0, 0, a + math.pi / 2), ("bark_dark",))

    shades = ("leaf_olive", "leaf_light", "leaf_light", "leaf_mid")
    cz = 5.0
    p.ico((top.x, top.y, cz), 1.20, 2, (1, 1, 1.12), (0, 0, r.uniform(0, TAU)), shades)
    for i in range(7):
        a = TAU * i / 7 + r.uniform(-0.3, 0.3)
        rad = r.uniform(0.55, 1.05)
        p.ico((top.x + math.cos(a) * rad, top.y + math.sin(a) * rad,
               cz + r.uniform(-0.55, 1.0)), r.uniform(0.62, 0.95), 2, (1, 1, 0.88),
              (0, 0, r.uniform(0, TAU)), shades)
    p.ico((top.x + 0.05, top.y, cz + 1.55), 0.62, 2, (1, 1, 0.9), (0, 0, 0), shades)
    for i in range(4):
        a = TAU * i / 4
        p.stick((top.x * 0.5, top.y * 0.5, cz - 0.4),
                (top.x + math.cos(a) * 0.8, top.y + math.sin(a) * 0.8, cz), 0.05, 0.012, 4,
                ("birch",))
    return p.finish()


def tree_pine(name, seed, height=7.0, spread=1.85):
    p = Prop(name, "trees", seed)
    r = p.rng
    p.stick((0, 0, 0), (0, 0, height * 0.94), 0.30, 0.055, 7, ("bark_dark", "bark"))

    steps = (0.27, 0.41, 0.55, 0.69, 0.82)
    for i, t in enumerate(steps):
        z = height * t
        rad = spread * (1.0 - t) + 0.30
        depth = height * 0.245
        p.cone((0, 0, z), rad, 0.035, depth, 8, (0, 0, r.uniform(0, TAU)), LEAF_PINE)
    p.cone((0, 0, height * 0.92), spread * 0.20, 0.01, height * 0.16, 7,
           (0, 0, r.uniform(0, TAU)), ("pine_mid", "pine_light"))
    return p.finish()


def tree_willow(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    mid = Vector((0.15, -0.05, 1.5))
    top = Vector((0.05, 0.10, 3.1))
    p.stick((0, 0, 0), mid, 0.40, 0.28, 7, BARK)
    p.stick(mid, top, 0.28, 0.16, 7, BARK)

    shades = ("leaf_mid", "leaf_light", "leaf_mid", "leaf_olive")
    p.ico((top.x, top.y, 3.55), 1.50, 2, (1.2, 1.2, 0.62), (0, 0, r.uniform(0, TAU)), shades)
    for i in range(8):
        a = TAU * i / 8 + r.uniform(-0.2, 0.2)
        rad = r.uniform(1.2, 1.85)
        p.ico((top.x + math.cos(a) * rad, top.y + math.sin(a) * rad,
               3.30 + r.uniform(-0.2, 0.3)), r.uniform(0.7, 1.0), 2,
              (1, 1, 0.6), (0, 0, r.uniform(0, TAU)), shades)
    for i in range(14):
        a = TAU * i / 14 + r.uniform(-0.12, 0.12)
        rad = r.uniform(1.2, 2.05)
        z = r.uniform(2.0, 3.15)
        p.ico((top.x + math.cos(a) * rad, top.y + math.sin(a) * rad, z),
              r.uniform(0.32, 0.62), 2, (0.85, 0.85, 1.25), (0, 0, r.uniform(0, TAU)),
              ("leaf_mid", "leaf_deep", "leaf_light"))
    for i in range(6):
        a = TAU * i / 6
        p.stick((top.x, top.y, 3.2),
                (top.x + math.cos(a) * 1.7, top.y + math.sin(a) * 1.7, 2.75),
                0.085, 0.02, 5, ("bark",))
    return p.finish()


def tree_dead(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    top = Vector((0.18, -0.08, 3.1))
    p.stick((0, 0, 0), top, 0.30, 0.10, 7, ("bark_light", "wood_grey"))
    for i in range(6):
        a = TAU * i / 6 + r.uniform(-0.4, 0.4)
        start = Vector((top.x * 0.6, top.y * 0.6, r.uniform(1.35, 2.95)))
        length = r.uniform(0.9, 1.9)
        end = start + Vector((math.cos(a) * length, math.sin(a) * length,
                              r.uniform(0.35, 1.3)))
        p.stick(start, end, 0.085, 0.012, 5, ("bark_light", "wood_grey"))
        if i % 2 == 0:
            p.stick(end, end + Vector((math.cos(a + 0.9) * 0.45, math.sin(a + 0.9) * 0.45, 0.45)),
                    0.04, 0.01, 4, ("bark_light",))
    p.stick(top, (top.x + 0.12, top.y + 0.04, 4.05), 0.10, 0.02, 5, ("bark_light",))
    return p.finish()


def tree_sapling(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    p.stick((0, 0, 0), (0.05, 0.02, 1.35), 0.055, 0.035, 5, ("bark",))
    shades = ("leaf_light", "leaf_mid", "leaf_olive")
    for i in range(4):
        a = TAU * i / 4 + r.uniform(-0.3, 0.3)
        p.ico((0.05 + math.cos(a) * r.uniform(0.14, 0.35),
               0.02 + math.sin(a) * r.uniform(0.14, 0.35),
               r.uniform(1.25, 1.75)), r.uniform(0.32, 0.46), 2, (1, 1, 0.9), shades=shades)
    p.ico((0.05, 0.02, 1.85), 0.30, 2, (1, 1, 0.9), shades=shades)
    return p.finish()


def tree_stump(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    p.cone((0, 0, 0.36), 0.44, 0.36, 0.72, 8, (0, 0, r.uniform(0, TAU)),
           ("bark", "bark_light"), cap="bark_dark")
    p.cyl((0, 0, 0.715), 0.31, 0.035, "Z", 8, ("wood_pale", "wood_light"))
    for i in range(4):
        a = TAU * i / 4 + r.uniform(-0.3, 0.3)
        p.stick((math.cos(a) * 0.28, math.sin(a) * 0.28, 0.16),
                (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.015),
                0.10, 0.02, 5, ("bark_dark",))
    p.warp(lambda v: setattr(v.co, "z", v.co.z + r.uniform(-0.045, 0.045)), 0.69, 1e9)
    p.ico((-0.12, 0.10, 0.74), 0.22, 2, (1.2, 1.0, 0.3), (0, 0, r.uniform(0, TAU)), ("moss",))
    return p.finish()


def fallen_log(name, seed):
    p = Prop(name, "trees", seed)
    r = p.rng
    start = Vector((-1.35, 0.02, 0.30))
    end = Vector((1.30, -0.06, 0.36))
    p.stick(start, end, 0.33, 0.26, 9, ("bark", "bark_light"), cap="wood_pale")
    for i in range(3):
        t = 0.25 + i * 0.24
        base = start.lerp(end, t)
        a = r.uniform(0, TAU)
        p.stick(base, base + Vector((math.cos(a) * 0.25, math.sin(a) * 0.5, r.uniform(0.35, 0.7))),
                0.075, 0.02, 5, ("bark_light",))
    for i in range(3):
        t = 0.2 + i * 0.3
        base = start.lerp(end, t)
        p.ico((base.x, base.y + r.uniform(-0.1, 0.1), base.z + 0.24),
              r.uniform(0.12, 0.20), 2, (1.4, 0.9, 0.25), (0, 0, r.uniform(0, TAU)), ("moss",))
    return p.finish()


# ---------------------------------------------------------------------------
# bushes
# ---------------------------------------------------------------------------

def bush_sphere(name, seed, size=0.82, shades=LEAF_LIGHT, berries=0, blossom=0):
    p = Prop(name, "bushes", seed)
    r = p.rng
    p.ico((0, 0, size * 0.56), size * 0.72, 2, (1.05, 0.95, 0.82),
          (0, 0, r.uniform(0, TAU)), shades)
    for i in range(5):
        a = TAU * i / 5 + r.uniform(-0.3, 0.3)
        rad = size * r.uniform(0.35, 0.48)
        p.ico((math.cos(a) * rad, math.sin(a) * rad, size * r.uniform(0.40, 0.62)),
              size * r.uniform(0.42, 0.56), 2, (1, 1, 0.85),
              (0, 0, r.uniform(0, TAU)), shades)
    for i in range(3):
        a = TAU * i / 3 + r.uniform(-0.4, 0.4)
        p.stick((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.0),
                (math.cos(a) * size * 0.45, math.sin(a) * size * 0.45, size * 0.55),
                0.035, 0.012, 4, ("bark",))

    def surface(radius_scale):
        a = r.uniform(0, TAU)
        z = r.uniform(-0.45, 0.8)
        horiz = max(0.0, 1.0 - z * z) ** 0.5
        return (math.cos(a) * size * radius_scale * horiz,
                math.sin(a) * size * radius_scale * horiz,
                size * (0.56 + z * 0.58))

    for i in range(berries):
        p.ico(surface(0.74), r.uniform(0.045, 0.06), 1, (1, 1, 1), (0, 0, 0), ("berry",))
    for i in range(blossom):
        p.ico(surface(0.82), r.uniform(0.075, 0.120), 1, (1, 1, 0.70), (0, 0, 0),
              ("blossom", "blossom", "blossom_pale"))
    return p.finish()


def bush_hedge(name, seed):
    p = Prop(name, "bushes", seed)
    r = p.rng
    for i in range(5):
        p.ico((-1.0 + i * 0.5, 0, 0.33), 0.52, 2, (0.62, 0.85, 0.72),
              (0, 0, r.uniform(0, TAU)), ("leaf_deep", "leaf_mid"))
    for i in range(9):
        x = -1.15 + i * 0.29
        p.ico((x, r.uniform(-0.05, 0.05), 0.60 + r.uniform(-0.05, 0.12)),
              r.uniform(0.30, 0.42), 2, (1, 0.9, 0.8), (0, 0, r.uniform(0, TAU)),
              ("leaf_mid", "leaf_light", "leaf_deep"))
    for i in range(2):
        x = -1.28 if i == 0 else 1.28
        p.ico((x, 0, 0.48), 0.40, 2, (0.6, 0.9, 1.0), (0, 0, 0), ("leaf_deep", "leaf_mid"))
    return p.finish()


def bush_bramble(name, seed):
    p = Prop(name, "bushes", seed)
    r = p.rng
    for i in range(6):
        a = TAU * i / 6 + r.uniform(-0.3, 0.3)
        length = r.uniform(0.7, 1.15)
        mid = (math.cos(a) * length * 0.55, math.sin(a) * length * 0.55, 0.62)
        end = (math.cos(a) * length, math.sin(a) * length, 0.16)
        p.stick((0, 0, 0.0), mid, 0.035, 0.025, 4, ("bark",))
        p.stick(mid, end, 0.025, 0.008, 4, ("bark",))
        p.ico((mid[0], mid[1], mid[2] + 0.06), r.uniform(0.24, 0.34), 2, (1, 1, 0.8),
              (0, 0, r.uniform(0, TAU)), ("leaf_deep", "leaf_mid"))
        for j in range(4):
            p.ico((end[0] + r.uniform(-0.14, 0.14), end[1] + r.uniform(-0.14, 0.14),
                   end[2] + r.uniform(0.0, 0.3)), r.uniform(0.13, 0.22), 2,
                  (1, 1, 1), (0, 0, r.uniform(0, TAU)), ("leaf_mid", "leaf_light"))
        if i % 2 == 0:
            p.ico((mid[0], mid[1], mid[2] + 0.12), 0.05, 1, (1, 1, 1), (0, 0, 0), ("berry",))
    return p.finish()


# ---------------------------------------------------------------------------
# nature scatter
# ---------------------------------------------------------------------------

def rock_cluster(name, seed, size=1.0):
    p = Prop(name, "nature", seed)
    r = p.rng
    for i in range(4):
        a = TAU * i / 4 + r.uniform(-0.5, 0.5)
        rad = size * r.uniform(0.0, 0.55)
        s = size * r.uniform(0.35, 0.62)
        loc = (math.cos(a) * rad, math.sin(a) * rad, s * 0.55)
        p.ico(loc, s, 2, (1.2, 1.0, 0.75), (r.uniform(-0.25, 0.25), r.uniform(-0.25, 0.25),
                                           r.uniform(0, TAU)), STONE)
    p.ico((size * 0.22, -size * 0.1, size * 0.55), size * 0.28, 2, (1.5, 1.2, 0.2),
          (0, 0, r.uniform(0, TAU)), ("moss", "moss", "leaf_mid"))
    return p.finish()


def mushroom_cluster(name, seed):
    p = Prop(name, "nature", seed)
    r = p.rng
    spots = [(-0.14, 0.02, 0.0), (0.11, -0.04, 0.02), (0.02, 0.16, -0.02)]
    for i, (x, y, dy) in enumerate(spots):
        h = r.uniform(0.16, 0.30)
        stem_r = r.uniform(0.035, 0.055)
        p.cyl((x, y, h * 0.5 + dy), stem_r, h, "Z", 6, ("wood_pale", "blossom_pale"),
              r2=stem_r * 1.35)
        cap_r = r.uniform(0.11, 0.20)
        cz = h + dy + cap_r * 0.28
        p.ico((x, y, cz), cap_r, 2, (1.0, 1.0, 0.58), (0, 0, r.uniform(0, TAU)),
              ("paint_red", "paint_red", "wood_red"))
        for j in range(4):
            a = TAU * j / 4 + r.uniform(-0.3, 0.3)
            p.ico((x + math.cos(a) * cap_r * 0.55, y + math.sin(a) * cap_r * 0.55,
                   cz + cap_r * 0.34), cap_r * r.uniform(0.12, 0.18), 1, (1, 1, 0.5),
                  (0, 0, 0), ("paint_white", "flower_white"))
    return p.finish()


def grass_tuft(name, seed):
    p = Prop(name, "nature", seed)
    r = p.rng
    for i in range(9):
        a = TAU * i / 9 + r.uniform(-0.35, 0.35)
        height = r.uniform(0.28, 0.62)
        base = Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0.0))
        tip = Vector((math.cos(a) * r.uniform(0.10, 0.24), math.sin(a) * r.uniform(0.10, 0.24),
                      height))
        p.stick(base, tip, 0.028, 0.004, 4, ("leaf_mid", "leaf_light", "leaf_olive"))
    return p.finish()


def reeds(name, seed):
    p = Prop(name, "nature", seed)
    r = p.rng
    for i in range(7):
        a = TAU * i / 7 + r.uniform(-0.3, 0.3)
        rad = r.uniform(0.1, 0.32)
        height = r.uniform(0.9, 1.5)
        base = (math.cos(a) * rad, math.sin(a) * rad, 0)
        tip = (base[0] + math.cos(a) * 0.08, base[1] + math.sin(a) * 0.08, height)
        p.stick(base, tip, 0.022, 0.006, 4, ("leaf_deep", "leaf_olive"))
        if i % 2 == 0:
            p.cyl((tip[0], tip[1], height - 0.10), 0.045, 0.22, "Z", 6,
                  ("wood_dark", "bark"), r2=0.035)
    for i in range(5):
        a = TAU * i / 5 + r.uniform(-0.3, 0.3)
        p.stick((0, 0, 0), (math.cos(a) * 0.5, math.sin(a) * 0.5, r.uniform(0.35, 0.7)),
                0.025, 0.004, 4, ("leaf_mid", "leaf_deep"))
    return p.finish()


def flower_patch(name, seed):
    p = Prop(name, "nature", seed)
    r = p.rng
    for i in range(11):
        x = r.uniform(-0.32, 0.32)
        y = r.uniform(-0.32, 0.32)
        h = r.uniform(0.22, 0.46)
        p.stick((x, y, 0), (x, y, h), 0.012, 0.006, 4, ("leaf_mid", "leaf_olive"))
        petals = r.choice(("flower_white", "flower_yellow", "blossom", "flower_white"))
        p.ico((x, y, h), r.uniform(0.035, 0.055), 1, (1, 1, 0.55), (0, 0, r.uniform(0, TAU)),
              (petals,))
        if r.random() < 0.5:
            p.ico((x, y, h + 0.018), 0.018, 1, (1, 1, 0.6), (0, 0, 0), ("flower_yellow",))
    return p.finish()


# ---------------------------------------------------------------------------
# stable props
# ---------------------------------------------------------------------------

def _bucket(p, x, y, z, top_r, bot_r, height, body, fill=None, handle=True):
    p.cone((x, y, z + height * 0.5), bot_r, top_r, height, 10, (0, 0, 0), body)
    p.cyl((x, y, z + height - 0.012), top_r * 0.90, 0.025, "Z", 10,
          (fill or "wood_dark",))
    p.cyl((x, y, z + height * 0.45), (bot_r + top_r) * 0.52, 0.035, "Z", 10,
          ("metal_dark",))
    if handle:
        pts = arc_points((x - top_r * 0.9, y, z + height), (x + top_r * 0.9, y, z + height),
                         top_r * 1.0, 6)
        for i in range(len(pts) - 1):
            p.stick(pts[i], pts[i + 1], 0.016, 0.016, 4, ("metal",))


def water_trough(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.box((0, 0, 0.20), (1.85, 0.72, 0.10), (0, 0, 0), ("wood_dark",))
    for sy in (-1, 1):
        p.box((0, sy * 0.325, 0.44), (1.85, 0.07, 0.48), (0, 0, 0), WOOD)
    for sx in (-1, 1):
        p.box((sx * 0.89, 0, 0.44), (0.07, 0.65, 0.48), (0, 0, 0), WOOD)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.80, sy * 0.29, 0.09), (0.13, 0.13, 0.18), (0, 0, 0), ("wood_dark",))
    p.box((0, 0, 0.40), (1.68, 0.55, 0.03), (0, 0, 0), ("water",))
    for sy in (-1, 1):
        p.box((0, sy * 0.333, 0.65), (1.87, 0.03, 0.05), (0, 0, 0), ("metal_dark",))
    for i in range(3):
        p.box((-0.55 + i * 0.55, 0, 0.30), (0.06, 0.74, 0.10), (0, 0, 0), ("wood",))
    return p.finish()


def hay_round(name, seed):
    p = Prop(name, "stable", seed)
    p.cone((0, 0, 0.72), 0.70, 0.70, 1.20, 12, (0, math.pi / 2, 0), HAY, cap="hay_dark")
    for i, rad in enumerate((0.52, 0.34, 0.16)):
        p.cyl((0.612, 0, 0.72), rad, 0.02, "X", 12, ("hay_dark",))
    for sx in (-1, 1):
        p.cyl((sx * 0.35, 0, 0.72), 0.706, 0.035, "X", 12, ("rope",))
    return p.finish()


def hay_square(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.box((0, 0, 0.26), (1.10, 0.62, 0.50), (0, 0, 0), HAY)
    p.box((0.05, 0.02, 0.76), (1.05, 0.60, 0.48), (0, 0, r.uniform(-0.12, 0.12)), HAY)
    for sx in (-1, 1):
        for z in (0.26, 0.76):
            p.box((sx * 0.30, 0, z), (0.045, 0.65, 0.51), (0, 0, 0), ("rope",))
    for i in range(4):
        p.ico((r.uniform(-0.4, 0.4), r.uniform(-0.25, 0.25), 1.02),
              r.uniform(0.08, 0.14), 1, (1.3, 1, 0.5), (0, 0, r.uniform(0, TAU)), HAY)
    return p.finish()


def hay_feeder(name, seed):
    p = Prop(name, "stable", seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.55, sy * 0.33, 0.55), (0.09, 0.09, 1.10), (0, 0, 0), ("wood",))
    for z in (0.38, 0.72, 1.04):
        for sy in (-1, 1):
            p.box((0, sy * 0.33, z), (1.18, 0.055, 0.11), (0, 0, 0), ("wood_light",))
        for sx in (-1, 1):
            p.box((sx * 0.55, 0, z), (0.055, 0.72, 0.11), (0, 0, 0), ("wood_light",))
    p.box((0, 0, 0.44), (0.95, 0.52, 0.38), (0, 0, 0), HAY)
    for i in range(5):
        p.ico((p.rng.uniform(-0.4, 0.4), p.rng.uniform(-0.2, 0.2), 0.68),
              0.14, 1, (1.2, 1, 0.8), (0, 0, p.rng.uniform(0, TAU)), HAY)
    return p.finish()


def feed_bucket(name, seed):
    p = Prop(name, "stable", seed)
    _bucket(p, 0, 0, 0, 0.23, 0.17, 0.26, ("metal_dark",), fill="feed")
    p.ico((0, 0, 0.24), 0.17, 2, (1, 1, 0.35), (0, 0, 0), ("feed",))
    return p.finish()


def water_bucket(name, seed):
    p = Prop(name, "stable", seed)
    _bucket(p, 0, 0, 0, 0.20, 0.15, 0.28, ("churn",), fill="water")
    return p.finish()


def saddle_rack(name, seed):
    p = Prop(name, "stable", seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.stick((sx * 0.42, sy * 0.34, 0), (sx * 0.42, 0, 0.92), 0.045, 0.035, 5, ("wood",))
        p.stick((sx * 0.42, -0.34, 0), (sx * 0.42, 0.34, 0), 0.03, 0.03, 4, ("wood",))
    p.box((0, 0, 0.86), (0.78, 0.24, 0.09), (0, 0, 0), ("wood_light",))
    p.box((0, 0, 0.925), (0.82, 0.28, 0.06), (0, 0, 0), ("rope",))
    for sx in (-1, 1):
        p.stick((sx * 0.34, 0, 0.90), (sx * 0.52, 0, 1.10), 0.062, 0.042, 6, ("wood_light",))
        p.stick((sx * 0.52, 0, 1.10), (sx * 0.46, 0, 1.18), 0.042, 0.030, 6, ("wood_light",))
    return p.finish()


def hitching_post(name, seed):
    p = Prop(name, "stable", seed)
    for sx in (-1, 1):
        p.stick((sx * 1.25, 0, 0), (sx * 1.25, 0, 1.15), 0.075, 0.065, 6, ("wood",))
        p.stick((sx * 1.25, 0, 0.55), (sx * 1.25, -0.42, 0), 0.045, 0.03, 4, ("wood",))
    p.stick((-1.32, 0, 1.00), (1.32, 0, 1.00), 0.055, 0.055, 6, ("wood_light",))
    for sx in (-0.55, 0.55):
        p.cyl((sx, 0, 0.93), 0.065, 0.025, "X", 8, ("metal",))
    return p.finish()


def mounting_block(name, seed):
    p = Prop(name, "stable", seed)
    steps = ((0.58, 0.18), (0.06, 0.36), (-0.46, 0.54))
    for i, (x, h) in enumerate(steps):
        p.box((x, 0, h * 0.5), (0.50, 0.86, h), (0, 0, 0), ("wood", "wood_light"))
    for sy in (-1, 1):
        p.box((0.06, sy * 0.44, 0.27), (1.60, 0.06, 0.54), (0, 0, 0), ("wood_dark",))
    for i in range(3):
        p.box((-0.46, -0.28 + i * 0.28, 0.545), (0.48, 0.05, 0.02), (0, 0, 0), ("wood_dark",))
    return p.finish()


def feed_sack(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.ico((0, 0, 0.35), 0.30, 2, (1.0, 0.95, 1.15), (0.05, 0.03, 0.15), ("sack", "sack", "rope"))
    p.cone((0, 0, 0.70), 0.13, 0.055, 0.20, 7, (0, 0, 0), ("sack",))
    p.cyl((0, 0, 0.72), 0.085, 0.035, "Z", 7, ("rope",))
    for i in range(3):
        p.box((r.uniform(-0.15, 0.15), -0.27, 0.22 + i * 0.09), (0.25, 0.02, 0.03),
              (0, 0, r.uniform(-0.5, 0.5)), ("rope",))
    return p.finish()


def grooming_tote(name, seed):
    p = Prop(name, "stable", seed)
    p.box((0, 0, 0.10), (0.44, 0.30, 0.20), (0, 0, 0), ("wood_light",))
    p.box((0, 0, 0.203), (0.36, 0.22, 0.02), (0, 0, 0), ("wood_dark",))
    pts = arc_points((-0.19, 0, 0.20), (0.19, 0, 0.20), 0.26, 5)
    for i in range(len(pts) - 1):
        p.stick(pts[i], pts[i + 1], 0.018, 0.018, 4, ("rope",))
    for i, x in enumerate((-0.13, 0.0, 0.13)):
        p.stick((x, 0.02, 0.16), (x, 0.13, 0.35 + i * 0.02), 0.022, 0.018, 5, ("wood",))
        p.box((x, 0.15, 0.34 + i * 0.02), (0.05, 0.12, 0.06), (0.3, 0, 0), ("wood_light",))
        p.box((x, 0.15, 0.29 + i * 0.02), (0.045, 0.10, 0.04), (0.3, 0, 0), ("bark_dark",))
    return p.finish()


# ---------------------------------------------------------------------------
# yard props
# ---------------------------------------------------------------------------

def wheelbarrow(name, seed):
    p = Prop(name, "yard", seed)
    p.box((0.05, 0, 0.46), (0.82, 0.55, 0.07), (0, 0, 0), ("wood",))
    for sy in (-1, 1):
        p.box((0.05, sy * 0.27, 0.61), (0.82, 0.05, 0.30), (sy * 0.22, 0, 0), ("wood_light",))
    p.box((0.44, 0, 0.60), (0.06, 0.55, 0.30), (0, 0, 0), ("wood_light",))
    p.box((-0.36, 0, 0.60), (0.06, 0.55, 0.28), (0, 0, 0), ("wood_light",))
    for sy in (-1, 1):
        p.stick((-0.36, sy * 0.22, 0.50), (-1.05, sy * 0.30, 0.72), 0.035, 0.030, 5, ("wood",))
        p.stick((-0.16, sy * 0.20, 0.44), (-0.28, sy * 0.22, 0.0), 0.035, 0.028, 5, ("wood",))
    p.cyl((0.52, 0, 0.30), 0.29, 0.12, "Y", 12, ("wood_dark",), cap="wood")
    p.cyl((0.52, 0, 0.30), 0.075, 0.16, "Y", 8, ("metal_dark",))
    for i in range(3):
        p.box((0.52, 0, 0.30), (0.50, 0.035, 0.05), (0, i * math.pi / 3, 0), ("wood_light",))
    for sy in (-1, 1):
        p.stick((0.52, sy * 0.06, 0.30), (0.34, sy * 0.20, 0.46), 0.025, 0.025, 4, ("metal_dark",))
    return p.finish()


def barrel(name, seed):
    p = Prop(name, "yard", seed)
    segs = ((0.14, 0.26, 0.32, 0.28), (0.42, 0.32, 0.35, 0.28),
            (0.70, 0.35, 0.31, 0.28), (0.92, 0.31, 0.24, 0.16))
    for z, r1, r2, h in segs:
        p.cone((0, 0, z), r1, r2, h, 12, (0, 0, 0), ("wood", "wood_light"), cap="wood_dark")
    for z, rad in ((0.18, 0.345), (0.50, 0.362), (0.80, 0.335)):
        p.cyl((0, 0, z), rad, 0.045, "Z", 12, ("metal_dark",))
    p.cyl((0, 0, 1.005), 0.23, 0.03, "Z", 12, ("wood_dark",))
    return p.finish()


def crate(name, seed):
    p = Prop(name, "yard", seed)
    s = 0.60
    p.box((0, 0, 0.035), (s, s, 0.07), (0, 0, 0), ("wood_dark",))
    for i, z in enumerate((0.11, 0.25, 0.39, 0.53)):
        for sy in (-1, 1):
            p.box((0, sy * s * 0.5, z), (s, 0.028, 0.115), (0, 0, 0), ("wood_light", "wood"))
        for sx in (-1, 1):
            p.box((sx * s * 0.5, 0, z), (0.028, s, 0.115), (0, 0, 0), ("wood_light", "wood"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * s * 0.46, sy * s * 0.46, 0.29), (0.055, 0.055, 0.58),
                  (0, 0, 0), ("wood_dark",))
    for sy in (-1, 1):
        p.box((0, sy * s * 0.49, 0.585), (s + 0.02, 0.05, 0.05), (0, 0, 0), ("wood"))
    return p.finish()


def milk_churn(name, seed):
    p = Prop(name, "yard", seed)
    p.cone((0, 0, 0.26), 0.21, 0.17, 0.52, 10, (0, 0, 0), ("churn",))
    p.cone((0, 0, 0.57), 0.145, 0.125, 0.12, 10, (0, 0, 0), ("churn",))
    p.cone((0, 0, 0.68), 0.165, 0.10, 0.10, 10, (0, 0, 0), ("churn",))
    p.ico((0, 0, 0.74), 0.055, 1, (1, 1, 0.8), (0, 0, 0), ("metal_dark",))
    for sx in (-1, 1):
        p.box((sx * 0.17, 0, 0.61), (0.06, 0.10, 0.04), (0, 0, sx * 0.35), ("metal_dark",))
    p.cyl((0, 0, 0.45), 0.184, 0.03, "Z", 10, ("metal_dark",))
    return p.finish()


def bench(name, seed):
    p = Prop(name, "yard", seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.58, sy * 0.17, 0.22), (0.08, 0.08, 0.44), (0, 0, 0), ("wood_dark",))
        p.box((sx * 0.58, 0.19, 0.62), (0.08, 0.08, 0.46), (-0.18, 0, 0), ("wood_dark",))
    for i, y in enumerate((-0.18, 0.0, 0.18)):
        p.box((0, y, 0.46), (1.40, 0.13, 0.05), (0, 0, 0), ("wood_light",))
    for i, z in enumerate((0.72, 0.90)):
        p.box((0, 0.25, z), (1.40, 0.055, 0.14), (-0.18, 0, 0), ("wood_light",))
    return p.finish()


def firewood_stack(name, seed):
    p = Prop(name, "yard", seed)
    r = p.rng
    rows = (((-0.36, -0.12, 0.12, 0.36), 0.10),
            ((-0.24, 0.0, 0.24), 0.275),
            ((-0.12, 0.12), 0.45))
    for xs, z in rows:
        for x in xs:
            length = r.uniform(0.55, 0.65)
            p.cyl((x, 0, z), 0.095, length, "Y", 8, ("bark", "wood"), cap="wood_pale")
    p.box((0, -0.34, 0.02), (0.95, 0.07, 0.04), (0, 0, 0), ("wood_dark",))
    return p.finish()


def apple_basket(name, seed):
    p = Prop(name, "yard", seed)
    r = p.rng
    p.cone((0, 0, 0.14), 0.24, 0.31, 0.28, 12, (0, 0, 0), ("wood_light", "wood"), cap="wood_dark")
    for z in (0.06, 0.15, 0.24):
        p.cyl((0, 0, z), 0.30, 0.022, "Z", 12, ("wood_dark",))
    p.cyl((0, 0, 0.285), 0.27, 0.02, "Z", 12, ("wood_dark",))
    for i in range(6):
        a = TAU * i / 6
        rad = 0.16 if i % 2 == 0 else 0.11
        p.ico((math.cos(a) * rad, math.sin(a) * rad, 0.34 + (i % 2) * 0.04),
              0.075, 1, (1, 1, 0.95), (0, 0, r.uniform(0, TAU)), ("apple", "apple", "apple_green"))
    pts = arc_points((-0.30, 0, 0.28), (0.30, 0, 0.28), 0.33, 7)
    for i in range(len(pts) - 1):
        p.stick(pts[i], pts[i + 1], 0.018, 0.018, 4, ("rope",))
    return p.finish()


def flower_planter(name, seed):
    p = Prop(name, "yard", seed)
    r = p.rng
    p.box((0, 0, 0.20), (0.80, 0.38, 0.40), (0, 0, 0), ("wood_light", "wood"))
    for sy in (-1, 1):
        p.box((0, sy * 0.20, 0.38), (0.84, 0.04, 0.06), (0, 0, 0), ("wood_dark",))
    for sx in (-1, 1):
        p.box((sx * 0.41, 0, 0.38), (0.04, 0.42, 0.06), (0, 0, 0), ("wood_dark",))
    p.box((0, 0, 0.395), (0.72, 0.30, 0.02), (0, 0, 0), ("soil",))
    for i in range(9):
        x = r.uniform(-0.30, 0.30)
        y = r.uniform(-0.11, 0.11)
        h = r.uniform(0.50, 0.72)
        p.stick((x, y, 0.40), (x, y, h), 0.012, 0.006, 4, ("leaf_mid",))
        colour = r.choice(("flower_white", "flower_yellow", "blossom", "blossom_pale"))
        p.ico((x, y, h), r.uniform(0.05, 0.075), 1, (1, 1, 0.6),
              (0, 0, r.uniform(0, TAU)), (colour,))
        p.ico((x + 0.02, y, h + 0.02), 0.022, 1, (1, 1, 0.7), (0, 0, 0), ("flower_yellow",))
    return p.finish()


def well(name, seed):
    p = Prop(name, "yard", seed)
    r = p.rng
    for i in range(12):
        a = TAU * i / 12
        p.box((math.cos(a) * 0.86, math.sin(a) * 0.86, 0.36), (0.47, 0.24, 0.72),
              (0, 0, a), STONE)
        if i % 2 == 0:
            p.box((math.cos(a) * 0.86, math.sin(a) * 0.86, 0.76), (0.44, 0.26, 0.12),
                  (0, 0, a), ("stone_light",))
    p.cyl((0, 0, 0.68), 0.66, 0.04, "Z", 14, ("water",))
    for sx in (-1, 1):
        p.box((sx * 0.86, 0, 1.16), (0.11, 0.11, 2.32), (0, 0, 0), ("wood_dark",))
    p.stick((-0.92, 0, 2.02), (0.92, 0, 2.02), 0.075, 0.075, 6, ("wood",))
    for sy in (-1, 1):
        p.box((0, sy * 0.42, 2.34), (1.95, 0.95, 0.07), (sy * -0.60, 0, 0), ("roof_red",))
    p.stick((-0.98, 0, 2.58), (0.98, 0, 2.58), 0.05, 0.05, 5, ("wood_dark",))
    p.stick((0, 0, 2.00), (0, 0, 1.02), 0.022, 0.022, 5, ("rope",))
    p.cone((0, 0, 0.92), 0.15, 0.12, 0.28, 8, (0, 0, 0), ("wood",), cap="wood_dark")
    p.cyl((0, 0, 0.92), 0.153, 0.03, "Z", 8, ("metal_dark",))
    p.stick((0.92, 0, 2.02), (1.20, 0, 1.86), 0.03, 0.025, 4, ("metal",))
    return p.finish()


def water_pump(name, seed):
    p = Prop(name, "yard", seed)
    p.box((0, 0, 0.09), (0.54, 0.54, 0.18), (0, 0, 0), ("stone", "stone_light"))
    p.box((0, 0, 0.22), (0.36, 0.36, 0.12), (0, 0, 0), ("stone_dark",))
    p.cyl((0, 0, 0.62), 0.065, 0.72, "Z", 8, ("metal",))
    p.box((0, 0, 1.03), (0.24, 0.22, 0.26), (0, 0, 0), ("metal_dark",))
    p.cone((0, 0, 1.17), 0.13, 0.07, 0.10, 6, (0, 0, 0), ("metal",))
    p.stick((0, 0.06, 1.00), (0, 0.40, 0.92), 0.045, 0.040, 6, ("metal",))
    p.stick((0, 0.40, 0.92), (0, 0.40, 0.80), 0.040, 0.035, 6, ("metal",))
    p.stick((0, -0.08, 1.08), (0.38, -0.43, 1.20), 0.028, 0.022, 5, ("metal",))
    p.stick((0.38, -0.43, 1.20), (0.50, -0.52, 1.17), 0.035, 0.035, 5, ("wood_dark",))
    p.box((0, 0.48, 0.10), (0.76, 0.46, 0.20), (0, 0, 0), ("stone", "stone_light"))
    p.box((0, 0.48, 0.195), (0.66, 0.36, 0.02), (0, 0, 0), ("water",))
    return p.finish()


def signpost(name, seed):
    p = Prop(name, "yard", seed)
    p.stick((0, 0, 0), (0, 0, 1.95), 0.075, 0.06, 6, ("wood_dark",))
    p.cone((0, 0, 1.98), 0.11, 0.02, 0.14, 6, (0, 0, 0), ("wood_dark",))
    for z, sign in ((1.62, 1), (1.30, -1)):
        p.box((sign * 0.36, 0, z), (0.94, 0.06, 0.24), (0, 0, 0), ("wood_light",))
        p.box((sign * 0.86, 0, z), (0.18, 0.06, 0.18), (0, 0, math.pi / 4), ("wood_light",))
        p.box((sign * 0.30, -0.045, z), (0.58, 0.012, 0.10), (0, 0, 0), ("flower_white",))
        p.box((sign * 0.30, 0.045, z), (0.58, 0.012, 0.10), (0, 0, 0), ("flower_white",))
    return p.finish()


def lantern_post(name, seed):
    p = Prop(name, "yard", seed)
    p.box((0, 0, 0.06), (0.26, 0.26, 0.12), (0, 0, 0), ("stone_dark",))
    p.box((0, 0, 1.02), (0.10, 0.10, 2.04), (0, 0, 0), ("wood_dark",))
    p.stick((0, 0, 2.00), (0.44, 0, 1.94), 0.03, 0.025, 5, ("metal_dark",))
    p.stick((0.44, 0, 1.94), (0.44, 0, 1.82), 0.02, 0.02, 4, ("metal_dark",))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.44 + sx * 0.085, sy * 0.085, 1.68), (0.02, 0.02, 0.26),
                  (0, 0, 0), ("metal_dark",))
    p.box((0.44, 0, 1.55), (0.22, 0.22, 0.03), (0, 0, 0), ("metal_dark",))
    p.box((0.44, 0, 1.81), (0.22, 0.22, 0.03), (0, 0, 0), ("metal_dark",))
    p.box((0.44, 0, 1.68), (0.15, 0.15, 0.22), (0, 0, 0), ("glass_warm",))
    p.cone((0.44, 0, 1.90), 0.17, 0.02, 0.14, 4, (0, 0, math.pi / 4), ("metal_dark",))
    return p.finish()


# ---------------------------------------------------------------------------
# garden and farmyard props
# ---------------------------------------------------------------------------

def chicken_coop(name, seed):
    p = Prop(name, "garden", seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.52, sy * 0.32, 0.19), (0.09, 0.09, 0.38), (0, 0, 0), ("wood_dark",))
    p.box((0, 0, 0.55), (1.40, 0.92, 0.06), (0, 0, 0), ("wood_dark",))
    p.box((0, 0, 0.85), (1.30, 0.84, 0.56), (0, 0, 0), ("plaster", "wood"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.63, sy * 0.40, 0.85), (0.07, 0.07, 0.56), (0, 0, 0), ("wood",))
    for sy in (-1, 1):
        p.box((0, sy * 0.30, 1.27), (1.56, 0.78, 0.06), (sy * -0.82, 0, 0), ("roof_red",))
    p.stick((-0.80, 0, 1.50), (0.80, 0, 1.50), 0.045, 0.045, 4, ("wood_dark",))
    p.box((0.20, -0.435, 0.78), (0.34, 0.03, 0.40), (0, 0, 0), ("bark_dark",))
    p.box((-0.42, -0.435, 0.92), (0.24, 0.03, 0.20), (0, 0, 0), ("bark_dark",))
    ramp_rot = 0.52
    p.box((0.20, -0.85, 0.30), (0.32, 1.02, 0.045), (ramp_rot, 0, 0), ("wood_light",))
    for i in range(3):
        p.box((0.20, -1.10 + i * 0.22, 0.14 + i * 0.15), (0.34, 0.05, 0.035),
              (ramp_rot, 0, 0), ("wood_dark",))
    p.box((0.82, 0.10, 0.72), (0.30, 0.34, 0.26), (0, 0, 0), ("plaster",))
    p.box((0.82, 0.10, 0.86), (0.36, 0.40, 0.05), (0, 0, 0), ("roof_red",))
    return p.finish()


def beehive(name, seed):
    p = Prop(name, "garden", seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.22, sy * 0.16, 0.12), (0.06, 0.06, 0.24), (0, 0, 0), ("wood_dark",))
    p.box((0, 0, 0.26), (0.56, 0.46, 0.05), (0, 0, 0), ("wood",))
    for i, z in enumerate((0.40, 0.62, 0.84)):
        p.box((i * 0.01, 0, z), (0.46 - i * 0.01, 0.40, 0.21), (0, 0, 0), ("wood_pale", "wood_light"))
    p.box((0, -0.205, 0.36), (0.24, 0.02, 0.05), (0, 0, 0), ("bark_dark",))
    p.box((0, -0.245, 0.33), (0.32, 0.10, 0.03), (0, 0, 0), ("wood",))
    p.box((0, 0, 0.98), (0.58, 0.52, 0.05), (0, 0, 0), ("wood_dark",))
    p.cone((0, 0, 1.06), 0.38, 0.03, 0.12, 4, (0, 0, math.pi / 4), ("roof", "roof_red"))
    return p.finish()


def fence_panel(name, seed):
    p = Prop(name, "garden", seed)
    for sx in (-1, 1):
        p.box((sx * 1.25, 0, 0.60), (0.11, 0.11, 1.20), (0, 0, 0), ("wood",))
    for z in (0.34, 0.70, 1.02):
        p.box((0, 0, z), (2.42, 0.06, 0.13), (0, 0, 0), ("wood_light",))
    for sx in (-1, 1):
        p.box((sx * 1.25, 0, 1.235), (0.16, 0.16, 0.07), (0, 0, 0), ("wood_dark",))
    return p.finish()


def farm_gate(name, seed):
    p = Prop(name, "garden", seed)
    for sx in (-1, 1):
        p.box((sx * 1.32, 0, 0.66), (0.14, 0.14, 1.32), (0, 0, 0), ("wood_dark",))
    for sx in (-1, 1):
        p.box((sx * 1.06, 0, 0.66), (0.09, 0.09, 1.00), (0, 0, 0), ("wood_light",))
    for z in (0.28, 1.10):
        p.box((0, 0, z), (2.20, 0.08, 0.13), (0, 0, 0), ("wood_light",))
    p.stick((-1.02, 0, 0.34), (1.02, 0, 1.04), 0.045, 0.045, 4, ("wood",))
    for x in (-0.55, 0, 0.55):
        p.box((x, 0, 0.70), (0.06, 0.05, 0.78), (0, 0, 0), ("wood",))
    p.box((1.02, 0, 0.92), (0.16, 0.06, 0.10), (0, 0, 0), ("metal_dark",))
    return p.finish()


# ---------------------------------------------------------------------------
# jump course props
# ---------------------------------------------------------------------------

def jump_wing(name, seed):
    p = Prop(name, "course", seed)
    p.box((0, 0, 0.045), (0.72, 0.09, 0.09), (0, 0, 0), ("wood",))
    p.box((0, 0, 0.045), (0.09, 0.72, 0.09), (0, 0, 0), ("wood",))
    p.box((0, 0, 0.86), (0.10, 0.10, 1.70), (0, 0, 0), ("paint_white",))
    for z in (0.42, 0.86, 1.30):
        p.box((0, 0, z), (0.115, 0.115, 0.16), (0, 0, 0), ("paint_red",))
    p.box((0, 0, 1.72), (0.14, 0.14, 0.05), (0, 0, 0), ("paint_red",))
    for z in (0.32, 0.58, 0.84, 1.10):
        p.cyl((0, 0, z), 0.035, 0.34, "Y", 6, ("metal",))
        p.cyl((0, 0.18, z), 0.055, 0.035, "Y", 6, ("metal_dark",))
    return p.finish()


def jump_pole(name, seed):
    p = Prop(name, "course", seed)
    bands = 10
    band = 0.30
    for i in range(bands):
        x = -1.5 + band * (i + 0.5)
        p.cyl((x, 0, 0.06), 0.05, band, "X", 8, ("paint_red" if i % 2 == 0 else "paint_white",),
              cap="paint_white")
    return p.finish()


# ---------------------------------------------------------------------------
# grooming tools
# ---------------------------------------------------------------------------

def curry_comb(name, seed):
    p = Prop(name, "grooming", seed)
    r = p.rng
    p.ico((0, 0, 0.030), 0.078, 3, (1.18, 1.0, 0.32), (0, 0, 0), ("rubber",))
    for ring, count, rad in ((0, 6, 0.020), (1, 11, 0.044), (2, 15, 0.066)):
        for i in range(count):
            a = TAU * i / count + ring * 0.18
            p.ico((math.cos(a) * rad, math.sin(a) * rad * 0.82, 0.047), 0.0068, 1,
                  (1, 1, 1.4), (0, 0, 0), ("rubber", "rubber", "metal_dark"))
    p.box((0.052, 0, 0.038), (0.030, 0.070, 0.010), (0, 0, 0), ("leather",))
    return p.finish()


def _groom_brush(name, seed, back, bristles, width=0.13, depth=0.085, length=0.024):
    p = Prop(name, "grooming", seed)
    r = p.rng
    half = width * 0.5
    p.ico((0, 0, 0.028), half, 2, (1.0, depth / width, 0.36), (0, 0, 0), (back,))
    p.cyl((0, 0, 0.020), half * 0.98, 0.020, "Z", 16, ("wood_dark",))
    cols, rows = 17, 9
    for i in range(cols):
        for j in range(rows):
            x = -width * 0.40 + i * (width * 0.80 / (cols - 1))
            y = -depth * 0.36 + j * (depth * 0.72 / (rows - 1))
            top = 0.046 - (x / (width * 0.62)) ** 2 * 0.018 - (y / (depth * 0.70)) ** 2 * 0.012
            h = length * r.uniform(0.86, 1.08)
            p.cyl((x, y, top + h * 0.5), 0.0032, h, "Z", 4, (bristles,), r2=0.0022)
    return p.finish()


def dandy_brush(name, seed):
    return _groom_brush(name, seed, "wood_light", "bristle_dark")


def soft_brush(name, seed):
    return _groom_brush(name, seed, "wood", "bristle_pale", width=0.125, depth=0.08,
                        length=0.026)


def face_brush(name, seed):
    return _groom_brush(name, seed, "wood_light", "bristle_grey",
                        width=0.085, depth=0.055, length=0.020)


def hoof_pick(name, seed):
    p = Prop(name, "grooming", seed)
    p.stick((-0.135, -0.010, 0.016), (0.010, 0.0, 0.020), 0.015, 0.018, 8, ("wood_dark",))
    p.stick((0.010, 0, 0.020), (0.052, 0, 0.052), 0.012, 0.009, 6, ("metal_dark",))
    p.stick((0.052, 0, 0.052), (0.082, 0, 0.014), 0.007, 0.002, 5, ("metal",))
    p.box((-0.158, -0.010, 0.012), (0.036, 0.048, 0.020), (0, 0, 0), ("wood",))
    for i in range(3):
        for j in range(3):
            p.cyl((-0.170 + i * 0.012, -0.022 + j * 0.012, 0.004), 0.0035, 0.014, "Z", 4,
                  ("bristle_dark",), r2=0.002)
    return p.finish()


def sponge(name, seed):
    p = Prop(name, "grooming", seed)
    r = p.rng
    p.ico((0, 0, 0.045), 0.078, 2, (1.24, 1.0, 0.52), (0, 0, 0), ("sponge",))
    p.warp(lambda v: (setattr(v.co, "x", v.co.x + r.uniform(-0.009, 0.009)),
                      setattr(v.co, "y", v.co.y + r.uniform(-0.009, 0.009)),
                      setattr(v.co, "z", v.co.z + r.uniform(-0.005, 0.005))))
    for i in range(9):
        a = r.uniform(0, TAU)
        rad = r.uniform(0.015, 0.062)
        p.ico((math.cos(a) * rad, math.sin(a) * rad * 0.8, 0.070 + r.uniform(-0.012, 0.004)),
              r.uniform(0.006, 0.010), 1, (1, 1, 0.6), (0, 0, 0),
              ("wood_dark", "bark_dark"))
    return p.finish()


def sweat_scraper(name, seed):
    p = Prop(name, "grooming", seed)
    p.box((0, 0, 0.030), (0.240, 0.014, 0.060), (0, 0, 0), ("rubber",))
    for sx in (-1, 1):
        p.box((sx * 0.140, 0, 0.044), (0.062, 0.013, 0.052), (0, sx * 0.42, 0), ("rubber",))
    for sx in (-1, 1):
        p.box((sx * 0.058, 0, 0.090), (0.014, 0.026, 0.120), (0, 0, 0), ("wood",))
    p.box((0, 0, 0.150), (0.130, 0.028, 0.022), (0, 0, 0), ("wood_light",))
    p.box((0, 0, 0.058), (0.150, 0.040, 0.030), (0, 0, 0), ("wood_dark",))
    return p.finish()


# ---------------------------------------------------------------------------
# extra stable gear
# ---------------------------------------------------------------------------

def hay_net(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.ico((0, 0, 0.28), 0.30, 2, (1.0, 1.0, 0.92), (0, 0, 0), HAY)
    p.ico((0.05, 0.02, 0.47), 0.22, 2, (1, 1, 0.90),
          (0, 0, r.uniform(0, TAU)), HAY)
    rings = ((0.10, 0.27), (0.24, 0.315), (0.38, 0.275), (0.52, 0.175))
    for z, rad in rings:
        pts = [Vector((math.cos(TAU * i / 12) * rad, math.sin(TAU * i / 12) * rad, z))
               for i in range(13)]
        for i in range(12):
            p.stick(pts[i], pts[i + 1], 0.0075, 0.0075, 3, ("rope",))
    for i in range(8):
        a = TAU * i / 8
        p.stick((math.cos(a) * 0.275, math.sin(a) * 0.275, 0.10),
                (math.cos(a) * 0.115, math.sin(a) * 0.115, 0.56),
                0.0065, 0.0065, 3, ("rope",))
    p.cyl((0, 0, 0.60), 0.045, 0.035, "Z", 6, ("rope",))
    return p.finish()


def pitchfork(name, seed):
    p = Prop(name, "stable", seed)
    p.stick((0.0, 0.0, 0.17), (0.09, 0.035, 1.42), 0.026, 0.019, 6, ("wood",))
    p.box((0.0, 0.0, 0.185), (0.24, 0.048, 0.045), (0, 0, 0), ("metal_dark",))
    for i in range(4):
        x = -0.088 + i * 0.0587
        p.stick((x, 0, 0.175), (x * 1.35, 0.0, 0.004), 0.010, 0.004, 4, ("metal",))
    return p.finish()


def broom(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.stick((0.0, 0, 1.30), (0.02, 0.0, 0.44), 0.020, 0.028, 6, ("wood_light",))
    for i in range(38):
        a = TAU * i / 38 + r.uniform(-0.10, 0.10)
        rad = r.uniform(0.05, 0.17)
        p.stick((0.02 + r.uniform(-0.020, 0.020), r.uniform(-0.020, 0.020), 0.46),
                (0.02 + math.cos(a) * rad, math.sin(a) * rad, 0.004),
                0.013, 0.0055, 4, ("bristle_pale", "hay_dark", "bristle_grey"))
    for z in (0.38, 0.45, 0.50):
        p.cyl((0.02, 0, z), 0.052 + (z - 0.38) * 0.55, 0.028, "Z", 10, ("rope",))
    return p.finish()


def muck_tub(name, seed):
    p = Prop(name, "stable", seed)
    p.cone((0, 0, 0.16), 0.30, 0.39, 0.32, 12, (0, 0, 0), ("rubber",), cap="metal_dark")
    p.cyl((0, 0, 0.315), 0.395, 0.030, "Z", 12, ("metal", "metal_dark"))
    for sx in (-1, 1):
        for dz in (0.10, 0.24):
            p.cyl((sx * 0.375, 0, dz), 0.022, 0.055, "X", 5, ("metal_dark",))
    p.box((0, 0, 0.30), (0.70, 0.035, 0.025), (0, 0, 0), ("metal",))
    return p.finish()


def saddle_blanket(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    p.box((0, 0, 0.038), (0.68, 0.54, 0.075), (0, 0, r.uniform(-0.03, 0.03)), ("paint_white",))
    p.box((0.0, 0, 0.110), (0.64, 0.50, 0.070), (0, 0, r.uniform(-0.04, 0.04)), ("paint_red",))
    p.box((0.015, 0, 0.176), (0.60, 0.46, 0.062), (0, 0, r.uniform(-0.05, 0.05)),
          ("paint_white",))
    for i in range(3):
        p.box((-0.19 + i * 0.19, 0, 0.210), (0.028, 0.45, 0.018), (0, 0, 0), ("paint_red",))
    p.box((0, 0, 0.115), (0.69, 0.045, 0.135), (0, 0, 0), ("leather",))
    p.box((0.155, 0, 0.150), (0.055, 0.032, 0.030), (0, 0, 0), ("metal",))
    return p.finish()


def lead_rope(name, seed):
    p = Prop(name, "stable", seed)
    for rad, z in ((0.255, 0.015), (0.195, 0.030), (0.135, 0.045)):
        pts = [Vector((math.cos(TAU * i / 14) * rad, math.sin(TAU * i / 14) * rad, z))
               for i in range(15)]
        for i in range(14):
            p.stick(pts[i], pts[i + 1], 0.017, 0.017, 4, ("rope",))
    p.stick((0.135, 0, 0.045), (0.36, 0.17, 0.018), 0.017, 0.014, 5, ("rope",))
    p.box((0.375, 0.175, 0.022), (0.040, 0.060, 0.022), (0, 0.35, 0.35), ("metal",))
    return p.finish()


def carrot_bunch(name, seed):
    p = Prop(name, "stable", seed)
    r = p.rng
    for i in range(6):
        a = TAU * i / 6 + r.uniform(-0.2, 0.2)
        rad = r.uniform(0.030, 0.060)
        x, y = math.cos(a) * rad, math.sin(a) * rad
        tilt = math.radians(r.uniform(8, 16))
        p.cone((x, y, 0.085), 0.005, 0.019, 0.17, 7, (tilt, tilt * 0.7, a), ("carrot",))
        tip = (x, y, 0.170)
        for j in range(3):
            aa = a + (j - 1) * 0.5
            p.stick(tip, (x + math.cos(aa) * r.uniform(0.03, 0.07),
                          y + math.sin(aa) * r.uniform(0.03, 0.07),
                          0.170 + r.uniform(0.045, 0.085)), 0.005, 0.0015, 4,
                    ("leaf_mid", "leaf_light"))
    return p.finish()


# ---------------------------------------------------------------------------
# crowd
# ---------------------------------------------------------------------------

def _figure_hat(p, z, brim=0.16, crown=0.10, colour="straw"):
    p.cyl((0, 0.01, z + 0.010), brim, 0.020, "Z", 10, (colour, "hay_dark"))
    p.cyl((0, 0.01, z + 0.055), crown * 0.62, 0.075, "Z", 8, (colour,))


def _standing_figure(name, seed, coat, trousers, hat=None, scarf=False):
    p = Prop(name, "crowd", seed)
    r = p.rng
    for sx in (-1, 1):
        p.stick((sx * 0.085, 0, 0.03), (sx * 0.100, 0.005, 0.90), 0.060, 0.050, 5, (trousers,))
        p.box((sx * 0.10, -0.035, 0.035), (0.105, 0.215, 0.065), (0, 0, 0), ("boot",))
        p.stick((sx * 0.175, 0.005, 1.24), (sx * 0.205, -0.020, 0.93), 0.052, 0.038, 5, (coat,))
        p.ico((sx * 0.205, -0.030, 0.885), 0.042, 1, (1, 1, 0.9), (0, 0, 0), ("skin",))
    p.box((0, 0, 1.055), (0.345, 0.230, 0.400), (0, 0, 0), (coat,))
    p.box((0, 0, 0.865), (0.315, 0.215, 0.100), (0, 0, 0), (coat,))
    p.box((0, 0, 0.800), (0.285, 0.200, 0.075), (0, 0, 0), (trousers,))
    p.cyl((0, 0, 1.285), 0.052, 0.070, "Z", 7, ("skin",))
    p.ico((0, -0.005, 1.395), 0.105, 2, (0.95, 1.0, 1.05), (0, 0, 0), ("skin",))
    p.ico((0, 0.018, 1.430), 0.098, 2, (1.0, 1.0, 0.72), (0, 0, 0), ("hair",))
    if scarf:
        p.box((0, 0, 1.245), (0.230, 0.190, 0.055), (0, 0, 0), ("coat_red",))
    if hat is not None:
        _figure_hat(p, 1.455, colour=hat)
    return p.finish()


def _seated_figure(name, seed, coat, trousers, hat=None, child=False):
    p = Prop(name, "crowd", seed)
    r = p.rng
    p.box((0, 0, 0.075), (0.300, 0.245, 0.155), (0, 0, 0), (trousers,))
    p.box((0, 0.010, 0.300), (0.350, 0.240, 0.310), (math.radians(-5), 0, 0), (coat,))
    p.box((0, 0.015, 0.455), (0.300, 0.225, 0.090), (0, 0, 0), (coat,))
    p.cyl((0, 0.005, 0.520), 0.048, 0.065, "Z", 7, ("skin",))
    p.ico((0, -0.005, 0.590), 0.100, 2, (0.95, 1.0, 1.05), (0, 0, 0), ("skin",))
    p.ico((0, 0.020, 0.620), 0.092, 2, (1.0, 1.0, 0.70), (0, 0, 0), ("hair",))
    for sx in (-1, 1):
        p.stick((sx * 0.095, -0.015, 0.105), (sx * 0.110, -0.250, 0.090), 0.062, 0.052, 5, (trousers,))
        p.stick((sx * 0.110, -0.250, 0.085), (sx * 0.120, -0.300, -0.345), 0.050, 0.036, 5, (trousers,))
        p.box((sx * 0.120, -0.330, -0.370), (0.105, 0.205, 0.065), (0, 0, 0), ("boot",))
        p.stick((sx * 0.180, 0.010, 0.440), (sx * 0.195, -0.170, 0.190), 0.050, 0.038, 5, (coat,))
        p.ico((sx * 0.195, -0.205, 0.155), 0.042, 1, (1, 1, 0.9), (0, 0, 0), ("skin",))
    if hat is not None:
        _figure_hat(p, 0.640, brim=0.145, colour=hat)
    if child:
        p.warp(lambda v: setattr(v.co, "z", v.co.z * 0.82))
        p.warp(lambda v: setattr(v.co, "x", v.co.x * 0.72))
        p.warp(lambda v: setattr(v.co, "y", v.co.y * 0.72))
    return p.finish()


def spectator_standing_a(name, seed):
    return _standing_figure(name, seed, "coat_blue", "coat_grey", hat="straw")


def spectator_standing_b(name, seed):
    return _standing_figure(name, seed, "coat_mustard", "denim", scarf=True)


def spectator_seated_a(name, seed):
    return _seated_figure(name, seed, "coat_red", "coat_grey")


def spectator_seated_b(name, seed):
    return _seated_figure(name, seed, "coat_green", "denim", hat="straw")


def spectator_seated_c(name, seed):
    return _seated_figure(name, seed, "coat_grey", "boot")


def spectator_child(name, seed):
    return _seated_figure(name, seed, "coat_blue", "denim", child=True)


# ---------------------------------------------------------------------------
# arena dressing
# ---------------------------------------------------------------------------

def judge_bell(name, seed):
    p = Prop(name, "arena", seed)
    p.cyl((0, 0, 0.010), 0.062, 0.020, "Z", 10, ("brass", "metal_dark"))
    p.cone((0, 0, 0.060), 0.054, 0.016, 0.090, 10, (0, 0, 0), ("brass",), cap="metal_dark")
    p.cyl((0, 0, 0.014), 0.010, 0.018, "Z", 6, ("metal_dark",))
    p.stick((-0.030, 0, 0.112), (0.030, 0, 0.112), 0.010, 0.010, 5, ("metal_dark",))
    p.stick((0, 0, 0.112), (0, 0, 0.150), 0.012, 0.015, 6, ("wood_dark",))
    p.ico((0, 0, 0.158), 0.018, 1, (1, 1, 0.9), (0, 0, 0), ("wood_dark",))
    return p.finish()


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

def build_trees():
    tree_oak("tree_oak_01", 101, height=5.8, spread=1.9)
    tree_oak("tree_oak_02", 102, height=5.1, spread=2.25)
    tree_oak("tree_oak_03", 103, height=6.5, spread=1.7)
    tree_oak("tree_oak_autumn", 104, height=5.6, spread=1.95, shades=AUTUMN)
    tree_oak("tree_apple", 105, height=4.6, spread=1.6, apples=True)
    tree_birch("tree_birch", 106)
    tree_pine("tree_pine_01", 107, height=7.4, spread=1.95)
    tree_pine("tree_pine_02", 108, height=5.6, spread=1.45)
    tree_willow("tree_willow", 109)
    tree_dead("tree_dead", 110)
    tree_sapling("tree_sapling", 111)
    tree_stump("tree_stump", 112)
    fallen_log("fallen_log", 113)


def build_bushes():
    bush_sphere("bush_round", 201, size=0.85)
    bush_sphere("bush_large", 202, size=1.15, shades=LEAF)
    bush_sphere("bush_berry", 203, size=0.8, berries=14)
    bush_sphere("bush_flower", 204, size=0.75, blossom=11)
    bush_sphere("bush_flower_pale", 205, size=0.9, blossom=13)
    bush_hedge("hedge_section", 206)
    bush_bramble("bush_bramble", 207)


def build_nature():
    rock_cluster("rock_cluster_01", 301, size=0.9)
    rock_cluster("rock_cluster_02", 302, size=1.4)
    mushroom_cluster("mushroom_cluster", 303)
    grass_tuft("grass_tuft", 304)
    grass_tuft("grass_tuft_small", 305)
    reeds("reeds", 306)
    flower_patch("flower_patch", 307)


def build_stable():
    water_trough("water_trough", 401)
    hay_round("hay_round", 402)
    hay_square("hay_square", 403)
    hay_feeder("hay_feeder", 404)
    feed_bucket("feed_bucket", 405)
    water_bucket("water_bucket", 406)
    saddle_rack("saddle_rack", 407)
    hitching_post("hitching_post", 408)
    mounting_block("mounting_block", 409)
    feed_sack("feed_sack", 410)
    grooming_tote("grooming_tote", 411)
    hay_net("hay_net", 412)
    pitchfork("pitchfork", 413)
    broom("broom", 414)
    muck_tub("muck_tub", 415)
    saddle_blanket("saddle_blanket", 416)
    lead_rope("lead_rope", 417)
    carrot_bunch("carrot_bunch", 418)


def build_yard():
    wheelbarrow("wheelbarrow", 501)
    barrel("barrel", 502)
    crate("crate", 503)
    milk_churn("milk_churn", 504)
    bench("bench", 505)
    firewood_stack("firewood_stack", 506)
    apple_basket("apple_basket", 507)
    flower_planter("flower_planter", 508)
    well("well", 509)
    water_pump("water_pump", 510)
    signpost("signpost", 511)
    lantern_post("lantern_post", 512)


def build_garden():
    chicken_coop("chicken_coop", 601)
    beehive("beehive", 602)
    fence_panel("fence_panel", 603)
    farm_gate("farm_gate", 604)


def build_course():
    jump_wing("jump_wing", 701)
    jump_pole("jump_pole", 702)


def build_crowd():
    spectator_standing_a("spectator_standing_a", 901)
    spectator_standing_b("spectator_standing_b", 902)
    spectator_seated_a("spectator_seated_a", 903)
    spectator_seated_b("spectator_seated_b", 904)
    spectator_seated_c("spectator_seated_c", 905)
    spectator_child("spectator_child", 906)


def showground_arch(name, seed):
    p = Prop(name, "arena", seed)
    for sz in (-1, 1):
        p.box((0, 0.28, sz * 3.15), (0.30, 0.56, 0.30), (0, 0, 0), ("wood_dark",))
        p.box((0, 2.20, sz * 3.15), (0.26, 3.90, 0.26), (0, 0, 0), ("wood", "wood_light"))
    p.box((0, 4.33, 0), (0.32, 0.34, 6.86), (0, 0, 0), ("wood_dark",))
    p.box((0, 4.78, 0), (0.10, 0.62, 6.10), (0, 0, 0), ("paint_red",))
    p.box((0, 4.48, 0), (0.12, 0.10, 6.20), (0, 0, 0), ("wood_light",))
    for sz in (-1, 1):
        p.box((0, 4.78, sz * 3.10), (0.13, 0.68, 0.12), (0, 0, 0), ("wood_dark",))
    return p.finish()


def build_arena():
    judge_bell("judge_bell", 1001)
    showground_arch("showground_arch", 1002)


def build_grooming():
    curry_comb("curry_comb", 801)
    dandy_brush("dandy_brush", 802)
    soft_brush("soft_brush", 803)
    face_brush("face_brush", 804)
    hoof_pick("hoof_pick", 805)
    sponge("sponge", 806)
    sweat_scraper("sweat_scraper", 807)


def build_all():
    build_trees()
    build_bushes()
    build_nature()
    build_stable()
    build_yard()
    build_garden()
    build_course()
    build_grooming()
    build_crowd()
    build_arena()


# ---------------------------------------------------------------------------
# export, layout, save, render
# ---------------------------------------------------------------------------

def mesh_bounds(obj):
    verts = obj.data.vertices
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_props():
    manifest = []
    for p in ALL_PROPS:
        path = os.path.join(OUT_DIR, p.category, p.name + ".glb")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        lo, hi = mesh_bounds(p.obj)
        dims = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        bpy.ops.object.select_all(action="DESELECT")
        p.obj.select_set(True)
        bpy.context.view_layer.objects.active = p.obj
        bpy.ops.export_scene.gltf(
            filepath=path, use_selection=True, export_format="GLB",
            export_apply=True, export_yup=True)
        try:
            p.obj.asset_mark()
            p.obj.asset_data.description = "%s prop from the Groom library" % p.category
            p.obj.asset_data.tags.new(p.category)
        except Exception as exc:
            print("[props] asset tag skipped for", p.name, exc)
        manifest.append({
            "name": p.name,
            "category": p.category,
            "file": os.path.relpath(path, ROOT).replace(os.sep, "/"),
            "size_m": [round(d, 3) for d in dims],
            "triangles": tri_count(p.obj),
            "materials": list(p.slots),
        })
    os.makedirs(OUT_DIR, exist_ok=True)
    if STAGE == "all":
        with open(os.path.join(OUT_DIR, "props_manifest.json"), "w") as fh:
            json.dump({"props": manifest}, fh, indent=2)
    print("[props] exported %d props" % len(manifest))


LABELS = []
ROWS = {}
CATEGORY_ORDER = ("trees", "bushes", "nature", "stable", "yard", "garden",
                  "course", "grooming", "crowd", "arena")


def layout_props():
    cats = [c for c in CATEGORY_ORDER if any(p.category == c for p in ALL_PROPS)]
    y = 0.0
    for cat in cats:
        items = sorted([p for p in ALL_PROPS if p.category == cat], key=lambda q: q.name)
        sizes = []
        for p in items:
            lo, hi = mesh_bounds(p.obj)
            sizes.append((hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
        max_w = max(s[0] for s in sizes)
        max_d = max(s[1] for s in sizes)
        cols = 5
        cell_w = max(2.3, max_w + 1.15)
        cell_d = max(2.4, max_d + 2.0)
        rows = (len(items) + cols - 1) // cols
        category_rows = []
        for i, p in enumerate(items):
            lo, hi = mesh_bounds(p.obj)
            w = hi[0] - lo[0]
            col = i % cols
            row = i // cols
            x = col * cell_w + (cell_w - w) * 0.5
            yy = y + row * cell_d
            p.obj.location = (x - lo[0], yy - lo[1], 0)
            label = add_label(p.name.replace("_", " "),
                              (col * cell_w + cell_w * 0.5, yy - 0.55, 0.02))
            LABELS.append((cat, label))
            if len(category_rows) <= row:
                category_rows.append({"items": [], "labels": []})
            category_rows[row]["items"].append(p)
            category_rows[row]["labels"].append(label)
        ROWS[cat] = category_rows
        y += rows * cell_d + 5.0
    return cats


def add_label(text, loc):
    curve = bpy.data.curves.new("label_" + text.replace(" ", "_"), type="FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.size = 0.28
    obj = bpy.data.objects.new(curve.name, curve)
    obj.location = loc
    obj.rotation_euler = (math.radians(90), 0, 0)
    mat = material("bark_dark")
    obj.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def setup_studio():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = False
    scene.eevee.taa_render_samples = 32
    scene.eevee.use_gtao = True
    if hasattr(scene.eevee, "use_soft_shadows"):
        scene.eevee.use_soft_shadows = True
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.15
    world = bpy.data.worlds.new("PropWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.56, 0.63, 0.70, 1.0)
    bg.inputs["Strength"].default_value = 0.85
    scene.world = world

    ground_mat = bpy.data.materials.new("P_ground")
    ground_mat.use_nodes = True
    bsdf = ground_mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.44, 0.46, 0.40, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    me = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=140.0)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(ground_mat)
    ground = bpy.data.objects.new("Ground", me)
    bpy.context.scene.collection.objects.link(ground)

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.0
    sun_data.angle = math.radians(16)
    sun_data.color = (1.0, 0.94, 0.84)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(52), math.radians(8), math.radians(38))
    bpy.context.scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("Fill", type="AREA")
    fill_data.energy = 700.0
    fill_data.size = 20.0
    fill_data.color = (0.78, 0.86, 1.0)
    fill = bpy.data.objects.new("Fill", fill_data)
    fill.location = (0, -14, 12)
    fill.rotation_euler = (math.radians(52), 0, 0)
    bpy.context.scene.collection.objects.link(fill)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 12.0
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam
    return cam, ground


def _bbox_points(obj):
    lo, hi = mesh_bounds(obj)
    corners = []
    for x in (lo[0], hi[0]):
        for y in (lo[1], hi[1]):
            for z in (lo[2], hi[2]):
                corners.append(obj.location + Vector((x, y, z)))
    return corners


def _basis(elev_deg):
    elev = math.radians(elev_deg)
    view_dir = Vector((0.0, math.cos(elev), -math.sin(elev)))
    right = view_dir.cross(Vector((0.0, 0.0, 1.0))).normalized()
    up = right.cross(view_dir).normalized()
    return view_dir, right, up


def _project(points, right, up):
    xs = [p.dot(right) for p in points]
    ys = [p.dot(up) for p in points]
    return min(xs), max(xs), min(ys), max(ys)


def frame_points(cam, points, res_x, res_y, elev_deg=32.0, margin=1.10, scale=None):
    view_dir, right, up = _basis(elev_deg)
    x0, x1, y0, y1 = _project(points, right, up)
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    dist = 90.0
    cam.location = right * cx + up * cy - view_dir * dist
    cam.rotation_euler = view_dir.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    if scale is None:
        scale = max(x1 - x0, (y1 - y0) * res_x / res_y) * margin
    cam.data.ortho_scale = scale
    cam.data.clip_end = 400.0


TILE_W, TILE_H = 620, 540
CAPTION_H = 84
SHEET_COLS = 4


def render_contact_sheet(cam, cat):
    items = sorted([p for p in ALL_PROPS if p.category == cat], key=lambda q: q.name)
    scene = bpy.context.scene
    scene.render.resolution_x = TILE_W
    scene.render.resolution_y = TILE_H
    tiles = []
    for p in items:
        for q in ALL_PROPS:
            q.obj.hide_render = q is not p
        for _, label in LABELS:
            label.hide_render = True
        frame_points(cam, _bbox_points(p.obj), TILE_W, TILE_H,
                     elev_deg=24.0, margin=1.22)
        path = os.path.join(ART_DIR, "_tile_%s_%s.png" % (cat, p.name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append((p, path))
    compose_sheet(cat, tiles)
    for _, path in tiles:
        os.remove(path)


def compose_sheet(cat, tiles):
    from PIL import Image, ImageDraw, ImageFont
    import glob

    def font(size, bold=False):
        name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        for root in ("/usr/share/fonts/truetype/dejavu/",
                     "/usr/share/fonts/dejavu/", "C:/Windows/Fonts/"):
            path = root + name
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
        return ImageFont.load_default()

    title_font = font(42, True)
    sub_font = font(17)
    name_font = font(21, True)
    meta_font = font(16)

    gutter = 14
    pad = 26
    header = 96
    cols = SHEET_COLS
    rows = (len(tiles) + cols - 1) // cols
    cell_w = TILE_W + gutter
    cell_h = TILE_H + CAPTION_H + gutter
    width = pad * 2 + cols * cell_w - gutter
    height = header + pad + rows * cell_h - gutter + pad
    sheet = Image.new("RGB", (width, height), (233, 230, 219))
    draw = ImageDraw.Draw(sheet)
    draw.text((pad, 24), cat.upper(), font=title_font, fill=(38, 40, 32))
    draw.text((pad, 68), "%d props  ·  metres, origin on the ground" % len(tiles),
              font=sub_font, fill=(112, 111, 98))

    for index, (p, path) in enumerate(tiles):
        col, row = index % cols, index // cols
        x = pad + col * cell_w
        y = header + pad + row * cell_h
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        draw.rectangle([x, y, x + TILE_W - 1, y + TILE_H - 1], outline=(214, 211, 198))
        draw.text((x + 4, y + TILE_H + 10), p.name.replace("_", " "),
                  font=name_font, fill=(44, 46, 37))
        lo, hi = mesh_bounds(p.obj)
        dims = "%.2f × %.2f × %.2f m   ·   %d tris" % (
            hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], tri_count(p.obj))
        draw.text((x + 4, y + TILE_H + 40), dims, font=meta_font, fill=(110, 109, 96))

    out = os.path.join(ART_DIR, "props_" + cat + ".png")
    sheet.save(out)
    print("[props] composed", out)


HERO = (
    ("tree_oak_01", (-4.4, 2.8), 25.0, 1.00),
    ("tree_birch", (-6.0, -0.2), 5.0, 0.95),
    ("tree_apple", (0.9, 3.6), 0.0, 0.90),
    ("tree_pine_01", (5.0, 2.2), 8.0, 1.00),
    ("bush_flower", (-1.6, -2.2), 0.0, 1.00),
    ("bush_round", (2.5, -2.3), 40.0, 1.00),
    ("bush_berry", (5.0, -2.0), 0.0, 1.00),
    ("water_trough", (-0.7, -0.7), -8.0, 1.00),
    ("hay_round", (2.7, 0.0), 14.0, 1.00),
    ("hay_net", (-2.3, 1.0), 30.0, 1.00),
    ("wheelbarrow", (-4.4, -2.0), 30.0, 1.00),
    ("saddle_rack", (-2.1, -0.4), 62.0, 1.00),
    ("crate", (4.2, -1.4), 22.0, 1.00),
    ("apple_basket", (1.5, -1.9), 8.0, 1.00),
    ("water_bucket", (-1.2, -2.0), 0.0, 1.00),
    ("fence_panel", (6.9, -0.6), 12.0, 1.00),
    ("jump_wing", (6.3, -2.4), 0.0, 1.00),
)


def _exclude_prop_collections(exclude):
    layer = bpy.context.view_layer.layer_collection
    for coll in CATEGORY_COLLECTIONS.values():
        child = layer.children.get(coll.name)
        if child is not None:
            child.exclude = exclude


def render_hero(cam, ground):
    for _, label in LABELS:
        label.hide_render = True
    _exclude_prop_collections(True)
    hero_coll = bpy.data.collections.new("hero_preview")
    bpy.context.scene.collection.children.link(hero_coll)
    by_name = {p.name: p for p in ALL_PROPS}
    dupes = []
    for name, (x, y), rz, scale in HERO:
        src = by_name[name]
        obj = src.obj.copy()
        obj.data = src.obj.data
        obj.name = "hero_" + name
        obj.location = (x, y, 0.0)
        obj.rotation_euler = (0, 0, math.radians(rz))
        obj.scale = (scale, scale, scale)
        obj.hide_render = False
        hero_coll.objects.link(obj)
        dupes.append(obj)

    ground_mat = ground.data.materials[0]
    bsdf = ground_mat.node_tree.nodes["Principled BSDF"]
    old_colour = tuple(bsdf.inputs["Base Color"].default_value)
    bsdf.inputs["Base Color"].default_value = (0.20, 0.28, 0.15, 1.0)

    cam.data.type = "PERSP"
    cam.data.lens = 32.0
    cam.location = (1.0, -16.6, 4.2)
    target = Vector((0.9, 1.2, 2.00))
    cam.rotation_euler = (target - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.eevee.taa_render_samples = 64
    scene.render.filepath = os.path.join(ART_DIR, "props_overview.png")
    bpy.ops.render.render(write_still=True)
    print("[props] rendered", scene.render.filepath)

    bsdf.inputs["Base Color"].default_value = old_colour
    for obj in dupes:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(hero_coll)
    _exclude_prop_collections(False)
    for p in ALL_PROPS:
        p.obj.hide_render = False
    for _, label in LABELS:
        label.hide_render = False


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(ART_DIR, exist_ok=True)

    builders = {
        "trees": build_trees, "bushes": build_bushes, "nature": build_nature,
        "stable": build_stable, "yard": build_yard, "garden": build_garden,
        "course": build_course, "grooming": build_grooming,
        "crowd": build_crowd, "arena": build_arena,
    }
    if STAGE == "all":
        build_all()
    elif STAGE in builders:
        builders[STAGE]()
    else:
        raise SystemExit("unknown --stage %r (choose all or one of %s)"
                         % (STAGE, ", ".join(builders)))
    print("[props] built %d props" % len(ALL_PROPS))
    export_props()
    cats = layout_props()

    cam, ground = setup_studio()
    for cat in cats:
        render_contact_sheet(cam, cat)
    if STAGE == "all":
        render_hero(cam, ground)
    for p in ALL_PROPS:
        p.obj.hide_render = False
    for _, label in LABELS:
        label.hide_render = False
    if STAGE == "all":
        bpy.ops.wm.save_as_mainfile(filepath=LIB_BLEND)
        print("[props] saved", LIB_BLEND)
    else:
        print("[props] stage %r built; library .blend and manifest left untouched" % STAGE)


main()
