"""Build the Livery logo as a Godot-ready GLB.

Run headless:
    blender --background --factory-startup --python tools/make_livery_logo.py

The logo is a horizontal lockup: a soft pink rounded plaque, a gold
horseshoe on the left with nail heads, and the word LIVERY in Quicksand
Bold on the right.  It faces -Y in Blender, so it faces +Z in Godot, and
its origin sits at the bottom centre of the plaque.

Outputs:
    Models/livery_logo.glb
    artifacts/livery_logo/livery_logo.blend
    artifacts/livery_logo/preview.png
    artifacts/livery_logo/preview_3q.png
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = "/home/chrismills029/liv/groom"
TARGET = os.path.join(PROJECT, "Models", "livery_logo.glb")
ARTIFACTS = os.path.join(PROJECT, "artifacts", "livery_logo")
UI_TEXTURE = os.path.join(PROJECT, "assets", "images", "livery_logo_ui.png")
FONT = "/usr/share/fonts/truetype/quicksand/Quicksand-Bold.ttf"

TARGET_WIDTH = 0.98
PLAQUE_DEPTH = 0.08
TEXT_EXTRUDE = 0.038
SHOE_DEPTH = 0.042

BLUSH = "#F5C6D2"
RASPBERRY = "#7C2F4E"
GOLD = "#D6A45E"
LIV_GOLD = "#DCA45C"
NAIL = "#8A5A2B"


def srgb(hex_string):
    value = hex_string.lstrip("#")
    channels = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    linear = []
    for c in channels:
        linear.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*linear, 1.0)


def make_material(name, hex_color, metallic=0.0, roughness=0.5):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def bbox(objects):
    points = []
    for obj in objects:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def finish(obj, material, auto_smooth=True, angle=35.0):
    obj.data.materials.append(material)
    if auto_smooth:
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(angle)
    return obj


def build_wordmark(material, body="LIVERY", suffix=""):
    curve = bpy.data.curves.new("WordmarkCurve" + suffix, "FONT")
    curve.body = body
    curve.font = bpy.data.fonts.load(FONT)
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.extrude = TEXT_EXTRUDE * 0.5
    curve.bevel_depth = 0.008
    curve.bevel_resolution = 3
    curve.resolution_u = 8
    curve.space_character = 0.98

    obj = bpy.data.objects.new("LiveryLogo_Wordmark" + suffix, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0004)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, material)


def build_horseshoe(material):
    mesh = bpy.data.meshes.new("HorseshoeMesh")
    bm = bmesh.new()

    steps = 96
    start = math.radians(130.0)
    end = math.radians(410.0)
    outer, inner = [], []
    for i in range(steps + 1):
        u = i / steps
        angle = start + (end - start) * u
        edge = min(u, 1.0 - u)
        width = 0.15 + 0.21 * smoothstep(edge / 0.32)
        flare = 0.06 * (1.0 - smoothstep(edge / 0.22))
        radius_out = 1.0 + flare
        radius_in = 1.0 - width
        outer.append(bm.verts.new((math.cos(angle) * radius_out, math.sin(angle) * radius_out, 0.0)))
        inner.append(bm.verts.new((math.cos(angle) * radius_in, math.sin(angle) * radius_in, 0.0)))

    bm.verts.ensure_lookup_table()
    for i in range(steps):
        bm.faces.new((outer[i], outer[i + 1], inner[i + 1], inner[i]))

    result = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    lifted = [e for e in result["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=lifted, vec=(0.0, 0.0, SHOE_DEPTH))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("LiveryLogo_Horseshoe", mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Rounded", "BEVEL")
    bevel.width = 0.030
    bevel.segments = 5
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(30)
    return finish(obj, material)


def build_nails(material):
    mesh = bpy.data.meshes.new("NailsMesh")
    bm = bmesh.new()
    for offset in (-105.0, -70.0, -35.0, 35.0, 70.0, 105.0):
        angle = math.radians(270.0 + offset)
        radius = 0.885
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=12,
            radius1=0.039,
            radius2=0.031,
            depth=0.03,
            matrix=Matrix.Translation((x, y, SHOE_DEPTH + 0.006)),
        )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("LiveryLogo_Nails", mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, material, auto_smooth=False)


def build_plaque(width, height, material):
    radius = height * 0.24
    segments = 8
    half_w, half_h = width * 0.5, height * 0.5
    corners = (
        (half_w - radius, half_h - radius, 0.0),
        (-half_w + radius, half_h - radius, 90.0),
        (-half_w + radius, -half_h + radius, 180.0),
        (half_w - radius, -half_h + radius, 270.0),
    )

    outline = []
    for cx, cy, start in corners:
        for i in range(segments + 1):
            angle = math.radians(start + 90.0 * i / segments)
            outline.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))

    mesh = bpy.data.meshes.new("PlaqueMesh")
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, -PLAQUE_DEPTH)) for x, y in outline]
    face = bm.faces.new(verts)
    result = bmesh.ops.extrude_face_region(bm, geom=[face])
    lifted = [e for e in result["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=lifted, vec=(0.0, 0.0, PLAQUE_DEPTH))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("LiveryLogo_Plaque", mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Rounded", "BEVEL")
    bevel.width = 0.016
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(30)
    return finish(obj, material)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"

    pink = make_material("Livery_PinkPlaque", BLUSH, roughness=0.55)
    gold = make_material("Livery_Gold", GOLD, metallic=0.85, roughness=0.3)
    berry = make_material("Livery_Raspberry", RASPBERRY, roughness=0.42)
    nail_gold = make_material("Livery_NailGold", NAIL, metallic=0.9, roughness=0.38)

    liv_gold = make_material("Livery_LivGold", LIV_GOLD, metallic=0.55, roughness=0.34)
    liv = build_wordmark(liv_gold, "LIV", "_Liv")
    ery = build_wordmark(berry, "ERY", "_Ery")
    for obj in (liv, ery):
        simplify = obj.modifiers.new("Simplify", "DECIMATE")
        simplify.decimate_type = "DISSOLVE"
        simplify.angle_limit = math.radians(3.0)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=simplify.name)

    lo_liv, hi_liv = bbox([liv])
    lo_ery, hi_ery = bbox([ery])
    liv_w = hi_liv.x - lo_liv.x
    ery_w = hi_ery.x - lo_ery.x
    text_h = max(hi_liv.y - lo_liv.y, hi_ery.y - lo_ery.y)
    text_gap = text_h * 0.085
    text_w = liv_w + text_gap + ery_w
    bpy.ops.object.select_all(action="DESELECT")

    shoe = build_horseshoe(gold)
    shoe.scale = (text_h * 0.64, text_h * 0.64, 1.0)
    bpy.context.view_layer.objects.active = shoe
    shoe.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    shoe.select_set(False)

    nails = build_nails(nail_gold)
    nails.scale = (text_h * 0.64, text_h * 0.64, 1.0)
    bpy.context.view_layer.objects.active = nails
    nails.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    nails.select_set(False)

    lo_shoe, hi_shoe = bbox([shoe])
    shoe_w = hi_shoe.x - lo_shoe.x
    shoe_h = hi_shoe.y - lo_shoe.y

    pad_x = text_h * 0.62
    pad_y = text_h * 0.52
    gap = text_h * 0.34
    plaque_w = pad_x * 2.0 + shoe_w + gap + text_w
    plaque_h = max(text_h, shoe_h) + pad_y * 2.0

    plaque = build_plaque(plaque_w, plaque_h, pink)

    shoe_x = -plaque_w * 0.5 + pad_x + shoe_w * 0.5
    text_x = shoe_x + shoe_w * 0.5 + gap + text_w * 0.5
    liv_x = text_x - text_w * 0.5 + liv_w * 0.5
    ery_x = liv_x + liv_w * 0.5 + text_gap + ery_w * 0.5
    for obj, x in ((shoe, shoe_x), (nails, shoe_x), (liv, liv_x), (ery, ery_x)):
        obj.location.x = x
        obj.location.y = 0.0

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = liv

    turn = Matrix.Rotation(math.radians(90.0), 4, "X")
    for obj in meshes:
        obj.matrix_world = turn @ obj.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = bbox(meshes)
    factor = TARGET_WIDTH / (hi.x - lo.x)
    for obj in meshes:
        obj.scale *= factor
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    lo, hi = bbox(meshes)
    offset = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    for obj in meshes:
        obj.location += offset

    root = bpy.data.objects.new("LiveryLogo", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.1
    bpy.context.collection.objects.link(root)
    for obj in meshes:
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()

    lo, hi = bbox(meshes)
    tris = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
    print(f"[livery] size: {hi.x - lo.x:.3f} x {hi.y - lo.y:.3f} x {hi.z - lo.z:.3f} m")
    print(f"[livery] tris: {tris}")

    os.makedirs(ARTIFACTS, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [root]:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=TARGET,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print(f"[livery] wrote {TARGET}")

    render_previews(scene)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ARTIFACTS, "livery_logo.blend"))


def look_at(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_area(name, location, power, size, color=(1.0, 1.0, 1.0)):
    light = bpy.data.lights.new(name, "AREA")
    light.energy = power
    light.shape = "DISK"
    light.size = size
    light.color = color
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    look_at(obj, (0.0, 0.0, 0.16))
    return obj


def render_previews(scene):
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = srgb("#FDF3F6")
    background.inputs["Strength"].default_value = 0.3
    scene.world = world

    backdrop_mat = bpy.data.materials.new("PreviewBackdrop")
    backdrop_mat.use_nodes = True
    nodes = backdrop_mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = srgb("#F7DDE4")
    emission.inputs["Strength"].default_value = 1.15
    output = nodes.new("ShaderNodeOutputMaterial")
    backdrop_mat.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])

    bpy.ops.mesh.primitive_plane_add(size=10.0, location=(0.0, 1.2, 0.2), rotation=(math.radians(90.0), 0.0, 0.0))
    backdrop = bpy.context.object
    backdrop.name = "PreviewBackdrop"
    backdrop.data.materials.append(backdrop_mat)
    backdrop.visible_diffuse = False
    backdrop.visible_glossy = False

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 62.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    add_area("Key", (-1.4, -2.3, 2.1), 80.0, 3.0, (1.0, 0.96, 0.94))
    add_area("Fill", (1.9, -1.9, 0.5), 32.0, 3.0, (0.95, 0.97, 1.0))
    add_area("Rim", (0.4, 1.7, 1.6), 55.0, 2.0, (1.0, 0.92, 0.95))

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 420
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    camera.location = (0.0, -2.12, 0.16)
    look_at(camera, (0.0, 0.0, 0.16))
    scene.render.filepath = os.path.join(ARTIFACTS, "preview.png")
    bpy.ops.render.render(write_still=True)

    camera.location = (1.15, -2.25, 0.85)
    look_at(camera, (0.0, 0.0, 0.15))
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 560
    scene.render.filepath = os.path.join(ARTIFACTS, "preview_3q.png")
    bpy.ops.render.render(write_still=True)

    backdrop = bpy.data.objects.get("PreviewBackdrop")
    if backdrop is not None:
        backdrop.hide_render = True
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.09
    camera.location = (0.0, -2.5, 0.147)
    look_at(camera, (0.0, 0.0, 0.147))
    scene.render.film_transparent = True
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 360
    scene.render.image_settings.color_mode = "RGBA"
    os.makedirs(os.path.dirname(UI_TEXTURE), exist_ok=True)
    scene.render.filepath = UI_TEXTURE
    bpy.ops.render.render(write_still=True)
    print(f"[livery] wrote {UI_TEXTURE}")


if __name__ == "__main__":
    main()
