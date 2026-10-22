"""Add a second UV set to the horse for one-sided grooming.

The coat mesh uses mirrored UVs: the left and right sides share texels, so a
UV-space groom brush cannot clean one side without cleaning the other.  This
script keeps the original UV set (TEXCOORD_0, used by the coat texture) but adds
a second set (TEXCOORD_1) where every face is placed into a left or right half
based on its centroid on the model's lateral axis (local X).  Mirror faces end
up in disjoint halves, so the runtime groom mask can separate them without
re-unwrapping the coat or rebaking its texture.

Run headless (Blender 3.4+):

    blender --background --factory-startup --python tools/add_groom_uv.py -- \
        --input Models/horse_riggedgame_ready_clips.glb \
        --output /tmp/horse_uv1.glb
"""

import argparse
import os
import sys

import bpy


# Half the atlas per side, leaving a padding strip in the middle so a brush
# cannot reach across the seam.
SIDE_SCALE = 0.49
LEFT_OFFSET = 0.0
RIGHT_OFFSET = 0.51


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="source GLB")
    parser.add_argument("--output", required=True, help="destination GLB")
    parser.add_argument("--name", default="GroomUV", help="new UV layer name")
    return parser.parse_args(argv)


def mesh_objects():
    return [o for o in bpy.context.scene.objects
            if o.type == "MESH" and o.data.uv_layers]


def add_uv_layer(mesh_obj, name):
    me = mesh_obj.data
    if name in me.uv_layers:
        me.uv_layers.remove(me.uv_layers[name])
    original = me.uv_layers[0]
    groom = me.uv_layers.new(name=name)

    right_faces = 0
    left_faces = 0
    for poly in me.polygons:
        centre_x = 0.0
        for vertex_index in poly.vertices:
            centre_x += me.vertices[vertex_index].co.x
        centre_x /= max(1, len(poly.vertices))
        right = centre_x > 0.0
        if right:
            right_faces += 1
        else:
            left_faces += 1
        offset = RIGHT_OFFSET if right else LEFT_OFFSET
        for loop_index in poly.loop_indices:
            u = original.data[loop_index].uv
            groom.data[loop_index].uv = (offset + u.x * SIDE_SCALE, u.y)
    # Keep the original UV set as the render/export primary.
    me.uv_layers.active = original
    me.uv_layers[0].active_render = True
    if hasattr(groom, "active_render"):
        groom.active_render = False
    print("[groom-uv] %s: left faces=%d right faces=%d" % (mesh_obj.name, left_faces, right_faces))


def main():
    args = parse_args()
    src = os.path.abspath(args.input)
    dst = os.path.abspath(args.output)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)

    meshes = mesh_objects()
    if not meshes:
        raise RuntimeError("no mesh with UVs found in %s" % src)
    for mesh_obj in meshes:
        add_uv_layer(mesh_obj, args.name)

    armatures = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    tracks = 0
    actions = len([a for a in bpy.data.actions if a.fcurves])
    for arm in armatures:
        if arm.animation_data:
            tracks += len(arm.animation_data.nla_tracks)
    print("[groom-uv] armatures=%d actions=%d nla_tracks=%d" % (len(armatures), actions, tracks))

    if tracks > 0:
        export_kwargs = dict(export_nla_strips=True)
    else:
        export_kwargs = dict(export_nla_strips=False)

    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_yup=True,
        export_animations=True,
        export_frame_range=False,
        export_frame_step=1,
        export_force_sampling=True,
        export_anim_single_armature=False,
        export_reset_pose_bones=True,
        export_optimize_animation_size=False,
        export_skins=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        **export_kwargs
    )
    print("[groom-uv] wrote %s" % dst)


if __name__ == "__main__":
    main()
