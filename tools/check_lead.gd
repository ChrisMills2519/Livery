extends SceneTree

## Headless check for leading the horse on foot.
##
##   godot --headless --path . --script res://tools/check_lead.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _failures: Array[String] = []
var _start := 0
var _state := 0
var _state_ms := 0
var _rest_pos := Vector3.ZERO
var _dragging := false
var _drag_dir := Vector3.ZERO
var _drag_speed := 0.0
var _turn_min_align := 1.0
var _turn_start := Vector3.ZERO


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if _start == 0:
		_start = now
	if _dragging and _player != null:
		_player.global_position += _drag_dir * _drag_speed * delta
	if _horse != null:
		var planar := Vector2(_horse.velocity.x, _horse.velocity.z)
		if planar.length() > 0.2:
			var forward := -_horse.global_transform.basis.z
			forward.y = 0.0
			_turn_min_align = minf(
				_turn_min_align,
				forward.normalized().dot(Vector3(planar.x, 0.0, planar.y).normalized())
			)
	match _state:
		0:
			if now - _start >= 300:
				_begin()
				_next(1, now)
		1:
			if now - _state_ms >= 200:
				_check(_horse.can_lead(_player), "horse can be led from just outside saddle range")
				_check(not _horse.can_mount(_player), "mount prompt is out of range at that distance")
				_send_key(KEY_F)
				_check(_player.leading, "F takes the lead")
				_check(_horse.get("leader") == _player, "horse knows its handler")
				_next(2, now)
		2:
			if now - _state_ms >= 200:
				_check(_prompt_text().contains("RELEASE"), "prompt offers RELEASE (got '%s')" % _prompt_text())
				Input.action_press("move_forward")
				_next(3, now)
		3:
			if now - _state_ms >= 2500:
				Input.action_release("move_forward")
				_next(4, now)
		4:
			if now - _state_ms >= 1500:
				var target: Vector3 = _player.global_transform * _horse.lead_offset
				var gap := Vector2(
					_horse.global_position.x - target.x,
					_horse.global_position.z - target.z
				).length()
				var speed := Vector2(_horse.velocity.x, _horse.velocity.z).length()
				print("lead settle: gap=%.2f speed=%.2f horse_z=%.2f" % [
					gap, speed, _horse.global_position.z
				])
				_check(gap < 0.6, "horse settles at the handler's shoulder (gap %.2f m)" % gap)
				_check(_horse.global_position.z < -1.0, "horse followed the handler")
				_check(speed < 0.4, "led horse comes to a stop when the handler stops")
				_check(_rein_visible(), "lead rope is drawn while leading")
				# A handler stepping sideways makes the horse turn on the rope, and
				# it has to walk the way it is facing through that turn instead of
				# sliding sideways across the ground.
				_turn_min_align = 1.0
				_turn_start = _horse.global_position
				_dragging = true
				_drag_dir = Vector3(1.0, 0.0, 0.0)
				_drag_speed = 1.6
				_next(8, now)
		8:
			if now - _state_ms >= 1200:
				_dragging = false
				var moved := _horse.global_position.distance_to(_turn_start)
				print("lead turn: dot=%.2f moved=%.2f m" % [_turn_min_align, moved])
				_check(moved > 0.3, "the led horse covers ground through the turn (%.2f m)" % moved)
				_check(
					_turn_min_align > 0.9,
					"the led horse walks the way it faces through a turn (dot %.2f)"
					% _turn_min_align
				)
				_next(9, now)
		9:
			if now - _state_ms >= 900:
				_send_key(KEY_F)
				_check(not _player.leading, "F releases the lead")
				_check(_horse.get("leader") == null, "horse is free after release")
				_next(5, now)
		5:
			if now - _state_ms >= 300:
				_rest_pos = _horse.global_position
				_player.global_position = _horse.global_position + Vector3(0.0, 0.05, 6.0)
				_player.velocity = Vector3.ZERO
				_next(6, now)
		6:
			if now - _state_ms >= 800:
				_check(_horse.global_position.distance_to(_rest_pos) < 0.10, "released horse stays put")
				_check(not _rein_visible(), "lead rope hides when the lead is dropped")
				_player.global_position = _horse.global_position + Vector3(0.0, 0.05, -1.2)
				_player.velocity = Vector3.ZERO
				_next(7, now)
		7:
			if now - _state_ms >= 400:
				_check(_player.is_on_floor(), "player is grounded next to the horse")
				_send_key(KEY_F)
				_check(_player.leading, "lead can be taken again before mounting")
				_send_key(KEY_E)
				_check(_player.mounted, "E mounts straight from the lead")
				_check(not _player.leading, "mounting drops the lead")
				_check(_horse.get("leader") == null, "horse is not led once mounted")
				_send_key(KEY_F)
				_check(_player.mounted, "F does nothing in the saddle")
				_finish()
				return true
	if now - _start > 15000:
		_fail("timed out in state %d" % _state)
		_finish()
		return true
	return false


func _begin() -> void:
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D
	if _player == null or _horse == null:
		_fail("missing scene nodes")
		_finish()
		return
	_horse.global_position = Vector3.ZERO
	_horse.rotation.y = 0.0
	_horse.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 0.05, 2.4)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO


func _next(state: int, now: int) -> void:
	_state = state
	_state_ms = now


func _prompt_text() -> String:
	var prompt := _horse.get_node("MountPrompt") as Label3D
	return prompt.text if prompt != null else ""


func _rein_visible() -> bool:
	var reins := _player.get_node("Reins") as Node3D
	var mesh := reins.get_node("ReinMesh") as MeshInstance3D
	return mesh.visible and mesh.mesh != null and mesh.mesh.get_surface_count() > 0


func _send_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	_player.call("_unhandled_input", event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("LEAD CHECK: PASS")
		quit(0)
	else:
		print("LEAD CHECK: FAIL")
		quit(1)
