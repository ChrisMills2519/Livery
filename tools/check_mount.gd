extends SceneTree

## Headless verification for the mounted rider.
##
##   godot --headless --path . --script res://tools/check_mount.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _state := 0
var _state_ms := 0
var _start_ms := 0
var _failures: Array[String] = []
var _turn_yaw := 0.0


func _initialize() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_fail("cannot load main scene")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	# Time-based stages: headless runs far faster than 60 fps, so frame counts
	# would exercise the camera blend for only a few milliseconds.
	var now := Time.get_ticks_msec()
	match _state:
		0:
			if now - _start_ms >= 100:
				_begin()
				if _player == null or _horse == null:
					return false
				_state = 1
				_state_ms = now
		1:
			if now - _state_ms >= 100:
				_mount()
				_state = 2
				_state_ms = now
		2:
			if now - _state_ms >= 500:
				_check_mounted("rest")
				_turn_yaw = _player.rotation.y
				# Headless cannot capture the mouse, so drive the look helper
				# directly and let the horse turn in place toward it.
				_player.call("_look", Vector2(400.0, 0.0))
				_state = 21
				_state_ms = now
		21:
			if now - _state_ms >= 500:
				_check_mouse_turn()
				Input.action_press("move_forward")
				_state = 3
				_state_ms = now
		3:
			if now - _state_ms >= 900:
				_check_mounted("walk")
				Input.action_release("move_forward")
				_player.dismount()
				_state = 4
				_state_ms = now
		4:
			if now - _state_ms >= 600:
				_check_dismount()
				_state = 5
				_finish()
	if now - _start_ms > 10000:
		_fail("timed out before reaching dismount")
		_finish()
	return false


func _begin() -> void:
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_horse = _world.get_node_or_null("Horse") as CharacterBody3D
	if _player == null:
		_fail("Player node missing")
	if _horse == null:
		_fail("Horse node missing")
	if _player == null or _horse == null:
		_finish()
		return
	print("player=", _player.global_position, " horse=", _horse.global_position)
	print("seat=", _horse.get_rider_seat_position())
	# Put the player beside the horse, inside the mount radius.
	_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
	_player.velocity = Vector3.ZERO


func _mount() -> void:
	var prompt := _horse.get_node("MountPrompt") as Label3D
	print("can_mount=", _horse.can_mount(_player), " player=", _player.global_position, " prompt=", prompt.visible)
	if not prompt.visible:
		_fail("mount prompt is not visible when the player is in range")
	_player.try_mount()
	if not _player.mounted:
		_fail("try_mount() did not set mounted")


func _check_mounted(label: String) -> void:
	if not _player.mounted:
		_fail(label + ": player is not mounted")
		return
	var contact := (_player.get_node("SeatContact") as Marker3D).global_position
	var seat: Vector3 = _horse.get_rider_seat_position()
	var seat_err := contact.distance_to(seat)
	var anim_player := _player.get_node("AnimationPlayer") as AnimationPlayer
	var anim: String = anim_player.current_animation
	var ride_active := bool(_player.get_node("RidePose").get("active"))
	var collision: CollisionShape3D = _player.get_node("Collision")
	var prompt := _horse.get_node("MountPrompt") as Label3D
	var model := _player.get_node("Model") as Node3D
	var model_fwd := model.global_transform.basis.z.normalized()
	var horse_fwd := -_horse.global_transform.basis.z.normalized()
	var yaw_err := rad_to_deg(model_fwd.angle_to(horse_fwd))
	var skel := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
	var profile = _player.get("character_profile")
	print("  profile=", profile.display_name if profile != null else "<none>")
	var hip_offset: float = float(_player.get("hips_to_seat")) if _player.get("hips_to_seat") != null else 0.10
	print("%s: seat_err=%.4f anim=%s playing=%s ride_pose=%s collision_disabled=%s yaw_err=%.2f hips_above_seat=%.3f" % [
		label, seat_err, anim, str(anim_player.is_playing()), str(ride_active), str(collision.disabled), yaw_err, hips.y - seat.y
	])
	if seat_err > 0.02:
		_fail("%s: seat contact is %.3f m from the saddle" % [label, seat_err])
	if not ride_active:
		_fail(label + ": riding pose overlay is not active")
	if anim_player.is_playing():
		_fail("%s: locomotion mixer is still playing %s" % [label, anim])
	_check_ride_pose(skel, label)
	if not collision.disabled:
		_fail(label + ": player collision should be disabled")
	if prompt.visible:
		_fail(label + ": mount prompt is still visible while riding")
	if yaw_err > 5.0:
		_fail("%s: rider faces %.2f deg away from the horse" % [label, yaw_err])
	if absf(hips.y - seat.y - hip_offset) > 0.02:
		_fail("%s: hips are %.3f m above the saddle, expected %.3f" % [label, hips.y - seat.y, hip_offset])
	var pivot := _player.get_node("CameraPivot") as Node3D
	var cam := _player.get_node("CameraPivot/Camera3D") as Camera3D
	var want_pivot := Vector3(0.0, 1.0, 0.0)
	var want_camera := Vector3(0.0, 0.0, 4.2)
	if profile != null:
		want_pivot = profile.ride_pivot
		want_camera = profile.ride_camera
	print("  camera pivot=%s camera=%s want=%s/%s" % [pivot.position, cam.position, want_pivot, want_camera])
	if label == "walk":
		if pivot.position.distance_to(want_pivot) > 0.05:
			_fail("%s: camera pivot did not blend to the riding offset" % label)
		if cam.position.distance_to(want_camera) > 0.05:
			_fail("%s: camera did not blend to the riding distance" % label)


func _check_ride_pose(skel: Skeleton3D, label: String) -> void:
	var expected := {
		"LeftUpperLeg": Vector3(0.45, -0.40, 0.80),
		"RightUpperLeg": Vector3(-0.45, -0.40, 0.80),
		"LeftLowerLeg": Vector3(0.02, -0.968, -0.25),
		"RightLowerLeg": Vector3(-0.02, -0.968, -0.25),
		"LeftFoot": Vector3(0.0, 0.17, 0.985),
		"RightFoot": Vector3(0.0, 0.17, 0.985),
		"LeftUpperArm": Vector3(0.12, -0.985, 0.10),
		"RightUpperArm": Vector3(-0.12, -0.985, 0.10),
		"LeftLowerArm": Vector3(-0.18, -0.44, 0.88),
		"RightLowerArm": Vector3(0.18, -0.44, 0.88),
		"LeftHand": Vector3(-0.12, -0.37, 0.92),
		"RightHand": Vector3(0.12, -0.37, 0.92),
	}
	for bone_name in expected.keys():
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			_fail("%s: missing bone %s" % [label, bone_name])
			continue
		var dir := skel.get_bone_global_pose(idx).basis.y.normalized()
		var target: Vector3 = (expected[bone_name] as Vector3).normalized()
		var angle := rad_to_deg(dir.angle_to(target))
		print("  pose %-15s dir=%s angle=%.1f" % [bone_name, dir, angle])
		if angle > 12.0:
			_fail("%s: %s points %.1f deg away from the riding pose" % [label, bone_name, angle])


func _check_mouse_turn() -> void:
	var yaw_delta := absf(wrapf(_player.rotation.y - _turn_yaw, -PI, PI))
	var horse_fwd := -_horse.global_transform.basis.z
	horse_fwd.y = 0.0
	var rider_fwd := -_player.global_transform.basis.z
	rider_fwd.y = 0.0
	var heading_error := 0.0
	if horse_fwd.length_squared() > 0.001 and rider_fwd.length_squared() > 0.001:
		heading_error = rad_to_deg(horse_fwd.normalized().angle_to(rider_fwd.normalized()))
	var speed := Vector2(_horse.velocity.x, _horse.velocity.z).length()
	print("mouse turn: player_yaw=%.2f horse_heading_err=%.1f speed=%.2f" % [
		yaw_delta, heading_error, speed
	])
	if yaw_delta < 0.5:
		_fail("mouse look did not rotate the player (%.2f rad)" % yaw_delta)
	if heading_error > 15.0:
		_fail("stationary horse did not turn toward the mouse (%.1f deg off)" % heading_error)
	if speed > 0.1:
		_fail("horse turned in place but drifted (%.2f m/s)" % speed)


func _check_dismount() -> void:
	if _player == null or _horse == null:
		return
	var collision: CollisionShape3D = _player.get_node("Collision")
	var anim: String = (_player.get_node("AnimationPlayer") as AnimationPlayer).current_animation
	var horizontal := Vector2(
		_player.global_position.x - _horse.global_position.x,
		_player.global_position.z - _horse.global_position.z
	).length()
	print("dismount: anim=%s collision_disabled=%s pos=%s horizontal=%.3f" % [
		anim, str(collision.disabled), _player.global_position, horizontal
	])
	if _player.mounted:
		_fail("dismount: still mounted")
	if collision.disabled:
		_fail("dismount: player collision is still disabled")
	if anim != "humanoid/Idle":
		_fail("dismount: expected humanoid/Idle, got " + anim)
	if horizontal < 0.9:
		_fail("dismount: player is still inside the horse (%.3f m)" % horizontal)
	if absf(_player.global_position.y) > 0.5:
		_fail("dismount: player did not land on the ground (y=%.3f)" % _player.global_position.y)
	var fsm := _horse.get_node_or_null("AnimStateMachine")
	if fsm == null:
		_fail("dismount: horse has no AnimStateMachine")
		return
	var horse_anim: String = fsm.player.current_animation if fsm.player != null else ""
	print("dismount horse: state=%s anim=%s speed=%.2f" % [
		fsm.current_state, horse_anim,
		Vector2(_horse.velocity.x, _horse.velocity.z).length()
	])
	if fsm.current_state != "idle":
		_fail("dismount: horse FSM is %s, expected idle" % fsm.current_state)
	if horse_anim != "Idle":
		_fail("dismount: horse is playing %s, expected Idle" % horse_anim)


func _finish() -> void:
	Input.action_release("move_forward")
	if _failures.is_empty():
		print("MOUNT CHECK: PASS")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("MOUNT CHECK: FAIL")
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)
