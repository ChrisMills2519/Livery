extends SceneTree

## Headless verification for the footprint trail.
##
##   godot --headless --path . --script res://tools/check_footprints.gd
##
## Covers the trail itself (slots, ring buffer, stamp placement), the contact
## detector, and the two emitters driven through their real in-game path: the
## player mounts, rides the horse at walk and jumps, then walks on foot.  The
## shader is not compiled headless; tools/screenshot_footprints.gd is the render
## pass that proves the material draws.

const MAIN := "res://scenes/main.tscn"
const TRAIL_GROUP := "footprint_trail"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _trail: Node3D
var _failures: Array[String] = []

var _phase := 0
var _phase_ms := 0
var _start_ms := 0

var _ride_path: Array[Vector3] = []
var _walk_path: Array[Vector3] = []
var _ride_prints := 0
var _stand_prints := 0
var _air_prints := 0
var _airborne_seen := false
var _air_clean := true


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
	var now := Time.get_ticks_msec()
	match _phase:
		0:
			if now - _start_ms < 250:
				return false
			_bind()
			if _player == null or _horse == null or _trail == null:
				_finish()
				return true
			_check_trail()
			_check_stamp()
			_check_detector()
			_check_ring()
			_trail.call("clear")
			# Stand the pair in open grass, away from the stable prompts.
			_horse.global_position = Vector3(6.0, 0.0, -10.0)
			_horse.rotation.y = PI
			_horse.velocity = Vector3.ZERO
			_player.global_position = Vector3(7.4, 0.05, -10.0)
			_player.rotation.y = PI
			_player.velocity = Vector3.ZERO
			_phase = 1
			_phase_ms = now
		1:
			if now - _phase_ms < 350:
				return false
			_player.call("try_mount")
			_check(bool(_player.get("mounted")), "player mounts the horse for the ride test")
			_phase = 2
			_phase_ms = now
		2:
			if now - _phase_ms < 250:
				return false
			_ride_prints = int(_trail.call("stamped_count"))
			Input.action_press("move_forward")
			_phase = 3
			_phase_ms = now
		3:
			_ride_path.append(_horse.global_position)
			if now - _phase_ms >= 2000:
				Input.action_release("move_forward")
				Input.action_press("jump")
				_phase = 4
				_phase_ms = now
		4:
			Input.action_release("jump")
			_ride_path.append(_horse.global_position)
			if bool(_horse.get("airborne")):
				_airborne_seen = true
				_air_prints = int(_trail.call("stamped_count"))
				_phase = 5
				_phase_ms = now
			elif now - _phase_ms > 1500:
				_fail("horse never left the ground for the airborne test")
				_phase = 6
				_phase_ms = now
		5:
			_ride_path.append(_horse.global_position)
			if bool(_horse.get("airborne")):
				# Only frames that are still airborne are counted: the landing frame
				# legitimately plants a hoof again.
				if int(_trail.call("stamped_count")) != _air_prints:
					_air_clean = false
			else:
				_check(_air_clean, "no hoof prints are laid while airborne")
				_check(_airborne_seen, "the ride test actually went airborne")
				_phase = 6
				_phase_ms = now
		6:
			if now - _phase_ms < 900:
				return false
			_stand_prints = int(_trail.call("stamped_count"))
			_check(
				_stand_prints > _ride_prints,
				"riding lays hoof prints (%d -> %d)" % [_ride_prints, _stand_prints]
			)
			_check(
				_prints_near_path(0, _ride_path, 1.6),
				"every hoof print lands within 1.6 m of the horse's path"
			)
			var kinds := _kinds_present()
			_check(kinds == [0], "the ridden horse lays hoof prints only (got %s)" % str(kinds))
			_player.call("dismount")
			_horse.call("board")
			_phase = 7
			_phase_ms = now
		7:
			if now - _phase_ms < 400:
				return false
			var boarded := int(_trail.call("stamped_count"))
			_check(boarded == _stand_prints, "a boarded horse lays no prints")
			_horse.call("release_from_stable", _horse.global_transform)
			# Park the horse well away and stop it, so only the walker can lay
			# prints in the next phase.
			_horse.global_position = Vector3(-16.0, 0.0, -28.0)
			_horse.velocity = Vector3.ZERO
			_horse.rotation.y = 0.0
			_player.global_position = Vector3(2.0, 0.05, -12.0)
			_player.rotation.y = 0.0
			_player.velocity = Vector3.ZERO
			_phase = 8
			_phase_ms = now
		8:
			if now - _phase_ms < 400:
				return false
			_trail.call("clear")
			Input.action_press("move_forward")
			_phase = 9
			_phase_ms = now
		9:
			_walk_path.append(_player.global_position)
			if now - _phase_ms >= 2500:
				Input.action_release("move_forward")
				_phase = 10
				_phase_ms = now
		10:
			if now - _phase_ms < 250:
				return false
			var boots := int(_trail.call("stamped_count"))
			_check(boots >= 3, "walking lays boot prints (got %d)" % boots)
			_check(_prints_near_path(1, _walk_path, 0.9), "every boot print lands within 0.9 m of the player's path")
			_check(_only_kind(1), "the walking character lays boot prints only")
			_finish()
			return true
	return false


func _bind() -> void:
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_horse = _world.get_node_or_null("Horse") as CharacterBody3D
	_trail = _world.get_node_or_null("Footprints") as Node3D


func _check_trail() -> void:
	_check(_trail != null, "main scene owns a Footprints trail")
	if _trail == null:
		return
	_check(_trail.is_in_group(TRAIL_GROUP), "trail registers in the %s group" % TRAIL_GROUP)
	_check(
		get_first_node_in_group(TRAIL_GROUP) == _trail,
		"emitters can find the trail through its group"
	)
	_check(int(_trail.call("slot_count")) > 0, "trail has a print pool")
	var material := _trail.call("get_material") as ShaderMaterial
	_check(material != null, "trail uses a ShaderMaterial")
	if material != null:
		_check(material.shader != null, "footprint shader is loaded")
		_check(material.get_shader_parameter("lifetime") != null, "shader exposes the fade lifetime")
		_check(material.get_shader_parameter("now") != null, "shader exposes the trail clock")
		_check(
			is_equal_approx(float(material.get_shader_parameter("lifetime")), float(_trail.get("print_lifetime"))),
			"the material lifetime matches the trail export"
		)
	# The trail must be able to draw inside the yard, not only at the origin.
	_check(_trail.get_node_or_null("FootprintMesh") != null, "trail builds its MultiMesh instance")


func _check_stamp() -> void:
	_trail.call("clear")
	_trail.call("stamp", Vector3(3.5, 0.0, -17.25), 1.1, 0, Vector2(0.13, 0.16), 0.8)
	var slot := _trail.call("get_slot", 0) as Dictionary
	_check(not slot.is_empty(), "stamping writes a slot")
	if slot.is_empty():
		return
	var position: Vector3 = slot["position"]
	var scale: Vector3 = slot["scale"]
	_check(absf(position.y - 0.012) < 0.001, "print sits just above the ground (y %.3f)" % position.y)
	_check(absf(position.x - 3.5) < 0.001 and absf(position.z + 17.25) < 0.001, "print lands where it was stamped")
	_check(
		absf(scale.x - 0.13) < 0.01 and absf(scale.z - 0.16) < 0.01,
		"print keeps its size (%.2f x %.2f)" % [scale.x, scale.z]
	)
	_check(int(slot["kind"]) == 0, "print records its kind")
	_check(absf(float(slot["strength"]) - 0.8) < 0.01, "print records its strength")
	_check(int(_trail.call("next_slot")) == 1, "the ring buffer advances")


func _check_detector() -> void:
	var script := load("res://scripts/footprint_emitter.gd")
	_check(script != null, "footprint emitter script loads")
	if script == null:
		return
	_check(bool(script.is_contact(0.30, 0.20, 0.25, 0.20, 0.05)), "a downward-then-up bone counts as a contact")
	_check(not bool(script.is_contact(0.20, 0.25, 0.30, 0.20, 0.05)), "a rising bone is not a contact")
	_check(not bool(script.is_contact(0.60, 0.45, 0.50, 0.20, 0.05)), "a high swinging bone is not a contact")
	_check(not bool(script.is_contact(INF, 0.20, 0.25, 0.20, 0.05)), "the first sample never stamps")


func _check_ring() -> void:
	_trail.call("clear")
	var slots := int(_trail.call("slot_count"))
	for i in range(slots + 8):
		_trail.call("stamp", Vector3(float(i % 7), 0.0, -12.0), 0.0, 0, Vector2(0.13, 0.16), 1.0)
	_check(int(_trail.call("stamped_count")) == slots + 8, "every stamp is counted")
	_check(int(_trail.call("next_slot")) == 8, "the ring buffer wraps without overrunning")
	var wrapped := _trail.call("get_slot", 0) as Dictionary
	_check(not wrapped.is_empty(), "wrapped slots stay readable")
	if not wrapped.is_empty():
		var position: Vector3 = wrapped["position"]
		_check(
			absf(position.x - float(slots % 7)) < 0.001,
			"the oldest print was replaced by the newest"
		)


func _prints_near_path(kind: int, path: Array[Vector3], limit: float) -> bool:
	if path.is_empty():
		return false
	var slots := int(_trail.call("slot_count"))
	for i in range(slots):
		var slot := _trail.call("get_slot", i) as Dictionary
		if slot.is_empty():
			continue
		if int(slot["kind"]) != kind:
			continue
		var position: Vector3 = slot["position"]
		var best := INF
		for point in path:
			best = minf(best, Vector2(position.x - point.x, position.z - point.z).length())
		if best > limit:
			_fail("%s print %d is %.2f m from the travelled path" % [_kind_name(kind), i, best])
			return false
	return true


func _kinds_present() -> Array:
	var kinds: Array = []
	var slots := int(_trail.call("slot_count"))
	for i in range(slots):
		var slot := _trail.call("get_slot", i) as Dictionary
		if slot.is_empty():
			continue
		var kind := int(slot["kind"])
		if not kinds.has(kind):
			kinds.append(kind)
	kinds.sort()
	return kinds


func _only_kind(kind: int) -> bool:
	var slots := int(_trail.call("slot_count"))
	for i in range(slots):
		var slot := _trail.call("get_slot", i) as Dictionary
		if slot.is_empty():
			continue
		if int(slot["kind"]) != kind:
			_fail("unexpected %s print in the trail" % _kind_name(int(slot["kind"])))
			return false
	return true


func _kind_name(kind: int) -> String:
	return "hoof" if kind == 0 else "boot"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")
	if _failures.is_empty():
		print("FOOTPRINT CHECK: PASS")
		quit(0)
	else:
		print("FOOTPRINT CHECK: FAIL (%d)" % _failures.size())
		quit(1)
