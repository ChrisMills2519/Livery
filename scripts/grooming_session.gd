extends Node

## Player-facing grooming session.
##
## The session owns the orbit camera, the brush and the grooming HUD.  It
## freezes the horse (through Horse.begin_grooming), hides the normal HUD and
## player model, routes pointer rays into GroomSurface, and restores every
## saved piece of state on exit.

const GroomingHUD := preload("res://scripts/grooming_hud.gd")
const TOOL_IDS := ["curry", "dandy", "soft", "face", "hoof"]
const TOOL_COLORS := {
	"curry": Color(0.86, 0.46, 0.30, 1.0),
	"dandy": Color(0.90, 0.72, 0.42, 1.0),
	"soft": Color(0.94, 0.89, 0.76, 1.0),
	"face": Color(0.90, 0.78, 0.90, 1.0),
	"hoof": Color(0.72, 0.76, 0.78, 1.0),
}
const HOOF_BONES := ["L Finger0", "R Finger0", "L Toe0", "R Toe0"]
const COMPLETE_CLEAN := 0.90
const COMPLETE_POLISH := 0.55

var active := false
var finished := false

var _horse: Node3D
var _player: Node3D
var _surface
var _hud
var _bay: Node
var _normal_hud: CanvasLayer

var _camera: Camera3D
var _brush: Node3D
var _brush_head_material: StandardMaterial3D
var _brush_rest := Vector3(0.34, -0.23, -0.82)
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _dust: CPUParticles3D
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_tween: Tween

var _hoof_clumps: Array = []
var _hooves := [false, false, false, false]
var _tool_index := 0
var _mask_active := false
var _painting := false
var _orbiting := false
var _yaw := 1.60
var _pitch := 0.16
var _distance := 4.25
var _target := Vector3.ZERO
var _last_paint_pos := Vector3.ZERO
var _has_last_paint := false
var _hint_cooldown := 0.0
var _progress_accum := 0.0
var _clean := 0.0
var _polish := 0.0
var _complete_announced := false
var _finished := false
var _exit_in_progress := false
var _result := {}

var _saved_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _saved_controls := true
var _saved_model_visible := true
var _saved_hud_visible := true
var _saved_camera_current := true
var _saved_course_visible := true


func _ready() -> void:
	_bay = get_parent()
	_build_nodes()
	set_process(false)
	set_process_unhandled_input(false)


func _build_nodes() -> void:
	_camera = Camera3D.new()
	_camera.name = "GroomCamera"
	_camera.fov = 38.0
	_camera.near = 0.05
	_camera.far = 45.0
	_camera.current = false
	add_child(_camera)
	_build_brush()
	_build_ring()
	_build_dust()

	_hud = GroomingHUD.new()
	add_child(_hud)
	_hud.visible = false
	_hud.tool_selected.connect(_set_tool)
	_hud.finish_requested.connect(_on_finish_requested)
	_hud.return_requested.connect(_on_return_requested)
	_hud.mask_toggled.connect(_on_mask_toggled)

	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 40
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)


func _build_brush() -> void:
	_brush = Node3D.new()
	_brush.name = "Brush"
	_brush.position = _brush_rest
	_brush.rotation_degrees = Vector3(-14, -22, 18)
	_brush.scale = Vector3.ONE * 0.62
	_brush.visible = false
	_camera.add_child(_brush)

	var handle := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.009
	cylinder.bottom_radius = 0.013
	cylinder.height = 0.27
	cylinder.radial_segments = 10
	handle.mesh = cylinder
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.25, 0.12, 1.0)
	wood.roughness = 0.85
	handle.material_override = wood
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush.add_child(handle)

	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.115, 0.045, 0.045)
	head.mesh = box
	head.position = Vector3(0, 0.155, 0)
	_brush_head_material = StandardMaterial3D.new()
	_brush_head_material.albedo_color = TOOL_COLORS["curry"].darkened(0.18)
	_brush_head_material.roughness = 0.95
	head.material_override = _brush_head_material
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush.add_child(head)

	var bristles := MeshInstance3D.new()
	var bristle_mesh := BoxMesh.new()
	bristle_mesh.size = Vector3(0.125, 0.032, 0.052)
	bristles.mesh = bristle_mesh
	bristles.position = Vector3(0, 0.122, 0)
	var bristle_material := StandardMaterial3D.new()
	bristle_material.albedo_color = Color(0.24, 0.19, 0.13, 1.0)
	bristle_material.roughness = 1.0
	bristles.material_override = bristle_material
	bristles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush.add_child(bristles)


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "BrushRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.095
	torus.outer_radius = 0.108
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_color = Color(0.86, 0.46, 0.30, 0.9)
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 8
	_dust.lifetime = 0.55
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.direction = Vector3.UP
	_dust.spread = 55.0
	_dust.gravity = Vector3(0, -3.0, 0)
	_dust.initial_velocity_min = 0.25
	_dust.initial_velocity_max = 0.75
	_dust.scale_amount_min = 0.7
	_dust.scale_amount_max = 1.25
	_dust.local_coords = false
	_dust.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_material.albedo_color = Color(0.38, 0.30, 0.20, 0.72)
	quad.material = dust_material
	_dust.mesh = quad
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)


## Enter the bay.  The bay supplies both anchors so a test or a future second
## yard can reuse the same session without editing transform constants.
func enter(horse_anchor: Transform3D, groomer_anchor: Transform3D) -> bool:
	if active or _exit_in_progress:
		return false
	if _hud == null:
		return false
	_horse = get_tree().get_first_node_in_group("horse") as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _horse == null or _player == null:
		return false
	if bool(_player.get("mounted")):
		return false
	_surface = _horse.get("groom_surface")
	if _surface == null:
		return false
	if not bool(_horse.call("begin_grooming", horse_anchor)):
		return false

	_saved_mouse_mode = Input.mouse_mode
	_saved_controls = bool(_player.get("controls_enabled"))
	var player_camera := _player.get("camera") as Camera3D
	_saved_camera_current = player_camera != null and player_camera.current
	var player_model := _player.get("model") as Node3D
	_saved_model_visible = player_model == null or player_model.visible
	_normal_hud = get_tree().get_first_node_in_group("gameplay_hud") as CanvasLayer
	_saved_hud_visible = _normal_hud == null or _normal_hud.visible
	var course := get_tree().get_first_node_in_group("riding_course") as Node3D
	if course != null:
		_saved_course_visible = course.visible
		course.visible = false

	_player.set("controls_enabled", false)
	_player.set("velocity", Vector3.ZERO)
	_player.global_position = groomer_anchor.origin + Vector3(0, 0.03, 0)
	_player.look_at(Vector3(horse_anchor.origin.x, _player.global_position.y, horse_anchor.origin.z), Vector3.UP)
	if player_model != null:
		player_model.visible = false
	if player_camera != null:
		player_camera.current = false
	if _normal_hud != null:
		_normal_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _bay != null and _bay.has_method("set_session_active"):
		_bay.call("set_session_active", true)

	var hooves_state = _horse.get("groomed_hooves")
	if hooves_state is Array:
		_hooves = hooves_state.duplicate()
	_build_hoof_clumps()
	_hud.reset_for_session()
	_hud.visible = true
	_hud.set_tool(0)
	_hud.set_mask_active(false)
	_hud.set_progress(0.0, 0.0, _count_hooves())
	_hud.set_complete(false)

	_tool_index = 0
	_mask_active = false
	_finished = false
	finished = false
	_complete_announced = false
	_painting = false
	_orbiting = false
	_has_last_paint = false
	_clean = 0.0
	_polish = 0.0
	_result = {}
	_hint_cooldown = 0.0
	_progress_accum = 0.0
	_surface.call("set_mask_view", false)
	_surface.call("set_dirt_level", _surface.get("current_dirt_level"))
	_brush.visible = true
	_ring.visible = false
	_dust.emitting = false
	_update_tool_visuals()

	_camera.current = true
	_update_camera()
	active = true
	set_process(true)
	set_process_unhandled_input(true)

	_fade.color.a = 1.0
	_fade_to(0.0, 0.35)
	_update_progress()
	_hud.show_toast("Curry first, then dandy, then polish. Take your time.", 3.0)
	return true


func exit_session() -> void:
	if not active or _exit_in_progress:
		return
	_exit_in_progress = true
	if not _finished:
		finish_grooming()
	_painting = false
	_orbiting = false
	_ring.visible = false
	_brush.visible = false
	_fade_to(1.0, 0.20)
	await get_tree().create_timer(0.22).timeout

	if _camera != null:
		_camera.current = false
	var player_camera: Camera3D = null
	var player_model: Node3D = null
	if _player != null:
		player_camera = _player.get("camera") as Camera3D
		player_model = _player.get("model") as Node3D
	if player_camera != null:
		player_camera.current = _saved_camera_current
	if player_model != null:
		player_model.visible = _saved_model_visible
	if _player != null:
		_player.set("controls_enabled", _saved_controls)
	if _normal_hud != null:
		_normal_hud.visible = _saved_hud_visible
	var course := get_tree().get_first_node_in_group("riding_course") as Node3D
	if course != null:
		course.visible = _saved_course_visible
	Input.mouse_mode = _saved_mouse_mode
	_hud.visible = false
	if _horse != null:
		_horse.call("end_grooming")
	_clear_hoof_clumps()
	if _bay != null and _bay.has_method("set_session_active"):
		_bay.call("set_session_active", false)
	active = false
	set_process(false)
	set_process_unhandled_input(false)
	_fade_to(0.0, 0.28)
	_exit_in_progress = false


func _process(delta: float) -> void:
	if not active:
		return
	_update_camera()
	_hint_cooldown = maxf(0.0, _hint_cooldown - delta)
	if not _finished:
		if _painting and not _hud.is_pointer_over_ui():
			_paint_at_screen(get_viewport().get_mouse_position())
		elif not _painting:
			_update_cursor(get_viewport().get_mouse_position())
	_update_brush(delta)
	_progress_accum += delta
	if _progress_accum > 0.18:
		_progress_accum = 0.0
		_update_progress()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_set_tool(0)
				return
			KEY_2:
				_set_tool(1)
				return
			KEY_3:
				_set_tool(2)
				return
			KEY_4:
				_set_tool(3)
				return
			KEY_5:
				_set_tool(4)
				return
			KEY_TAB:
				_on_mask_toggled(not _mask_active)
				return
			KEY_ESCAPE:
				if _finished:
					exit_session()
				else:
					finish_grooming()
				return
	if _finished:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_painting = event.pressed
				if event.pressed:
					_has_last_paint = false
					if not _hud.is_pointer_over_ui():
						_paint_at_screen(event.position)
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = maxf(2.6, _distance - 0.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = minf(6.0, _distance + 0.25)
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.006
			_pitch = clampf(_pitch + event.relative.y * 0.004, -0.05, 0.75)
			_update_camera()
		elif _painting:
			if not _hud.is_pointer_over_ui():
				_paint_at_screen(event.position)
		else:
			_update_cursor(event.position)


func _set_tool(index: int) -> void:
	if index < 0 or index >= TOOL_IDS.size():
		return
	var changed := _tool_index != index
	_tool_index = index
	if _hud != null:
		_hud.set_tool(index)
	_update_tool_visuals()
	if changed and active and _tool_id() == "hoof":
		_hud.show_toast("Pick each muddy hoof — four in all.", 1.8)


func _tool_id() -> String:
	return TOOL_IDS[clampi(_tool_index, 0, TOOL_IDS.size() - 1)]


func _update_tool_visuals() -> void:
	if _brush_head_material != null:
		_brush_head_material.albedo_color = TOOL_COLORS[_tool_id()].darkened(0.18)
	if _ring_material != null:
		var c: Color = TOOL_COLORS[_tool_id()]
		_ring_material.albedo_color = Color(c.r, c.g, c.b, 0.9)
	# The mud clumps only matter to the hoof pick.  Showing them all the time
	# made the bay look like the horse had dropped four stones on the mat.
	for i in range(_hoof_clumps.size()):
		var clump = _hoof_clumps[i]
		if clump != null and is_instance_valid(clump):
			clump.visible = _tool_id() == "hoof" and not bool(_hooves[i])


func _update_camera() -> void:
	if _horse == null or _camera == null:
		return
	_target = _horse.global_position + Vector3(0, 1.02, -0.12)
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	var desired := _target + offset
	var query := PhysicsRayQueryParameters3D.create(_target, desired)
	var excluded: Array[RID] = []
	var horse_body := _horse as CollisionObject3D
	if horse_body != null:
		excluded.append(horse_body.get_rid())
	if _player != null:
		var player_body := _player as CollisionObject3D
		if player_body != null:
			excluded.append(player_body.get_rid())
	query.exclude = excluded
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var inward := (_target - desired).normalized()
		desired = hit["position"] - inward * 0.22
	_camera.global_position = desired
	_camera.look_at(_target, Vector3.UP)


func _pick(screen_pos: Vector2) -> Dictionary:
	if _surface == null or _camera == null:
		return {}
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	var result = _surface.call("pick_ray", origin, direction)
	if result is Dictionary:
		return result
	return {}


func _update_cursor(screen_pos: Vector2) -> void:
	if _finished:
		_ring.visible = false
		return
	if _hud != null and _hud.is_pointer_over_ui():
		_ring.visible = false
		return
	var hit := _pick(screen_pos)
	if hit.is_empty():
		_ring.visible = false
		return
	_update_ring(hit)


func _update_ring(hit: Dictionary) -> void:
	if _ring == null or hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var y := normal.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var radius := 0.13
	if _surface != null and _surface.has_method("brush_world_radius"):
		radius = _surface.call("brush_world_radius", _tool_id())
	var scale := maxf(0.25, radius / 0.1)
	var basis := Basis(x, y, z).scaled(Vector3.ONE * scale)
	var position: Vector3 = hit.get("position", Vector3.ZERO) + normal * 0.006
	_ring.global_transform = Transform3D(basis, position)
	_ring.visible = true


func _paint_at_screen(screen_pos: Vector2) -> bool:
	if not active or _finished:
		return false
	if _hud != null and _hud.is_pointer_over_ui():
		return false
	var hit := _pick(screen_pos)
	if _tool_id() == "hoof":
		# The clump sits in front of the hoof and can project just past the
		# little hoof mesh, so give the visible clump its own screen-space hit
		# test.  Otherwise a player clicking the mud ball itself would miss.
		var clump_index := _clump_at_screen(screen_pos)
		if clump_index >= 0:
			mark_hoof(clump_index)
			return false
		if hit.is_empty():
			_ring.visible = false
			return false
		_update_ring(hit)
		_try_hoof_pick(hit)
		return false
	if hit.is_empty():
		_ring.visible = false
		return false
	_update_ring(hit)
	if _has_last_paint and _last_paint_pos.distance_to(hit.get("position", Vector3.ZERO)) < 0.010:
		return false
	var result = _surface.call("paint_hit", hit, _tool_id())
	if result is Dictionary and bool(result.get("ok", false)):
		_has_last_paint = true
		_last_paint_pos = hit.get("position", Vector3.ZERO)
		_emit_dust(_last_paint_pos)
		return true
	if result is Dictionary:
		_show_hint(String(result.get("reason", "zone")), int(result.get("zone", 0)))
	return false


func _clump_at_screen(screen_pos: Vector2) -> int:
	if _camera == null:
		return -1
	var best := -1
	var best_distance := 30.0
	for i in range(_hoof_clumps.size()):
		if i >= _hooves.size() or _hooves[i]:
			continue
		var clump = _hoof_clumps[i]
		if clump == null or not is_instance_valid(clump) or not (clump as Node3D).visible:
			continue
		var point := (clump as Node3D).global_position
		if _camera.is_position_behind(point):
			continue
		var screen := _camera.unproject_position(point)
		var distance := screen.distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _try_hoof_pick(hit: Dictionary) -> void:
	var zone := int(hit.get("zone", 0))
	if zone != 2 and zone != 4:
		_show_hint("zone", zone)
		return
	var position: Vector3 = hit.get("position", Vector3.ZERO)
	var best := -1
	var best_distance := 0.42
	for i in range(4):
		if _hooves[i]:
			continue
		var clump = _hoof_clumps[i] if i < _hoof_clumps.size() else null
		if clump == null:
			continue
		var d := (clump as Node3D).global_position.distance_to(position)
		if d < best_distance:
			best_distance = d
			best = i
	if best < 0:
		_show_hint("zone", zone)
		return
	mark_hoof(best)


## Public so the headless check and future interactions can exercise the same
## path as the hoof pick without synthesising a pointer ray.
func mark_hoof(index: int) -> bool:
	if _horse == null or index < 0 or index >= 4:
		return false
	if not bool(_horse.call("mark_hoof", index)):
		return false
	_hooves[index] = true
	var clump = _hoof_clumps[index] if index < _hoof_clumps.size() else null
	if clump != null:
		_emit_dust((clump as Node3D).global_position)
		clump.visible = false
	_hud.set_progress(_clean, _polish, _count_hooves())
	_hud.show_toast("Hoof cleared. %d / 4" % _count_hooves(), 1.6)
	return true


func _count_hooves() -> int:
	var count := 0
	for done in _hooves:
		if done:
			count += 1
	return count


func _show_hint(reason: String, _zone: int) -> void:
	if _hud == null or _hint_cooldown > 0.0:
		return
	_hint_cooldown = 1.35
	var tool := _tool_id()
	var text := "Try another tool on this area."
	match reason:
		"dirty":
			text = "Brush the dirt away first — the soft brush only polishes clean coat."
		"hoof":
			text = "Aim the hoof pick at a muddy hoof."
		"zone":
			match tool:
				"curry":
					text = "The curry comb is for the body; use a brush on the legs and face."
				"dandy":
					text = "Keep the dandy brush off the face."
				"soft":
					text = "The soft brush polishes the coat and legs; the face needs the face brush."
				"face":
					text = "The face brush only touches the face."
				"hoof":
					text = "Aim the hoof pick at a muddy hoof."
	_hud.show_toast(text, 1.7)


func _update_progress() -> void:
	if _surface == null or _hud == null:
		return
	var cov = _surface.call("coverage")
	if cov is Dictionary:
		_clean = float(cov.get("clean", 0.0))
		_polish = float(cov.get("polish", 0.0))
	var hooves := _count_hooves()
	_hud.set_progress(_clean, _polish, hooves)
	var complete := _is_complete()
	_hud.set_complete(complete)
	if complete and not _complete_announced:
		_complete_announced = true
		_hud.show_toast("Grooming complete — press Esc to finish.", 3.0)


func _is_complete() -> bool:
	return _clean >= COMPLETE_CLEAN and _polish >= COMPLETE_POLISH and _count_hooves() == 4


func finish_grooming() -> void:
	if not active or _finished:
		return
	_update_progress()
	var hooves := _count_hooves()
	var complete := _is_complete()
	var result = _horse.call("apply_grooming_result", _clean, _polish, hooves, complete)
	if result is Dictionary:
		_result = result
	else:
		_result = {"clean": _clean, "polish": _polish, "hooves": hooves, "complete": complete}
	_finished = true
	finished = true
	_painting = false
	_ring.visible = false
	_brush.visible = false
	_mask_active = false
	if _surface != null:
		_surface.call("set_mask_view", false)
	_hud.set_mask_active(false)
	_hud.show_result(_result)


func _on_finish_requested() -> void:
	finish_grooming()


func _on_return_requested() -> void:
	exit_session()


func _on_mask_toggled(enabled: bool) -> void:
	_mask_active = enabled
	if _surface != null:
		_surface.call("set_mask_view", enabled)
	if _hud != null:
		_hud.set_mask_active(enabled)
	if _brush != null:
		_brush.visible = not enabled and not _finished
	if enabled and _ring != null:
		_ring.visible = false


func _emit_dust(position: Vector3) -> void:
	if _dust == null:
		return
	_dust.global_position = position
	_dust.restart()
	_dust.emitting = true


func _update_brush(_delta: float) -> void:
	if _brush == null or not _brush.visible:
		return
	var bob := sin(Time.get_ticks_msec() * 0.004) * 0.004
	_brush.position = _brush_rest + Vector3(0, bob, 0)
	var rotation := _brush.rotation_degrees
	rotation.z = 18.0 + sin(Time.get_ticks_msec() * 0.003) * 1.5
	_brush.rotation_degrees = rotation


func _fade_to(alpha: float, duration: float) -> void:
	if _fade == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, duration)


func _build_hoof_clumps() -> void:
	_clear_hoof_clumps()
	var skeletons := _horse.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		for i in range(4):
			_hoof_clumps.append(null)
		return
	var skeleton := skeletons[0] as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var mud := StandardMaterial3D.new()
	mud.albedo_color = Color(0.30, 0.22, 0.14, 1.0)
	mud.roughness = 1.0
	for i in range(4):
		var bone := _find_bone_containing(skeleton, HOOF_BONES[i])
		if bone < 0:
			_hoof_clumps.append(null)
			continue
		var bone_pose := skeleton.get_bone_global_pose(bone)
		var position := skeleton.global_transform * bone_pose.origin
		var clump := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		sphere.radial_segments = 8
		sphere.rings = 4
		clump.mesh = sphere
		clump.material_override = mud
		clump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clump)
		clump.global_position = position + Vector3(0, 0.055, 0)
		clump.visible = _tool_id() == "hoof" and not bool(_hooves[i])
		_hoof_clumps.append(clump)


func _find_bone_containing(skeleton: Skeleton3D, part: String) -> int:
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).contains(part):
			return i
	return -1


func _clear_hoof_clumps() -> void:
	for clump in _hoof_clumps:
		if clump != null and is_instance_valid(clump):
			clump.queue_free()
	_hoof_clumps.clear()


## Helpers used by the headless checks and review screenshots.
func set_tool(index: int) -> void:
	_set_tool(index)


func paint_at_screen(screen_pos: Vector2) -> bool:
	return _paint_at_screen(screen_pos)


func get_result() -> Dictionary:
	return _result.duplicate()


func get_camera() -> Camera3D:
	return _camera
