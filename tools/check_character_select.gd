extends SceneTree

## Headless verification for the character-select screen and its handoff.
##
##   godot --headless --path . --script res://tools/check_character_select.gd

const SELECT_SCENE := "res://scenes/character_select.tscn"
const CHRIS := preload("res://resources/characters/chris.tres")
const LIV := preload("res://resources/characters/liv.tres")

var _select: Node3D
var _game: Node
var _state := 0
var _state_ms := 0
var _start_ms := 0
var _spin_start := 0.0
var _failures: Array[String] = []


func _initialize() -> void:
	_game = root.get_node_or_null("GameState")
	_select = (load(SELECT_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_select)
	current_scene = _select
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	match _state:
		0:
			if now - _start_ms < 450:
				return false
			_check_initial()
			_spin_start = _select._turntable.rotation.y
			_state = 1
			_state_ms = now
		1:
			if now - _state_ms < 250:
				return false
			if is_equal_approx(_spin_start, _select._turntable.rotation.y):
				_fail("turntable is not rotating")
			else:
				print("  turntable spin: %.3f rad" % (
					_select._turntable.rotation.y - _spin_start
				))
			_select._unhandled_input(_key(KEY_RIGHT))
			_state = 2
			_state_ms = now
		2:
			if now - _state_ms < 250:
				return false
			_check_liv()
			_select._unhandled_input(_key(KEY_LEFT))
			_state = 3
			_state_ms = now
		3:
			if now - _state_ms < 200:
				return false
			_check_back_to_chris()
			_select._unhandled_input(_key(KEY_2))
			if _select._selected != 1:
				_fail("number key 2 did not select Liv")
			_select._commit_selection()
			_check_commit()
			_select._unhandled_input(_key(KEY_ENTER))
			if not _select._start_button.disabled:
				_fail("start button was not disabled during the transition")
			_state = 4
			_state_ms = now
		4:
			# The main scene now carries the grooming bay and its baked coat
			# mask, so the synchronous world load runs close to six seconds on
			# the test machine, and 18 s when the full check suite is running
			# beside it (measured 2026-10-26: 8 s standalone, 18 s under load).
			# The assertion here is the mounted player and a cleared fade, not a
			# stopwatch, so the window is generous and the cap below still
			# catches a genuine hang.
			if now - _state_ms > 25000:
				_fail("timed out waiting for the mounted handoff")
				_finish()
				return true
			var scene := current_scene
			if scene == null or scene.name != "Main":
				return false
			var player := scene.get_node_or_null("Player") as CharacterBody3D
			if player == null or not player.mounted:
				return false
			var fade := root.get_node_or_null("SceneFade")
			if fade == null:
				_fail("SceneFade autoload is missing")
				_finish()
				return true
			var cover := fade.get_node_or_null("Cover") as ColorRect
			if cover == null:
				_fail("fade cover is missing")
				_finish()
				return true
			# Do not accept a mounted state that is still behind the black
			# transition cover; the player has to be able to see the game.
			if cover.visible and cover.modulate.a > 0.02:
				return false
			_check_mounted(player)
			_finish()
			return true
	if now - _start_ms > 45000:
		_fail("timed out")
		_finish()
		return true
	return false


func _check_initial() -> void:
	if _select._previews.size() != 2:
		_fail("expected 2 previews, got %d" % _select._previews.size())
		return
	if _select._selected != 0:
		_fail("expected Chris to be selected on launch")
	var first: Dictionary = _select._previews[0]
	var second: Dictionary = _select._previews[1]
	if not (first["holder"] as Node3D).visible:
		_fail("Chris preview is hidden")
	if (second["holder"] as Node3D).visible:
		_fail("Liv preview is visible while Chris is selected")
	var animator: AnimationPlayer = first["animator"]
	if animator.current_animation != "humanoid/Idle" or not animator.is_playing():
		_fail("Chris preview is not playing humanoid/Idle")
	var skeleton := (first["model"] as Node3D).find_child(
		"GeneralSkeleton", true, false
	) as Skeleton3D
	if skeleton == null or skeleton.get_bone_count() != 52:
		_fail("Chris preview skeleton is missing or has the wrong bone count")
	var height := float(first["height"])
	if absf(height - 1.89) > 0.02:
		_fail("Chris preview height %.3f, expected 1.89" % height)
	if _select._camera == null or not _select._camera.current:
		_fail("preview camera is not current")
	if _select._start_button == null or not _select._start_button.text.contains("Ride"):
		_fail("start button is missing or unlabeled")
	if _select._card_buttons.size() != 2:
		_fail("expected two character cards")
	print("  initial: Chris visible, Idle playing, height=%.3f, cards=%d" % [
		height, _select._card_buttons.size()
	])


func _check_liv() -> void:
	if _select._selected != 1:
		_fail("select-next did not choose Liv")
		return
	var first: Dictionary = _select._previews[0]
	var second: Dictionary = _select._previews[1]
	if (first["holder"] as Node3D).visible:
		_fail("Chris preview is still visible")
	if not (second["holder"] as Node3D).visible:
		_fail("Liv preview is not visible")
	if not (second["animator"] as AnimationPlayer).is_playing():
		_fail("Liv preview is not playing")
	if not _select._role_label.text.contains("LIGHT SEAT"):
		_fail("role copy did not follow the selection")
	if not _select._blurb_label.text.contains("shortened leathers"):
		_fail("blurb copy did not follow the selection")
	if not _select._ring_material.emission.is_equal_approx(LIV.accent):
		_fail("accent ring did not follow the selection")
	print("  selected Liv: visible, copy updated, accent=%s" % _select._role_label.text)


func _check_back_to_chris() -> void:
	if _select._selected != 0:
		_fail("select-previous did not return to Chris")
	if not (_select._previews[0]["holder"] as Node3D).visible:
		_fail("Chris preview did not return")
	if not _select._role_label.text.contains("STEADY HAND"):
		_fail("role copy did not return to Chris")


func _check_commit() -> void:
	if _game == null:
		_fail("GameState autoload is missing")
		return
	if _game.selected_character != LIV:
		_fail("GameState did not receive the Liv profile")
	if not _game.auto_mount_on_start:
		_fail("GameState did not request the mounted start")
	print("  handoff queued: %s, mounted=%s" % [
		_game.selected_character.display_name, str(_game.auto_mount_on_start)
	])


func _check_mounted(player: CharacterBody3D) -> void:
	var horse := current_scene.get_node_or_null("Horse") as Node3D
	if horse == null:
		_fail("handoff scene has no horse")
		return
	var profile = player.character_profile
	if profile != LIV:
		_fail("handoff kept the wrong body: %s" % (
			profile.display_name if profile != null else "<none>"
		))
	if _game.auto_mount_on_start:
		_fail("auto-mount request was not consumed")
	if not player.controls_enabled:
		_fail("controls are still locked after the handoff")
	var contact := (player.get_node("SeatContact") as Marker3D).global_position
	var seat_err := contact.distance_to(horse.get_rider_seat_position())
	var skel := player.get_node("Model").find_child(
		"GeneralSkeleton", true, false
	) as Skeleton3D
	if skel == null or skel.get_bone_count() != 65:
		_fail("handoff mounted the wrong skeleton")
	if seat_err > 0.02:
		_fail("handoff seat error is %.3f m" % seat_err)
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	if camera == null or not camera.current:
		_fail("handoff did not hand the view to the riding camera")
	print("  mounted handoff: body=%s bones=%d seat_err=%.4f controls=%s" % [
		profile.display_name, skel.get_bone_count() if skel != null else -1,
		seat_err, str(player.controls_enabled)
	])


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nCHARACTER SELECT CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("\nCHARACTER SELECT CHECK: FAIL (%d)" % _failures.size())
		quit(1)
