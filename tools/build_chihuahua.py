"""Build the rigged, animated Chihuahua from Models/chihuahua_derp_dog.glb.

Usage:
    blender --background --factory-startup --python tools/build_chihuahua.py -- [--stage base|gaits|extra|all]

Produces Models/chihuahua.glb and artifacts/chihuahua_build.blend
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
STAGE = "all"
if "--stage" in ARGS:
    STAGE = ARGS[ARGS.index("--stage") + 1]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Models/chihuahua_derp_dog.glb")
OUT = os.path.join(ROOT, "Models/chihuahua.glb")
BLEND = os.path.join(ROOT, "artifacts/chihuahua_build.blend")
SCALE = 0.46
FPS = 30
LOOP_CLIPS = {"Idle", "Idle_Alert", "Walk", "Trot", "Run", "Sit", "Bark", "Howl", "Fetch", "Jump", "Bite", "Rest_Pose"}
ONE_SHOT = {"Death", "Fall"}

## Every clip the exported GLB carries.  The NLA rebuild walks this list so a
## helper object's action cannot leak in as an extra animation.
CLIP_NAMES = [
    "Bark", "Bite", "Death", "Eat", "Fall", "Fetch", "Howl", "Idle",
    "Idle_Alert", "Jump", "Lie", "Rest_Pose", "Run", "Shake", "Sit",
    "Sleep", "TailWag", "Trot", "Walk",
]

arm = None
sc = None


def log(*a):
    print("[chihuahua]", *a)


def setup():
    global arm, sc
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.name = "Chihuahua"
    arm.data.name = "Chihuahua"
    if arm.animation_data:
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    meshes.sort(key=lambda o: len(o.data.vertices))
    if len(meshes) == 2:
        meshes[0].name = "Chihuahua_Eyes"
        meshes[1].name = "Chihuahua_Body"
    # strip the importer suffix from action names
    for act in bpy.data.actions:
        if "_Skinned" in act.name:
            act.name = act.name.split("_Skinned")[0]
    for act in bpy.data.actions:
        act.use_fake_user = True
    log("actions", sorted(a.name for a in bpy.data.actions))


def scale_rig():
    """Bake SCALE into mesh data, bone rest positions and pose location curves."""
    # meshes
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.transform(Matrix.Scale(SCALE, 4))
            o.data.update()
    # bones
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for b in arm.data.edit_bones:
        b.head = b.head * SCALE
        b.tail = b.tail * SCALE
    bpy.ops.object.mode_set(mode="OBJECT")
    # pose location curves (Hips only in the source)
    for act in bpy.data.actions:
        for fc in act.fcurves:
            if not fc.data_path.endswith(".location"):
                continue
            for k in fc.keyframe_points:
                k.co.y *= SCALE
                k.handle_left.y *= SCALE
                k.handle_right.y *= SCALE
    # sit the feet exactly on z=0
    bpy.context.view_layer.update()
    zmin = min((o.matrix_world @ v.co).z for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices)
    log("scale", SCALE, "feet z before lift", round(zmin, 5))
    if abs(zmin) > 1e-6:
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.data.transform(Matrix.Translation((0, 0, -zmin)))
                o.data.update()
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        for b in arm.data.edit_bones:
            b.head.z -= zmin
            b.tail.z -= zmin
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type == "MESH":
            ws = [o.matrix_world @ v.co for v in o.data.vertices]
            log(o.name, "verts", len(o.data.vertices),
                "z", round(min(v.z for v in ws), 4), "..", round(max(v.z for v in ws), 4),
                "y", round(min(v.y for v in ws), 4), "..", round(max(v.y for v in ws), 4))


def downscale_textures():
    for img in bpy.data.images:
        if max(img.size) > 1024:
            log("resize", img.name, tuple(img.size), "-> 1024")
            img.scale(1024, 1024)
            img.pack()


def get_action(name):
    return bpy.data.actions.get(name)


def read_pose(action, frame):
    """Return {bone: (quat, location)} in pose space."""
    arm.animation_data.action = action
    sc.frame_set(int(frame))
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in arm.pose.bones}


def quat_curves(act, bone):
    path = 'pose.bones["%s"].rotation_quaternion' % bone
    fcs = [fc for fc in act.fcurves if fc.data_path == path]
    return sorted(fcs, key=lambda f: f.array_index)


def loc_curves(act, bone):
    path = 'pose.bones["%s"].location' % bone
    fcs = [fc for fc in act.fcurves if fc.data_path == path]
    return sorted(fcs, key=lambda f: f.array_index)


def close_loop(act, blend=4, eps_deg=0.0):
    """Ease the last `blend` keys so the clip returns exactly to its first pose."""
    changed = 0
    for pb in arm.pose.bones:
        fcs = quat_curves(act, pb.name)
        if len(fcs) != 4:
            continue
        n = min(len(fc.keyframe_points) for fc in fcs)
        if n < 2:
            continue
        q0 = Quaternion([fc.keyframe_points[0].co.y for fc in fcs])
        q1 = Quaternion([fc.keyframe_points[n - 1].co.y for fc in fcs])
        q0.normalize(); q1.normalize()
        delta = q1.inverted() @ q0
        if delta.angle < math.radians(eps_deg):
            continue
        changed += 1
        for j in range(max(0, n - blend), n):
            t = (j - (n - blend) + 1) / blend
            w = t * t * (3 - 2 * t)
            corr = Quaternion().slerp(delta, w)
            q = Quaternion([fc.keyframe_points[j].co.y for fc in fcs])
            q.normalize()
            q = (q @ corr).normalized()
            for i, fc in enumerate(fcs):
                fc.keyframe_points[j].co.y = q[i]
    for pb in arm.pose.bones:
        fcs = loc_curves(act, pb.name)
        if len(fcs) != 3:
            continue
        n = min(len(fc.keyframe_points) for fc in fcs)
        if n < 2:
            continue
        p0 = Vector([fc.keyframe_points[0].co.y for fc in fcs])
        p1 = Vector([fc.keyframe_points[n - 1].co.y for fc in fcs])
        d = p0 - p1
        if d.length < 1e-4:
            continue
        changed += 1
        for j in range(max(0, n - blend), n):
            t = (j - (n - blend) + 1) / blend
            w = t * t * (3 - 2 * t)
            p = Vector([fc.keyframe_points[j].co.y for fc in fcs]) + d * w
            for i, fc in enumerate(fcs):
                fc.keyframe_points[j].co.y = p[i]
    for fc in act.fcurves:
        fc.update()
    return changed


def close_all_loops():
    for name in sorted(LOOP_CLIPS):
        act = get_action(name)
        if act:
            n = close_loop(act)
            log("loop", name, "bones eased", n, "range", tuple(round(v, 2) for v in act.frame_range))


# ---------------------------------------------------------------- gaits

## Each leg as a sagittal chain (scapula/pelvis, thigh, shank, hock) plus a
## rigid paw.  The stride is authored by pinning the paw tip of every foot to a
## ground path and solving the chain onto it, so a planted paw travels backwards
## at exactly the clip's ground speed instead of skating.
LEG_CHAIN = {
    "LF": dict(
        chain=("Front_Leg_Shoulder_L", "Front_Leg_Upper_L", "Front_Leg_Lower_L", "Front_Leg_Ankle_L"),
        paw=("Front_Leg_Foot_L", "Front_Leg_Tip_L"), tip="Front_Leg_Tip_L",
    ),
    "RF": dict(
        chain=("Front_Leg_Shoulder_R", "Front_Leg_Upper_R", "Front_Leg_Lower_R", "Front_Leg_Ankle_R"),
        paw=("Front_Leg_Foot_R", "Front_Leg_Tip_R"), tip="Front_Leg_Tip_R",
    ),
    "LH": dict(
        chain=("Back_Leg_Pelvis_L", "Back_Leg_Upper_L", "Back_Leg_Lower_L", "Back_Leg_Ankle_L"),
        paw=("Back_Leg_Foot_L", "Back_Leg_Foot_1_L", "Back_Leg_Tip_L"), tip="Back_Leg_Tip_L",
    ),
    "RH": dict(
        chain=("Back_Leg_Pelvis_R", "Back_Leg_Upper_R", "Back_Leg_Lower_R", "Back_Leg_Ankle_R"),
        paw=("Back_Leg_Foot_R", "Back_Leg_Foot_1_R", "Back_Leg_Tip_R"), tip="Back_Leg_Tip_R",
    ),
}

## frames: cycle length at FPS.  duty: fraction of the cycle a foot is planted.
## stride: metres the body covers per cycle, which is the clip's ground speed
## times its duration.  offsets: foot phase, 0.0 = foot strike.
## The stance excursion is stride * duty and must stay inside the leg's reach
## (about 0.19 m for this rig); build_gait clamps it and logs the result.
GAITS = {
    "Walk": dict(
        frames=10, duty=0.64, lift=0.030,
        offsets={"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
        bob=0.005, bob_hz=2, sway=0.004, roll=1.2, yaw=2.0, tail=5.0,
    ),
    "Trot": dict(
        frames=7, duty=0.36, lift=0.040,
        offsets={"LF": 0.0, "RH": 0.0, "RF": 0.5, "LH": 0.5},
        bob=0.008, bob_hz=2, sway=0.002, roll=1.0, yaw=1.2, tail=8.0,
    ),
    "Run": dict(
        frames=6, duty=0.24, lift=0.052,
        offsets={"LH": 0.0, "RH": 0.12, "LF": 0.42, "RF": 0.54},
        bob=0.014, bob_hz=1, sway=0.0, roll=2.0, yaw=0.8, tail=10.0,
    ),
}
TWO_PI = 2.0 * math.pi
# Above this the stance stops being a plant: the paw is dragged instead.
MAX_EXCURSION = 0.19
# Fraction of the leg chain a foot target may use.  Keeping a little back from
# a locked-straight leg is what stops the IK from snapping at the extremes.
REACH_FACTOR = 0.97


def leg_rest():
    """Rest geometry: where the IK aims, and the level paw attitude."""
    out = {}
    for key, spec in LEG_CHAIN.items():
        distal = arm.data.bones[spec["chain"][-1]]
        tip = arm.data.bones[spec["tip"]]
        out[key] = dict(
            target_rest=distal.tail_local.copy(),
            tip_rest=tip.tail_local.copy(),
            # Ankle tail to paw tip with the paw level: constant by construction.
            foot_offset=(tip.tail_local - distal.tail_local).copy(),
            paw_rots=[arm.data.bones[b].matrix_local.to_quaternion() for b in spec["paw"]],
        )
    return out


def foot_windows(rest):
    """Fore-aft span every paw can reach at its rest height, relative to rest.

    The source rig stands with nearly straight legs, so the paw sits close to
    its forward limit.  The stance has to be centred where the whole chain can
    still bend, otherwise the foot goes short and the plant breaks.
    """
    windows = {}
    for key, geo in rest.items():
        chain = LEG_CHAIN[key]["chain"]
        reach = sum(arm.data.bones[b].length for b in chain) * REACH_FACTOR
        root = arm.pose.bones[chain[0]].head.copy()
        lo, hi = None, None
        steps = 97
        for i in range(steps):
            dy = -0.12 + 0.24 * i / (steps - 1.0)
            target = geo["tip_rest"] + Vector((0.0, dy, 0.0)) - geo["foot_offset"]
            if (target - root).length <= reach:
                if lo is None:
                    lo = dy
                hi = dy
        if lo is None:
            lo, hi = 0.0, 0.0
        log("reach", key, round(lo, 3), "..", round(hi, 3), "m from rest")
        windows[key] = (lo, hi)
    return windows


def make_target(name):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.03
    bpy.context.scene.collection.objects.link(empty)
    return empty


def add_ik(bone_name, chain, target):
    con = arm.pose.bones[bone_name].constraints.new("IK")
    con.target = target
    con.chain_count = len(chain)
    con.use_tail = True
    con.use_stretch = False
    return con


def add_copy_rotation(bone_name, target):
    con = arm.pose.bones[bone_name].constraints.new("COPY_ROTATION")
    con.target = target
    con.target_space = "WORLD"
    con.owner_space = "WORLD"
    con.mix_mode = "REPLACE"
    return con


def bind_legs(name, rest):
    """A foot target and a level-paw guide per leg, as the horse gaits do."""
    targets, guides, helpers, constraints = {}, {}, [], []
    for key, leg in LEG_CHAIN.items():
        target = make_target("%s_%s_target" % (name, key))
        targets[key] = target
        helpers.append(target)
        constraints.append(add_ik(leg["chain"][-1], leg["chain"], target))
        # Each paw bone keeps its own rest attitude, so the paw hangs exactly
        # as it does at rest instead of curling under.
        guides[key] = []
        for i, bone_name in enumerate(leg["paw"]):
            guide = make_target("%s_%s_%s_rot" % (name, key, bone_name))
            guide.rotation_mode = "QUATERNION"
            guide.rotation_quaternion = rest[key]["paw_rots"][i]
            guides[key].append(guide)
            helpers.append(guide)
            constraints.append(add_copy_rotation(bone_name, guide))
    return targets, guides, helpers, constraints


def bake_gait(name, last_frame, helpers):
    """Bake the IK pose into plain bone keys, then drop the constraint rig."""
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(
        frame_start=0,
        frame_end=last_frame,
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
        baked.frame_end = float(last_frame)
    for helper in helpers:
        bpy.data.objects.remove(helper, do_unlink=True)
    return baked


def foot_path(phase, duty, excursion, lift):
    """Paw offset from its rest spot: stance drags back, swing eases forward."""
    if phase < duty:
        u = phase / duty
        return -excursion * 0.5 + excursion * u, 0.0
    u = (phase - duty) / max(1e-5, 1.0 - duty)
    ease = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
    return excursion * 0.5 - excursion * ease, lift * math.sin(math.pi * u)


def build_gait(name):
    spec = GAITS[name]
    n = spec["frames"]
    duty = spec["duty"]
    lift = spec["lift"]
    base = copy_pose(read_pose(get_action("Idle"), 1))
    for pb in arm.pose.bones:
        q, loc = base.get(pb.name, (Quaternion(), Vector()))
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.location = loc
    bpy.context.view_layer.update()
    rest = leg_rest()
    windows = foot_windows(rest)
    # Every paw covers the same ground travel, so the shared excursion is the
    # narrowest window; each foot is then centred inside its own window.
    excursion = min(hi - lo for lo, hi in windows.values())
    excursion = min(excursion, MAX_EXCURSION)
    centres = {k: (lo + hi) * 0.5 for k, (lo, hi) in windows.items()}
    cycle_s = n / FPS
    log(name, "cycle", round(cycle_s, 3), "s",
        "stance excursion", round(excursion, 3), "m",
        "centres", {k: round(v, 3) for k, v in centres.items()},
        "ground speed", round(excursion / (duty * cycle_s), 3), "m/s")

    # Replace the source clip of the same name outright.
    stale = bpy.data.actions.get(name)
    if stale is not None:
        bpy.data.actions.remove(stale)
    arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    targets, guides, helpers, _constraints = bind_legs(name, rest)

    # Authored on frames 0..n (the last key repeats the first pose exactly), so
    # the exported clip is exactly one cycle long with no dead lead-in.
    for f in range(0, n + 1):
        u = (f % n) / float(n)
        pose = copy_pose(base)
        phase_u = TWO_PI * u
        bob = spec["bob"] * math.sin(TWO_PI * spec["bob_hz"] * u + math.pi)
        add_hips_world(pose, (spec["sway"] * math.sin(phase_u), 0.0, bob))
        add_rot(pose, "Spine_1", Z, math.radians(spec["yaw"]) * math.sin(phase_u))
        add_rot(pose, "Spine_2", Z, math.radians(spec["yaw"] * 0.6) * math.sin(phase_u))
        add_rot(pose, "Spine_1", Y, math.radians(spec["roll"]) * math.sin(phase_u))
        # The neck holds the head steady while the trunk sways under it.
        add_rot(pose, "Head", Z, math.radians(-spec["yaw"] * 0.8) * math.sin(phase_u))
        add_rot(pose, "Head", X, math.radians(-2.0) * math.sin(TWO_PI * spec["bob_hz"] * u + math.pi))
        add_rot(pose, "Tail_Base", Z, math.radians(spec["tail"]) * math.sin(phase_u - 0.6))
        add_rot(pose, "Tail_Mid", Z, math.radians(spec["tail"] * 0.7) * math.sin(phase_u - 1.0))

        for pb in arm.pose.bones:
            q, loc = pose.get(pb.name, (Quaternion(), Vector()))
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.location = loc

        wants = {}
        for key, leg in LEG_CHAIN.items():
            geo = rest[key]
            phase = (u + spec["offsets"][key]) % 1.0
            dy, dz = foot_path(phase, duty, excursion, lift)
            wants[key] = geo["tip_rest"] + Vector((0.0, dy + centres[key], dz))
            spot = geo["target_rest"]
            targets[key].location = arm.matrix_world @ Vector(
                (spot.x, spot.y + dy + centres[key], spot.z + dz))
            # Level while planted, toe folded up through the swing.
            tuck = 0.0
            if phase >= duty:
                swing_u = (phase - duty) / max(1e-5, 1.0 - duty)
                tuck = math.radians(-16.0) * math.sin(math.pi * swing_u)
            for i, guide in enumerate(guides[key]):
                guide.rotation_quaternion = (
                    Quaternion((1.0, 0.0, 0.0), tuck) @ geo["paw_rots"][i])

        # The paw hangs off a joint the solver also turns, so the tip starts a
        # few millimetres off its path.  Two correction passes put it on the
        # ground exactly, which is what keeps the plant from sinking or
        # skating.
        for _pass in range(2):
            bpy.context.view_layer.update()
            for key, leg in LEG_CHAIN.items():
                fix = wants[key] - arm.pose.bones[leg["tip"]].tail
                fix.x = 0.0
                targets[key].location += arm.matrix_world.to_3x3() @ fix

        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
        arm.pose.bones["Hips"].keyframe_insert("location", frame=f)
        for key in LEG_CHAIN:
            targets[key].keyframe_insert("location", frame=f)
            for guide in guides[key]:
                guide.keyframe_insert("rotation_quaternion", frame=f)

    baked = bake_gait(name, n, helpers)
    log("built", name, "keys", n + 1, "duration", round(n / FPS, 3))
    return baked


def clear_anim():
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)


def build_action(name, frames):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    clear_anim()
    arm.animation_data.action = act
    for f in sorted(frames):
        pose = frames[f]
        for pb in arm.pose.bones:
            q, loc = pose.get(pb.name, (Quaternion(), Vector()))
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.location = loc
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            if pb.name == "Hips":
                pb.keyframe_insert("location", frame=f, group=pb.name)
    for fc in act.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
        fc.update()
    return act


def build_gaits():
    for name in ("Walk", "Trot", "Run"):
        build_gait(name)


# ---------------------------------------------------------------- new clips

def world_axis_quat(bone, axis, angle):
    M = arm.data.bones[bone].matrix_local.to_3x3()
    a = (M.inverted() @ Vector(axis)).normalized()
    return Quaternion(a, angle)


def add_rot(pose, bone, axis, angle):
    q, loc = pose[bone]
    pose[bone] = [world_axis_quat(bone, axis, angle) @ q, loc]


def add_hips_world(pose, vec):
    M = arm.data.bones["Hips"].matrix_local.to_3x3()
    pose["Hips"][1] = pose["Hips"][1] + (M.inverted() @ Vector(vec))


def base_idle():
    return read_pose(get_action("Idle"), 1)


def copy_pose(p):
    return {b: [q.copy(), loc.copy()] for b, (q, loc) in p.items()}


X = (1, 0, 0)
Y = (0, 1, 0)
Z = (0, 0, 1)


def build_tailwag():
    n = 22
    frames = {}
    for f in range(1, n + 1):
        u = (f - 1) / (n - 1)
        ph = 2 * math.pi * u
        p = copy_pose(base_idle())
        for i, b in enumerate(["Tail_Base", "Tail_Mid", "Tail_Mid001", "Tail_End", "Tail_Tip"]):
            add_rot(p, b, Z, math.radians(9 + 4 * i) * math.sin(ph - 0.5 * i))
        add_rot(p, "Tail_Base", X, math.radians(-8))
        for b in ("Spine_1", "Spine_2"):
            add_rot(p, b, Z, math.radians(2.0) * math.sin(ph + math.pi))
        add_rot(p, "Hips", Z, math.radians(2.5) * math.sin(ph))
        add_rot(p, "Ear_L", Y, math.radians(3) * math.sin(ph))
        add_rot(p, "Ear_R", Y, math.radians(-3) * math.sin(ph))
        frames[f] = p
    build_action("TailWag", frames)
    log("built TailWag", n, "frames")


def build_shake():
    n = 32
    frames = {}
    for f in range(1, n + 1):
        u = (f - 1) / (n - 1)
        env = math.sin(math.pi * u) ** 1.3
        ph = 2 * math.pi * 7 * u
        p = copy_pose(base_idle())
        for b, a in (("Spine_1", 6), ("Spine_2", 7), ("Spine_3", 8), ("Spine_4", 6)):
            add_rot(p, b, Z, math.radians(a) * env * math.sin(ph))
        for b, a in (("Head", 0),):
            pass
        add_rot(p, "Nose", Z, math.radians(10) * env * math.sin(ph + math.pi))
        add_rot(p, "Ear_L", X, math.radians(18) * env * math.sin(ph + 1.2))
        add_rot(p, "Ear_R", X, math.radians(18) * env * math.sin(ph + 1.2))
        add_rot(p, "Ear_L", Y, math.radians(8) * env * math.sin(ph))
        add_rot(p, "Ear_R", Y, math.radians(-8) * env * math.sin(ph))
        for i, b in enumerate(["Tail_Base", "Tail_Mid", "Tail_Mid001", "Tail_End", "Tail_Tip"]):
            add_rot(p, b, Z, math.radians(10 + 4 * i) * env * math.sin(ph - 0.45 * i))
        add_rot(p, "Hips", Z, math.radians(5) * env * math.sin(ph + math.pi))
        add_hips_world(p, (0, 0, 0.004 * env))
        frames[f] = p
    build_action("Shake", frames)
    log("built Shake", n, "frames")


def build_eat():
    n = 45
    frames = {}
    for f in range(1, n + 1):
        u = (f - 1) / (n - 1)
        chew = 2 * math.pi * 4 * u
        p = copy_pose(base_idle())
        add_rot(p, "Spine_3", X, math.radians(26))
        add_rot(p, "Spine_4", X, math.radians(24))
        add_rot(p, "Nose", X, math.radians(14))
        add_rot(p, "Spine_2", X, math.radians(8))
        # small head bob with the chewing
        add_rot(p, "Spine_4", X, math.radians(2.5) * math.sin(chew))
        add_rot(p, "Chin", X, math.radians(9) * (0.5 + 0.5 * math.sin(chew)))
        add_rot(p, "Tail_Base", Z, math.radians(3) * math.sin(chew * 0.5))
        frames[f] = p
    build_action("Eat", frames)
    log("built Eat", n, "frames")


# Death frame 35 is the side-lying pose the body settles into; the last frame
# of Death drifts further and sinks through the floor.
DEATH_LIE_FRAME = 35


def lying_pose(head_down=False):
    """Use a frame of Death as a ground-true lying pose."""
    death = get_action("Death")
    frame = min(DEATH_LIE_FRAME, int(death.frame_range[1]))
    p = copy_pose(read_pose(death, frame))
    if not head_down:
        add_rot(p, "Spine_3", X, math.radians(-16))
        add_rot(p, "Spine_4", X, math.radians(-18))
        add_rot(p, "Nose", X, math.radians(-8))
        for side in ("L", "R"):
            add_rot(p, "Ear_" + side, X, math.radians(-10))
    return p


def snapshot():
    return {pb.name: [pb.rotation_quaternion.copy(), pb.location.copy()]
            for pb in arm.pose.bones}


def build_lie():
    n = 52
    death = get_action("Death")
    d0, d1 = [int(round(v)) for v in death.frame_range]
    arm.animation_data.action = death
    frames = {}
    for f in range(1, n + 1):
        fr = d0 + (d1 - d0) * (f - 1) / (n - 1)
        base = int(fr)
        sc.frame_set(base, subframe=fr - base)
        frames[f] = snapshot()
    build_action("Lie", frames)
    log("built Lie", n, "frames from Death motion")


def build_sleep():
    n = 90
    target = lying_pose(head_down=True)
    frames = {}
    for f in range(1, n + 1):
        u = (f - 1) / (n - 1)
        breath = math.sin(2 * math.pi * u)
        p = copy_pose(target)
        add_rot(p, "Spine_2", X, math.radians(1.6) * breath)
        add_rot(p, "Spine_3", X, math.radians(1.2) * breath)
        add_rot(p, "Stomach", X, math.radians(2.2) * breath)
        add_rot(p, "Tail_Tip", Z, math.radians(3) * math.sin(2 * math.pi * 0.5 * u))
        frames[f] = p
    build_action("Sleep", frames)
    log("built Sleep", n, "frames")


LOW_BONES = ["Front_Leg_Tip_L", "Front_Leg_Tip_R", "Back_Leg_Tip_L", "Back_Leg_Tip_R",
             "Stomach_tip", "Chin_Tip", "Tail_Tip", "Nose"]


def clip_min_z():
    z = 1e9
    for b in LOW_BONES:
        pb = arm.pose.bones[b]
        z = min(z, pb.head.z, pb.tail.z)
    return z


def ground_clip(act, cyclic, margin=0.002):
    """Lift the hips per key so no low point of the rig sinks through z=0."""
    fcs = loc_curves(act, "Hips")
    if len(fcs) != 3:
        return 0.0
    n = min(len(fc.keyframe_points) for fc in fcs)
    frames = [int(round(fcs[0].keyframe_points[i].co.x)) for i in range(n)]
    arm.animation_data.action = act
    lifts = []
    for f in frames:
        sc.frame_set(f)
        lifts.append(max(0.0, margin - clip_min_z()))
    sm = [max(lifts[max(0, i - 1):min(n, i + 2)]) for i in range(n)]
    if cyclic:
        both = max(sm[0], sm[-1])
        sm[0] = sm[-1] = both
    M = arm.data.bones["Hips"].matrix_local.to_3x3()
    up = (M.inverted() @ Vector((0, 0, 1))).normalized()
    for i in range(n):
        if sm[i] <= 1e-6:
            continue
        for j, fc in enumerate(fcs):
            k = fc.keyframe_points[i]
            d = up[j] * sm[i]
            k.co.y += d
            k.handle_left.y += d
            k.handle_right.y += d
    for fc in fcs:
        fc.update()
    return max(sm)


def measure_gait(name):
    """Contact duty, stance travel and the ground speed a planted paw implies."""
    act = get_action(name)
    if act is None:
        return
    arm.animation_data.action = act
    f0, f1 = [int(round(v)) for v in act.frame_range]
    # How far above its own lowest point a paw still counts as planted; the
    # skeleton's height origin is not the ground.
    contact_margin = 0.012
    # A short stance (the Run plants for under two frames) only measures fairly
    # with subframe sampling.
    sub = 8
    dt = 1.0 / (FPS * sub)
    tips = {k: [] for k in LEG_CHAIN}
    for i in range((f1 - f0) * sub):
        sc.frame_set(f0 + i // sub, subframe=(i % sub) / float(sub))
        for k, leg in LEG_CHAIN.items():
            tips[k].append(arm.pose.bones[leg["tip"]].tail.copy())
    duties, travels, slips = [], [], []
    for pts in tips.values():
        floor_z = min(p.z for p in pts)
        contact_z = floor_z + contact_margin
        duties.append(sum(1 for p in pts if p.z < contact_z) / max(1, len(pts) - 1))
        runs, run = [], []
        for p in pts:
            if p.z < contact_z:
                run.append(p)
            else:
                if len(run) > 1:
                    runs.append(run)
                run = []
        if len(run) > 1:
            runs.append(run)
        for r in runs:
            travels.append(max(p.y for p in r) - min(p.y for p in r))
            for i in range(1, len(r)):
                step = r[i].y - r[i - 1].y
                # Only the backward half of the contact window is a plant; the
                # swing brushes near the ground too and would drag the median
                # down.
                if step > 0:
                    slips.append(step / dt)

    def med(xs):
        xs.sort()
        return xs[len(xs) // 2] if xs else 0.0

    log("measured", name, "cycle", round((f1 - f0) / FPS, 3), "s",
        "duty", round(med(duties), 2),
        "stance travel", round(med(travels), 3), "m",
        "ground speed", round(abs(med(slips)), 3), "m/s",
        "samples", len(slips))


# ---------------------------------------------------------------- export

def rebuild_nla():
    ad = arm.animation_data
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for name in CLIP_NAMES:
        act = bpy.data.actions.get(name)
        if act is None:
            log("nla missing", name)
            continue
        tr = ad.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, 1, act)
        st.name = name
        st.frame_start = 1
        st.action_frame_start = act.frame_range[0]
        st.action_frame_end = act.frame_range[1]
        tr.mute = False
    log("nla tracks", [(t.name, len(t.strips)) for t in ad.nla_tracks])


def export():
    clear_anim()
    arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type in {"MESH", "ARMATURE"}:
            o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    kwargs = dict(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=True,
        export_nla_strips=True,
        export_nla_strips_merged_animation_name="Animations",
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_frame_step=1,
        export_optimize_animation_size=False,
        export_anim_slide_to_zero=False,
        export_bake_animation=False,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
        export_extras=False,
        export_cameras=False,
        export_lights=False,
    )
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kwargs = {k: v for k, v in kwargs.items() if k in valid or k == "filepath"}
    bpy.ops.export_scene.gltf(**kwargs)
    log("exported", OUT, os.path.getsize(OUT), "bytes")


def save():
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    log("saved", BLEND)


def main():
    setup()
    scale_rig()
    downscale_textures()
    close_all_loops()
    if STAGE in ("gaits", "all"):
        build_gaits()
    if STAGE in ("extra", "all"):
        build_tailwag()
        build_shake()
        build_eat()
        build_lie()
        build_sleep()
    # Walk/Trot/Run are authored on the ground already; lifting their hips
    # would pull the planted paws out of contact.
    for n in ("TailWag", "Shake", "Eat", "Lie", "Sleep"):
        act = bpy.data.actions.get(n)
        if act:
            lift = ground_clip(act, cyclic=(n != "Lie"))
            log("ground", n, "max lift", round(lift, 4))
    for n in ("Walk", "Trot", "Run"):
        measure_gait(n)
    close_all_loops()
    rebuild_nla()
    save()
    if STAGE == "all":
        export()


main()
