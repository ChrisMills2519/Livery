extends SceneTree

## Headless verification for the riding loop.
##
##   godot --headless --path . --script res://tools/check_jump_and_loop.gd
##
## Covers the gait state machine, the mounted jump arc and air state, the
## fence-clear detection and the reward loop.

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _course: Node
var _fsm: Node
var _failures: Array[String] = []

var _state := 0
var _state_ms := 0
var _start_ms := 0
var _max_jump_y := 0.0
var _jump_frames := 0
var _saw_air := false
var _double_jump_checked := false
var _money_before := 0
var _game: Node


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
			Input.action_press("move_forward")
			_next(3, now)
		3:
			if elapsed >= 500:
				_check_walk()
				Input.action_press("gallop")
				_next(4, now)
		4:
			if elapsed >= 1700:
				_check_canter()
				Input.action_release("gallop")
				Input.action_release("move_forward")
				_next(5, now)
		5:
			if elapsed >= 600:
				_horse.global_position = Vector3(45, 0.1, 45)
				_horse.velocity = Vector3.ZERO
				_next(6, now)
		6:
			if elapsed >= 500:
				Input.action_press("jump")
				_next(7, now)
		7:
			_max_jump_y = maxf(_max_jump_y, _horse.global_position.y)
			if _horse.is_airborne():
				_saw_air = true
				_jump_frames += 1
				if not _double_jump_checked:
					_double_jump_checked = true
					if _horse.jump():
						_fail("a second jump was accepted while airborne")
			if _saw_air and not _horse.is_airborne():
				Input.action_release("jump")
				_check_jump()
				_next(8, now)
			if elapsed > 3000:
				_fail("horse never left the ground")
				_finish()
		8:
			if elapsed >= 300:
				# Park the mounted horse in the middle of the arena.  Standing
				# there is free riding: nothing may start on its own.
				_horse.global_position = Vector3(-28.0, 0.1, -6.0)
				_horse.velocity = Vector3.ZERO
				_next(81, now)
		81:
			if elapsed >= 400:
				_check_no_auto_start()
				_clear_fence(0)
				_next(82, now)
		82:
			if elapsed >= 250:
				_check_started_by_fence()
				_horse.global_position = Vector3(40.0, 0.1, 40.0)
				_horse.velocity = Vector3.ZERO
				_next(83, now)
		83:
			if elapsed >= 300:
				_check_cancelled()
				# The loose practice jump opens a round as well, but it is not one
				# of the eight fences.
				var practice := _world.get_node("ArenaCourse/ArenaJumps/PracticeJump") as Node3D
				_horse.global_position = practice.global_position + Vector3(0.0, 1.6, 0.0)
				_horse.velocity = Vector3(0.0, 2.0, 0.0)
				_horse.airborne = true
				_next(84, now)
		84:
			if elapsed >= 300:
				_check_practice_started()
				_horse.global_position = Vector3(40.0, 0.1, 40.0)
				_horse.velocity = Vector3.ZERO
				_next(85, now)
		85:
			if elapsed >= 300:
				_check_cancelled()
				_horse.global_position = Vector3(-28.0, 0.1, -6.0)
				_horse.velocity = Vector3.ZERO
				_next(9, now)
		9:
			if elapsed >= 250:
				_clear_fence(0)
				_next(91, now)
		91:
			if elapsed >= 250:
				_check_round_started()
				_check_cleared(1)
				_next(10, now)
		10:
			if elapsed >= 200:
				if _course.cleared_count >= _course.get_jump_count():
					_check_finish()
					_next(13, now)
				else:
					_clear_fence(_course.cleared_count)
					_next(10, now)
		13:
			if elapsed >= 900:
				_check_reset()
				_player.dismount()
				_player.global_position = Vector3(45.0, 0.1, 45.0)
				_player.velocity = Vector3.ZERO
				Input.action_press("jump")
				_next(14, now)
		14:
			if elapsed >= 150:
				var state: String = _player.get("_current_anim_state")
				var anim: String = _player.get_node("AnimationPlayer").current_animation
				print("on-foot jump: state=%s anim=%s" % [state, anim])
				if state != "air":
					_fail("on-foot jump did not enter the air state (got %s)" % state)
				if not anim.ends_with("Jump"):
					_fail("on-foot air state is not using the Jump clip (got %s)" % anim)
				Input.action_release("jump")
				_next(15, now)
		15:
			if elapsed >= 900:
				var state: String = _player.get("_current_anim_state")
				print("on-foot landing: state=%s on_floor=%s" % [state, str(_player.is_on_floor())])
				if state == "air":
					_fail("on-foot landing never left the air state")
				_finish()
	if now - _start_ms > 20000:
		_fail("timed out")
		_finish()
	return false


func _next(state: int, now: int) -> void:
	_state = state
	_state_ms = now


func _begin() -> void:
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_horse = _world.get_node_or_null("Horse") as CharacterBody3D
	_course = _world.get_node_or_null("RidingCourse")
	if _player == null or _horse == null or _course == null:
		_fail("missing Player, Horse or RidingCourse")
		_finish()
		return
	_fsm = _horse.get_node("AnimStateMachine")
	_game = root.get_node_or_null("GameState")
	if _game == null:
		_fail("GameState autoload is missing")
		_finish()
		return
	_money_before = _game.money
	_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
	_player.velocity = Vector3.ZERO


func _mount() -> void:
	_player.try_mount()
	if not _player.mounted:
		_fail("try_mount() failed")
		return
	_player.rotation.y = 0.0
	_horse.global_position = Vector3(40, 0.05, 50)
	_horse.velocity = Vector3.ZERO


func _check_walk() -> void:
	var speed := Vector2(_horse.velocity.x, _horse.velocity.z).length()
	print("walk: speed=%.2f fsm=%s anim=%s" % [speed, _fsm.current_state, _fsm.player.current_animation])
	if speed < 1.5:
		_fail("walk speed did not ramp up (%.2f)" % speed)
	if _fsm.current_state != "walk":
		_fail("expected walk state, got " + _fsm.current_state)


func _check_canter() -> void:
	var speed := Vector2(_horse.velocity.x, _horse.velocity.z).length()
	print("canter: speed=%.2f fsm=%s anim=%s" % [speed, _fsm.current_state, _fsm.player.current_animation])
	if speed < 4.6:
		_fail("holding run did not reach canter speed (%.2f)" % speed)
	if _fsm.current_state != "canter":
		_fail("expected canter state, got " + _fsm.current_state)
	var expected := clampf(speed / _fsm.canter_reference_speed, 0.7, 1.5)
	if absf(_fsm.player.speed_scale - expected) > 0.05:
		_fail("canter playback speed is not matched to ground speed")


func _check_jump() -> void:
	print("jump: max_y=%.2f frames=%d fsm_airborne=%s" % [
		_max_jump_y, _jump_frames, str(_fsm.airborne)
	])
	if _max_jump_y < 1.5:
		_fail("jump apex too low (%.2f m)" % _max_jump_y)
	if _max_jump_y > 2.6:
		_fail("jump apex suspiciously high (%.2f m)" % _max_jump_y)
	if not _saw_air:
		_fail("airborne flag never became true")
	if _fsm.airborne:
		_fail("FSM is still airborne after landing")


func _check_no_auto_start() -> void:
	print("idle in arena: state=%s clears=%d" % [_course.state, _course.cleared_count])
	if _course.state != "idle":
		_fail("riding into the arena started a round on its own")
	if _course.cleared_count != 0:
		_fail("a round had progress before any fence was cleared")


func _check_started_by_fence() -> void:
	print("first fence: state=%s clears=%d" % [_course.state, _course.cleared_count])
	if _course.state != "running":
		_fail("clearing the first fence did not start a round")
	if _course.cleared_count != 1:
		_fail("the fence that started the round was not counted (clears=%d)" % _course.cleared_count)


func _check_practice_started() -> void:
	print("practice jump: state=%s clears=%d" % [_course.state, _course.cleared_count])
	if _course.state != "running":
		_fail("clearing the practice jump did not start a round")
	if _course.cleared_count != 0:
		_fail("the practice jump was counted as a course fence (clears=%d)" % _course.cleared_count)


func _check_cancelled() -> void:
	print("left arena: state=%s clears=%d money=%d" % [
		_course.state, _course.cleared_count, _game.money
	])
	if _course.state != "idle":
		_fail("leaving the training area did not cancel the round")
	if _course.cleared_count != 0:
		_fail("the cancelled round kept its progress")
	if _game.money != _money_before:
		_fail("a cancelled round paid money")


func _check_round_started() -> void:
	# Keep the test short; the real course waits six seconds so the result card
	# can be read.
	_course.reset_delay = 0.8
	print("round state=%s jumps=%d money=%d" % [_course.state, _course.get_jump_count(), _game.money])
	if _course.get_jump_count() != 8:
		_fail("expected 8 course fences, found %d" % _course.get_jump_count())
	if _course.state != "running":
		_fail("clearing a fence did not start the round")
	_check_number_blocks()


func _check_number_blocks() -> void:
	for i in range(_course.get_jump_count()):
		var data: Dictionary = _course.get("_jumps")[i]
		var jump := data["node"] as Node3D
		# The fence that started the round is already cleared by now, so its
		# number label is expected to be showing.  The rest must be hidden.
		_check_number_block(jump, "Jump_%02d" % (i + 1), bool(data["cleared"]))
	var practice := _world.get_node_or_null("ArenaCourse/ArenaJumps/PracticeJump") as Node3D
	if practice == null:
		_fail("practice jump is missing")
	else:
		_check_number_block(practice, "PracticeJump")


func _check_number_block(jump: Node3D, label: String, cleared := false) -> void:
	var block := jump.get_node_or_null("NumberBlock") as Node3D
	if block == null:
		_fail("%s has no physical number block" % label)
	else:
		var bounds := AABB()
		var has_mesh := false
		for mesh in block.find_children("*", "MeshInstance3D", true, false):
			var instance := mesh as MeshInstance3D
			if instance.mesh == null:
				continue
			var box: AABB = instance.global_transform * instance.get_aabb()
			bounds = box if not has_mesh else bounds.merge(box)
			has_mesh = true
		if not has_mesh:
			_fail("%s number block has no mesh" % label)
		elif absf(bounds.position.y) > 0.03:
			_fail("%s number block base is %.3f m off the ground" % [label, bounds.position.y])
	var number_label := jump.get_node_or_null("NumberLabel") as Label3D
	if number_label != null and number_label.visible and not cleared:
		_fail("%s floating number is visible before the fence is cleared" % label)


func _clear_fence(index: int) -> void:
	var data: Dictionary = _course.get("_jumps")[index]
	var aabb: AABB = data["aabb"]
	var centre := aabb.get_center()
	# Put the horse in the air above the fence; that is what a real jump does.
	_horse.global_position = Vector3(centre.x, 1.6, centre.z)
	_horse.velocity = Vector3(0.0, 2.0, 0.0)
	_horse.airborne = true


func _check_cleared(expected: int) -> void:
	print("cleared=%d" % _course.cleared_count)
	if _course.cleared_count != expected:
		_fail("expected %d cleared fences, got %d" % [expected, _course.cleared_count])


func _check_finish() -> void:
	print("finished: state=%s clears=%d money=%d skill=%.1f" % [
		_course.state, _course.cleared_count, _game.money, _horse.jumping_skill
	])
	if _course.state != "finished":
		_fail("round did not finish after all fences were cleared")
	if _course.cleared_count != 8:
		_fail("expected 8 cleared fences, got %d" % _course.cleared_count)
	if _game.money <= _money_before:
		_fail("completing the round did not pay money")
	if _horse.jumping_skill <= 1.0:
		_fail("completing the round did not train the horse's jumping")
	if _game.best_round_time <= 0.0:
		_fail("no best round time was recorded")
	for i in range(_course.get_jump_count()):
		var data: Dictionary = _course.get("_jumps")[i]
		var number_label := (data["node"] as Node3D).get_node_or_null("NumberLabel") as Label3D
		if number_label == null or not number_label.visible or number_label.text != "CLEAR":
			_fail("fence %d did not show its CLEAR status" % (i + 1))


func _check_reset() -> void:
	print("reset: state=%s clears=%d" % [_course.state, _course.cleared_count])
	if _course.state != "idle":
		_fail("round did not reset to idle")
	if _course.cleared_count != 0:
		_fail("cleared count did not reset")
	for i in range(_course.get_jump_count()):
		var jump: Dictionary = _course.get("_jumps")[i]
		if jump["cleared"]:
			_fail("fence %d still marked cleared after reset" % (i + 1))


func _finish() -> void:
	Input.action_release("move_forward")
	Input.action_release("gallop")
	Input.action_release("jump")
	Input.action_release("jump")
	if _failures.is_empty():
		print("RIDE LOOP CHECK: PASS")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("RIDE LOOP CHECK: FAIL")
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)
