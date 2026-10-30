extends SceneTree

## End-to-end fence test: the horse must be stopped by the rails at a gallop,
## then clear the same fence when it jumps at the right moment.
##
##   godot --headless --path . --script res://tools/check_fence_jump.gd

const MAIN := "res://scenes/main.tscn"
var _fence_x := -26.9305
var _fence_z := -12.0

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _course: Node
var _failures: Array[String] = []

var _state := 0
var _state_ms := 0
var _start_ms := 0
var _jump_sent := false
var _max_z := -999.0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	var elapsed := now - _state_ms
	match _state:
		0:
			if now - _start_ms >= 120:
				_begin()
				_next(1, now)
		1:
			if elapsed >= 80:
				_mount()
				_next(2, now)
		2:
			if elapsed >= 120:
				_course.start_round()
				_setup_approach()
				_next(3, now)
		3:
			# Ride straight at the fence without jumping.  The rail must be
			# knocked down but must not stop the horse dead: it carries on.
			_max_z = maxf(_max_z, _horse.global_position.z)
			if elapsed >= 1800:
				print("ground approach: z=%.2f max_z=%.2f faults=%d" % [
					_horse.global_position.z, _max_z, _course.faults
				])
				if _max_z < _fence_z - 0.7:
					_fail("horse did not reach the fence on the ground (z=%.2f)" % _max_z)
				if _max_z < _fence_z + 0.5:
					_fail("knocked rail stopped the horse dead (z=%.2f)" % _max_z)
				if _course.faults < 4:
					_fail("hitting the fence did not record a knockdown (faults=%d)" % _course.faults)
				Input.action_release("move_forward")
				Input.action_release("gallop")
				_next(4, now)
		4:
			if elapsed >= 400:
				_setup_approach()
				_next(5, now)
		5:
			_max_z = maxf(_max_z, _horse.global_position.z)
			# Jump about two metres before the rails.
			if not _jump_sent and _horse.global_position.z > _fence_z - 2.2:
				Input.action_press("jump")
				_jump_sent = true
				print("jump at z=%.2f speed=%.2f" % [
					_horse.global_position.z,
					Vector2(_horse.velocity.x, _horse.velocity.z).length()
				])
			if elapsed >= 1800:
				Input.action_release("jump")
				Input.action_release("move_forward")
				Input.action_release("gallop")
				print("jumped approach: z=%.2f max_z=%.2f clears=%d" % [
					_horse.global_position.z, _max_z, _course.cleared_count
				])
				if _max_z < _fence_z + 0.7:
					_fail("jumping horse did not cross the fence (z=%.2f)" % _max_z)
				if _course.cleared_count < 1:
					_fail("fence was crossed in the air but not counted as cleared")
				_finish()
	if now - _start_ms > 15000:
		_fail("timed out")
		_finish()
	return false


func _next(state: int, now: int) -> void:
	_state = state
	_state_ms = now


func _begin() -> void:
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D
	_course = _world.get_node("RidingCourse")
	if _player == null or _horse == null or _course == null:
		_fail("missing scene nodes")
		_finish()
		return


func _mount() -> void:
	_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
	_player.velocity = Vector3.ZERO
	_player.try_mount()
	if not _player.mounted:
		_fail("could not mount the horse")


func _setup_approach() -> void:
	# Face +Z, the direction the fence must be jumped from.
	_player.rotation.y = PI
	var jump: Dictionary = _course.get("_jumps")[0]
	var aabb: AABB = jump["aabb"]
	var centre := aabb.get_center()
	_fence_x = centre.x
	_fence_z = centre.z
	var jump_node: Node3D = jump["node"]
	if jump_node.has_method("reset_jump"):
		jump_node.reset_jump()
	_horse.global_position = Vector3(_fence_x, 0.05, _fence_z - 5.0)
	_horse.rotation.y = PI
	_horse.velocity = Vector3(0.0, 0.0, 6.5)
	_horse.set("_ride_speed", 6.5)
	_horse.airborne = false
	_jump_sent = false
	_max_z = -999.0
	Input.action_press("move_forward")
	Input.action_press("gallop")


func _finish() -> void:
	Input.action_release("move_forward")
	Input.action_release("gallop")
	Input.action_release("jump")
	if _failures.is_empty():
		print("FENCE JUMP CHECK: PASS")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("FENCE JUMP CHECK: FAIL")
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)
