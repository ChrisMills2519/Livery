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
##
## It also covers the ways a real phone loses the stick: a touch-up the OS never
## delivered (iOS cancels a touch rather than ending it), a late touch-up from
## the finger that used to own it, and the same presses arriving as real
## InputEventScreenTouch / ScreenDrag events through _input().

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
	_check(
		_device._parse_query("?touch=1&touchdebug=1", "touchdebug") == "1"
		and _device._parse_query("?touch=1", "touchdebug") == "",
		"a web URL can ask for the touch debug readout")
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
	await _check_stick_takeover()
	await _check_simultaneous_thumbs()
	await _check_steer_frame()
	await _check_look()
	await _check_lost_release()
	await _check_push_reclaim()
	await _check_live_thumb_keeps_stick()
	await _check_stick_self_heal()
	await _check_negative_index()
	await _check_raw_events()
	await _check_keyboard_still_works()
	await _check_context_mount()
	await _check_gallop_button()
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


# --- Ride: stick takeover ---------------------------------------------------

func _check_stick_takeover() -> void:
	# A resting contact (palm, forearm, a thumb that has not pushed yet) grabs
	# the stick half first; the thumb that actually pushes must still take over.
	_touch.feed_touch(30, Vector2(120, 420), true)
	_check(_touch.is_stick_active(), "a resting contact arms the stick")
	_touch.feed_touch(31, Vector2(230, 500), true)
	_touch.feed_drag(31, Vector2(230, 430), Vector2(0, -70))
	_check(_touch.get_move_input().y < -0.5, "a pushing thumb takes the stick from a resting contact")
	_check(int(_touch._stick_index) == 31, "the stick follows the pushing thumb")

	# Lifting the pushing thumb hands the stick to the finger still down, so the
	# player keeps steering instead of dropping to a dead stick.
	_touch.feed_touch(31, Vector2(230, 430), false)
	_check(_touch.is_stick_active() and int(_touch._stick_index) == 30,
		"lifting the thumb hands the stick back to the resting finger")

	# A lost release (app switch, dropped event) must not wedge the index: a
	# fresh press for the same index re-arms instead of being ignored.
	_touch.feed_touch(30, Vector2(150, 460), true)
	_touch.feed_drag(30, Vector2(150, 390), Vector2(0, -70))
	_check(_touch.get_move_input().y < -0.5, "a repeated press on a stale index re-arms the stick")
	_touch.feed_touch(30, Vector2(150, 390), false)
	await _frames(2)
	_check(not _touch.is_stick_active() and _touch.get_move_input().length() < 0.01,
		"releasing the last finger leaves no stick held")

	# Backgrounding the app can swallow the touch-ups entirely; focus loss must
	# release the fingers so the stick is not wedged when the player returns.
	_touch.feed_touch(32, Vector2(200, 500), true)
	_touch.feed_drag(32, Vector2(200, 430), Vector2(0, -70))
	_check(_touch.is_stick_active(), "the stick is held before the app loses focus")
	_touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(not _touch.is_stick_active() and _touch.get_move_input().length() < 0.01,
		"losing focus releases a stick whose touch-up never arrived")


# --- Ride: the held stick owns the movement frame ---------------------------

func _check_steer_frame() -> void:
	var base := Vector2(200, 500)
	_touch.feed_touch(50, base, true)
	_touch.feed_drag(50, base + Vector2(0, -60), Vector2(0, -60))
	await _frames(2)
	_check(bool(_player.call("is_steering_with_stick")), "a pushed stick owns the movement frame")
	var frame: float = _player.call("steer_yaw")
	var yaw_before: float = _player.rotation.y
	await _physics_frames(6)

	# Look 120 px right while the thumb holds the direction.
	_touch.feed_touch(51, Vector2(960, 300), true)
	for i in range(6):
		_touch.feed_drag(51, Vector2(980 + i * 20, 300), Vector2(20, 0))
	await _frames(3)
	_check(absf(_player.rotation.y - yaw_before) > 0.1, "the look drag still turns the camera")
	_check(is_equal_approx(float(_player.call("steer_yaw")), frame),
		"the held stick keeps its frame while the camera turns")

	await _physics_frames(4)
	var planar := Vector2(_player.velocity.x, _player.velocity.z)
	var want := Basis(Vector3.UP, frame) * Vector3(0.0, 0.0, -1.0)
	var want_flat := Vector2(want.x, want.z).normalized()
	if planar.length() > 0.5:
		_check(planar.normalized().angle_to(want_flat) < 0.2,
			"walking keeps its line while the camera turns (%.0f deg off)" % rad_to_deg(planar.normalized().angle_to(want_flat)))

	_touch.feed_touch(51, Vector2(1080, 300), false)
	_touch.feed_touch(50, base + Vector2(0, -60), false)
	await _frames(2)
	_check(not bool(_player.call("is_steering_with_stick")), "releasing the stick frees the frame")
	_check(is_equal_approx(float(_player.call("steer_yaw")), _player.rotation.y),
		"the free frame follows the camera again")

	# Pushing again re-aims from wherever the camera is looking now.
	var yaw_now: float = _player.rotation.y
	_touch.feed_touch(52, base, true)
	_touch.feed_drag(52, base + Vector2(0, -60), Vector2(0, -60))
	await _frames(2)
	_check(is_equal_approx(float(_player.call("steer_yaw")), yaw_now),
		"a fresh push re-aims from the current view")
	_touch.feed_touch(52, base + Vector2(0, -60), false)
	await _frames(2)


# --- Ride: look drag --------------------------------------------------------

func _check_look() -> void:
	var yaw := _player.rotation.y
	_touch.feed_touch(5, Vector2(1000, 300), true)
	_touch.feed_drag(5, Vector2(1060, 300), Vector2(60, 0))
	await _frames(3)
	_touch.feed_touch(5, Vector2(1060, 300), false)
	var turned := absf(_player.rotation.y - yaw)
	_check(turned > 0.05, "a right-hand drag turns the player's yaw")
	# Dragging to look must not swing the view at the full mouse rate: movement
	# is camera-relative, so a 1:1 drag re-aims the heading and spins.
	var raw := 60.0 * float(_player.get("mouse_sensitivity"))
	_check(absf(turned - raw * 0.55) < 0.005,
		"a touch drag applies its own gain, not the mouse rate (%.3f vs %.3f rad)" % [turned, raw])


# --- Ride: a touch-up the OS never delivered --------------------------------

func _check_lost_release() -> void:
	# The reported phone fault.  iOS cancels a touch instead of ending it (a
	# back-swipe at the edge, Safari's toolbar moving, a system gesture), and
	# Godot's web input has no event for that, so the touch-up never arrives
	# while the stick is pushed.  The next thumb must still get a stick.
	var base := Vector2(200, 500)
	_touch.feed_touch(70, base, true)
	_touch.feed_drag(70, base + Vector2(0, -90), Vector2(0, -90))
	_check(_touch.is_stick_active() and _touch.is_stick_pushing(),
		"a pushed stick is held before its release is lost")
	# No touch-up for 70: the OS dropped it.
	await _wait_ms(400)

	var yaw_before: float = _player.rotation.y
	_touch.feed_touch(71, base + Vector2(30, 20), true)
	_check(int(_touch._stick_index) == 71, "a lost touch-up does not lock the next thumb out")
	_touch.feed_drag(71, base + Vector2(30, -50), Vector2(0, -70))
	_check(_touch.get_move_input().y < -0.4, "the thumb that took over steers")
	var start := _player.global_position
	await _physics_frames(30)
	var walked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(walked > 0.2, "the player walks again after a cancelled touch (moved %.2f m)" % walked)
	_check(is_equal_approx(_player.rotation.y, yaw_before),
		"taking the stick over does not turn the view")

	# The stale finger's touch-up can still turn up later; it must not kill the
	# thumb that took over from it.
	_touch.feed_touch(70, base + Vector2(0, -90), false)
	await _frames(2)
	_check(int(_touch._stick_index) == 71 and _touch.is_stick_active(),
		"a late touch-up from the stale finger leaves the new stick alone")
	_touch.feed_touch(71, base + Vector2(30, -50), false)
	await _frames(2)
	_check(not _touch.is_stick_active(), "lifting the new thumb ends the stick")


# --- Ride: recovering the stick by pushing -----------------------------------

func _check_push_reclaim() -> void:
	# A press that lands before the stale holder times out is filed idle, so the
	# push is what has to recover the stick.  Without it the player would have to
	# lift and press again to move at all.
	var base := Vector2(200, 500)
	_touch.feed_touch(75, base, true)
	_touch.feed_drag(75, base + Vector2(0, -80), Vector2(0, -80))
	_touch.feed_touch(76, base + Vector2(50, 30), true)
	_check(int(_touch._stick_index) == 75, "inside the window the old holder keeps the stick")
	# 75 is dead now; 76 pushes past the resting distance and takes over.
	await _wait_ms(400)
	_touch.feed_drag(76, base + Vector2(50, -40), Vector2(0, -70))
	_check(int(_touch._stick_index) == 76, "a push takes a stick whose holder went quiet")
	_check(_touch.get_move_input().y < -0.4, "the recovered stick steers")
	_touch.feed_touch(76, base + Vector2(50, -40), false)
	_touch.feed_touch(75, base + Vector2(0, -80), false)
	await _frames(2)
	_check(not _touch.is_stick_active(), "the stick is free once the stale finger finally lifts")


# --- Ride: a live thumb keeps the stick --------------------------------------

func _check_live_thumb_keeps_stick() -> void:
	var base := Vector2(200, 500)
	_touch.feed_touch(72, base, true)
	_touch.feed_drag(72, base + Vector2(0, -70), Vector2(0, -70))
	_touch.feed_touch(73, base + Vector2(40, 40), true)
	_check(int(_touch._stick_index) == 72, "a resting second contact does not steal a live stick")
	_touch.feed_touch(73, base + Vector2(40, 40), false)

	# The holder goes quiet, exactly as it does while walking a straight line.
	await _wait_ms(400)
	_touch.feed_touch(74, base + Vector2(60, 30), true)
	_check(int(_touch._stick_index) == 74, "a thumb that lands after the holder goes quiet takes the stick")
	_touch.feed_touch(74, base + Vector2(60, 30), false)
	_touch.feed_touch(72, base + Vector2(0, -70), false)
	await _frames(2)
	_check(not _touch.is_stick_active(), "the stick is free after both fingers lift")


# --- Ride: an index with no finger left --------------------------------------

func _check_stick_self_heal() -> void:
	_touch._stick_index = 999
	_touch._stick_owned = true
	await _frames(2)
	_check(int(_touch._stick_index) == -1, "a stick index with no finger behind it is dropped")
	_check(not _touch.is_stick_active(), "the dropped index is not left marked as owned")
	_touch.feed_touch(77, Vector2(200, 500), true)
	_check(int(_touch._stick_index) == 77, "the stick arms again after the dead index is cleared")
	_touch.feed_touch(77, Vector2(200, 500), false)
	await _frames(2)


# --- Ride: a touch index that is negative ------------------------------------

## iOS Safari's touch identifiers climb for the life of the page and overflow
## into a negative int32; a real device reported -410517893.  The layer kept -1
## as its "no stick" sentinel and tested the sign, so a live stick read as
## absent: the ring was not drawn, the steering frame stayed on the camera, and
## `get_move_input()` returned bare keyboard input, which left both the walk and
## the horse with nothing.  Any test of ownership belongs on `_stick_owned`.
func _check_negative_index() -> void:
	var id := -410517893
	var base := Vector2(210, 510)
	_touch.feed_touch(id, base, true)
	_check(_touch.is_stick_active(), "a negative touch index arms the stick")
	_touch.feed_drag(id, base + Vector2(0, -70), Vector2(0, -70))
	_check(_touch.get_move_input().y < -0.4, "a negative index steers the stick")
	_check(_touch.is_stick_pushing(), "a negative index owns the movement frame")
	var start := _player.global_position
	await _physics_frames(30)
	var walked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(walked > 0.2, "the player walks from a negative index (moved %.2f m)" % walked)
	_touch.feed_touch(id, base + Vector2(0, -70), false)
	await _frames(2)
	_check(
		not _touch.is_stick_active() and _touch.get_move_input().length() < 0.01,
		"lifting a negative index releases the stick")


# --- Ride: real touch events through _input() --------------------------------

func _check_raw_events() -> void:
	# This is the path the phone actually uses: the event reaches _input(), which
	# claims the finger before the GUI and marks it handled.  The other cases call
	# feed_touch() directly, so they cannot see a fault in that layer.
	var base := Vector2(220, 520)
	Input.parse_input_event(_touch_event(0, _window_point(base), true))
	await _frames(2)
	_check(int(_touch._stick_index) == 0, "a real touch event claims the stick through _input")
	Input.parse_input_event(
		_drag_event(0, _window_point(base + Vector2(0, -70)), Vector2(0, -70))
	)
	await _frames(2)
	_check(_touch.get_move_input().y < -0.4, "a real drag event steers the stick")
	var start := _player.global_position
	await _physics_frames(30)
	var walked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(walked > 0.2, "the player walks from a real touch event (moved %.2f m)" % walked)
	Input.parse_input_event(_touch_event(0, _window_point(base + Vector2(0, -70)), false))
	await _frames(2)
	_check(not _touch.is_stick_active(), "a real touch-up releases the stick")


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


# --- Ride: gallop button, gait readout and the brake -------------------------

func _cluster_ids() -> Array:
	var ids := []
	for def in _touch._cluster():
		ids.append(String(def["id"]))
	return ids


func _horse_speed() -> float:
	var v: Vector3 = _horse.get("velocity")
	return Vector2(v.x, v.z).length()


func _check_gallop_button() -> void:
	# The ring and the ride classify the gait separately, so the two pairs of
	# thresholds have to stay equal or the ring starts lying.
	var horse_consts: Dictionary = _horse.get_script().get_script_constant_map()
	var touch_consts: Dictionary = _touch.get_script().get_script_constant_map()
	_check(
		is_equal_approx(float(horse_consts["STEER_DEADZONE"]), float(touch_consts["GAIT_DEADZONE"]))
		and is_equal_approx(float(horse_consts["TROT_NOTCH"]), float(touch_consts["TROT_NOTCH"])),
		"the ring and the ride share their gait thresholds")

	_check(not _cluster_ids().has("gallop"), "the gallop button is hidden while dismounted")
	_check(_touch.button_center("gallop") == Vector2.ZERO, "a hidden gallop button has no hit rect")

	_player.try_mount()
	await _physics_frames(4)
	_check(bool(_player.get("mounted")), "the player mounts for the gallop check")
	if not bool(_player.get("mounted")):
		return
	_check(_cluster_ids().has("gallop"), "the gallop button appears in the saddle")

	var gallop: Vector2 = _touch.button_center("gallop")
	_check(gallop != Vector2.ZERO, "the gallop button has a hit rect")
	_check(String(_touch._button_at(gallop).get("id", "")) == "gallop",
		"the gallop button answers at its centre")
	_check(String(_touch._button_at(gallop + Vector2(0.0, -55.0)).get("id", "")) != "gallop",
		"the gallop hit rect ends at its own radius")

	# The ring's magnitude asks for the gait, and the button asks for the canter.
	var base := Vector2(200, 500)
	_touch.feed_touch(70, base, true)
	_touch.feed_drag(70, base + Vector2(0, -70), Vector2(0, -70))
	await _frames(2)
	_check(_touch.stick_gait() == "walk", "a half push asks for a walk (ring reads %s)" % _touch.stick_gait())
	_touch.feed_drag(70, base + Vector2(0, -116), Vector2(0, -46))
	await _frames(2)
	_check(_touch.stick_gait() == "trot", "a full push asks for a trot (ring reads %s)" % _touch.stick_gait())

	_touch.feed_touch(71, gallop, true)
	await _frames(2)
	_check(Input.is_action_pressed("gallop"), "touching GALLOP holds the gallop action")
	_check(_touch.stick_gait() == "canter", "the ring reads canter while the gallop is held")
	_touch.feed_touch(71, gallop, false)
	await _frames(2)
	_check(not Input.is_action_pressed("gallop"), "lifting the thumb releases the gallop")
	_check(_touch.stick_gait() == "trot", "releasing the gallop leaves the ring on the trot")

	# Open ground: against the yard's stable wall, move_and_slide would write the
	# collision back into velocity and the brake would be reading a wall.
	_horse.global_position = Vector3(40.0, 0.1, 40.0)
	_horse.set("velocity", Vector3.ZERO)
	_horse.set("_ride_speed", 0.0)
	_touch.feed_touch(71, gallop, true)
	await _wait_ms(1700)
	_check(_horse_speed() > 4.6,
		"the gallop button and a full stick canter the horse (%.2f m/s)" % _horse_speed())
	_touch.feed_touch(71, gallop, false)

	# Pulled back past the notch and held, the horse brakes instead of turning
	# round and running at the camera.  Sampled per frame because the brake
	# passes through a stop and then into a rein-back.
	var yaw_before: float = _horse.rotation.y
	_touch.feed_drag(70, base + Vector2(0, 116), Vector2(0, 232))
	var stopped := false
	for i in range(90):
		if _horse_speed() < 0.1:
			stopped = true
		await physics_frame
	_check(stopped, "pulling the stick back brakes the horse inside 1.5 s")
	_check(_touch.stick_gait() == "halt", "the ring reads halt while braking")
	_check(absf(wrapf(_horse.rotation.y - yaw_before, -PI, PI)) < 0.05,
		"the brake gesture does not turn the horse round")
	_touch.feed_touch(70, base + Vector2(0, 116), false)
	await _frames(2)
	_player.call("dismount")
	await _physics_frames(4)


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

	# The touch brush works above the thumb, so the finger does not cover the
	# red/green disk.  The hoof pick keeps the finger position (small targets).
	_session.call("set_tool", 0)
	var aim: Vector2 = _session.call("_brush_screen_pos", Vector2(600, 400))
	var lift := 400.0 - aim.y
	_check(is_equal_approx(aim.x, 600.0) and lift > 30.0 and lift < 120.0,
		"the touch brush cleans above the finger (lifted %.0f px)" % lift)
	_session.call("set_tool", 4)
	var hoof_aim: Vector2 = _session.call("_brush_screen_pos", Vector2(600, 400))
	_check(hoof_aim.is_equal_approx(Vector2(600, 400)), "the hoof pick stays under the finger")
	_session.call("set_tool", 0)

	# One finger paints; a second finger takes over as an orbit and pinch.
	_touch.feed_touch(10, Vector2(600, 300), true)
	_check(_touch.is_painting(), "one finger starts a paint stroke")
	_touch.feed_touch(11, Vector2(700, 300), true)
	_check(not _touch.is_painting(), "a second finger stops painting")

	var yaw: float = _session.get("_yaw")
	var distance: float = _session.get("_distance")
	_touch.feed_drag(10, Vector2(620, 300), Vector2(20, 0))
	_touch.feed_drag(11, Vector2(720, 300), Vector2(20, 0))
	await _frames(2)
	_check(not is_equal_approx(float(_session.get("_yaw")), yaw), "two-finger drag orbits the groom camera")
	_check(is_equal_approx(float(_session.get("_distance")), distance),
		"orbiting with a steady gap does not zoom the camera")

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


func _check_simultaneous_thumbs() -> void:
	# The reported problem: moving right with the left thumb while the right
	# thumb turns the camera.  Both fingers must keep their own job and the
	# stick must not so much as flinch.
	_touch.feed_touch(40, Vector2(200, 500), true)
	_touch.feed_drag(40, Vector2(280, 500), Vector2(80, 0))
	await _frames(2)
	var steering: Vector2 = _touch.get_move_input()
	_check(steering.x > 0.5 and absf(steering.y) < 0.05, "the stick holds a rightward push")
	_touch.feed_touch(41, Vector2(960, 320), true)
	for i in range(6):
		_touch.feed_drag(41, Vector2(970 + i * 10, 320), Vector2(10, 0))
	await _frames(2)
	_check(_touch.get_move_input().is_equal_approx(steering), "a look drag leaves the stick push untouched")
	_check(int(_touch._stick_index) == 40, "a right-hand drag cannot steal the stick")
	_touch.feed_touch(41, Vector2(1020, 320), false)
	_touch.feed_touch(40, Vector2(280, 500), false)
	await _frames(2)


# --- Helpers ----------------------------------------------------------------

## Window-space point for a viewport-space position.  The viewport maps an
## OS touch into canvas coordinates with the inverse of its final transform, so a
## test that parses its own event has to apply that transform forward first - the
## same trip a phone's touch makes before _input() sees it.
func _window_point(pos: Vector2) -> Vector2:
	return get_root().get_final_transform() * pos


func _touch_event(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	return event


func _drag_event(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	return event


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
