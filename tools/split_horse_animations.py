"""Split the horse GLB's single 60 second take into named animation clips.

Run headless (Blender 3.4+):

    blender --background --factory-startup --python tools/split_horse_animations.py -- \
        --input Models/horse_riggedgame_ready.glb \
        --output Models/horse_riggedgame_ready_clips.glb

The source file has one glTF animation called "Animations" that packs every
action back to back. This script copies the parts of that action into one
Blender action per clip, pushes each action onto its own single-strip NLA
track, and exports those tracks as separate glTF animations.

Clip boundaries are measured from the baked 24 fps take. The gaits were
located by forward-kinematics analysis of the four hooves:

    trot   29.5 - 33.3 s   diagonal pairs
    canter 33.3 - 35.6 s   fast gait (the take has no separate gallop)
    walk   35.6 - 39.0 s   four-beat sequence

The current runtime state machine used 46-48.4 s for walk (all hooves are
static there) and 39-42 s for canter (the horse lies down and gets up).
These windows replace those.
"""

import argparse
import os
import sys

import bpy

FPS = 24.0

# (name, start_seconds, end_seconds). Covers the full 0 - 60.333 s take.
CLIPS = [
    ("Idle_Standing_A", 0.0, 5.5),
    ("Paw", 5.5, 9.0),
    ("Idle_Look_A", 9.0, 13.0),
    ("Idle_Standing_B", 13.0, 17.5),
    ("Look", 17.5, 21.0),
    ("Paw_Hind", 21.0, 24.0),
    ("Graze", 24.0, 27.0),
    ("Idle_Standing_C", 27.0, 29.5),
    ("Trot", 29.5, 33.3),
    ("Canter", 33.3, 35.6),
    ("Walk", 35.6, 39.0),
    ("LieDown", 39.0, 41.5),
    ("StandUp", 41.5, 42.0),
    ("Rear", 42.0, 43.3),
    ("Buck", 43.3, 44.6),
    ("HeadToss", 44.6, 49.0),
    ("Idle_Standing_D", 49.0, 52.3),
    ("LookUp", 52.3, 54.2),
    ("Idle_Standing_E", 54.2, 57.0),
    ("Idle_Low", 57.0, 60.333333),
]


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="source GLB")
    parser.add_argument("--output", required=True, help="destination GLB")
    return parser.parse_args(argv)


def find_armature():
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def source_action(armature):
    if armature.animation_data and armature.animation_data.action:
        return armature.animation_data.action
    actions = [a for a in bpy.data.actions if a.fcurves]
    if len(actions) == 1:
        return actions[0]
    raise RuntimeError("could not identify a single source action")


def action_base_frame(action):
    frames = [kp.co.x for fc in action.fcurves for kp in fc.keyframe_points]
    if not frames:
        raise RuntimeError("source action has no keyframes")
    return min(frames)


def build_clip_action(source, name, start_frame, end_frame, base_frame, fps):
    """Copy only the keys inside the window into a fresh action starting at 0."""
    duration_frames = end_frame - start_frame
    new = bpy.data.actions.new(name)
    new.use_fake_user = True

    for fc in source.fcurves:
        # Bone tracks only. Object-level tracks make the exporter emit extra
        # per-object animations for the wrapper empties.
        if not fc.data_path.startswith("pose.bones["):
            continue
        group = fc.group.name if fc.group else ""
        nfc = new.fcurves.new(fc.data_path, index=fc.array_index, action_group=group)

        points = []
        kp_start = None
        kp_end = None
        for kp in fc.keyframe_points:
            x = kp.co.x
            if start_frame - 1e-4 <= x <= end_frame + 1e-4:
                points.append((x - start_frame, kp.co.y))
                if kp_start is None or x < kp_start:
                    kp_start = x
                if kp_end is None or x > kp_end:
                    kp_end = x

        # Hold the pose when the window starts/ends between sparse keys.
        if kp_start is None or kp_start > start_frame + 1e-4:
            points.insert(0, (0.0, fc.evaluate(start_frame)))
        if kp_end is None or kp_end < end_frame - 1e-4:
            points.append((duration_frames, fc.evaluate(end_frame)))

        # Drop duplicate times (keep the last value at a given time).
        dedup = {}
        for x, y in points:
            dedup[round(x, 6)] = y
        ordered = sorted(dedup.items())

        nfc.keyframe_points.add(len(ordered))
        for kp, (x, y) in zip(nfc.keyframe_points, ordered):
            kp.co = (x, y)
            kp.interpolation = "LINEAR"
        nfc.update()

    new.use_frame_range = True
    new.frame_start = 0.0
    new.frame_end = duration_frames
    return new, duration_frames


def main():
    args = parse_args()
    src = os.path.abspath(args.input)
    dst = os.path.abspath(args.output)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = int(FPS)
    scene.render.fps_base = 1.0

    bpy.ops.import_scene.gltf(filepath=src)

    armature = find_armature()
    if armature is None:
        raise RuntimeError("no armature found in %s" % src)

    source = source_action(armature)
    base = action_base_frame(source)
    print("[split] source action: %s (base frame %.1f, %.2f s)" % (
        source.name, base,
        (max(kp.co.x for fc in source.fcurves for kp in fc.keyframe_points) - base) / FPS))

    clips = []
    for name, start_s, end_s in CLIPS:
        start_frame = base + round(start_s * FPS)
        end_frame = base + round(end_s * FPS)
        if end_frame <= start_frame:
            raise RuntimeError("clip %s has an empty frame range" % name)
        action, duration_frames = build_clip_action(source, name, start_frame, end_frame, base, FPS)
        clips.append((action, duration_frames))
        print("[split] %-16s frames %4d-%4d  %.3f s" % (
            name, start_frame - base, end_frame - base, duration_frames / FPS))

    # Do not export the original 60 s action; only the NLA tracks below.
    armature.animation_data.action = None
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])

    for action, duration_frames in clips:
        track = armature.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.name = action.name
        strip.action_frame_start = 0.0
        strip.action_frame_end = duration_frames
        strip.frame_start = 0.0
        strip.frame_end = duration_frames

    bpy.data.actions.remove(source)

    scene.frame_start = 0
    scene.frame_end = int(max(d for _, d in clips))

    # Export the whole scene. Using use_selection=True together with force
    # sampling makes the exporter add a constant "animation" for every
    # un-animated wrapper empty it selects.
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
        export_nla_strips=True,
        export_anim_single_armature=False,
        export_reset_pose_bones=True,
        export_optimize_animation_size=False,
        export_skins=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    print("[split] wrote %s with %d clips" % (dst, len(clips)))


if __name__ == "__main__":
    main()
