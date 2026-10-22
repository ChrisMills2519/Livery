extends Node

## Phase-driven jump animation for the horse.
##
## The rigged horse asset has no jump clip, so an airborne pose can be
## authored here instead.  This overlay was written for the previous Bip01 rig
## and is disabled while the horse runs on the newer 56-bone skeleton; the
## physical jump still plays the gait pose in the air.
##
## When re-enabling it, remap the bone names below to the active skeleton.
## The aiming is done in skeleton space, so it does not depend on the rig's
## local bone axes.
##
## Directions are expressed as (up, forward) with forward being +Z in the
## skeleton's space (the head sits at +Z from the pelvis).

const POSE_TAKEOFF := {
	"spine_3": Vector2(0.96, 0.28),
	"spine_4": Vector2(0.92, 0.39),
	"spine_5": Vector2(0.85, 0.52),
	"head": Vector2(0.10, 0.99),
	"front_leg_upper": Vector2(-0.45, 0.89),
	"front_leg_lower": Vector2(-0.85, -0.52),
	"back_leg_upper": Vector2(-0.75, -0.66),
	"back_leg_lower": Vector2(-0.60, -0.80),
	"tail_1": Vector2(0.35, -0.93),
}

const POSE_APEX := {
	"spine_3": Vector2(0.70, 0.71),
	"spine_4": Vector2(0.65, 0.76),
	"spine_5": Vector2(0.50, 0.86),
	"head": Vector2(0.30, 0.95),
	"front_leg_upper": Vector2(0.10, 0.99),
	"front_leg_lower": Vector2(-0.95, 0.31),
	"back_leg_upper": Vector2(-0.45, -0.89),
	"back_leg_lower": Vector2(-0.30, -0.95),
	"tail_1": Vector2(0.55, -0.83),
}

const POSE_DESCENT := {
	"spine_3": Vector2(0.50, 0.86),
	"spine_4": Vector2(0.40, 0.91),
	"spine_5": Vector2(0.30, 0.95),
	"head": Vector2(0.55, 0.83),
	"front_leg_upper": Vector2(-0.85, 0.52),
	"front_leg_lower": Vector2(-0.95, 0.31),
	"back_leg_upper": Vector2(-0.80, -0.60),
	"back_leg_lower": Vector2(-0.70, -0.71),
	"tail_1": Vector2(0.20, -0.98),
}

const FRONT_BONES := ["front_leg_upper", "front_leg_lower", "front_leg_ankle", "front_leg_foot"]
const HIND_BONES := ["back_leg_upper", "back_leg_lower", "back_leg_ankle", "back_leg_foot"]

var active := true

var _skeleton: Skeleton3D
var _bone_targets: Array[Dictionary] = []
var _weight := 0.0


func _ready() -> void:
	# Run after the AnimationPlayer has written the gait pose.  A higher
	# process priority means this node is processed later in the idle frame.
	process_priority = 100
	var root: Node = get_parent()
	if root == null:
		return
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("HorseJumpPose: no Skeleton3D found")
		return
	_skeleton = found[0] as Skeleton3D
	_build_bone_targets()
	set_process(false)


func _build_bone_targets() -> void:
	_bone_targets.clear()
	if _skeleton == null:
		return
	for bone_name in POSE_TAKEOFF.keys():
		var indices := _resolve_bones(bone_name)
		for idx in indices:
			_bone_targets.append({
				"index": idx,
				"takeoff": _direction(POSE_TAKEOFF[bone_name]),
				"apex": _direction(POSE_APEX[bone_name]),
				"descent": _direction(POSE_DESCENT[bone_name]),
			})


func _resolve_bones(key: String) -> Array[int]:
	var result: Array[int] = []
	if _skeleton == null:
		return result
	var direct := _skeleton.find_bone(key)
	if direct >= 0:
		result.append(direct)
		return result
	for side in ["_l", "_r"]:
		var idx := _skeleton.find_bone(key + side)
		if idx >= 0:
			result.append(idx)
	return result


func _direction(up_forward: Vector2) -> Vector3:
	# Skeleton space has +Y up and +Z toward the head.
	var dir := Vector3(0.0, up_forward.x, up_forward.y)
	return dir.normalized()


## Called every frame by the horse.  `phase` is 0 at takeoff and 1 at landing.
func apply(phase: float, airborne: bool) -> void:
	if not active or _skeleton == null:
		set_process(false)
		return
	var target_weight := 0.0
	if airborne:
		var fade_in := smoothstep(0.0, 0.10, phase)
		var fade_out := 1.0 - smoothstep(0.78, 0.95, phase)
		target_weight = fade_in * fade_out
	_weight = lerpf(_weight, target_weight, 0.5)
	if _weight <= 0.001:
		set_process(false)
		return
	set_process(true)
	_apply_pose(phase, _weight)


func _apply_pose(phase: float, weight: float) -> void:
	var t := clampf(phase, 0.0, 1.0)
	for entry in _bone_targets:
		var idx: int = entry["index"]
		var target: Vector3
		if t <= 0.45:
			var rise := smoothstep(0.0, 0.45, t)
			target = (entry["takeoff"] as Vector3).lerp(entry["apex"] as Vector3, rise)
		else:
			var fall := smoothstep(0.45, 0.85, t)
			target = (entry["apex"] as Vector3).lerp(entry["descent"] as Vector3, fall)
		if target.length_squared() < 0.0001:
			continue
		var current := _skeleton.get_bone_global_pose(idx)
		var current_dir := current.basis.y.normalized()
		if current_dir.is_zero_approx():
			continue
		var align := Quaternion(current_dir, target.normalized())
		var wanted := Basis(align) * current.basis
		var q := current.basis.get_rotation_quaternion().slerp(
			wanted.get_rotation_quaternion(), weight
		)
		_skeleton.set_bone_global_pose(idx, Transform3D(Basis(q), current.origin))
		# Children need the updated parent transform before they are aimed.
		_skeleton.force_update_all_bone_transforms()
