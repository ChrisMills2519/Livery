"""Render sampled frames of a horse GLB's take so the clips can be eyeballed.

Run headless:

    blender --background --factory-startup --python tools/render_horse_frames.py -- \
        --input Models/horse_riggedgame_ready.glb \
        --frames 28,29,30,31,32,33,34,35,36,37,38,39,40 \
        --out /tmp/opencode/horse

Writes one PNG per requested time (seconds) and, when Pillow is available, a
horizontal contact sheet next to them.  Workbench is used because this machine
has no real VRAM for EEVEE/Cycles GPU work.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--frames", required=True, help="comma-separated seconds")
    parser.add_argument("--out", required=True)
    parser.add_argument("--width", type=int, default=360)
    parser.add_argument("--height", type=int, default=300)
    parser.add_argument("--view", default="side", choices=["side", "front", "three_quarter"])
    parser.add_argument("--sheet", default="", help="optional contact sheet filename")
    parser.add_argument("--clip", default="", help="action/clip name to play (multi-clip GLB)")
    return parser.parse_args(argv)


def find_armature():
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def scene_bounds():
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            low = Vector((min(low[i], world[i]) for i in range(3)))
            high = Vector((max(high[i], world[i]) for i in range(3)))
    return low, high


def place_camera(view):
    low, high = scene_bounds()
    center = (low + high) * 0.5
    size = (high - low).length
    if view == "front":
        direction = Vector((0.0, 0.35, 1.0))
    elif view == "three_quarter":
        direction = Vector((1.0, 0.35, 0.7))
    else:
        direction = Vector((1.0, 0.18, 0.0))
    direction.normalize()
    camera_data = bpy.data.cameras.new("SheetCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = size * 0.72
    camera = bpy.data.objects.new("SheetCam", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = center + direction * size * 1.6
    look = center - camera.location
    camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.resolution_percentage = 100

    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.input))
    arm = find_armature()
    if arm is None:
        print("[frames] no armature in %s" % args.input)
    elif args.clip:
        matches = [a for a in bpy.data.actions
                   if a.name == args.clip or a.name.startswith(args.clip + "_")]
        if not matches:
            raise RuntimeError("no action for clip %r (have %s)" % (
                args.clip, ", ".join(sorted(a.name for a in bpy.data.actions))))
        action = matches[0]
        arm.animation_data.action = action
        arm.animation_data.use_nla = False
        print("[frames] playing %s (%.3f s)" % (
            action.name, (action.frame_range[1] - action.frame_range[0]) / scene.render.fps))
    place_camera(args.view)

    os.makedirs(args.out, exist_ok=True)
    times = [float(t) for t in args.frames.split(",") if t.strip()]
    paths = []
    for t in times:
        scene.frame_set(int(round(t * scene.render.fps)))
        path = os.path.join(args.out, "f_%06.2f.png" % t)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
        print("[frames] %6.2fs -> %s" % (t, path))

    sheet = args.sheet or ("sheet_%s.png" % args.view)
    montage(paths, os.path.join(args.out, sheet), args.width, args.height)
    print("[frames] wrote %s" % os.path.join(args.out, sheet))


def montage(paths, out, width, height):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("[frames] Pillow not available; skipping contact sheet")
        return
    cols = min(6, len(paths))
    rows = int(math.ceil(len(paths) / cols))
    label = 22
    sheet = Image.new("RGB", (cols * width, rows * (height + label)), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(paths):
        image = Image.open(path).convert("RGB")
        c = i % cols
        r = i // cols
        x = c * width
        y = r * (height + label)
        sheet.paste(image, (x, y))
        name = os.path.splitext(os.path.basename(path))[0].replace("f_", "")
        draw.text((x + 6, y + height + 4), name, fill=(220, 220, 220))
    sheet.save(out)


if __name__ == "__main__":
    main()
