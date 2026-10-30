extends SceneTree

## Headless verification for both player bodies.
##
##   godot --headless --path . --script res://tools/check_player_models.gd
##
## Swaps Chris and Liv through the real player scene, checks the shared
## humanoid library actually drives each skeleton, then mounts, rides and
## dismounts each one.  The seat, hips, hands, reins and camera are all
## measured against that character's profile.

const MAIN := "res://scenes/main.tscn"
const PROFILES := [
	preload("res://resources/characters/chris.tres"),
	preload("res://resources/characters/liv.tres"),
]
const REQUIRED_BONES := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _profile_index := 0
var _state := 0
var _state_ms := 0
var _start_ms := 0
var _idle_pose := Transform3D()
var _failures: Array[String] = []
var _metrics := {}


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	match _state:
		0:
			if now - _start_ms >= 150:
				_player = _world.get_node_or_null("Player") as CharacterBody3D
				_horse = _world.get_node_or_null("Horse") as CharacterBody3D
				if _player == null or _horse == null:
					_fail("Player or Horse node missing")
					_finish()
					return true
				_apply_profile()
				_state = 1
				_state_ms = now
		1:
			if now - _state_ms >= 400:
				_check_idle("idle start")
				_idle_pose = _hips_pose(_skeleton())
				_metrics["idle_pose"] = _idle_pose
				_state = 2
				_state_ms = now
		2:
			if now - _state_ms >= 400:
				_check_idle("idle moving")
				var current := _hips_pose(_skeleton())
				var moved := not current.is_equal_approx(_idle_pose)
				print("  idle moved: ", moved)
				if not moved:
					_fail("%s: Idle is not driving the skeleton" % _label())
				_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
				_player.velocity = Vector3.ZERO
				_state = 3
				_state_ms = now
		3:
			if now - _state_ms >= 300:
				if not _player.is_on_floor():
					_fail(_label() + ": player did not settle on the floor before mounting")
				_player.try_mount()
				if not _player.mounted:
					_fail(_label() + ": try_mount() failed")
				_state = 4
				_state_ms = now
		4:
			if now - _state_ms >= 650:
				_check_mounted()
				_player.dismount()
				_state = 5
				_state_ms = now
		5:
			if now - _state_ms >= 350:
				_check_dismounted()
				_profile_index += 1
				if _profile_index >= PROFILES.size():
					_finish()
					return true
				_apply_profile()
				_state = 1
				_state_ms = now
	if now - _start_ms > 30000:
		_fail("timed out")
		_finish()
		return true
	return false


func _apply_profile() -> void:
	var profile: PlayerModelProfile = PROFILES[_profile_index]
	print("\n== %s ==" % profile.display_name)
	_player.set_character(profile)
	_metrics = {}


func _label() -> String:
	return PROFILES[_profile_index].display_name


func _skeleton() -> Skeleton3D:
	var model := _player.get_node_or_null("Model")
	if model == null:
		return null
	return model.find_child("GeneralSkeleton", true, false) as Skeleton3D


func _check_idle(label: String) -> void:
	var skel := _skeleton()
	if skel == null:
		_fail(_label() + " (" + label + "): GeneralSkeleton missing")
		return
	for bone in REQUIRED_BONES:
		if skel.find_bone(bone) < 0:
			_fail("%s: missing humanoid bone %s" % [_label(), bone])
	var anim := _player.get_node("AnimationPlayer") as AnimationPlayer
	if anim.current_animation != "humanoid/Idle" or not anim.is_playing():
		_fail("%s (%s): expected humanoid/Idle, got %s" % [_label(), label, anim.current_animation])
	var model := _player.get_node("Model") as Node3D
	# The shared humanoid library is the only mixer allowed on a body.  An
	# embedded GLB AnimationPlayer is a latent second mixer after a swap.
	var embedded := model.find_children("*", "AnimationPlayer", true, false)
	if not embedded.is_empty():
		_fail("%s: model carries an embedded AnimationPlayer (%s)" % [_label(), embedded[0].name])
	var bounds := _model_bounds(model)
	var height: float = bounds["height"]
	var min_y: float = bounds["min_y"]
	print("  %s: height=%.3f min_y=%.3f bones=%d" % [label, height, min_y, skel.get_bone_count()])
	if height < 1.2 or height > 2.2:
		_fail("%s: model height %.2f is outside 1.2-2.2 m" % [_label(), height])
	if absf(min_y) > 0.06:
		_fail("%s: feet are %+.3f m off the ground" % [_label(), min_y])
	_metrics["height"] = height

	var hips := _bone_world(skel, "Hips")
	var head := _bone_world(skel, "Head")
	var left_foot := _bone_world(skel, "LeftFoot")
	var right_foot := _bone_world(skel, "RightFoot")
	var left_hand := _bone_world(skel, "LeftHand")
	var right_hand := _bone_world(skel, "RightHand")
	var head_above := head.y - hips.y
	var feet_below := hips.y - minf(left_foot.y, right_foot.y)
	var hand_span := absf(left_hand.x - hips.x) + absf(right_hand.x - hips.x)
	print("  %s: head-above-hips=%.3f hips-above-feet=%.3f hand-span=%.3f" % [label, head_above, feet_below, hand_span])
	if head_above < 0.25:
		_fail("%s (%s): head is only %.2f m above the hips" % [_label(), label, head_above])
	if feet_below < 0.35:
		_fail("%s (%s): feet are only %.2f m below the hips" % [_label(), label, feet_below])
	if hand_span < 0.10 or hand_span > 2.0:
		_fail("%s (%s): hand span %.2f is implausible" % [_label(), label, hand_span])
	for bone_name in ["Hips", "Head", "LeftHand", "RightHand"]:
		var t := _bone_transform(skel, bone_name)
		if not _finite(t):
			_fail("%s: %s has a non-finite transform" % [_label(), bone_name])


func _check_mounted() -> void:
	if not _player.mounted:
		_fail(_label() + ": not mounted")
		return
	var skel := _skeleton()
	if skel == null:
		_fail(_label() + ": no skeleton while mounted")
		return
	var seat: Vector3 = _horse.get_rider_seat_position()
	var contact := (_player.get_node("SeatContact") as Marker3D).global_position
	var seat_err := contact.distance_to(seat)
	var hips := _bone_world(skel, "Hips")
	var above := hips.y - seat.y
	var ride := _player.get_node("RidePose")
	var active := bool(ride.get("active"))
	var anim := _player.get_node("AnimationPlayer") as AnimationPlayer
	var collision := _player.get_node("Collision") as CollisionShape3D
	var pivot := _player.get_node("CameraPivot") as Node3D
	var cam := _player.get_node("CameraPivot/Camera3D") as Camera3D
	var profile: PlayerModelProfile = PROFILES[_profile_index]
	var left_hand: Vector3 = _player.get_hand_anchor("Left")
	var right_hand: Vector3 = _player.get_hand_anchor("Right")
	var left_rein := left_hand.distance_to(_horse.get_bit_anchor("L"))
	var right_rein := right_hand.distance_to(_horse.get_bit_anchor("R"))
	print("  seat_err=%.4f hips_above_seat=%.3f ride_pose=%s anim_playing=%s" % [
		seat_err, above, str(active), str(anim.is_playing())
	])
	print("  camera pivot=%s (want %s) camera=%s (want %s)" % [
		pivot.position, profile.ride_pivot, cam.position, profile.ride_camera
	])
	print("  reins L=%.3f R=%.3f" % [left_rein, right_rein])
	if seat_err > 0.02:
		_fail("%s: seat contact is %.3f m from the saddle" % [_label(), seat_err])
	if absf(above - profile.hips_to_seat) > 0.02:
		_fail("%s: hips are %.3f m above the saddle, expected %.3f" % [_label(), above, profile.hips_to_seat])
	if not active:
		_fail(_label() + ": riding pose overlay is not active")
	if anim.is_playing():
		_fail("%s: locomotion mixer is still playing %s" % [_label(), anim.current_animation])
	if not collision.disabled:
		_fail(_label() + ": collision should be disabled while mounted")
	if pivot.position.distance_to(profile.ride_pivot) > 0.05:
		_fail("%s: camera pivot did not blend to %s" % [_label(), profile.ride_pivot])
	# The boom eases out to the walking pose through the collision solver, so it
	# may still be opening here and may legitimately come in for scenery.  What
	# must hold is that it left the on-foot 3 m camera behind and never passed
	# the pose the profile asks for.
	var boom := cam.position.length()
	if boom > profile.ride_camera.length() + 0.05:
		_fail("%s: camera sits %.2f m back, past the %.2f m pose" % [_label(), boom, profile.ride_camera.length()])
	if boom < 4.0:
		_fail("%s: camera boom is %.2f m, still on the on-foot camera" % [_label(), boom])
	if left_rein < 0.25 or left_rein > 1.4:
		_fail("%s: left rein length %.2f is implausible" % [_label(), left_rein])
	if right_rein < 0.25 or right_rein > 1.4:
		_fail("%s: right rein length %.2f is implausible" % [_label(), right_rein])
	_metrics["seat_err"] = seat_err
	_metrics["hips_above_seat"] = above
	_metrics["rein_left"] = left_rein
	_metrics["rein_right"] = right_rein


func _check_dismounted() -> void:
	if _player.mounted:
		_fail(_label() + ": still mounted after dismount")
	var collision := _player.get_node("Collision") as CollisionShape3D
	var anim := _player.get_node("AnimationPlayer") as AnimationPlayer
	var horizontal := Vector2(
		_player.global_position.x - _horse.global_position.x,
		_player.global_position.z - _horse.global_position.z
	).length()
	print("  dismount: anim=%s collision_disabled=%s horizontal=%.3f y=%.3f" % [
		anim.current_animation, str(collision.disabled), horizontal, _player.global_position.y
	])
	if collision.disabled:
		_fail(_label() + ": collision is still disabled")
	if anim.current_animation != "humanoid/Idle":
		_fail("%s: expected humanoid/Idle after dismount, got %s" % [_label(), anim.current_animation])
	if horizontal < 0.9:
		_fail("%s: dismounted inside the horse (%.2f m)" % [_label(), horizontal])
	if absf(_player.global_position.y) > 0.5:
		_fail("%s: dismount did not land on the ground" % _label())
	print("  metrics: ", _metrics)


func _model_bounds(model: Node3D) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var to_model := model.global_transform.affine_inverse()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		for corner in [
			Vector3(box.position.x, box.position.y, box.position.z),
			Vector3(box.end.x, box.position.y, box.position.z),
			Vector3(box.position.x, box.end.y, box.position.z),
			Vector3(box.end.x, box.end.y, box.position.z),
			Vector3(box.position.x, box.position.y, box.end.z),
			Vector3(box.end.x, box.position.y, box.end.z),
			Vector3(box.position.x, box.end.y, box.end.z),
			Vector3(box.end.x, box.end.y, box.end.z),
		]:
			var p: Vector3 = to_model * (mi.global_transform * corner)
			lo = lo.min(p)
			hi = hi.max(p)
	return {"height": hi.y - lo.y, "min_y": lo.y}


func _bone_transform(skel: Skeleton3D, bone_name: String) -> Transform3D:
	var index := skel.find_bone(bone_name)
	if index < 0:
		return Transform3D()
	return skel.get_bone_global_pose(index)


func _bone_world(skel: Skeleton3D, bone_name: String) -> Vector3:
	return skel.global_transform * _bone_transform(skel, bone_name).origin


func _hips_pose(skel: Skeleton3D) -> Transform3D:
	if skel == null:
		return Transform3D()
	return skel.get_bone_pose(skel.find_bone("Hips"))


func _finite(t: Transform3D) -> bool:
	for row in 3:
		for col in 3:
			if not is_finite(t.basis[row][col]):
				return false
	if not is_finite(t.origin.x) or not is_finite(t.origin.y) or not is_finite(t.origin.z):
		return false
	return true


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nPLAYER MODEL CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("\nPLAYER MODEL CHECK: FAIL (%d)" % _failures.size())
		quit(1)
