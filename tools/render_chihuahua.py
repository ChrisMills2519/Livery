"""Render contact sheets of the Chihuahua clips.

Usage:
    blender --background --factory-startup --python tools/render_chihuahua.py -- \
        artifacts/chihuahua_build.blend artifacts/chihuahua Idle,Walk 4 side
"""
import bpy, sys, os
from mathutils import Vector
from PIL import Image, ImageDraw

args = sys.argv[sys.argv.index("--") + 1:]
src, outdir, clips = args[0], args[1], args[2].split(",")
nshots = int(args[3]) if len(args) > 3 else 4
view = args[4] if len(args) > 4 else "side"
os.makedirs(outdir, exist_ok=True)

if src.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 8
sc.cycles.use_denoising = False
sc.render.resolution_x = 400
sc.render.resolution_y = 400
sc.render.image_settings.file_format = "PNG"

world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.09, 0.10, 1)
sc.world = world

bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
plane = bpy.context.object
mat = bpy.data.materials.new("ground")
mat.use_nodes = True
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Base Color"].default_value = (0.16, 0.16, 0.17, 1)
bsdf.inputs["Roughness"].default_value = 0.9
plane.data.materials.append(mat)

for loc, energy, size in (((2.2, -1.6, 2.2), 500, 2.5), ((-2.0, 0.8, 1.6), 220, 2.0)):
    ld = bpy.data.lights.new("L", "AREA")
    ld.energy, ld.size = energy, size
    ob = bpy.data.objects.new("L", ld)
    sc.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 0.15)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

bpy.context.view_layer.update()
mesh_objs = [o for o in bpy.data.objects if o.type == "MESH" and o != plane]
pts = [o.matrix_world @ v.co for o in mesh_objs for v in o.data.vertices]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
ctr = (mn + mx) / 2
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(mx.y - mn.y, mx.z - mn.z) * 1.18
cam = bpy.data.objects.new("Cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
if view == "top":
    cam.location = (0.0, ctr.y, 2.0)
    cam.rotation_euler = (Vector((0, ctr.y, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
elif view == "three_quarter":
    cam.location = (1.5, ctr.y - 1.5, ctr.z + 1.1)
    cam.rotation_euler = (Vector((0, ctr.y, ctr.z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = max(mx.y - mn.y, mx.z - mn.z) * 1.35
else:
    cam.location = (2.0, ctr.y, ctr.z)
    cam.rotation_euler = (Vector((0, ctr.y, ctr.z)) - cam.location).to_track_quat("-Z", "Y").to_euler()

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
if arm.animation_data:
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True

for clip in clips:
    act = next((a for a in bpy.data.actions if a.name == clip), None)
    if not act:
        print("MISSING", clip)
        continue
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    frames = [round(f0 + (f1 - f0) * i / max(1, nshots - 1)) for i in range(nshots)]
    tiles = []
    for i, f in enumerate(frames):
        sc.frame_set(int(f))
        p = os.path.join(outdir, f"{clip}_{view}_{i}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        tiles.append((p, int(f)))
    W = 400 * len(tiles)
    sheet = Image.new("RGB", (W, 400), (20, 20, 22))
    d = ImageDraw.Draw(sheet)
    for i, (p, f) in enumerate(tiles):
        sheet.paste(Image.open(p).convert("RGB"), (400 * i, 0))
        d.text((400 * i + 8, 8), f"{clip} f{f}", fill=(255, 245, 200))
    out = os.path.join(outdir, f"sheet_{clip}_{view}.png")
    sheet.save(out)
    print("SHEET", out, "frames", frames)
