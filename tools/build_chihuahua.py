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
LOOP_CLIPS = {"Idle", "Idle_Alert", "Walk", "Sit", "Bark", "Howl", "Fetch", "Jump", "Bite", "Rest_Pose"}
ONE_SHOT = {"Death", "Fall"}

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

LEGS = {
    "LF": ["Front_Leg_Shoulder_L", "Front_Leg_Upper_L", "Front_Leg_Lower_L", "Front_Leg_Ankle_L",
           "Front_Leg_Foot_L", "Front_Leg_Tip_L"],
    "RF": ["Front_Leg_Shoulder_R", "Front_Leg_Upper_R", "Front_Leg_Lower_R", "Front_Leg_Ankle_R",
           "Front_Leg_Foot_R", "Front_Leg_Tip_R"],
    "LH": ["Back_Leg_Pelvis_L", "Back_Leg_Upper_L", "Back_Leg_Lower_L", "Back_Leg_Ankle_L",
           "Back_Leg_Foot_L", "Back_Leg_Foot_1_L", "Back_Leg_Tip_L"],
    "RH": ["Back_Leg_Pelvis_R", "Back_Leg_Upper_R", "Back_Leg_Lower_R", "Back_Leg_Ankle_R",
           "Back_Leg_Foot_R", "Back_Leg_Foot_1_R", "Back_Leg_Tip_R"],
}
TIPS = {"LF": "Front_Leg_Tip_L", "RF": "Front_Leg_Tip_R", "LH": "Back_Leg_Tip_L", "RH": "Back_Leg_Tip_R"}


def walk_foot_phase(walk, cycle):
    arm.animation_data.action = walk
    ys = {k: [] for k in LEGS}
    for i in range(cycle):
        sc.frame_set(1 + i)
        for k, tip in TIPS.items():
            ys[k].append(arm.pose.bones[tip].tail.y)
    phases = {}
    for k, vals in ys.items():
        i = min(range(len(vals)), key=lambda j: vals[j])
        phases[k] = i / cycle
    return phases


def scale_quat(d, amp):
    """Slerp with extrapolation, so amp > 1 amplifies a swing."""
    if d.angle < 1e-8:
        return Quaternion()
    return Quaternion(d.axis, d.angle * amp)


def mean_quat(qs):
    ref = qs[0]
    acc = [0.0, 0.0, 0.0, 0.0]
    for q in qs:
        s = 1.0 if q.dot(ref) >= 0 else -1.0
        for i in range(4):
            acc[i] += q[i] * s
    m = Quaternion(acc)
    m.normalize()
    return m


def derive_gait(name, cycle, phase_target, amp_legs, amp_body, bob, lift=(0, 0, 0)):
    walk = get_action("Walk")
    src_cycle = int(round(walk.frame_range[1] - walk.frame_range[0]))
    natural = walk_foot_phase(walk, src_cycle)
    shifts = {k: phase_target[k] - natural[k] for k in LEGS}
    log(name, "natural foot phase", {k: round(v, 3) for k, v in natural.items()},
        "shifts", {k: round(v, 3) for k, v in shifts.items()})

    leg_bone_group = {}
    for k, bones in LEGS.items():
        for b in bones:
            leg_bone_group[b] = k
    body_bones = [pb.name for pb in arm.pose.bones if pb.name not in leg_bone_group]

    # sample Walk on the retimed/phased timeline
    samples = {}
    nkeys = cycle + 1

    def src_frame(u, shift):
        return 1.0 + ((u + shift) % 1.0) * src_cycle

    for f in range(1, nkeys + 1):
        u = (f - 1) / cycle
        cache = {}
        pose = {}
        for g in list(LEGS) + [None]:
            sf = src_frame(u, shifts[g] if g else 0.0)
            key = round(sf, 4)
            if key not in cache:
                cache[key] = sample_bones(walk, sf)
            bones = LEGS[g] if g else body_bones
            for b in bones:
                pose[b] = cache[key][b]
        samples[f] = pose
        if f % 5 == 0:
            log("  ", name, "sampled", f, "/", nkeys)

    # per-bone cycle mean, used to amplify swing without changing posture
    means = {}
    for b in samples[1]:
        means[b] = mean_quat([samples[f][b][0] for f in range(1, cycle + 1)])

    hips = arm.pose.bones["Hips"]
    up_local = (arm.data.bones["Hips"].matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()

    frames = {}
    for f in range(1, nkeys + 1):
        u = (f - 1) / cycle
        pose = {}
        for b, (q, loc) in samples[f].items():
            amp = amp_legs if b in leg_bone_group else amp_body
            d = means[b].inverted() @ q
            q2 = (means[b] @ scale_quat(d, amp)).normalized()
            pose[b] = [q2, loc.copy()]
        bob_add = bob * (0.5 + 0.5 * math.sin(2 * math.pi * 2 * u))
        pose["Hips"][1] = pose["Hips"][1] + up_local * bob_add
        if lift[0]:
            add_rot(pose, "Spine_3", X, math.radians(lift[0]))
        if lift[1]:
            add_rot(pose, "Spine_4", X, math.radians(lift[1]))
        if lift[2]:
            add_rot(pose, "Tail_Base", X, math.radians(lift[2]))
        frames[f] = pose

    act = build_action(name, frames)
    log("built", name, "cycle", cycle, "keys", nkeys, "duration", round(cycle / FPS, 3))
    return act


def sample_bone(action, bone, frame):
    """Evaluate one bone of an action at an arbitrary frame via the pose."""
    return sample_bones(action, frame)[bone]


def sample_bones(action, frame):
    """Evaluate every bone of an action at an arbitrary frame."""
    arm.animation_data.action = action
    sc.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in arm.pose.bones}


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
    # trot: diagonal pairs, 0.67 s
    derive_gait("Trot", 20,
                {"LF": 0.0, "RH": 0.0, "RF": 0.5, "LH": 0.5},
                amp_legs=1.08, amp_body=1.03, bob=0.010, lift=(-5, -4, 8))
    # run: bound/gallop, hind pair then front pair, 0.47 s
    derive_gait("Run", 14,
                {"LH": 0.0, "RH": 0.08, "LF": 0.50, "RF": 0.58},
                amp_legs=1.35, amp_body=1.22, bob=0.028, lift=(-8, -6, 15))


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


def measure_speed(act, name):
    arm.animation_data.action = act
    f0, f1 = [int(round(v)) for v in act.frame_range]
    pts = {b: [] for b in ("Front_Leg_Tip_L", "Front_Leg_Tip_R", "Back_Leg_Tip_L", "Back_Leg_Tip_R")}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for b in pts:
            pts[b].append(arm.pose.bones[b].tail.copy())
    speeds = []
    for b, ps in pts.items():
        for i in range(1, len(ps)):
            if ps[i].z < 0.012 and ps[i - 1].z < 0.012:
                speeds.append((ps[i].y - ps[i - 1].y) * FPS)
    if speeds:
        speeds.sort()
        log("speed", name, round(speeds[len(speeds) // 2], 3), "m/s", "samples", len(speeds))


# ---------------------------------------------------------------- export

def rebuild_nla():
    ad = arm.animation_data
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    names = sorted(a.name for a in bpy.data.actions)
    for name in names:
        act = bpy.data.actions[name]
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
    for n in ("Trot", "Run", "TailWag", "Shake", "Eat", "Lie", "Sleep"):
        act = bpy.data.actions.get(n)
        if act:
            lift = ground_clip(act, cyclic=(n != "Lie"))
            log("ground", n, "max lift", round(lift, 4))
    for n in ("Walk", "Trot", "Run"):
        act = bpy.data.actions.get(n)
        if act:
            measure_speed(act, n)
    close_all_loops()
    rebuild_nla()
    save()
    if STAGE == "all":
        export()


main()
