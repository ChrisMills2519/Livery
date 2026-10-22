"""Measure what a horse GLB's animation clips actually contain.

Run (plain Python 3, no Blender needed):

    python3 tools/analyze_horse_clips.py --input Models/horse_riggedgame_ready_clips.glb

For every animation it evaluates the skeleton with forward kinematics and,
for each hoof, reports how far it reaches forward, how high it lifts, its
stance cadence, and the ground speed implied by the planted hoof sliding
backwards through the body.  Those numbers are what the runtime state
machine's reference speeds must be calibrated against; guessing them is why
foot sliding is invisible in the editor and obvious in play.

The source take is a single 60 s concatenation, so --scan additionally prints
where the animation is actually at rest (the real clip boundaries) instead of
trusting hand-picked times.
"""

import argparse
import json
import struct
import sys

import numpy as np

COMPONENT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
NUM_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

# Bone name fragments for the four hooves, matched by suffix so the script
# works on both the old Bip01 rig and the newer front_leg_* / back_leg_* rig
# regardless of node order.
FRONT_HOOF = ["Finger0Nub", "front_leg_foot"]
HIND_HOOF = ["Toe0Nub", "back_leg_toe"]


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise RuntimeError("%s is not a binary glTF" % path)
    offset = 12
    gltf = None
    binary = None
    while offset < length:
        chunk_len, chunk_type = struct.unpack("<II", data[offset:offset + 8])
        chunk = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif chunk_type == 0x004E4942:
            binary = chunk
        offset += 8 + chunk_len
    return gltf, binary


def accessor(gltf, binary, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    components = NUM_COMPONENTS[acc["type"]]
    dtype = np.dtype("<" + COMPONENT[acc["componentType"]])
    flat = np.frombuffer(binary, dtype=dtype, count=count * components, offset=offset)
    return flat.reshape(count, components).astype(np.float64)


def quat_to_basis(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


class Skeleton:
    def __init__(self, gltf, binary):
        self.gltf = gltf
        self.binary = binary
        self.nodes = gltf["nodes"]
        self.count = len(self.nodes)
        self.parent = [-1] * self.count
        for i, node in enumerate(self.nodes):
            for child in node.get("children", []):
                self.parent[child] = i
        self.name_to_index = {n.get("name"): i for i, n in enumerate(self.nodes)}
        self.pelvis = self._find_exact("Bip01 Pelvis")
        if self.pelvis is None:
            self.pelvis = self.name_to_index.get("hips")
        self.hooves = {}
        for side in ("L", "R"):
            for kind, frags in (("front", FRONT_HOOF), ("hind", HIND_HOOF)):
                idx = self._find_bone("Bip01 %s " % side, frags)
                if idx is not None:
                    self.hooves["%s_%s" % (kind, side)] = idx
        if self.pelvis is None:
            raise RuntimeError("no pelvis bone found")
        if not self.hooves:
            raise RuntimeError("no hoof bones found")

    def _find_exact(self, prefix):
        for i, node in enumerate(self.nodes):
            name = node.get("name", "")
            if name.startswith(prefix + "_") or name == prefix:
                return i
        return None

    def _find_bone(self, side_prefix, frags):
        for i, node in enumerate(self.nodes):
            name = node.get("name", "")
            if name.startswith(side_prefix) and any(f in name for f in frags):
                return i
        side = "l" if side_prefix.strip().endswith("L") else "r"
        for i, node in enumerate(self.nodes):
            name = node.get("name", "")
            if name.endswith("_" + side) and any(f in name for f in frags):
                return i
        return None

    def channels(self, anim_index):
        anim = self.gltf["animations"][anim_index]
        out = {}
        for channel in anim["channels"]:
            sampler = anim["samplers"][channel["sampler"]]
            times = accessor(self.gltf, self.binary, sampler["input"])[:, 0]
            values = accessor(self.gltf, self.binary, sampler["output"])
            out[(channel["target"]["node"], channel["target"]["path"])] = (times, values)
        return out

    def duration(self, anim_index):
        anim = self.gltf["animations"][anim_index]
        return max(
            self.gltf["accessors"][s["input"]].get("max", [0.0])[0]
            for s in anim["samplers"]
        )

    def _static(self, index):
        node = self.nodes[index]
        t = np.array(node.get("translation", [0, 0, 0]), dtype=float)
        r = np.array(node.get("rotation", [0, 0, 0, 1]), dtype=float)
        s = np.array(node.get("scale", [1, 1, 1]), dtype=float)
        return t, r, s

    def sample(self, anim_index, times):
        channels = self.channels(anim_index)

        def interp(key, t, default):
            if key not in channels:
                return default
            frame_times, values = channels[key]
            if t <= frame_times[0]:
                return values[0]
            if t >= frame_times[-1]:
                return values[-1]
            i = np.searchsorted(frame_times, t) - 1
            t0, t1 = frame_times[i], frame_times[i + 1]
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return values[i] * (1 - f) + values[i + 1] * f

        positions = []
        for t in times:
            local = {}
            for n in range(self.count):
                t0, r0, s0 = self._static(n)
                translation = interp((n, "translation"), t, t0)
                rotation = interp((n, "rotation"), t, r0)
                scale = interp((n, "scale"), t, s0)
                basis = quat_to_basis(rotation / np.linalg.norm(rotation)) * scale[None, :]
                matrix = np.eye(4)
                matrix[:3, :3] = basis
                matrix[:3, 3] = translation
                local[n] = matrix
            world = [None] * self.count

            def resolve(n):
                if world[n] is None:
                    world[n] = local[n] if self.parent[n] < 0 else resolve(self.parent[n]) @ local[n]
                return world[n]

            positions.append({n: resolve(n)[:3, 3].copy() for n in range(self.count)})
        return positions


def body_forward(positions, pelvis, hooves, frame):
    front = np.mean([positions[frame][hooves[k]] for k in hooves if k.startswith("front")], axis=0)
    hind = np.mean([positions[frame][hooves[k]] for k in hooves if k.startswith("hind")], axis=0)
    forward = front - hind
    forward[1] = 0.0
    norm = np.linalg.norm(forward)
    return forward / norm if norm > 1e-6 else np.array([0.0, 0.0, 1.0])


def analyze(skeleton, anim_index):
    name = skeleton.gltf["animations"][anim_index].get("name", "?")
    duration = skeleton.duration(anim_index)
    fps = 60.0
    n = max(2, int(round(duration * fps)))
    times = np.linspace(0.0, duration, n)
    positions = skeleton.sample(anim_index, times)
    pelvis = skeleton.pelvis
    hooves = skeleton.hooves

    forward = body_forward(positions, pelvis, hooves, 0)
    right = np.array([-forward[2], 0.0, forward[0]])

    report = {"name": name, "duration": duration, "hooves": {}}
    speeds = []
    for key, bone in hooves.items():
        fwd = np.array([np.dot(positions[i][bone] - positions[i][pelvis], forward) for i in range(n)])
        lat = np.array([np.dot(positions[i][bone] - positions[i][pelvis], right) for i in range(n)])
        up = np.array([positions[i][bone][1] for i in range(n)])
        ground = up - up.min()
        lift = up.max() - up.min()
        stance = ground < 0.25 * max(lift, 1e-6)
        slopes = np.diff(fwd) / (duration / (n - 1))
        planted_slopes = slopes[stance[:-1] & stance[1:]]
        backward = -np.median(planted_slopes[planted_slopes < 0]) if np.any(planted_slopes < 0) else 0.0
        speeds.append(backward)
        # Cadence: count how often the hoof rises through half its lift.
        above = ground > 0.5 * max(lift, 1e-6)
        rises = int(np.sum(np.diff(above.astype(int)) == 1))
        report["hooves"][key] = {
            "reach_fwd": float(fwd.max() - fwd.min()),
            "lift": float(lift),
            "lateral": float(lat.max() - lat.min()),
            "cadence": rises,
            "stride_period": float(duration / rises) if rises else 0.0,
            "stance_speed": float(backward),
        }
    report["natural_speed"] = float(np.median([s for s in speeds if s > 0.05])) if any(s > 0.05 for s in speeds) else 0.0
    report["seam"] = float(np.mean([
        np.linalg.norm(positions[0][hooves[k]] - positions[-1][hooves[k]]) for k in hooves
    ]))
    return report


def scan_rest(gltf, binary):
    skeleton = Skeleton(gltf, binary)
    anim_index = 0
    duration = skeleton.duration(anim_index)
    fps = 24.0
    n = int(round(duration * fps)) + 1
    times = np.arange(n) / fps
    positions = skeleton.sample(anim_index, times)
    # Motion energy: sum of per-bone displacement across consecutive frames.
    bones = [i for i in range(skeleton.count)]
    energy = np.zeros(n)
    for i in range(1, n):
        for b in bones:
            energy[i] += np.linalg.norm(positions[i][b] - positions[i - 1][b])
    kernel = np.ones(7) / 7
    smoothed = np.convolve(energy, kernel, mode="same")
    threshold = np.percentile(smoothed, 20)
    quiet = smoothed < threshold
    runs = []
    start = None
    for j in range(n):
        if quiet[j] and start is None:
            start = j
        elif not quiet[j] and start is not None:
            if j - start >= 6:
                runs.append((start / fps, (j - 1) / fps))
            start = None
    if start is not None and n - start >= 6:
        runs.append((start / fps, (n - 1) / fps))
    return runs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--clips", default="", help="comma-separated clip names; default all")
    parser.add_argument("--scan", action="store_true", help="report rest boundaries of the source take")
    args = parser.parse_args()

    gltf, binary = read_glb(args.input)
    if args.scan:
        print("REST BOUNDARIES (near-static runs, seconds):")
        for start, end in scan_rest(gltf, binary):
            print("  %6.2f - %6.2f   len %.2f" % (start, end, end - start))
        return

    skeleton = Skeleton(gltf, binary)
    wanted = set(args.clips.split(",")) if args.clips else None
    print("%-16s %6s  %-8s  %8s %8s  %6s  %8s" % (
        "clip", "dur", "natural", "reach", "lift", "seam", "cadence"))
    for i, anim in enumerate(gltf["animations"]):
        name = anim.get("name", "?")
        if wanted is not None and name not in wanted:
            continue
        r = analyze(skeleton, i)
        reach = np.mean([h["reach_fwd"] for h in r["hooves"].values()])
        lift = np.mean([h["lift"] for h in r["hooves"].values()])
        cadence = np.mean([h["cadence"] for h in r["hooves"].values()])
        print("%-16s %5.2fs  %6.2f m/s  %7.2fm %7.2fm  %6.3f  %7.1f" % (
            r["name"], r["duration"], r["natural_speed"], reach, lift, r["seam"], cadence))
        for key, h in sorted(r["hooves"].items()):
            print("      %-8s reach %.2f lift %.2f lat %.2f cadence %d period %.2fs stance %.2f m/s" % (
                key, h["reach_fwd"], h["lift"], h["lateral"], h["cadence"],
                h["stride_period"], h["stance_speed"]))


if __name__ == "__main__":
    main()
