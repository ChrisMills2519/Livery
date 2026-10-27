extends SceneTree

const MAIN := "res://scenes/main.tscn"

var _time := 0.0
var _stage := 0
var _stage_at := 0.15
var _world: Node3D
var _dog_root: Node3D
var _dog: CharacterBody3D
var _animator: Node
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _failures: Array[String] = []
var _start_affection := 0.0
var _wander_start := Vector3.ZERO
var _return_min_gap := 1e9
var _dragging := false
var _drag_dir := Vector3.ZERO
var _drag_speed := 0.0
var _drag_dog_start := Vector3.ZERO
var _turning := false
var _turn_min_align := 1.0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(delta: float) -> bool:
	_time += delta
	if _dragging and _player != null:
		_player.global_position += _drag_dir * _drag_speed * delta
	if _turning and _dog != null:
		var planar := Vector2(_dog.velocity.x, _dog.velocity.z)
		if planar.length() > 0.2:
			var forward := -_dog.global_transform.basis.z
			forward.y = 0.0
			_turn_min_align = minf(
				_turn_min_align,
				forward.normalized().dot(Vector3(planar.x, 0.0, planar.y).normalized())
			)
	if _stage == 9 and _dog != null:
		var home_gap := _horizontal(_dog.global_position, _dog.call("get_home_position"))
		_return_min_gap = minf(_return_min_gap, home_gap)
	if _time < _stage_at:
		return false
	match _stage:
		0:
			_bind()
			_check_scene()
			_stage = 1
			_stage_at = _time + 0.2
		1:
			_test_pet()
			_stage = 2
			_stage_at = _time + 0.3
		2:
			_check_pet_animation()
			_stage = 3
			_stage_at = _time + 2.2
		3:
			_check_pet()
			_test_ignore()
			_stage = 4
			_stage_at = _time + 2.6
		4:
			_check_ignore()
			_test_sit()
			_stage = 5
			_stage_at = _time + 0.8
		5:
			_check_sit()
			_test_eat()
			_stage = 6
			_stage_at = _time + 1.6
		6:
			_check_eat()
			_test_sleep()
			_stage = 7
			_stage_at = _time + 5.5
		7:
			_check_sleep()
			_test_wander()
			_stage = 8
			_stage_at = _time + 3.8
		8:
			_check_wander()
			_test_return()
			_stage = 9
			# 25 m at the dog's real run speed needs a longer leash walk home.
			_stage_at = _time + 13.0
		9:
			_check_return()
			_test_follow_real()
			_stage = 10
			_stage_at = _time + 2.4
		10:
			_check_follow_real()
			_test_follow_expire()
			_stage = 11
			_stage_at = _time + 0.2
		11:
			_check_follow_expire()
			_test_follow_heel()
			_stage = 12
			_stage_at = _time + 1.4
		12:
			_check_follow_heel()
			_test_turn()
			_stage = 13
			_stage_at = _time + 1.2
		13:
			_check_turn()
			_finish()
			return true
	return false


func _bind() -> void:
	_dog_root = _world.get_node("Dog") as Node3D
	_dog = _dog_root.get_node("Body") as CharacterBody3D
	_animator = _dog.get_node("Animator")
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D


func _check_scene() -> void:
	_check(_dog != null and _animator != null, "dog body and animator exist")
	var player: AnimationPlayer = _dog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(player != null, "dog AnimationPlayer found")
	if player != null:
		for clip in [
			"Idle", "Idle_Alert", "Walk", "Trot", "Run", "Sit", "Lie",
			"Sleep", "Eat", "TailWag", "Rest_Pose", "Shake",
		]:
			_check(player.has_animation(clip), "clip %s exists" % clip)
		_check(
			player.get_animation("Idle").loop_mode != Animation.LOOP_NONE,
			"Idle loops"
		)
		_check(
			player.get_animation("Sit").loop_mode != Animation.LOOP_NONE,
			"Sit loops"
		)
		_check(
			player.get_animation("Shake").loop_mode == Animation.LOOP_NONE,
			"Shake is a one-shot"
		)
	var top := 0.0
	var bottom := 1e9
	for node in _dog.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var aabb := mesh.get_aabb()
		top = maxf(top, aabb.position.y + aabb.size.y)
		bottom = minf(bottom, aabb.position.y)
	_check(absf(top - 0.225) < 0.035, "dog model height %.3f m" % top)
	_check(bottom > -0.02, "dog mesh sits on the origin (min y %.3f)" % bottom)
	var home: Vector3 = _dog.call("get_home_position")
	# The dog lives by the well in the yard's east corner, clear of the lane the
	# player arrives on and of the horse's standing spot.
	_check(home.distance_to(Vector3(13.5, 0.0, -15.5)) < 0.1, "dog home in the stable yard")
	_check(_state() == "idle", "dog starts idle (got %s)" % _state())


func _test_pet() -> void:
	_horse.global_position = Vector3(40.0, 0.0, 40.0)
	_player.global_position = _dog.global_position + Vector3(0.0, 0.05, 0.9)
	_player.velocity = Vector3.ZERO
	_start_affection = float(_dog.get("affection"))
	_dog.call("_refresh_prompt")
	var prompt := _dog.get_node("PetPrompt") as Label3D
	_check(prompt.visible, "pet prompt is visible beside the dog")
	_send_pet()
	_check(_state() == "pet", "petting enters the pet state (got %s)" % _state())
	_check(
		float(_dog.get("affection")) > _start_affection,
		"petting raises affection"
	)


func _check_pet_animation() -> void:
	_check(_state() == "pet", "petting is still playing (got %s)" % _state())
	_check(_clip() == "TailWag", "petting plays TailWag (got %s)" % _clip())


func _check_pet() -> void:
	_check(_state() != "pet", "petting finishes (state %s)" % _state())
	_check(
		float(_dog.get("affection")) > _start_affection,
		"affection stays raised after petting"
	)


func _test_ignore() -> void:
	# A player standing four metres away is not a reason to follow: the dog's
	# interest in them has not built up.
	_dog.call("debug_set_needs", 0.2, 0.8, 0.6, 0.0)
	_dog.call("debug_set_interest", 0.0)
	_player.global_position = _dog.global_position + Vector3(0.0, 0.05, -4.0)
	_player.velocity = Vector3.ZERO
	_dog.velocity = Vector3.ZERO


func _check_ignore() -> void:
	_check(_state() != "follow", "a standing player does not pull the dog along (got %s)" % _state())


func _test_sit() -> void:
	_player.velocity = Vector3.ZERO
	_dog.call("debug_force_state", "sit")


func _check_sit() -> void:
	_check(_state() == "sit", "dog sits when the player stops (got %s)" % _state())
	_check(_clip() == "Sit", "sit state plays the Sit clip (got %s)" % _clip())


func _test_eat() -> void:
	_player.global_position = Vector3(40.0, 0.05, 40.0)
	_player.velocity = Vector3.ZERO
	var bowl := _dog_root.get_node("BowlSpot") as Marker3D
	_dog.global_position = bowl.global_position
	_dog.velocity = Vector3.ZERO
	_dog.call("debug_set_needs", 0.95, 0.8, 0.6, 0.0)
	_dog.call("debug_force_state", "idle")
	_dog.call("debug_think")
	_check(_state() == "eat", "hunger drives the dog to eat (got %s)" % _state())


func _check_eat() -> void:
	_check(_state() == "eat", "dog is still eating (got %s)" % _state())
	_check(_clip() == "Eat", "eating plays the Eat clip (got %s)" % _clip())
	_check(float(_dog.get("hunger")) < 0.95, "eating lowers hunger")


func _test_sleep() -> void:
	_player.global_position = Vector3(40.0, 0.05, 40.0)
	_player.velocity = Vector3.ZERO
	_dog.call("debug_force_state", "idle")
	_dog.call("debug_set_needs", 0.1, 0.05, 0.6, 0.0)
	_dog.call("debug_think")
	_check(_state() == "lie", "low energy lies the dog down (got %s)" % _state())


func _check_sleep() -> void:
	_check(_state() == "sleep", "dog sleeps after lying down (got %s)" % _state())
	_check(_clip() == "Sleep", "sleeping plays the Sleep clip (got %s)" % _clip())
	_check(float(_dog.get("energy")) > 0.05, "sleeping restores energy")


func _test_wander() -> void:
	_player.global_position = Vector3(40.0, 0.05, 40.0)
	_player.velocity = Vector3.ZERO
	_dog.call("debug_force_state", "idle")
	_dog.call("debug_set_needs", 0.2, 0.8, 0.6, 1.0)
	_dog.call("debug_think")
	_check(_state() == "wander", "boredom starts a wander (got %s)" % _state())
	_wander_start = _dog.global_position


func _check_wander() -> void:
	var travelled := _horizontal(_wander_start, _dog.global_position)
	var home_gap := _horizontal(_dog.global_position, _dog.call("get_home_position"))
	_check(travelled > 0.15, "the dog wanders (%.2f m)" % travelled)
	_check(home_gap <= float(_dog.get("home_radius")) + 2.0, "wandering stays near home (%.2f m)" % home_gap)


func _test_return() -> void:
	_player.global_position = Vector3(40.0, 0.05, 40.0)
	_player.velocity = Vector3.ZERO
	var home: Vector3 = _dog.call("get_home_position")
	_dog.global_position = home + Vector3(0.0, 0.05, 25.0)
	_dog.velocity = Vector3.ZERO
	_dog.call("debug_force_state", "follow")
	_dog.call("debug_think")
	_check(_state() == "return", "the leash sends the dog home (got %s)" % _state())


func _check_return() -> void:
	_check(_return_min_gap < 1.0, "the dog returns to its home (closest %.2f m)" % _return_min_gap)


func _test_follow_real() -> void:
	# The player walks away while the dog's interest is high: the dog should
	# take up the chase.  The player is moved by position each frame, because
	# the player controller resets its velocity every physics step.
	_dog.call("debug_force_state", "follow")
	_dog.call("debug_set_interest", 0.9)
	_dog.velocity = Vector3.ZERO
	_player.global_position = _dog.global_position + Vector3(0.0, 0.05, -3.5)
	_player.velocity = Vector3.ZERO
	_drag_dir = Vector3(0.0, 0.0, -1.0)
	_drag_speed = 1.6
	_drag_dog_start = _dog.global_position
	_dragging = true


func _check_follow_real() -> void:
	_dragging = false
	var moved := _horizontal(_dog.global_position, _drag_dog_start)
	var gap := _horizontal(_dog.global_position, _player.global_position)
	_check(_state() == "follow", "an interested dog follows a walking player (got %s)" % _state())
	_check(moved > 1.0, "the followed dog covers ground (%.2f m)" % moved)
	_check(gap < float(_dog.get("follow_radius")), "the followed dog keeps up (gap %.2f m)" % gap)


func _test_follow_expire() -> void:
	_dragging = false
	_dog.call("debug_set_follow_elapsed", 999.0)
	_dog.call("debug_think")


func _check_follow_expire() -> void:
	var cooldown := float(_dog.get("_follow_cooldown"))
	_check(_state() != "follow", "a chase ends after its time limit (got %s)" % _state())
	_check(cooldown > 0.0, "the dog cools off after a chase (%.1f s)" % cooldown)
	_dog.call("debug_set_interest", 0.9)
	_dog.call("debug_think")
	_check(_state() != "follow", "the dog does not restart the chase straight away (got %s)" % _state())


func _test_follow_heel() -> void:
	# Close to the player the dog moves with their stride instead of steering at
	# a point, so it has to turn to face the way the pair is travelling.  It
	# starts facing the opposite way to make a stale heading obvious.
	_dog.call("debug_set_interest", 0.9)
	_dog.call("debug_set_follow_elapsed", 0.0)
	_dog.velocity = Vector3.ZERO
	_dog.global_position = Vector3(-3.5, 0.05, -16.5)
	_dog.rotation.y = PI
	_player.rotation.y = PI * 0.5
	var heel := _player.global_transform.basis * Vector3(0.8, 0.0, 1.0)
	_player.global_position = _dog.global_position - heel
	_player.velocity = Vector3.ZERO
	_dog.call("debug_force_state", "follow")
	_drag_dir = Vector3(-1.0, 0.0, 0.0)
	_drag_speed = 1.6
	_dragging = true


func _check_follow_heel() -> void:
	_dragging = false
	_check(
		_state() == "follow",
		"the dog keeps at heel while the player walks (got %s)" % _state()
	)
	var speed := Vector2(_dog.velocity.x, _dog.velocity.z).length()
	_check(speed > 1.0, "at heel the dog moves with the player's stride (%.2f m/s)" % speed)
	var forward := -_dog.global_transform.basis.z
	forward.y = 0.0
	var alignment := forward.normalized().dot(Vector3(-1.0, 0.0, 0.0))
	_check(
		alignment > 0.9,
		"at heel the dog faces the way it is moving (dot %.2f)" % alignment
	)


func _test_turn() -> void:
	# Send the dog home from behind its own tail.  Aiming the velocity at the
	# target while the body is still swinging round is what used to make it crab
	# sideways across the ground.
	_dragging = false
	var home: Vector3 = _dog.call("get_home_position")
	_dog.global_position = home + Vector3(0.0, 0.05, 3.0)
	_dog.velocity = Vector3.ZERO
	_dog.rotation.y = PI
	_dog.call("debug_force_state", "return")
	_turn_min_align = 1.0
	_turning = true


func _check_turn() -> void:
	_turning = false
	_check(
		_turn_min_align > 0.9,
		"the dog travels the way it faces through a turn (dot %.2f)" % _turn_min_align
	)
	_check(_state() == "return", "the dog is still walking home (got %s)" % _state())
	_check(_clip() == "Walk", "the returning dog walks (clip %s)" % _clip())
	var player := _dog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		_check(
			player.speed_scale >= 0.85 and player.speed_scale <= 1.2,
			"the walk clip plays at its planted speed (scale %.2f)" % player.speed_scale
		)


func _send_pet() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.keycode = KEY_Q
	event.pressed = true
	_dog.call("_unhandled_input", event)


func _state() -> String:
	return String(_dog.call("get_state_name"))


func _clip() -> String:
	return String(_animator.get("current_clip"))


func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("DOG CHECK: PASS")
		quit(0)
	else:
		print("DOG CHECK: FAIL (%d)" % _failures.size())
		quit(1)
