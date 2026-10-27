extends SceneTree

## Headless verification for Models/chihuahua.glb
##   godot --headless --path . --script tools/check_chihuahua_animations.gd

const EXPECTED := {
	"Bark": 2.800, "Bite": 0.867, "Death": 1.167, "Eat": 1.500,
	"Fall": 0.500, "Fetch": 1.000, "Howl": 2.333, "Idle": 1.333,
	"Idle_Alert": 1.600, "Jump": 2.200, "Lie": 1.733, "Rest_Pose": 0.333,
	"Run": 0.200, "Shake": 1.067, "Sit": 1.333, "Sleep": 3.000,
	"TailWag": 0.733, "Trot": 0.233, "Walk": 0.333,
}

## Ground speed (m/s) each gait plants its paws at, measured by
## tools/build_chihuahua.py.  dog_animator.gd plays the clips against these.
const GAIT_REFERENCE := {"Walk": 0.73, "Trot": 1.86, "Run": 3.26}
## How far above its own lowest point a paw still counts as planted.  The
## skeleton's height origin is not the ground, so this is measured per clip.
const CONTACT_MARGIN := 0.012
const GAIT_TIPS := [
	"Front_Leg_Tip_L", "Front_Leg_Tip_R", "Back_Leg_Tip_L", "Back_Leg_Tip_R"
]
const LOOPING := ["Idle", "Idle_Alert", "Walk", "Trot", "Run", "TailWag",
	"Sit", "Eat", "Sleep", "Bark", "Howl", "Fetch", "Jump", "Bite", "Shake"]

var _frames := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://Models/chihuahua.glb")
	if packed == null:
		push_error("Models/chihuahua.glb failed to load")
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	var failures: Array[String] = []
	var player: AnimationPlayer = _first(root, "AnimationPlayer") as AnimationPlayer
	var skel: Skeleton3D = _first(root, "Skeleton3D") as Skeleton3D
	var meshes := root.find_children("*", "MeshInstance3D", true, false)

	if player == null:
		failures.append("AnimationPlayer missing")
	else:
		var names := player.get_animation_list()
		print("ANIMATIONS (%d): %s" % [names.size(), names])
		for n in EXPECTED.keys():
			if not player.has_animation(n):
				failures.append("missing " + n)
				continue
			var anim := player.get_animation(n)
			var d := absf(anim.length - EXPECTED[n])
			var loop_ok := anim.loop_mode != Animation.LOOP_NONE
			print("%-12s len=%.3f exp=%.3f loop=%d" % [n, anim.length, EXPECTED[n], anim.loop_mode])
			if d > 0.04:
				failures.append("%s length %.3f != %.3f" % [n, anim.length, EXPECTED[n]])
			if n in LOOPING:
				var err := _wrap_error(anim)
				print("             wrap error %.5f" % err)
				if err > 2e-3:
					failures.append("%s does not loop (wrap %.4f)" % [n, err])

	if skel == null:
		failures.append("Skeleton3D missing")
	else:
		print("SKELETON bones=%d" % skel.get_bone_count())
		if skel.get_bone_count() != 49:
			failures.append("expected 49 bones, got %d" % skel.get_bone_count())
		var hips := skel.find_bone("Hips")
		print("Hips bone=%d %s" % [hips, skel.get_bone_name(hips) if hips >= 0 else "MISSING"])

	if meshes.is_empty():
		failures.append("no MeshInstance3D")
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var verts := 0
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.skin == null:
			failures.append(mi.name + " has no skin")
			continue
		for s in range(mi.mesh.get_surface_count()):
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			verts += v.size()
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var uv2 = a[Mesh.ARRAY_TEX_UV2]
			if uv2.is_empty():
				failures.append(mi.name + " surface %d lost UV2" % s)
			if not bones.is_empty():
				var stride: int = bones.size() / maxi(v.size(), 1)
				if stride > 4:
					failures.append("%s surface %d has %d influences" % [mi.name, s, stride])
				for i in range(v.size()):
					var wsum := 0.0
					for k in range(stride):
						wsum += weights[i * stride + k]
					if wsum < 0.99:
						failures.append("%s surface %d vertex %d weight %.3f" % [mi.name, s, i, wsum])
						break
			for p in v:
				var wp: Vector3 = mi.global_transform * p
				lo = lo.min(wp)
				hi = hi.max(wp)
	print("MESHES=%d VERTS=%d AABB size=(%.3f, %.3f, %.3f) min_y=%.3f" % [
		meshes.size(), verts, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.y])
	if absf((hi.y - lo.y) - 0.225) > 0.02:
		failures.append("height %.3f != 0.225" % (hi.y - lo.y))

	if player != null and skel != null:
		_check_gaits(player, skel, failures)

	if failures.is_empty():
		print("CHIHUAHUA ANIMATION CHECK: PASS")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		print("CHIHUAHUA ANIMATION CHECK: FAIL (%d)" % failures.size())
		quit(1)
	return true


## A gait is only natural if the planted paws stay planted: measure how fast
## the paws travel backwards while they are on the ground and compare that with
## the reference speed the runtime drives the dog at.
func _check_gaits(player: AnimationPlayer, skel: Skeleton3D, failures: Array[String]) -> void:
	var resume := player.current_animation
	for clip in GAIT_REFERENCE.keys():
		if not player.has_animation(clip):
			failures.append("missing gait " + clip)
			continue
		var anim := player.get_animation(clip)
		var steps := maxi(24, int(round(anim.length * 120.0)))
		var step_time := anim.length / float(steps)
		var tips := {}
		for tip in GAIT_TIPS:
			if skel.find_bone(tip) >= 0:
				tips[tip] = []
		player.play(clip)
		player.speed_scale = 1.0
		for i in range(steps):
			player.seek(step_time * float(i), true)
			skel.force_update_all_bone_transforms()
			for tip in tips.keys():
				var idx := skel.find_bone(tip)
				tips[tip].append(skel.get_bone_global_pose(idx).origin)
		var duty_sum := 0.0
		var legs := 0
		var slips: Array[float] = []
		for tip in tips.keys():
			var pts: Array = tips[tip]
			# Contact is measured against each paw's own lowest point: the
			# skeleton's height origin is not the ground.
			var floor_y := 1e9
			for p in pts:
				floor_y = minf(floor_y, p.y)
			var contact_z := floor_y + CONTACT_MARGIN
			var contact := 0
			for p in pts:
				if p.y < contact_z:
					contact += 1
			duty_sum += float(contact) / float(pts.size())
			legs += 1
			for i in range(1, pts.size()):
				var a: Vector3 = pts[i - 1]
				var b: Vector3 = pts[i]
				# Only the backward half of the contact window is a plant: the
				# swing brushes near the ground too.  The dog faces +Z, so a
				# planted paw travels towards -Z.
				if a.y < contact_z and b.y < contact_z and b.z < a.z:
					slips.append((a.z - b.z) / step_time)
		var duty := duty_sum / maxf(1.0, float(legs))
		slips.sort()
		var implied := slips[slips.size() / 2] if not slips.is_empty() else 0.0
		var reference: float = GAIT_REFERENCE[clip]
		print("%-6s duty %.2f planted %.3f m/s (reference %.3f)" % [clip, duty, implied, reference])
		if duty < 0.2 or duty > 0.9:
			failures.append("%s contact duty %.2f outside 0.2..0.9" % [clip, duty])
		if absf(implied - reference) > reference * 0.2:
			failures.append("%s paws travel %.3f m/s, not %.3f" % [clip, implied, reference])
	if resume != "":
		player.play(resume)


func _wrap_error(anim: Animation) -> float:
	var worst := 0.0
	for t in range(anim.get_track_count()):
		var n := anim.track_get_key_count(t)
		if n < 2:
			continue
		var a = anim.track_get_key_value(t, 0)
		var b = anim.track_get_key_value(t, n - 1)
		var e := 0.0
		if a is Quaternion:
			e = minf((a - b).length(), (a + b).length())
		elif a is Vector3:
			e = (a - b).length()
		worst = maxf(worst, e)
	return worst


func _first(n: Node, type: String) -> Node:
	if n.is_class(type):
		return n
	for c in n.get_children():
		var r := _first(c, type)
		if r != null:
			return r
	return null
