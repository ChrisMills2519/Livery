extends SceneTree

## Headless fit check for the saddle, bridle and reins.
##
##   godot --headless --path . --script res://tools/check_tack.gd

const MAIN := "res://scenes/main.tscn"

var _frame := 0
var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _failures: Array[String] = []


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		_player = _world.get_node("Player") as CharacterBody3D
		_horse = _world.get_node("Horse") as CharacterBody3D
		_player.global_position = _horse.global_position + Vector3(0.0, 0.05, -1.2)
		_player.velocity = Vector3.ZERO
		return false
	if _player == null:
		return false
	if _frame >= 8 and not _player.mounted and _player.is_on_floor():
		print("premount floor=%s horse_air=%s can=%s p=%s h=%s seat=%s" % [
			str(_player.is_on_floor()), str(_horse.airborne),
			str(_horse.can_mount(_player)), _player.global_position,
			_horse.global_position, _horse.get_rider_seat_position(),
		])
		_player.try_mount()
		print("after mount mounted=", _player.mounted)
		return false
	if not _player.mounted:
		if _frame > 90:
			_fail("player did not mount")
			_finish()
			return true
		return false
	if _frame < 36:
		return false
	_run_checks()
	return true


func _run_checks() -> void:
	if not _player.mounted:
		_fail("player did not mount")
		_finish()
		return
	var seat: Vector3 = _horse.get_rider_seat_position()
	var skeleton: Skeleton3D = _horse.find_children("*", "Skeleton3D", true, false)[0]
	var seat_bone := skeleton.find_bone("Bip01 Spine1_04_20")
	var seat_bone_global := skeleton.global_transform * skeleton.get_bone_global_pose(seat_bone)
	print("seat=%s spine=%s" % [seat, seat_bone_global.origin])

	var saddle := _horse.get_node("Tack/Saddle") as Node3D
	var bridle := _horse.get_node("Tack/Bridle") as Node3D
	if saddle == null or bridle == null:
		_fail("Tack/Saddle or Tack/Bridle missing")
		_finish()
		return

	var profile = _player.get("character_profile")
	if profile != null and saddle.get("_lift") != null:
		var expected_lift: float = profile.stirrup_lift
		var actual_lift: float = float(saddle.get("_lift"))
		print("stirrup lift expected=%.3f actual=%.3f" % [expected_lift, actual_lift])
		if absf(actual_lift - expected_lift) > 0.001:
			_fail("stirrup lift is %.3f, expected %.3f from the profile" % [actual_lift, expected_lift])

	var seat_mesh := saddle.get_node("Saddle_Seat") as MeshInstance3D
	var seat_local := saddle.global_transform.affine_inverse() * seat
	var seat_bounds := seat_mesh.get_aabb()
	print("seat local=%s aabb=%s" % [seat_local, seat_bounds])
	if not seat_bounds.has_point(seat_local):
		_fail("RiderSeat is outside the saddle seat")

	var girth := saddle.get_node("Saddle_Girth") as MeshInstance3D
	var girth_aabb := girth.global_transform * girth.get_aabb()
	print("girth world aabb pos=%s size=%s" % [girth_aabb.position, girth_aabb.size])
	if girth_aabb.size.y < 0.3:
		_fail("girth does not wrap the barrel (height %.2f)" % girth_aabb.size.y)

	var player_skel: Skeleton3D = _player.find_children("*", "Skeleton3D", true, false)[0]
	var horse_inv := _horse.global_transform.affine_inverse()
	for side in ["L", "R"]:
		var anchor := bridle.find_child("BitAnchor_" + side, true, false) as Node3D
		if anchor == null:
			_fail("BitAnchor_%s missing" % side)
			continue
		var bit := anchor.global_position
		var head_idx := skeleton.find_bone("Bip01 Head_06_5")
		var head_now := skeleton.global_transform * skeleton.get_bone_global_pose(head_idx)
		print("bit_%s=%s head_dist=%.3f" % [side, bit, bit.distance_to(head_now.origin)])
		if bit.distance_to(head_now.origin) > 0.65:
			_fail("bit %s is %.2f m from the head bone" % [side, bit.distance_to(head_now.origin)])
		var foot_name := ("Left" if side == "L" else "Right") + "Foot"
		var foot_idx := player_skel.find_bone(foot_name)
		var foot := player_skel.global_transform * player_skel.get_bone_global_pose(foot_idx)
		var tread := saddle.get_node("Saddle_Tread_" + side) as MeshInstance3D
		var foot_local := horse_inv * foot.origin
		var tread_local := horse_inv * tread.global_position
		print("foot_%s local=%s  tread_local=%s" % [side, foot_local, tread_local])
		var dxz := Vector2(foot_local.x - tread_local.x, foot_local.z - tread_local.z).length()
		var dy := foot_local.y - tread_local.y
		print("  stirrup dxz=%.3f dy=%.3f" % [dxz, dy])
		if dxz > 0.14:
			_fail("stirrup %s is %.2f m from the boot" % [side, dxz])
		if absf(dy) > 0.14:
			_fail("stirrup %s is %.2f m below/above the boot" % [side, dy])
		# A raised iron must stay attached to its shortened leather.  The
		# leather's lower end should still meet the iron ring.
		var leather := saddle.get_node_or_null("Saddle_StirrupLeather_" + side) as MeshInstance3D
		var iron := saddle.get_node_or_null("Saddle_Iron_" + side) as Node3D
		if leather != null and iron != null and leather.mesh != null:
			var box := leather.mesh.get_aabb()
			var end_low := leather.global_transform * Vector3(0.0, box.position.y, 0.0)
			var end_high := leather.global_transform * Vector3(0.0, box.end.y, 0.0)
			var lower := end_low if end_low.distance_to(tread.global_position) < end_high.distance_to(tread.global_position) else end_high
			var gap := lower.distance_to(iron.global_position)
			var upper := end_high if lower == end_low else end_low
			var buckle := saddle.get_node_or_null("Saddle_StirrupBuckle_" + side) as Node3D
			var top_gap := upper.distance_to(buckle.global_position) if buckle != null else 0.0
			print("  leather->iron gap=%.3f top gap=%.3f" % [gap, top_gap])
			if gap > 0.14:
				_fail("stirrup leather %s is %.2f m from its iron" % [side, gap])
			if buckle != null and top_gap > 0.14:
				_fail("stirrup leather %s is %.2f m from its buckle" % [side, top_gap])

		var hand_name := "Left" if side == "L" else "Right"
		var hand: Vector3 = _player.get_hand_anchor(hand_name)
		var rein_len: float = hand.distance_to(bit)
		print("hand_%s=%s rein=%.3f" % [side, hand, rein_len])
		if rein_len < 0.25 or rein_len > 1.4:
			_fail("rein %s length %.2f is implausible" % [side, rein_len])

	# The reins must be visible and have geometry while mounted.
	var reins := _player.get_node("Reins") as Node3D
	var mesh := reins.get_node("ReinMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		_fail("rein mesh missing")
	else:
		print("rein surfaces=%d visible=%s" % [
			mesh.mesh.get_surface_count(),
			str(mesh.visible),
		])
		if not mesh.visible:
			_fail("reins are hidden while mounted")
		if mesh.mesh.get_surface_count() == 0:
			_fail("reins produced no geometry")

	_finish()


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACK CHECK: PASS")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("TACK CHECK: FAIL")
		quit(1)
