extends SceneTree

## End-to-end grooming check.
##
##   godot --headless --path . --script res://tools/check_groom.gd
##
## Covers the player-facing path rather than just the surface API: stand at the
## bay, press G, paint through the session's camera ray, clear the hooves,
## finish, leave, and verify every piece of restored state.  A second visit
## verifies that a clean horse cannot farm trust.

var _failures: Array[String] = []
var _world: Node3D
var _horse: Node3D
var _player: Node3D
var _bay: Node
var _session
var _surface
var _normal_hud: CanvasLayer
var _groom_hud
var _player_camera: Camera3D
var _player_model: Node3D


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("GROOMING CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("GROOMING CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	_world = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	await process_frame
	_horse = _world.get_node_or_null("Horse")
	_player = _world.get_node_or_null("Player")
	_bay = _world.get_node_or_null("GroomingBay")
	_check(_horse != null and _player != null and _bay != null, "main scene nodes")
	if _horse == null or _player == null or _bay == null:
		return
	_session = _bay.get_node_or_null("Session")
	_surface = _horse.get("groom_surface")
	_player_camera = _player.get("camera") as Camera3D
	_player_model = _player.get("model") as Node3D
	_normal_hud = _bar_hud()
	_check(_session != null and _surface != null and _player_camera != null, "session surface and camera")
	if _session == null or _surface == null or _player_camera == null:
		return
	_groom_hud = _session.get("_hud")

	# The surface bake is deferred one beat so it stays out of the handoff.
	for i in range(120):
		await process_frame
		if float(_surface.get("last_bake_ms")) > 0.0:
			break
	_check(float(_surface.get("last_bake_ms")) > 0.0, "coat mask baked")
	_check(int(_surface.call("get_groomable_count")) > 0, "groomable texels exist")
	_check(int(_surface.get("picker").triangle_count) > 0, "picker triangles built")
	_check(float(_surface.get("last_bake_ms")) < 4000.0, "bake stays under four seconds")

	var horse_anchor := _bay.get_node("HorseAnchor") as Marker3D
	var groomer_anchor := _bay.get_node("GroomerAnchor") as Marker3D
	_player.global_position = groomer_anchor.global_position
	_horse.global_position = horse_anchor.global_position
	for i in range(3):
		await process_frame

	# The bay's own prompt and G action are the player-facing door.
	_bay.call("_process", 0.2)
	_check(bool(_bay.get("_can_groom")), "bay reports a valid grooming spot")
	var prompt := _bay.get("_prompt") as Label3D
	_check(prompt != null and prompt.visible and prompt.text == "G  ·  GROOM", "bay prompt")
	_send_groom()
	for i in range(8):
		await process_frame
	_check(bool(_session.get("active")), "G starts the session")
	_check(bool(_horse.get("grooming")), "horse is frozen for grooming")
	_check(not bool(_player.get("controls_enabled")), "player controls are frozen")
	_check(_player_model != null and not _player_model.visible, "player model hidden")
	_check(_normal_hud != null and not _normal_hud.visible, "gameplay HUD hidden")
	_check(_player_camera != null and not _player_camera.current, "player camera released")
	_check(bool(_session.get("_camera").current), "groom camera current")
	_check(_horse.get("tack") != null and not (_horse.get("tack") as Node3D).visible, "tack hidden")
	_check(_player.global_position.distance_to(groomer_anchor.global_position) < 0.2, "player moved to groomer anchor")

	var camera: Camera3D = _session.call("get_camera")
	var target: Vector3 = _horse.global_position + Vector3(0, 1.05, 0)
	var hit: Dictionary = _surface.call("pick_ray", camera.global_position, (target - camera.global_position).normalized())
	_check(not hit.is_empty(), "camera ray picks the horse")
	if hit.is_empty():
		return
	_check(int(hit.get("zone", 0)) == 1, "camera ray lands on the coat")
	_check(int(hit.get("island", -1)) >= 0, "picker reports a UV island")

	# The face brush must not touch the body, and soft polish needs clean coat.
	var soft_early: Dictionary = _surface.call("paint_hit", hit, "soft")
	_check(not bool(soft_early.get("ok", true)) and soft_early.get("reason", "") == "dirty", "soft brush rejects dirty coat")
	var face_on_body: Dictionary = _surface.call("paint_hit", hit, "face")
	_check(not bool(face_on_body.get("ok", true)) and face_on_body.get("reason", "") == "zone", "face brush rejects the body")
	var face_uv: Vector2 = _surface.call("find_uv_for_zone", 3)
	_check(face_uv.x >= 0.0, "face zone has a UV")
	_check(not bool(_surface.call("paint_uv", face_uv, 3, -1, "dandy", 0.1)), "dandy brush rejects the face")

	var curry: Dictionary = _surface.call("paint_hit", hit, "curry")
	_check(bool(curry.get("ok", false)), "curry paints the coat")
	_check(float(_surface.call("get_mask_value", hit["uv"], "loosen")) > 0.5, "curry loosens dirt")
	var dandy: Dictionary = _surface.call("paint_hit", hit, "dandy")
	_check(bool(dandy.get("ok", false)), "dandy paints the coat")
	_check(float(_surface.call("get_mask_value", hit["uv"], "clean")) > 0.8, "dandy lifts dirt")
	var soft: Dictionary = _surface.call("paint_hit", hit, "soft")
	_check(bool(soft.get("ok", false)), "soft brush polishes")
	_check(float(_surface.call("get_mask_value", hit["uv"], "polish")) > 0.4, "polish is recorded")
	var coverage_after: Dictionary = _surface.call("coverage")
	_check(float(coverage_after.get("clean", 0.0)) > 0.0, "coverage rises after brushing")

	# Mask view is a display mode only; it must not alter the mask.
	var clean_before_mask: float = float(_surface.call("get_mask_value", hit["uv"], "clean"))
	_session.call("_on_mask_toggled", true)
	await process_frame
	var material := _surface.get("material") as ShaderMaterial
	_check(material != null and float(material.get_shader_parameter("mask_view")) > 0.5, "mask view enabled")
	var brush := _session.get("_brush") as Node3D
	_check(brush != null and not brush.visible, "brush hidden in mask view")
	_session.call("_on_mask_toggled", false)
	_check(float(_surface.call("get_mask_value", hit["uv"], "clean")) == clean_before_mask, "mask view does not repaint")

	# The hoof pick is a pointer tool: clicking the mud clump in front of a hoof
	# has to clear that hoof through the same ray path as the mouse.
	_session.call("set_tool", 4)
	var clumps: Array = _session.get("_hoof_clumps")
	# Pick the clump nearest the camera; the far-side hooves are occluded by the
	# legs, so a click at their projected centre would correctly hit the near leg.
	var click_index := -1
	var click_distance := 1e9
	for i in range(clumps.size()):
		var clump = clumps[i]
		if clump == null:
			continue
		var d := camera.global_position.distance_to((clump as Node3D).global_position)
		if d < click_distance:
			click_distance = d
			click_index = i
	_check(click_index >= 0 and (clumps[click_index] as Node3D).visible, "hoof clump is visible with the pick")
	if click_index >= 0:
		var clump_screen: Vector2 = camera.unproject_position((clumps[click_index] as Node3D).global_position)
		_session.call("paint_at_screen", clump_screen)
		_check(bool(_horse.get("groomed_hooves")[click_index]), "hoof pick clears a hoof")
	for i in range(clumps.size()):
		if i != click_index:
			_check(bool(_session.call("mark_hoof", i)), "hoof %d cleared" % i)
	_check(int(_horse.get("hooves_cleaned")) == 4, "all four hooves counted")
	for clump in _session.get("_hoof_clumps"):
		_check(clump != null and not (clump as Node3D).visible, "cleared hoof clump hidden")

	# Fill the rest of the coat so the completion path can be exercised without
	# a two-minute brush sweep in a headless test.
	_surface.call("debug_fill", 1.0, 0.85)
	_session.call("_update_progress")
	_check(bool(_session.call("_is_complete")), "session reaches complete")
	var title := _groom_hud.get("_title_label") as Label
	_check(title != null and title.text == "GROOMING · COMPLETE", "HUD announces complete")

	_session.call("finish_grooming")
	var result: Dictionary = _session.call("get_result")
	_check(bool(result.get("complete", false)), "finish reports complete")
	_check(float(result.get("trust_gain", 0.0)) > 0.0, "completion pays trust")
	_check(bool(_session.get("finished")), "session is finished")
	_check(float(_surface.get("current_dirt_level")) <= 0.001, "completed horse is clean")
	var result_panel := _groom_hud.get("_result_panel") as PanelContainer
	_check(result_panel != null and result_panel.visible, "result panel visible")

	await _session.call("exit_session")
	await process_frame
	_check(not bool(_session.get("active")), "session inactive after exit")
	_check(not bool(_horse.get("grooming")), "horse leaves the grooming pose")
	_check(bool(_player.get("controls_enabled")), "player controls restored")
	_check(_player_model != null and _player_model.visible, "player model restored")
	_check(_normal_hud != null and _normal_hud.visible, "gameplay HUD restored")
	_check(_player_camera != null and _player_camera.current, "player camera restored")
	_check(not (_session.get("_camera") as Camera3D).current, "groom camera released")
	_check((_horse.get("tack") as Node3D).visible, "tack restored")
	_check(float(_horse.get("cleanliness")) >= 1.0, "horse cleanliness persisted")
	_check(int(_horse.get("hooves_cleaned")) == 4, "hoof state persisted")
	var trust_after: float = float(_horse.get("trust"))

	# A second visit on a clean horse must not pay again.
	_bay.call("_process", 0.2)
	_check(bool(_bay.get("_can_groom")), "bay is available again")
	_send_groom()
	await process_frame
	_check(bool(_session.get("active")), "second visit starts")
	_session.call("_update_progress")
	_check(bool(_session.call("_is_complete")), "clean horse is already complete")
	_session.call("finish_grooming")
	var second: Dictionary = _session.call("get_result")
	_check(float(second.get("trust_gain", 1.0)) == 0.0, "a second groom pays no extra trust")
	_check(is_equal_approx(float(_horse.get("trust")), trust_after), "trust unchanged on repeat")
	await _session.call("exit_session")
	await process_frame
	_check(not bool(_session.get("active")), "second visit exits cleanly")


func _send_groom() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	_bay.call("_unhandled_input", event)


func _bar_hud() -> CanvasLayer:
	return get_first_node_in_group("gameplay_hud") as CanvasLayer


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
