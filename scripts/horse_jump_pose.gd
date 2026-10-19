extends Node

## Phase-driven jump animation for the horse.
##
## The rigged horse asset has 20 clips and none of them is a jump (the closest
## are Rear and Buck), so the airborne pose is authored here instead of in a
## clip.  While the horse is in the air this node aims the spine, neck, front
## and hind leg chains at jump-shaped directions and blends that over whatever
## the AnimationPlayer is doing.  The aiming is done in skeleton space, so it
## does not depend on the rig's local bone axes.
##
## Directions are expressed as (up, forward) with forward being +Z in the
## skeleton's space (the head sits at +Z from the pelvis).

const POSE_TAKEOFF := {
	"Bip01 Spine_03_21": Vector2(0.98, 0.20),
	"Bip01 Spine1_04_20": Vector2(0.96, 0.28),
	"Bip01 Neck_01_19": Vector2(0.10, 0.995),
	"Bip01 Neck1_05_6": Vector2(0.20, 0.98),
	"Bip01 Head_06_5": Vector2(0.05, 0.999),
	"UpperArm": Vector2(-0.72, 0.69),
	"Forearm": Vector2(-0.92, 0.39),
	"Hand": Vector2(-0.75, -0.66),
	"Finger0": Vector2(-0.70, -0.71),
	"Thigh": Vector2(-0.72, -0.69),
	"Calf": Vector2(-0.55, -0.84),
	"HorseLink": Vector2(-0.95, 0.31),
	"Foot": Vector2(-1.0, 0.10),
	"Tail": Vector2(0.30, -0.95),
}

const POSE_APEX := {
	"Bip01 Spine_03_21": Vector2(0.92, 0.39),
	"Bip01 Spine1_04_20": Vector2(0.88, 0.47),
	"Bip01 Neck_01_19": Vector2(0.55, 0.83),
	"Bip01 Neck1_05_6": Vector2(0.35, 0.94),
	"Bip01 Head_06_5": Vector2(0.20, 0.98),
	"UpperArm": Vector2(-0.35, 0.94),
	"Forearm": Vector2(0.25, 0.97),
	"Hand": Vector2(-0.86, -0.51),
	"Finger0": Vector2(-0.75, -0.66),
	"Thigh": Vector2(-0.55, 0.84),
	"Calf": Vector2(-0.20, -0.98),
	"HorseLink": Vector2(-0.97, 0.24),
	"Foot": Vector2(-1.0, 0.05),
	"Tail": Vector2(0.45, -0.89),
}

const POSE_DESCENT := {
	"Bip01 Spine_03_21": Vector2(0.97, 0.24),
	"Bip01 Spine1_04_20": Vector2(0.95, 0.31),
	"Bip01 Neck_01_19": Vector2(0.68, 0.73),
	"Bip01 Neck1_05_6": Vector2(0.74, 0.67),
	"Bip01 Head_06_5": Vector2(0.60, 0.80),
	"UpperArm": Vector2(-0.85, 0.53),
	"Forearm": Vector2(-0.95, 0.31),
	"Hand": Vector2(-0.98, 0.20),
	"Finger0": Vector2(-0.90, 0.44),
	"Thigh": Vector2(-0.80, -0.60),
	"Calf": Vector2(-0.70, -0.71),
	"HorseLink": Vector2(-0.90, -0.44),
	"Foot": Vector2(-1.0, 0.0),
	"Tail": Vector2(0.20, -0.98),
}

const FRONT_BONES := ["UpperArm", "Forearm", "Hand", "Finger0"]
const HIND_BONES := ["Thigh", "Calf", "HorseLink", "Foot"]

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


## POSE keys are either a full bone name or a limb suffix such as "Thigh"
## which expands to the left and right bones.
func _resolve_bones(key: String) -> Array[int]:
	var result: Array[int] = []
	if key.begins_with("Bip01 "):
		var idx := _skeleton.find_bone(key)
		if idx >= 0:
			result.append(idx)
		return result
	for side in ["L", "R"]:
		for i in range(_skeleton.get_bone_count()):
			var name := _skeleton.get_bone_name(i)
			if name.begins_with("Bip01 " + side + " ") and name.contains(" " + key + "_"):
				result.append(i)
				break
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
