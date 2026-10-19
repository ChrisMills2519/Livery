extends SceneTree

## Builds the dedicated riding pose on the player's retargeted rig.
##
## Run with:
##     godot --headless --path . --script res://tools/build_ride_library.gd
##
## The player's GeneralSkeleton is a retargeted humanoid rig whose local rest
## axes differ from the original chris.glb.  Rather than guess at the local
## rotation composition, this tool puts the player scene in the tree, aims the
## bones with Skeleton3D.set_bone_global_pose(), reads back the local pose
## rotations the engine computed, and saves those as assets/animations/ride.res.
##
## NOTE: the saved clip does not reproduce the authored pose when the engine
## plays it back on this retargeted skeleton.  It is kept as an authoring
## reference only; the authoritative runtime pose is the bone overlay in
## scripts/ride_pose.gd.

const PLAYER_SCENE := "res://scenes/player.tscn"
const TARGET := "res://assets/animations/ride.res"
const LOOP_LENGTH := 2.0
const HIP_TILT_DEGREES := 8.0

# Absolute model-space directions (Godot skeleton space: +Y up, +Z forward).
const SPINE_DIR := Vector3(0.0, 0.9995, 0.03)
const CHEST_DIR := Vector3(0.0, 0.9985, 0.05)
const NECK_DIR := Vector3(0.0, 0.9998, -0.02)
const HEAD_DIR := Vector3(0.0, 1.0, 0.0)

var _player: Node
var _skeleton: Skeleton3D
var _rest_global: Array[Transform3D] = []
var _parents: Array[int] = []
var _targets := {}
var _hips_index := -1
var _failed := false
var _frame := 0


func _initialize() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_fail("cannot load player scene")
		quit(1)
		return
	_player = packed.instantiate()
	root.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_skeleton = _find_skeleton(_player)
	if _skeleton == null:
		_fail("player scene has no GeneralSkeleton")
		quit(1)
		return
	var anim := _find_animation_player(_player)
	if anim != null:
		anim.stop()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()

	_rest_global = _rest_globals(_skeleton)
	_parents.resize(_skeleton.get_bone_count())
	for i in range(_skeleton.get_bone_count()):
		_parents[i] = _skeleton.get_bone_parent(i)

	_hips_index = _skeleton.find_bone("Hips")
	if _hips_index < 0:
		_fail("player skeleton has no Hips")
		quit(1)
		return

	_build_targets()
	print("  player scene ready; waiting for skeleton transforms")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var anim := _find_animation_player(_player)
	if anim != null:
		anim.stop()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	_build_animation()
	_player.free()
	quit(0 if not _failed else 1)
	return true


func _build_targets() -> void:
	_targets.clear()
	_targets["Spine"] = SPINE_DIR
	_targets["Chest"] = CHEST_DIR
	_targets["UpperChest"] = CHEST_DIR
	_targets["Neck"] = NECK_DIR
	_targets["Head"] = HEAD_DIR

	for side in ["Left", "Right"]:
		var side_name: String = side
		var up_name := side_name + "UpperLeg"
		var lower_name := side_name + "LowerLeg"
		var foot_name := side_name + "Foot"
		var toes_name := side_name + "Toes"
		var shoulder_name := side_name + "Shoulder"
		var arm_name := side_name + "UpperArm"
		var forearm_name := side_name + "LowerArm"
		var hand_name := side_name + "Hand"
		var out := _side_sign(up_name)
		if out == 0.0:
			_fail("cannot determine side for " + up_name)
			continue
		# Thighs forward and out over the barrel, lower legs down/back.
		_targets[up_name] = Vector3(out * 0.45, -0.40, 0.80)
		_targets[lower_name] = Vector3(out * 0.02, -0.968, -0.25)
		_targets[foot_name] = Vector3(0.0, 0.17, 0.985)
		_targets[toes_name] = Vector3(0.0, 0.20, 0.98)
		# Arms hang down and forward, elbows bent, hands over the withers.
		_targets[shoulder_name] = Vector3(out, 0.0, 0.04)
		_targets[arm_name] = Vector3(out * 0.12, -0.985, 0.10)
		_targets[forearm_name] = Vector3(-out * 0.18, -0.44, 0.88)
		_targets[hand_name] = Vector3(-out * 0.12, -0.37, 0.92)


func _side_sign(bone_name: String) -> float:
	var idx := _skeleton.find_bone(bone_name)
	if idx < 0:
		return 0.0
	var x := _rest_global[idx].origin.x - _rest_global[_hips_index].origin.x
	return signf(x)


func _build_animation() -> void:
	var ride := Animation.new()
	ride.length = LOOP_LENGTH
	ride.loop_mode = Animation.LOOP_LINEAR
	for i in range(_skeleton.get_bone_count()):
		var track := ride.add_track(Animation.TYPE_ROTATION_3D)
		ride.track_set_path(track, NodePath("%GeneralSkeleton:" + _skeleton.get_bone_name(i)))
		ride.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		ride.track_set_interpolation_loop_wrap(track, true)

	var times := [0.0, LOOP_LENGTH * 0.5, LOOP_LENGTH]
	var worst := 0.0
	var worst_name := ""
	for t in times:
		var sway := 0.0 if t == 0.0 or t == LOOP_LENGTH else 1.0
		_apply_pose(sway)
		var dir_error := _check_pose_directions()
		if dir_error[0] > worst:
			worst = dir_error[0]
			worst_name = dir_error[1]
		for i in range(_skeleton.get_bone_count()):
			ride.track_insert_key(i, t, _skeleton.get_bone_pose_rotation(i))

	print("  pose direction check: worst %.3f deg at %s" % [worst, worst_name])
	if worst > 2.0:
		_fail("riding pose is not reaching its target directions")

	var library := AnimationLibrary.new()
	library.add_animation("Ride", ride)
	var err := ResourceSaver.save(library, TARGET)
	if err != OK:
		_fail("cannot save %s (error %d)" % [TARGET, err])
		return
	print("RIDE LIBRARY: PASS")
	print("  output=%s length=%.2f loop=%d tracks=%d bones=%d" % [
		TARGET, ride.length, ride.loop_mode, ride.get_track_count(), _skeleton.get_bone_count()
	])


func _apply_pose(sway: float) -> void:
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	for i in range(_skeleton.get_bone_count()):
		var name := _skeleton.get_bone_name(i)
		var target: Basis
		if i == _hips_index:
			target = Basis(Vector3.RIGHT, deg_to_rad(HIP_TILT_DEGREES)) * _rest_global[i].basis
		elif _targets.has(name):
			var dir: Vector3 = _targets[name]
			if name == "Chest" or name == "UpperChest":
				dir = Vector3(dir.x, dir.y, dir.z + 0.02 * sway)
			elif name == "Neck":
				dir = Vector3(dir.x, dir.y, dir.z - 0.01 * sway)
			target = _aim(_rest_global[i], dir)
		else:
			# Fingers and other unlisted bones stay at their rest pose and
			# follow their parent's global pose.
			continue
		var current := _skeleton.get_bone_global_pose(i)
		_skeleton.set_bone_global_pose(i, Transform3D(target, current.origin))
		_skeleton.force_update_all_bone_transforms()
		if name == "Hips" or name == "LeftUpperLeg":
			print("  set %s target=%s actual=%s" % [name, target.y.normalized(), _skeleton.get_bone_global_pose(i).basis.y.normalized()])
	_skeleton.force_update_all_bone_transforms()
	if _hips_index >= 0:
		print("  final Hips actual=", _skeleton.get_bone_global_pose(_hips_index).basis.y.normalized())


func _check_pose_directions() -> Array:
	var worst := 0.0
	var worst_name := ""
	for i in range(_skeleton.get_bone_count()):
		var name := _skeleton.get_bone_name(i)
		var expected: Vector3
		if i == _hips_index:
			expected = (Basis(Vector3.RIGHT, deg_to_rad(HIP_TILT_DEGREES)) * _rest_global[i].basis).y
		elif _targets.has(name):
			expected = (_targets[name] as Vector3).normalized()
		else:
			continue
		var actual := _skeleton.get_bone_global_pose(i).basis.y.normalized()
		var angle := rad_to_deg(actual.angle_to(expected.normalized()))
		if angle > 2.0:
			print("  DIR ERR %.2f %s expected=%s actual=%s" % [angle, name, expected.normalized(), actual])
		if angle > worst:
			worst = angle
			worst_name = name
	return [worst, worst_name]


func _aim(rest_global: Transform3D, direction: Vector3) -> Basis:
	var rest_dir := rest_global.basis.y.normalized()
	var target_dir := direction.normalized()
	var q := Quaternion(rest_dir, target_dir)
	return Basis(q) * rest_global.basis


func _rest_globals(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for i in range(sk.get_bone_count()):
		var p := sk.get_bone_parent(i)
		var parent := out[p] if p >= 0 else Transform3D.IDENTITY
		out[i] = parent * sk.get_bone_rest(i)
	return out


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	print("  FAIL: " + message)
