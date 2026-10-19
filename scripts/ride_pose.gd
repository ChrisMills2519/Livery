extends Node

## Applies the dedicated riding pose directly to the player's retargeted
## skeleton.
##
## The player's GeneralSkeleton is a humanoid retarget of chris.glb; its local
## rest axes differ from the source rig, so an imported Blender clip does not
## reproduce the pose.  This overlay aims each bone at an explicit model-space
## direction with Skeleton3D.set_bone_global_pose(), which the engine converts
## into the correct local pose rotations.  It runs only while mounted.

const HIPS_TILT_DEGREES := 8.0

const SPINE_DIR := Vector3(0.0, 0.9995, 0.03)
const CHEST_DIR := Vector3(0.0, 0.9985, 0.05)
const NECK_DIR := Vector3(0.0, 0.9998, -0.02)
const HEAD_DIR := Vector3(0.0, 1.0, 0.0)

## Two-point position while the horse is in the air: the rider folds forward
## over the horse's neck and gives the hands toward the withers.
const JUMP_HIPS_TILT_DEGREES := 20.0
const JUMP_SPINE_DIR := Vector3(0.0, 0.94, 0.34)
const JUMP_CHEST_DIR := Vector3(0.0, 0.92, 0.39)
const JUMP_NECK_DIR := Vector3(0.0, 0.985, 0.17)
const JUMP_HEAD_DIR := Vector3(0.0, 0.99, 0.14)
const JUMP_TARGETS := {
	"LeftUpperArm": Vector3(0.10, -0.88, 0.46),
	"RightUpperArm": Vector3(-0.10, -0.88, 0.46),
	"LeftLowerArm": Vector3(-0.14, -0.58, 0.80),
	"RightLowerArm": Vector3(0.14, -0.58, 0.80),
	"LeftHand": Vector3(-0.08, -0.52, 0.85),
	"RightHand": Vector3(0.08, -0.52, 0.85),
}

var active := false

var _skeleton: Skeleton3D
var _rest_global: Array[Transform3D] = []
var _targets := {}
var _hips_index := -1
var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("RidePose must be a child of the player")
		return
	rebuild_for_skeleton()


## Re-captures the rest pose and bone targets for the current body.  Called on
## start and again after a character swap, so the overlay follows either GLB.
func rebuild_for_skeleton(skeleton: Skeleton3D = null) -> void:
	if skeleton == null and _player != null:
		var model := _player.get_node_or_null("Model")
		if model != null:
			skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	_skeleton = skeleton
	_rest_global.clear()
	_targets.clear()
	_hips_index = -1
	if _skeleton == null:
		push_warning("RidePose: GeneralSkeleton not found")
		return
	_hips_index = _skeleton.find_bone("Hips")
	if _hips_index < 0:
		push_warning("RidePose: Hips bone not found")
		return
	_rest_global.resize(_skeleton.get_bone_count())
	for i in range(_skeleton.get_bone_count()):
		_rest_global[i] = _skeleton.get_bone_global_rest(i)
	_build_targets()


func activate() -> void:
	if _skeleton == null:
		return
	active = true
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	apply(0.0)


func deactivate() -> void:
	active = false


func apply(sway: float, jump := 0.0) -> void:
	if not active or _skeleton == null:
		return
	var fold := clampf(jump, 0.0, 1.0)
	var tilt := lerpf(HIPS_TILT_DEGREES, JUMP_HIPS_TILT_DEGREES, fold)
	for i in range(_skeleton.get_bone_count()):
		var bone_name := _skeleton.get_bone_name(i)
		var target: Basis
		if i == _hips_index:
			target = Basis(Vector3.RIGHT, deg_to_rad(tilt)) * _rest_global[i].basis
		elif _targets.has(bone_name):
			var dir: Vector3 = _targets[bone_name]
			if fold > 0.0:
				var jump_dir := _jump_direction(bone_name)
				if jump_dir != Vector3.ZERO:
					dir = (dir as Vector3).lerp(jump_dir, fold).normalized()
			if bone_name == "Chest" or bone_name == "UpperChest":
				dir = Vector3(dir.x, dir.y, dir.z + 0.02 * sway)
			elif bone_name == "Neck":
				dir = Vector3(dir.x, dir.y, dir.z - 0.01 * sway)
			target = _aim(_rest_global[i], dir)
		else:
			# Fingers and other unlisted bones stay at rest and follow their
			# parent's global pose.
			continue
		var current := _skeleton.get_bone_global_pose(i)
		_skeleton.set_bone_global_pose(i, Transform3D(target, current.origin))
		# The next child's head must use this bone's updated transform.
		_skeleton.force_update_all_bone_transforms()


func _jump_direction(bone_name: String) -> Vector3:
	match bone_name:
		"Spine":
			return JUMP_SPINE_DIR
		"Chest", "UpperChest":
			return JUMP_CHEST_DIR
		"Neck":
			return JUMP_NECK_DIR
		"Head":
			return JUMP_HEAD_DIR
	return JUMP_TARGETS.get(bone_name, Vector3.ZERO)


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
			continue
		_targets[up_name] = Vector3(out * 0.45, -0.40, 0.80)
		_targets[lower_name] = Vector3(out * 0.02, -0.968, -0.25)
		_targets[foot_name] = Vector3(0.0, 0.17, 0.985)
		_targets[toes_name] = Vector3(0.0, 0.20, 0.98)
		_targets[shoulder_name] = Vector3(out, 0.0, 0.04)
		_targets[arm_name] = Vector3(out * 0.12, -0.985, 0.10)
		_targets[forearm_name] = Vector3(-out * 0.18, -0.44, 0.88)
		_targets[hand_name] = Vector3(-out * 0.12, -0.37, 0.92)


func _side_sign(bone_name: String) -> float:
	var idx := _skeleton.find_bone(bone_name)
	if idx < 0 or _hips_index < 0:
		return 0.0
	return signf(_rest_global[idx].origin.x - _rest_global[_hips_index].origin.x)


func _aim(rest_global: Transform3D, direction: Vector3) -> Basis:
	var rest_dir := rest_global.basis.y.normalized()
	var target_dir := direction.normalized()
	var q := Quaternion(rest_dir, target_dir)
	return Basis(q) * rest_global.basis
