extends SceneTree

## Touch-controls check.
##
##   godot --headless --path . --script res://tools/check_touch.gd
##
## Headless has no touch hardware, so this feeds finger events straight into the
## TouchControls layer (the same functions the real InputEventScreenTouch and
## InputEventScreenDrag handlers call) and then verifies what gameplay does with
## the results: prompts, the analog stick, run hysteresis, look, the CONTEXT
## button, grooming gestures and the select-screen swipe.

const MAIN := "res://scenes/main.tscn"

var _failures: Array[String] = []
# Autoloads are looked up at runtime: in --script mode their names are not
# known identifiers at compile time (see check_character_select.gd).
var _device
var _touch
var _world: Node3D
var _player: CharacterBody3D
var _horse: Node3D
var _bay: Node
var _session


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("TOUCH CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("TOUCH CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	_device = root.get_node_or_null("Device")
	_touch = root.get_node_or_null("TouchControls")
	if _device == null or _touch == null:
		_check(false, "Device and TouchControls autoloads are registered")
		return
	_check(
		_device._parse_touch_query("?touch=1") == "1"
		and _device._parse_touch_query("?touch=0") == "0"
		and _device._parse_touch_query("?a=b&touch=1") == "1"
		and _device._parse_touch_query("touch=0") == "0",
		"a web URL can ask for touch or keyboard mode")
	_check(
		_device._parse_touch_query("") == ""
		and _device._parse_touch_query("?touch=") == ""
		and _device._parse_touch_query("?touch=2") == ""
		and _device._parse_touch_query("?touchy=1") == "",
		"a missing or malformed touch parameter falls back to detection")
	_device.set_touch_mode(0)
	_check(_device.pick("E  MOUNT", "TAP  MOUNT") == "E  MOUNT", "keyboard mode picks keyboard prompt text")
	_check(not _touch.feed_touch(90, Vector2(200, 500), true), "keyboard mode ignores touches")
	_device.set_touch_mode(1)
	_check(_device.is_touch(), "touch mode turns on")
	_check(_device.pick("E  MOUNT", "TAP  MOUNT") == "TAP  MOUNT", "touch mode picks touch prompt text")

	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	await _frames(30)
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_horse = _world.get_node_or_null("Horse") as Node3D
	_bay = _world.get_node_or_null("GroomingBay")
	_check(_player != null and _horse != null and _bay != null, "main scene has player, horse and bay")
	if _player == null or _horse == null or _bay == null:
		return
	_check(_touch.is_active() and _touch.mode == "ride", "player puts the layer in ride mode")

	await _check_stick()
	await _check_look()
	await _check_keyboard_still_works()
	await _check_context_mount()
	await _check_grooming_gestures()
	_check_select_swipe()


# --- Ride: stick, run, walk -------------------------------------------------

func _check_stick() -> void:
	var base := Vector2(200, 500)
	_touch.feed_touch(0, base, true)
	_touch.feed_drag(0, base + Vector2(0, -60), Vector2(0, -60))
	var move: Vector2 = _touch.get_move_input()
	_check(move.y < -0.4 and absf(move.x) < 0.05, "a forward push gives an analog forward move")
	_check(not _touch.is_running(), "a short push does not run")

	_touch.feed_drag(0, base + Vector2(0, -100), Vector2(0, -40))
	await _frames(2)
	_check(_touch.is_running() and Input.is_action_pressed("run"), "a push past 80% of the stick engages run")

	_touch.feed_drag(0, base + Vector2(0, -75), Vector2(0, 25))
	await _frames(2)
	_check(not _touch.is_running() and not Input.is_action_pressed("run"), "dropping below 70% releases run")

	_touch.feed_drag(0, base + Vector2(0, -60), Vector2(0, 15))
	var start := _player.global_position
	await _physics_frames(40)
	var walked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(walked > 0.3, "holding the stick walks the player on foot (moved %.2f m)" % walked)

	_touch.feed_touch(0, base + Vector2(0, -60), false)
	await _frames(2)
	_check(not _touch.is_stick_active() and _touch.get_move_input().length() < 0.01, "lifting the thumb stops the stick")


# --- Ride: look drag --------------------------------------------------------

func _check_look() -> void:
	var yaw := _player.rotation.y
	_touch.feed_touch(5, Vector2(1000, 300), true)
	_touch.feed_drag(5, Vector2(1060, 300), Vector2(60, 0))
	await _frames(3)
	_touch.feed_touch(5, Vector2(1060, 300), false)
	_check(absf(_player.rotation.y - yaw) > 0.05, "a right-hand drag turns the player's yaw")


# --- Keyboard stays live with touch on -------------------------------------

func _check_keyboard_still_works() -> void:
	Input.action_press("move_forward")
	await _frames(2)
	var keys: Vector2 = _touch.get_move_input()
	Input.action_release("move_forward")
	_check(keys.y < -0.9, "keyboard move still works with touch mode on")


# --- Ride: CONTEXT button ---------------------------------------------------

func _check_context_mount() -> void:
	var side := _horse.global_transform.basis.x.normalized()
	_player.global_position = _horse.global_position + side * 1.2 + Vector3.UP * 0.05
	await _physics_frames(30)
	await _wait_ms(350)
	_check(_touch.context_action() == "interact" and _touch.context_label() == "MOUNT",
		"CONTEXT offers MOUNT beside the horse (got %s)" % _touch.context_label())
	var center: Vector2 = _touch.button_center("context")
	_touch.feed_touch(6, center, true)
	_touch.feed_touch(6, center, false)
	await _physics_frames(10)
	_check(bool(_player.get("mounted")), "tapping CONTEXT mounts the horse")
	_player.call("dismount")
	await _frames(2)


# --- Grooming gestures --------------------------------------------------------

func _check_grooming_gestures() -> void:
	var horse_anchor := _bay.get_node("HorseAnchor") as Marker3D
	var groomer_anchor := _bay.get_node("GroomerAnchor") as Marker3D
	_player.global_position = groomer_anchor.global_position
	_horse.global_position = horse_anchor.global_position
	await _frames(3)
	_bay.call("_process", 0.2)
	_bay.call("_unhandled_input", _action("groom"))
	await _frames(8)
	_session = _bay.get_node_or_null("Session")
	_check(_session != null and bool(_session.get("active")), "the groom action starts the session")
	_check(_touch.mode == "groom", "the layer switches to groom mode")
	if _session == null:
		return

	# One finger paints; a second finger takes over as an orbit and pinch.
	_touch.feed_touch(10, Vector2(600, 300), true)
	_check(_touch.is_painting(), "one finger starts a paint stroke")
	_touch.feed_touch(11, Vector2(700, 300), true)
	_check(not _touch.is_painting(), "a second finger stops painting")

	var yaw: float = _session.get("_yaw")
	_touch.feed_drag(10, Vector2(620, 300), Vector2(20, 0))
	_touch.feed_drag(11, Vector2(720, 300), Vector2(20, 0))
	await _frames(2)
	_check(not is_equal_approx(float(_session.get("_yaw")), yaw), "two-finger drag orbits the groom camera")

	var distance: float = _session.get("_distance")
	_touch.feed_drag(10, Vector2(560, 300), Vector2(-60, 0))
	_touch.feed_drag(11, Vector2(760, 300), Vector2(60, 0))
	await _frames(2)
	_check(float(_session.get("_distance")) < distance, "spreading two fingers pinches the camera in")

	# Emulated mouse must not also orbit the camera in touch mode.
	var yaw_before: float = _session.get("_yaw")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(500, 0)
	_session.call("_unhandled_input", motion)
	_check(is_equal_approx(float(_session.get("_yaw")), yaw_before), "emulated mouse motion is ignored in touch mode")

	_touch.feed_touch(10, Vector2(560, 300), false)
	_touch.feed_touch(11, Vector2(760, 300), false)
	await _frames(2)
	_check(not _touch.is_painting(), "lifting both fingers leaves no stroke active")


# --- Select: swipe ----------------------------------------------------------

func _check_select_swipe() -> void:
	_touch.set_mode("select")
	_touch.feed_touch(20, Vector2(640, 360), true)
	_check(_touch.is_swiping(), "select mode: a drag starts a swipe")
	_touch.feed_drag(20, Vector2(700, 360), Vector2(60, 0))
	_check(absf(_touch.consume_swipe() - 60.0) < 0.01, "a swipe reports its horizontal travel")
	_touch.feed_touch(20, Vector2(700, 360), false)
	_check(not _touch.is_swiping(), "lifting the finger ends the swipe")
	_touch.set_mode("ride")


# --- Helpers ----------------------------------------------------------------

func _action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	event.strength = 1.0
	return event


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _physics_frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		print("  FAIL: ", label)
	else:
		print("  ok: ", label)
