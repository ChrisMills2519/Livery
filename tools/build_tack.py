"""Build a fitted saddle and bridle for the rigged horse and export GLBs.

Run headless with Blender 3.4+:

    blender --background --factory-startup --python tools/build_tack.py

Outputs:
    Models/tack/horse_saddle.glb
    Models/tack/horse_bridle.glb
    artifacts/tack_preview_side.png
    artifacts/tack_preview_front.png

The horse model is authored in Blender's world space as measured from
Models/horse_riggedgame_ready_clips.glb: +Z is up, -Y is forward (head), and    the seat sits around Y=0.1, Z=1.56.  The tack is exported with the same
    Y-up glTF conversion, so in Godot it lands in the same model space as the
    horse before the horse scene's 180 degree yaw.

    Leather/suede PBR maps (CC0 from ambientCG) are downloaded on demand into
    Models/tack/textures/.  Every mesh is cube-projected to a 0.34 m tile,
    smooth-shaded with a 45 degree auto-smooth, and the flap/knee/tread edges
    are beveled so the grain and highlights read at gameplay distance.  The
    bridle straps are fitted against measured cross-sections of the horse
    head (crownpiece over the poll, forehead browband, muzzle-hugging
    noseband, cheekpieces and throatlatch rooted at the crown ends).
    """

import math
import os
import urllib.request
import zipfile

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Models", "tack")
ART_DIR = os.path.join(ROOT, "artifacts")
HORSE_GLB = os.path.join(ROOT, "Models", "horse_riggedgame_ready_clips.glb")
TEX_DIR = os.path.join(ROOT, "Models", "tack", "textures")
TEXTURE_PACKS = {
    "Leather030_1K-JPG": "https://ambientcg.com/get?file=Leather030_1K-JPG.zip",
    "Leather039_1K-JPG": "https://ambientcg.com/get?file=Leather039_1K-JPG.zip",
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, roughness=0.8):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = color
    return mat


def ensure_textures():
    """Download and extract the CC0 leather packs if missing (idempotent)."""
    os.makedirs(TEX_DIR, exist_ok=True)
    for stem, url in TEXTURE_PACKS.items():
        marker = os.path.join(TEX_DIR, stem, stem + "_Color.jpg")
        if os.path.exists(marker):
            continue
        zpath = os.path.join(TEX_DIR, stem + ".zip")
        if not os.path.exists(zpath):
            print("[tack] downloading", url)
            urllib.request.urlretrieve(url, zpath)
        with zipfile.ZipFile(zpath) as zf:
            zf.extractall(os.path.join(TEX_DIR, stem))
        print("[tack] extracted", stem)


def textured_material(name, pack):
    """Leather PBR material: color + roughness + OpenGL normal maps.

    Roughness socket stays at 1.0 so the glTF roughnessFactor is neutral and
    the map carries absolute values; metallic stays 0.0 so the exported
    metallicFactor zeroes out the roughness image's blue channel.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def add_image(suffix, colorspace, location):
        img = bpy.data.images.load(os.path.join(TEX_DIR, pack, pack + suffix))
        img.colorspace_settings.name = colorspace
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.location = location
        return tex

    t_color = add_image("_Color.jpg", "sRGB", (-640, 300))
    t_rough = add_image("_Roughness.jpg", "Non-Color", (-640, -60))
    t_norm = add_image("_NormalGL.jpg", "Non-Color", (-640, -420))
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-300, -420)
    nt.links.new(t_color.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t_rough.outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(t_norm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    mat.diffuse_color = (0.30, 0.17, 0.09, 1.0)
    return mat


def _arc(center, u, v, ru, rv, a0, a1, steps, closed=False):
    """Sample an elliptical arc: center + u*ru*cos(a) + v*rv*sin(a)."""
    c = Vector(center)
    U = Vector(u)
    V = Vector(v)
    pts = []
    for i in range(steps):
        t = i / float(steps) if closed else i / float(steps - 1)
        a = math.radians(a0 + (a1 - a0) * t)
        pts.append(c + U * (ru * math.cos(a)) + V * (rv * math.sin(a)))
    return pts


def ribbon(name, path, width, thickness, width_hint, mat, close=False):
    """Sweep a rectangular cross-section along a polyline path.

    width runs along width_hint (projected perpendicular to the path);
    thickness runs across it.  Unlike strap() this handles curves and
    multi-segment paths as one continuous mesh.
    """
    pts = [Vector(p) for p in path]
    hint = Vector(width_hint).normalized()
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        if close:
            tangent = pts[(i + 1) % n] - pts[(i - 1) % n]
        elif i == 0:
            tangent = pts[1] - pts[0]
        elif i == n - 1:
            tangent = pts[-1] - pts[-2]
        else:
            tangent = pts[i + 1] - pts[i - 1]
        tangent.normalize()
        w = hint - hint.dot(tangent) * tangent
        if w.length < 1e-6:
            w = Vector((1.0, 0.0, 0.0)) - tangent.x * tangent
        w.normalize()
        nv = tangent.cross(w).normalized()
        hw = w * (width * 0.5)
        ht = nv * (thickness * 0.5)
        rings.append([p - hw - ht, p + hw - ht, p + hw + ht, p - hw + ht])
    verts = [tuple(v) for ring in rings for v in ring]
    faces = []
    segs = n if close else n - 1
    for i in range(segs):
        j = (i + 1) % n
        for k in range(4):
            a = i * 4 + k
            b = i * 4 + (k + 1) % 4
            c = j * 4 + (k + 1) % 4
            d = j * 4 + k
            faces.append((a, b, c, d))
    if not close:
        faces.append((3, 2, 1, 0))
        base = (n - 1) * 4
        faces.append((base, base + 1, base + 2, base + 3))
    return mesh_object(name, verts, faces, mat)


def uv_cube_project(objects, cube_size=0.34):
    """World-scale cube UVs so the leather grain is uniform on every part."""
    for ob in objects:
        if ob.type != "MESH":
            continue
        if not ob.data.uv_layers:
            ob.data.uv_layers.new(name="UVMap")
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=cube_size, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")


def smooth_meshes(objects, angle_deg=45.0):
    """Smooth everything but keep hard creases (boxes stay crisp)."""
    for ob in objects:
        if ob.type != "MESH":
            continue
        me = ob.data
        for poly in me.polygons:
            poly.use_smooth = True
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(angle_deg)


def bevel_edges(ob, offset=0.0035, segments=2, angle_deg=40.0):
    """Small bevel on sharp edges so highlights catch the flap/tread rims."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    limit = math.radians(angle_deg)
    edges = [
        e for e in bm.edges
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit
    ]
    if edges:
        bmesh.ops.bevel(
            bm, geom=edges, offset=offset, segments=segments,
            profile=0.7, affect="EDGES",
        )
        bm.to_mesh(ob.data)
    bm.free()


def mesh_object(name, verts, faces, mat, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for poly in me.polygons:
            poly.use_smooth = True
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def loft(name, sections, mat, cap=True):
    rings = []
    for y, ring in sections:
        rings.append([(x, y, z) for x, z in ring])
    verts = [v for ring in rings for v in ring]
    n = len(rings[0])
    faces = []
    for i in range(len(rings) - 1):
        for j in range(n):
            a = i * n + j
            b = i * n + (j + 1) % n
            c = (i + 1) * n + (j + 1) % n
            d = (i + 1) * n + j
            faces.append((a, b, c, d))
    if cap:
        faces.append(tuple(range(n - 1, -1, -1)))
        base = (len(rings) - 1) * n
        faces.append(tuple(base + j for j in range(n)))
    return mesh_object(name, verts, faces, mat)


def band(name, y, rx, rz, cz, width, thickness, mat, segments=20):
    verts = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        cx = rx * math.cos(a)
        czz = cz + rz * math.sin(a)
        radial = Vector((math.cos(a), 0.0, math.sin(a)))
        for dy in (-width * 0.5, width * 0.5):
            for dt in (-thickness * 0.5, thickness * 0.5):
                verts.append((cx + radial.x * dt, y + dy, czz + radial.z * dt))
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        for k in range(4):
            a = i * 4 + k
            b = i * 4 + (k + 1) % 4
            c = j * 4 + (k + 1) % 4
            d = j * 4 + k
            faces.append((a, b, c, d))
    return mesh_object(name, verts, faces, mat)


def strap(name, p0, p1, width, thickness, mat):
    p0 = Vector(p0)
    p1 = Vector(p1)
    mid = (p0 + p1) * 0.5
    direction = p1 - p0
    length = direction.length
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=mid)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (width, thickness, length)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = direction.normalized().to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    return ob


def box(name, center, size, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    ob.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    ob.data.materials.append(mat)
    return ob


def torus(name, center, major, minor, mat, rotation=(0.0, 0.0, 0.0), segments=16):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=segments,
        minor_segments=6,
        location=center,
        rotation=rotation,
    )
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    return ob


BACK_TOP = [
    (-0.40, 1.440), (-0.30, 1.460), (-0.20, 1.470), (-0.10, 1.450),
    (0.00, 1.440), (0.10, 1.435), (0.20, 1.440), (0.30, 1.450),
    (0.40, 1.455), (0.50, 1.440), (0.55, 1.430),
]


def back_top(y):
    if y <= BACK_TOP[0][0]:
        return BACK_TOP[0][1]
    for (y0, z0), (y1, z1) in zip(BACK_TOP, BACK_TOP[1:]):
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            return z0 + (z1 - z0) * t
    return BACK_TOP[-1][1]


def build_saddle(leather, suede, brass, steel):
    objs = []

    xs = [-0.33, -0.22, -0.11, 0.0, 0.11, 0.22, 0.33]
    ys = [-0.40, -0.30, -0.20, -0.10, 0.0, 0.10, 0.20, 0.30, 0.40, 0.50]
    pad_verts = []
    for y in ys:
        base = back_top(y)
        for x in xs:
            t = abs(x) / 0.33
            zt = base + 0.02 + 0.025 * (1.0 - t * t) - 0.12 * (t ** 4)
            pad_verts.append((x, y, zt))
            pad_verts.append((x, y, zt - 0.030))
    nx = len(xs)
    ny = len(ys)
    pad_faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            for layer in (0, 1):
                a = (j * nx + i) * 2 + layer
                b = (j * nx + i + 1) * 2 + layer
                c = ((j + 1) * nx + i + 1) * 2 + layer
                d = ((j + 1) * nx + i) * 2 + layer
                face = (a, b, c, d)
                pad_faces.append(face if layer == 0 else face[::-1])
    for i in range(nx - 1):
        a = i * 2
        b = (i + 1) * 2
        c = b + 1
        d = a + 1
        pad_faces.append((a, d, c, b))
        a = ((ny - 1) * nx + i) * 2
        b = ((ny - 1) * nx + i + 1) * 2
        c = b + 1
        d = a + 1
        pad_faces.append((a, b, c, d))
    for j in range(ny - 1):
        a = (j * nx) * 2
        b = ((j + 1) * nx) * 2
        c = b + 1
        d = a + 1
        pad_faces.append((a, b, c, d))
        a = (j * nx + nx - 1) * 2
        b = ((j + 1) * nx + nx - 1) * 2
        c = b + 1
        d = a + 1
        pad_faces.append((a, d, c, b))
    objs.append(mesh_object("Saddle_Pad", pad_verts, pad_faces, leather))

    stations = [
        (-0.30, 0.11, 1.590, 1.455),
        (-0.22, 0.19, 1.610, 1.445),
        (-0.10, 0.25, 1.590, 1.440),
        (0.03, 0.28, 1.565, 1.440),
        (0.16, 0.265, 1.585, 1.440),
        (0.28, 0.21, 1.640, 1.445),
        (0.36, 0.13, 1.605, 1.450),
    ]
    sections = []
    for y, w, zt, zb in stations:
        ring = [
            (-w * 0.5, zb),
            (-w * 0.5, zt - 0.035),
            (-w * 0.30, zt),
            (0.0, zt + 0.020),
            (w * 0.30, zt),
            (w * 0.5, zt - 0.035),
            (w * 0.5, zb),
            (0.0, zb - 0.006),
        ]
        sections.append((y, ring))
    objs.append(loft("Saddle_Seat", sections, suede))

    for side in (-1, 1):
        xt = 0.235 * side
        xb = 0.300 * side
        y0, y1 = -0.06, 0.36
        zt, zb = 1.485, 1.200
        t = 0.014 * side
        verts = [
            (xt, y0, zt), (xt, y1, zt), (xb, y1, zb), (xb, y0, zb),
            (xt - t, y0, zt), (xt - t, y1, zt), (xb - t, y1, zb), (xb - t, y0, zb),
        ]
        faces = [
            (0, 1, 2, 3), (7, 6, 5, 4),
            (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0),
        ]
        objs.append(mesh_object("Saddle_Flap_%s" % ("L" if side > 0 else "R"), verts, faces, leather))
        objs.append(box(
            "Saddle_KneeRoll_%s" % ("L" if side > 0 else "R"),
            (side * 0.248, -0.020, 1.455), (0.075, 0.15, 0.075), leather,
        ))

    objs.append(band("Saddle_Girth", -0.08, 0.285, 0.345, 1.100, 0.075, 0.014, leather, 22))
    objs.append(box("Saddle_GirthBuckle", (-0.292, -0.08, 1.165), (0.020, 0.075, 0.050), brass))

    for side in (-1, 1):
        suffix = "L" if side > 0 else "R"
        objs.append(strap(
            "Saddle_StirrupLeather_%s" % suffix,
            (side * 0.210, -0.050, 1.490),
            (side * 0.285, -0.150, 1.045),
            0.038, 0.012, leather,
        ))
        objs.append(torus(
            "Saddle_Iron_%s" % suffix,
            (side * 0.300, -0.150, 1.010), 0.065, 0.008, steel,
            rotation=(0.0, math.pi * 0.5, 0.0), segments=14,
        ))
        objs.append(box(
            "Saddle_Tread_%s" % suffix,
            (side * 0.300, -0.150, 0.949), (0.030, 0.115, 0.014), steel,
        ))
        objs.append(box(
            "Saddle_StirrupBuckle_%s" % suffix,
            (side * 0.215, -0.050, 1.455), (0.024, 0.045, 0.035), brass,
        ))

    for side in (-1, 1):
        objs.append(torus(
            "Saddle_DRing_%s" % ("L" if side > 0 else "R"),
            (side * 0.155, -0.205, 1.575), 0.022, 0.006, brass,
            rotation=(math.pi * 0.5, 0.0, 0.0), segments=12,
        ))
    return objs


def build_bridle(leather, brass, steel):
    """Bridle fitted against measured cross-sections of the horse head.

    Measured from Models/horse_riggedgame_ready_clips.glb (Blender space,
    -Y forward): skull top at y=-0.97 is z=1.855 with half-width 0.115;
    ear bases y=-1.00..-1.04 rise above z=1.87; forehead front y=-1.075 at
    z=1.80; cheek half-width 0.109 at y=-1.08/z=1.56; muzzle station y=-1.20
    spans z=[1.296,1.580] with half-width 0.074.  The bit, rings and anchors
    stay at the mouth corners (y=-1.16, z=1.39, rings x=+/-0.102).
    """
    objs = []
    empties = []

    # Crownpiece: arcs over the poll BEHIND the ear bases; width fore-aft.
    crown = _arc(
        (0.0, -0.970, 1.762), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
        0.115, 0.094, -20.0, 200.0, 17,
    )
    objs.append(ribbon("Bridle_Crown", crown, 0.045, 0.011, (0.0, 1.0, 0.0), leather))

    # Browband: surface-fitted arc across the forehead, below the ears,
    # ending on the crownpiece ends where the cheekpieces branch off.
    brow = [
        (0.108, -0.970, 1.730), (0.114, -1.005, 1.772),
        (0.092, -1.032, 1.787), (0.043, -1.065, 1.797),
        (0.000, -1.075, 1.800), (-0.043, -1.065, 1.797),
        (-0.092, -1.032, 1.787), (-0.114, -1.005, 1.772),
        (-0.108, -0.970, 1.730),
    ]
    objs.append(ribbon("Bridle_Browband", brow, 0.034, 0.010, (0.0, 0.0, 1.0), leather))

    # Noseband: snug full ring on the measured muzzle station (y=-1.20).
    nose = _arc(
        (0.0, -1.200, 1.438), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
        0.079, 0.145, 0.0, 360.0, 24, closed=True,
    )
    objs.append(ribbon("Bridle_Noseband", nose, 0.032, 0.011, (0.0, 1.0, 0.0), leather, close=True))

    cheek_r = [
        (0.109, -0.970, 1.734), (0.117, -1.030, 1.665),
        (0.101, -1.088, 1.560), (0.088, -1.128, 1.462),
        (0.102, -1.158, 1.424),
    ]
    throat_r = [
        (0.105, -0.970, 1.734), (0.112, -0.992, 1.585),
        (0.085, -1.012, 1.450), (0.000, -1.006, 1.443),
    ]
    for side in (-1, 1):
        suffix = "L" if side > 0 else "R"
        cheek = [(side * p[0], p[1], p[2]) for p in cheek_r]
        objs.append(ribbon("Bridle_Cheek_%s" % suffix, cheek, 0.027, 0.011, (0.0, 1.0, 0.0), leather))
        throat = [(side * p[0], p[1], p[2]) for p in throat_r]
        objs.append(ribbon("Bridle_Throat_%s" % suffix, throat, 0.025, 0.009, (0.0, 1.0, 0.0), leather))
    for side in (-1, 1):
        suffix = "L" if side > 0 else "R"
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=8, radius=0.007, depth=0.090,
            location=(side * 0.055, -1.160, 1.390),
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
        ob = bpy.context.object
        ob.name = "Bridle_Bit_%s" % suffix
        ob.data.materials.append(steel)
        objs.append(ob)
        objs.append(torus(
            "Bridle_BitRing_%s" % suffix,
            (side * 0.102, -1.160, 1.390), 0.032, 0.006, steel,
            rotation=(0.0, math.pi * 0.5, 0.0), segments=12,
        ))
        bpy.ops.object.empty_add(type="PLAIN_AXES", radius=0.018, location=(side * 0.102, -1.160, 1.390))
        anchor = bpy.context.object
        anchor.name = "BitAnchor_%s" % suffix
        empties.append(anchor)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.011, location=(0.0, -1.160, 1.390))
    joint = bpy.context.object
    joint.name = "Bridle_BitJoint"
    joint.data.materials.append(steel)
    objs.append(joint)
    return objs, empties


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_materials="EXPORT",
    )
    print("[tack] wrote", path)


def preview():
    if not os.path.exists(HORSE_GLB):
        return
    bpy.ops.import_scene.gltf(filepath=HORSE_GLB)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    cam_data = bpy.data.cameras.new("TackPreviewCamera")
    cam = bpy.data.objects.new("TackPreviewCamera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam_data.lens = 55.0

    shots = [
        ("tack_preview_side", Vector((3.4, -2.6, 2.3)), Vector((0.0, -0.15, 1.15))),
        ("tack_preview_front", Vector((2.0, -4.2, 2.0)), Vector((0.0, -0.35, 1.30))),
    ]
    os.makedirs(ART_DIR, exist_ok=True)
    for name, location, target in shots:
        cam.location = location
        cam.rotation_mode = "QUATERNION"
        cam.rotation_quaternion = (target - location).to_track_quat("-Z", "Y")
        scene.render.filepath = os.path.join(ART_DIR, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("[tack] wrote", scene.render.filepath)


def main():
    ensure_textures()
    reset_scene()
    leather = textured_material("Tack_Leather", "Leather030_1K-JPG")
    suede = textured_material("Tack_Suede", "Leather039_1K-JPG")
    brass = material("Tack_Brass", (0.65, 0.44, 0.12, 1.0), 0.85, 0.32)
    steel = material("Tack_Steel", (0.48, 0.50, 0.54, 1.0), 0.9, 0.28)

    saddle_objs = build_saddle(leather, suede, brass, steel)
    bridle_objs, bridle_empties = build_bridle(leather, brass, steel)

    meshes = [o for o in saddle_objs + bridle_objs if o.type == "MESH"]
    uv_cube_project(meshes, cube_size=0.34)
    for ob in meshes:
        if ob.name.startswith((
            "Saddle_Flap", "Saddle_KneeRoll", "Saddle_Tread",
            "Saddle_GirthBuckle", "Saddle_StirrupBuckle",
        )):
            bevel_edges(ob)
    smooth_meshes(meshes, 45.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    export(saddle_objs, os.path.join(OUT_DIR, "horse_saddle.glb"))
    export(bridle_objs + bridle_empties, os.path.join(OUT_DIR, "horse_bridle.glb"))
    preview()


if __name__ == "__main__":
    main()
