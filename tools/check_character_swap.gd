extends SceneTree

## Swaps the player body while mounted: Chris -> Liv -> Chris.
##
##   godot --headless --path . --script res://tools/check_character_swap.gd
##
## This exercises the runtime path used by the debug cycle key, including the
## skeleton rebuild, the ride-pose rest capture and the per-rider stirrup lift.

const MAIN := "res://scenes/main.tscn"
const CHRIS := preload("res://resources/characters/chris.tres")
const LIV := preload("res://resources/characters/liv.tres")

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _state := 0
var _state_ms := 0
var _start_ms := 0
var _failures: Array[String] = []


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
					_fail("Player or Horse missing")
					_finish()
					return true
				_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
				_player.velocity = Vector3.ZERO
				_state = 1
				_state_ms = now
		1:
			if now - _state_ms >= 300:
				_player.try_mount()
				if not _player.mounted:
					_fail("could not mount Chris")
					_finish()
					return true
				_state = 2
				_state_ms = now
		2:
			if now - _state_ms >= 500:
				_check("mounted Chris", CHRIS, 52)
				_player.set_character(LIV)
				_state = 3
				_state_ms = now
		3:
			if now - _state_ms >= 500:
				_check("swapped to Liv", LIV, 65)
				_player.set_character(CHRIS)
				_state = 4
				_state_ms = now
		4:
			if now - _state_ms >= 500:
				_check("swapped back to Chris", CHRIS, 52)
				_player.dismount()
				_state = 5
				_state_ms = now
		5:
			if now - _state_ms >= 350:
				if _player.mounted:
					_fail("still mounted after dismount")
				var collision := _player.get_node("Collision") as CollisionShape3D
				if collision.disabled:
					_fail("collision still disabled after dismount")
				_finish()
				return true
	if now - _start_ms > 15000:
		_fail("timed out")
		_finish()
		return true
	return false


func _check(label: String, profile: PlayerModelProfile, bone_count: int) -> void:
	if not _player.mounted:
		_fail(label + ": not mounted")
		return
	var model := _player.get_node("Model") as Node3D
	var skel := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skel == null:
		_fail(label + ": GeneralSkeleton missing")
		return
	if skel.get_bone_count() != bone_count:
		_fail("%s: %d bones, expected %d" % [label, skel.get_bone_count(), bone_count])
	var contact := (_player.get_node("SeatContact") as Marker3D).global_position
	var seat: Vector3 = _horse.get_rider_seat_position()
	var seat_err := contact.distance_to(seat)
	var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
	var above := hips.y - seat.y
	var ride_active := bool(_player.get_node("RidePose").get("active"))
	var collision := _player.get_node("Collision") as CollisionShape3D
	var saddle := _horse.get_node("Tack/Saddle") as Node3D
	var lift := float(saddle.get("_lift")) if saddle.get("_lift") != null else 0.0
	print("%s: bones=%d seat_err=%.4f hips_above=%.3f ride_pose=%s collision_disabled=%s lift=%.3f" % [
		label, skel.get_bone_count(), seat_err, above, str(ride_active),
		str(collision.disabled), lift
	])
	if seat_err > 0.02:
		_fail("%s: seat error %.3f" % [label, seat_err])
	if absf(above - profile.hips_to_seat) > 0.02:
		_fail("%s: hips %.3f above seat, expected %.3f" % [label, above, profile.hips_to_seat])
	if not ride_active:
		_fail(label + ": ride pose inactive")
	if not collision.disabled:
		_fail(label + ": collision enabled while mounted")
	if absf(lift - profile.stirrup_lift) > 0.001:
		_fail("%s: stirrup lift %.3f, expected %.3f" % [label, lift, profile.stirrup_lift])


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CHARACTER SWAP CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CHARACTER SWAP CHECK: FAIL")
		quit(1)
