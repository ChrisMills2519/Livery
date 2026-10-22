"""Build the horse's animation clip library from the rigged source.

The shipped 60 s take contains no locomotion: it is idle, look, graze, lie
down, rear and buck only.  The old Walk/Trot/Canter clips were slices of that,
which is why the horse glided.  This tool keeps the useful one-shots, then
*author* the missing gaits and a jump on the existing rig and bakes them into
actions that export as separate glTF animations.

    blender --background --factory-startup --python tools/build_horse_clips.py -- \
        --input Models/horse_riggedgame_ready.glb \
        --output Models/horse_riggedgame_ready_clips.glb

The gaits are built with a small IK rig (foot targets on a stance/swing path,
scapula included in the front chain) and baked to plain bone keyframes, so the
exported GLB needs no constraints.  Foot travel, duty factor and cycle length
are chosen so the measured ground speed is a realistic walk/trot/canter; the
runtime reference speeds are calibrated to the exported clips separately.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector, Quaternion, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import split_horse_animations as split  # noqa: E402

FPS = 24.0

# Root / body bones.
ROOT = "Bip01_00_40"
PELVIS = "Bip01 Pelvis_02_39"
SPINE = "Bip01 Spine_03_21"
SPINE1 = "Bip01 Spine1_04_20"
NECK = "Bip01 Neck_01_19"
NECK1 = "Bip01 Neck1_05_6"
HEAD = "Bip01 Head_06_5"
TAIL = "Bip01 Tail_036_38"

# Deforming leg bones.  The *_Nub helpers carry no vertex weights on this rig.
#
# The IK runs to the fetlock (the Forearm / HorseLink tail) and the hoof bone
# is orientation-locked separately.  Aiming the IK at the hoof tip instead
# works for the front leg but makes the horizontal hind "Foot" lever swing the
# hoof through a 0.7 m arc, so both legs use the fetlock as the target.
FRONT = {
    "L": {"chain": ["Bip01 L Clavicle_012_12", "Bip01 L UpperArm_013_11",
                    "Bip01 L Forearm_014_10"],
          "bone": "Bip01 L Forearm_014_10", "hoof": "Bip01 L Hand_015_9"},
    "R": {"chain": ["Bip01 R Clavicle_018_18", "Bip01 R UpperArm_019_17",
                    "Bip01 R Forearm_020_16"],
          "bone": "Bip01 R Forearm_020_16", "hoof": "Bip01 R Hand_021_15"},
}
HIND = {
    "L": {"chain": ["Bip01 L Thigh_024_27", "Bip01 L Calf_025_26",
                    "Bip01 L HorseLink_026_25"],
          "bone": "Bip01 L HorseLink_026_25", "hoof": "Bip01 L Foot_027_24"},
    "R": {"chain": ["Bip01 R Thigh_030_33", "Bip01 R Calf_031_32",
                    "Bip01 R HorseLink_032_31"],
          "bone": "Bip01 R HorseLink_032_31", "hoof": "Bip01 R Foot_033_30"},
}

# Discrete clips that already read correctly in the source take.  The windows
# are the ones verified by rendering the take; the old Walk/Trot/Canter rows
# are deliberately absent because those gaits do not exist in the source.
SOURCE_CLIPS = [
    ("Idle_Standing_A", 0.0, 5.0),
    ("Paw", 5.5, 9.0),
    ("Idle_Look_A", 9.0, 13.0),
    ("Look", 14.0, 17.5),
    ("Graze", 23.0, 26.5),
    ("Idle_Standing_C", 27.0, 30.0),
    ("Idle_Standing_D", 31.0, 38.0),
    ("LieDown", 38.5, 41.5),
    ("StandUp", 41.5, 42.5),
    ("Rear", 43.4, 44.8),
    ("HeadToss", 45.0, 49.0),
    ("LookUp", 52.3, 54.2),
    ("Idle_Standing_E", 54.2, 57.0),
    ("Idle_Low", 57.0, 60.33),
]

# Gait authoring parameters.  `stride` is how far a planted foot travels
# backwards through the body during stance, `duty` the fraction of the cycle
# spent on the ground, and `cycle` the loop length in frames at 24 fps.
# Ground speed = stride / (duty * cycle_seconds).
GAITS = {
    "Walk": {
        "cycle": 24,
        "stride": 1.00,
        "duty": 0.62,
        "lift": 0.14,
        "body_drop": 0.035,
        "bob": 0.014,
        "bob_hz": 2.0,
        "nod": 2.5,
        # Lateral-sequence walk: left hind, left fore, right hind, right fore.
        "footfall": {"HL": 0.00, "FL": 0.25, "HR": 0.50, "FR": 0.75},
    },
    "Trot": {
        "cycle": 16,
        "stride": 1.20,
        "duty": 0.45,
        "lift": 0.20,
        "body_drop": 0.045,
        "bob": 0.032,
        "bob_hz": 2.0,
        "nod": 3.0,
        # Diagonal pairs.
        "footfall": {"FL": 0.00, "HR": 0.00, "FR": 0.50, "HL": 0.50},
    },
    "Canter": {
        "cycle": 14,
        "stride": 1.40,
        "duty": 0.38,
        "lift": 0.24,
        "body_drop": 0.055,
        "bob": 0.045,
        "bob_hz": 1.0,
        "nod": 4.0,
        # Left-lead canter, three beats: right hind; left hind + right fore;
        # left fore, then a moment of suspension.
        "footfall": {"HR": 0.00, "HL": 0.33, "FR": 0.33, "FL": 0.66},
    },
}


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def bone_local_delta(pose_bone, world_delta):
    """World-space translation -> the bone's local location channel."""
    rest = pose_bone.bone.matrix_local.to_3x3()
    return rest.inverted() @ Vector(world_delta)


def bone_local_rotation(pose_bone, world_quat):
    """World-space rotation -> the bone's local rotation channel."""
    rest = pose_bone.bone.matrix_local.to_3x3()
    local = rest.inverted() @ world_quat.to_matrix() @ rest
    return local.to_quaternion()


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def add_ik(arm, bone_name, chain, target):
    pb = arm.pose.bones[bone_name]
    con = pb.constraints.new("IK")
    con.target = target
    con.chain_count = len(chain)
    con.use_tail = True
    con.use_stretch = False
    return con


def make_target(name):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.08
    bpy.context.scene.collection.objects.link(empty)
    return empty


def make_guide(name, rest_quat):
    empty = make_target(name)
    empty.rotation_mode = "QUATERNION"
    empty.rotation_quaternion = rest_quat
    return empty


def add_copy_rotation(arm, bone_name, target):
    con = arm.pose.bones[bone_name].constraints.new("COPY_ROTATION")
    con.target = target
    con.target_space = "WORLD"
    con.owner_space = "WORLD"
    con.mix_mode = "REPLACE"
    return con


def rest_tail(arm, bone_name):
    return arm.data.bones[bone_name].tail_local.copy()


def hoof_rest_rotation(arm, bone_name):
    return arm.data.bones[bone_name].matrix_local.to_quaternion().copy()


def author_gait(arm, name, spec, preview=False):
    cycle = int(spec["cycle"])
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = cycle

    reset_pose(arm)
    arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action

    targets = {}
    guides = {}
    rest = {}
    rest_rot = {}
    constraints = []
    for key, leg in (("FL", FRONT["L"]), ("FR", FRONT["R"]),
                     ("HL", HIND["L"]), ("HR", HIND["R"])):
        target = make_target("%s_%s" % (name, key))
        targets[key] = target
        rest[key] = rest_tail(arm, leg["bone"])
        constraints.append(add_ik(arm, leg["bone"], leg["chain"], target))
        # Keep the hoof level instead of letting it inherit the whole leg arc.
        rest_rot[key] = hoof_rest_rotation(arm, leg["hoof"])
        guide = make_guide("%s_%s_rot" % (name, key), rest_rot[key])
        guides[key] = guide
        constraints.append(add_copy_rotation(arm, leg["hoof"], guide))

    root = arm.pose.bones[ROOT]
    neck = arm.pose.bones[NECK]
    spine = arm.pose.bones[SPINE1]
    tail = arm.pose.bones[TAIL]

    phase_by_leg = spec["footfall"]
    stride = spec["stride"]
    duty = spec["duty"]
    lift = spec["lift"]

    for frame in range(cycle + 1):
        t = (frame % cycle) / cycle
        # Feet: each leg cycles through stance then a lifted swing.
        for key, target in targets.items():
            offset = phase_by_leg[key]
            p = (t - offset) % 1.0
            base = rest[key]
            pitch = 0.0
            if p < duty:
                s = p / duty
                y = -stride * 0.5 + stride * s
                z = 0.0
            else:
                s = (p - duty) / (1.0 - duty)
                y = stride * 0.5 - stride * smoothstep(s)
                z = lift * math.sin(math.pi * s)
                # Fold the toe up through the swing, level again for landing.
                pitch = math.radians(-14.0) * math.sin(math.pi * s)
            target.location = (base.x, base.y + y, base.z + z)
            guide = guides[key]
            guide.rotation_quaternion = Quaternion((1.0, 0.0, 0.0), pitch) @ rest_rot[key]
            guide.keyframe_insert("rotation_quaternion", frame=frame)

        # Body: a small drop and a bob so the shoulders/hips ride the beats.
        bob = spec["bob"] * math.cos(2.0 * math.pi * spec["bob_hz"] * t)
        root.location = bone_local_delta(root, (0.0, 0.0, -spec["body_drop"] + bob))
        pitch = math.radians(1.2) * math.sin(2.0 * math.pi * spec["bob_hz"] * t)
        root.rotation_quaternion = bone_local_rotation(root, Quaternion((1.0, 0.0, 0.0), pitch))

        nod = math.radians(spec["nod"]) * math.sin(2.0 * math.pi * t + math.pi * 0.35)
        neck.rotation_quaternion = bone_local_rotation(neck, Quaternion((1.0, 0.0, 0.0), nod))
        spine.rotation_quaternion = bone_local_rotation(
            spine, Quaternion((1.0, 0.0, 0.0), -nod * 0.35))
        tail.rotation_quaternion = bone_local_rotation(
            tail, Quaternion((0.0, 1.0, 0.0), math.radians(2.5) * math.sin(2.0 * math.pi * t)))

        root.keyframe_insert("location", frame=frame)
        root.keyframe_insert("rotation_quaternion", frame=frame)
        neck.keyframe_insert("rotation_quaternion", frame=frame)
        spine.keyframe_insert("rotation_quaternion", frame=frame)
        tail.keyframe_insert("rotation_quaternion", frame=frame)
        for target in targets.values():
            target.keyframe_insert("location", frame=frame)

    return bake(arm, name, cycle, targets, constraints, guides)


def author_jump(arm, name="Jump"):
    """A 0.9 s in-place jump: gather, push, tuck, reach for the ground, land."""
    cycle = 22
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = cycle

    reset_pose(arm)
    arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action

    targets = {}
    guides = {}
    rest = {}
    rest_rot = {}
    constraints = []
    for key, leg in (("FL", FRONT["L"]), ("FR", FRONT["R"]),
                     ("HL", HIND["L"]), ("HR", HIND["R"])):
        target = make_target("%s_%s" % (name, key))
        targets[key] = target
        rest[key] = rest_tail(arm, leg["bone"])
        constraints.append(add_ik(arm, leg["bone"], leg["chain"], target))
        rest_rot[key] = hoof_rest_rotation(arm, leg["hoof"])
        guide = make_guide("%s_%s_rot" % (name, key), rest_rot[key])
        guides[key] = guide
        constraints.append(add_copy_rotation(arm, leg["hoof"], guide))

    root = arm.pose.bones[ROOT]
    neck = arm.pose.bones[NECK]
    spine = arm.pose.bones[SPINE1]

    # Fetlock offset (dy, dz) by phase: gather, push, tuck, reach, land.
    def hoof_offset(leg, p):
        if leg.startswith("F"):
            if p < 0.18:                              # gather, weight back
                return (-0.03 * smoothstep(p / 0.18), 0.0)
            if p < 0.34:                              # fold up off the ground
                s = (p - 0.18) / 0.16
                return (-0.03 + 0.08 * smoothstep(s), 0.45 * smoothstep(s))
            if p < 0.66:                              # tight tuck under chest
                s = (p - 0.34) / 0.32
                return (0.05 + 0.03 * math.sin(math.pi * s),
                        0.45 + 0.05 * math.sin(math.pi * s))
            s = (p - 0.66) / 0.34                     # reach forward for landing
            return (0.05 - 0.35 * smoothstep(s), 0.50 * (1.0 - smoothstep(s)))
        else:
            if p < 0.18:                              # gather, hocks under body
                return (0.06 * smoothstep(p / 0.18), 0.0)
            if p < 0.34:                              # push: hind legs extend back
                s = (p - 0.18) / 0.16
                return (0.06 + 0.30 * smoothstep(s), 0.0)
            if p < 0.66:                              # air: hocks fold up
                s = (p - 0.34) / 0.32
                return (0.36 - 0.30 * smoothstep(s), 0.42 * smoothstep(s))
            s = (p - 0.66) / 0.34                     # land, hind come under body
            return (0.06 * (1.0 - smoothstep(s)), 0.42 * (1.0 - smoothstep(s)))

    for frame in range(cycle + 1):
        t = frame / cycle
        for key, target in targets.items():
            dy, dz = hoof_offset(key, t)
            base = rest[key]
            target.location = (base.x, base.y + dy, base.z + dz)
            # Tuck the toes while airborne, level for gather and landing.
            air = smoothstep((t - 0.28) / 0.10) * (1.0 - smoothstep((t - 0.70) / 0.14))
            pitch = math.radians(-22.0 if key.startswith("F") else -12.0) * air
            guide = guides[key]
            guide.rotation_quaternion = Quaternion((1.0, 0.0, 0.0), pitch) @ rest_rot[key]
            guide.keyframe_insert("rotation_quaternion", frame=frame)

        # Crouch, launch nose-up, float, then absorb the landing.  The runtime
        # supplies the real vertical arc; this only sells the body attitude.
        if t < 0.18:
            dz = -0.06 * smoothstep(t / 0.18)
            pitch = math.radians(3.0) * smoothstep(t / 0.18)
        elif t < 0.36:
            s = (t - 0.18) / 0.18
            dz = -0.06 + 0.15 * smoothstep(s)
            pitch = math.radians(3.0 - 16.0 * smoothstep(s))
        elif t < 0.66:
            s = (t - 0.36) / 0.30
            dz = 0.09 - 0.03 * smoothstep(s)
            pitch = math.radians(-13.0 + 8.0 * smoothstep(s))
        else:
            s = (t - 0.66) / 0.34
            dz = 0.06 - 0.12 * smoothstep(s)
            pitch = math.radians(-5.0 + 9.0 * smoothstep(s))

        root.location = bone_local_delta(root, (0.0, 0.0, dz))
        root.rotation_quaternion = bone_local_rotation(root, Quaternion((1.0, 0.0, 0.0), pitch))
        nod = math.radians(-14.0) * math.sin(math.pi * min(1.0, t / 0.8))
        neck.rotation_quaternion = bone_local_rotation(neck, Quaternion((1.0, 0.0, 0.0), nod))
        spine.rotation_quaternion = bone_local_rotation(
            spine, Quaternion((1.0, 0.0, 0.0), -nod * 0.4))

        root.keyframe_insert("location", frame=frame)
        root.keyframe_insert("rotation_quaternion", frame=frame)
        neck.keyframe_insert("rotation_quaternion", frame=frame)
        spine.keyframe_insert("rotation_quaternion", frame=frame)
        for target in targets.values():
            target.keyframe_insert("location", frame=frame)

    return bake(arm, name, cycle, targets, constraints, guides)


def bake(arm, name, cycle, targets, constraints, guides):
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(
        frame_start=0,
        frame_end=cycle,
        step=1,
        only_selected=True,
        visual_keying=True,
        clear_constraints=True,
        clear_parents=False,
        use_current_action=True,
        bake_types={"POSE"},
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    baked = arm.animation_data.action
    if baked is not None:
        baked.name = name
        baked.use_fake_user = True
        baked.use_frame_range = True
        baked.frame_start = 0.0
        baked.frame_end = float(cycle)
    for helper in list(targets.values()) + list(guides.values()):
        bpy.data.objects.remove(helper, do_unlink=True)
    return baked


def build_discrete(arm, source, base):
    actions = []
    for name, start_s, end_s in SOURCE_CLIPS:
        start_frame = base + round(start_s * FPS)
        end_frame = base + round(end_s * FPS)
        if end_frame <= start_frame:
            raise RuntimeError("clip %s has an empty range" % name)
        action, duration = split.build_clip_action(
            source, name, start_frame, end_frame, base, FPS)
        actions.append((action, duration))
        print("[build] %-16s %.3f s" % (name, duration / FPS))
    return actions


def push_nla(arm, actions):
    arm.animation_data.action = None
    while arm.animation_data.nla_tracks:
        arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
    for action, duration in actions:
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.name = action.name
        strip.action_frame_start = 0.0
        strip.action_frame_end = duration
        strip.frame_start = 0.0
        strip.frame_end = duration


def main():
    args = parse_args()
    src = os.path.abspath(args.input)
    dst = os.path.abspath(args.output)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = int(FPS)
    scene.render.fps_base = 1.0
    scene.frame_start = 0

    bpy.ops.import_scene.gltf(filepath=src)
    arm = split.find_armature()
    if arm is None:
        raise RuntimeError("no armature found in %s" % src)
    source = split.source_action(arm)
    base = split.action_base_frame(source)

    actions = build_discrete(arm, source, base)
    arm.animation_data.action = None

    for name, spec in GAITS.items():
        if args.only and name not in args.only:
            continue
        print("[build] authoring %s ..." % name)
        action = author_gait(arm, name, spec)
        if action is not None:
            actions.append((action, float(spec["cycle"])))
            print("[build] %-16s %.3f s (authored)" % (name, spec["cycle"] / FPS))

    if not args.only or "Jump" in args.only:
        print("[build] authoring Jump ...")
        action = author_jump(arm)
        if action is not None:
            actions.append((action, 22.0))
            print("[build] %-16s %.3f s (authored)" % ("Jump", 22.0 / FPS))

    bpy.data.actions.remove(source)
    push_nla(arm, actions)

    scene.frame_end = max(int(d) for _, d in actions)
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
    print("[build] wrote %s with %d clips" % (dst, len(actions)))


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--only", default="", help="comma-separated authored clips to build")
    return parser.parse_args(argv)


if __name__ == "__main__":
    main()
