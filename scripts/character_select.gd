extends Node3D

## Player-facing character select.
##
## The preview is a real 3D studio rather than a captured image: both bodies
## are instanced once, the inactive one is hidden, and the active body plays the
## shared humanoid Idle clip on a slowly rotating turntable.  Choosing a rider
## stores the profile in GameState and fades into main.tscn, where the player
## starts already mounted.

const HumanoidAnimation := preload("res://scripts/humanoid_animation.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const PROFILES := [
	preload("res://resources/characters/chris.tres"),
	preload("res://resources/characters/liv.tres"),
]
const BACKDROP_SHADER := preload("res://res/shaders/select_backdrop.gdshader")
const LiveryLogoButton := preload("res://scripts/livery_logo_button.gd")

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.74, 0.79, 0.71, 1.0)
const PANEL_WIDTH := 432.0
const AUTO_SPIN := 0.28

var _selected := 0
var _previews: Array[Dictionary] = []
var _turntable: Node3D
var _camera: Camera3D
var _ring_material: StandardMaterial3D
var _rim_light: OmniLight3D
var _brand_bar: ColorRect

var _role_label: Label
var _blurb_label: Label
var _index_label: Label
var _card_buttons: Array[Button] = []
var _start_button: Button

var _camera_target_position := Vector3.ZERO
var _camera_target_look := Vector3.ZERO
var _camera_look := Vector3.ZERO
var _spin_speed := AUTO_SPIN
var _dragging := false
var _starting := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TouchControls.set_mode("select")
	_build_environment()
	_build_stage()
	_build_previews()
	_build_ui()
	_select(_initial_index(), true)


func _process(delta: float) -> void:
	if _camera == null:
		return

	var blend := 1.0 - exp(-5.0 * delta)
	_camera.position = _camera.position.lerp(_camera_target_position, blend)
	_camera_look = _camera_look.lerp(_camera_target_look, blend)
	_camera.look_at(_camera_look, Vector3.UP)

	# A drag takes over from the turntable; letting go eases back into the
	# automatic presentation spin instead of snapping.
	if Device.is_touch():
		# Touch swipes come from the TouchControls layer; the emulated mouse only
		# follows the first finger, so it is not used here.
		_dragging = TouchControls.is_swiping()
		_turntable.rotation.y += TouchControls.consume_swipe() * 0.012
	elif _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	if _dragging:
		_spin_speed = 0.0
	else:
		_spin_speed = lerpf(_spin_speed, AUTO_SPIN, 1.0 - exp(-2.5 * delta))
		_turntable.rotation.y += _spin_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if Device.is_touch() and event is InputEventMouse:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_spin_speed = 0.0
		return
	if event is InputEventMouseMotion and _dragging:
		_turntable.rotation.y += event.relative.x * 0.012
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_select_previous()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_select_next()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_select(0)
		elif event.keycode == KEY_2:
			_select(1)
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_start_ride()


## Test/debug hook: the same environment variable that picks a body in the game
## also opens the select screen on that body.
func _initial_index() -> int:
	var requested := OS.get_environment("GROOM_CHARACTER").strip_edges().to_lower()
	for i in range(PROFILES.size()):
		if PROFILES[i].display_name.to_lower() == requested:
			return i
	if GameState.selected_character != null:
		var selected := PROFILES.find(GameState.selected_character)
		if selected >= 0:
			return selected
	return 0


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.10, 0.16, 0.13, 1.0)
	sky_material.sky_horizon_color = Color(0.42, 0.48, 0.38, 1.0)
	sky_material.sky_curve = 0.18
	sky_material.sky_energy_multiplier = 0.9
	sky_material.ground_bottom_color = Color(0.04, 0.06, 0.045, 1.0)
	sky_material.ground_horizon_color = Color(0.20, 0.24, 0.18, 1.0)
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 0.42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.03

	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	add_child(world)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 34.0
	_camera.near = 0.05
	_camera.far = 80.0
	_camera.current = true
	add_child(_camera)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(1.0, 0.93, 0.82, 1.0)
	key.light_energy = 1.55
	key.shadow_enabled = true
	key.shadow_blur = 1.4
	key.directional_shadow_max_distance = 20.0
	add_child(key)
	key.global_position = Vector3(-3.2, 4.2, 3.8)
	key.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.70, 0.84, 0.92, 1.0)
	fill.light_energy = 1.6
	fill.omni_range = 7.0
	fill.position = Vector3(2.4, 1.7, 3.0)
	add_child(fill)

	_rim_light = OmniLight3D.new()
	_rim_light.name = "RimLight"
	_rim_light.light_energy = 4.2
	_rim_light.omni_range = 8.0
	_rim_light.position = Vector3(2.2, 2.4, -2.4)
	add_child(_rim_light)


func _build_stage() -> void:
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.095, 0.085, 0.065, 1.0)
	floor_material.roughness = 0.88

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(60.0, 60.0)
	ground_mesh.material = floor_material
	ground.mesh = ground_mesh
	ground.position.y = -0.16
	add_child(ground)

	var plinth_material := StandardMaterial3D.new()
	plinth_material.albedo_color = Color(0.19, 0.17, 0.13, 1.0)
	plinth_material.roughness = 0.72
	plinth_material.metallic = 0.05

	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 1.55
	plinth_mesh.bottom_radius = 1.63
	plinth_mesh.height = 0.14
	plinth_mesh.radial_segments = 64
	plinth_mesh.material = plinth_material
	plinth.mesh = plinth_mesh
	plinth.position.y = -0.07
	add_child(plinth)

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = PROFILES[0].accent
	_ring_material.emission_enabled = true
	_ring_material.emission = PROFILES[0].accent
	_ring_material.emission_energy_multiplier = 1.4

	var ring := MeshInstance3D.new()
	ring.name = "AccentRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.28
	ring_mesh.outer_radius = 1.315
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 12
	ring_mesh.material = _ring_material
	ring.mesh = ring_mesh
	ring.position.y = 0.01
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = BACKDROP_SHADER
	var backdrop := MeshInstance3D.new()
	backdrop.name = "Backdrop"
	var backdrop_mesh := QuadMesh.new()
	backdrop_mesh.size = Vector2(22.0, 10.0)
	backdrop_mesh.material = backdrop_material
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0.0, 4.2, -6.5)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)


func _build_previews() -> void:
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	add_child(_turntable)

	for profile in PROFILES:
		var holder := Node3D.new()
		holder.name = profile.display_name + "Preview"
		_turntable.add_child(holder)

		var model := profile.scene.instantiate() as Node3D
		if model == null:
			push_error("CharacterSelect: %s has no model scene" % profile.display_name)
			continue
		model.name = "Model"
		model.rotation.y = deg_to_rad(profile.preview_yaw_degrees)
		model.scale = Vector3.ONE * profile.model_scale
		holder.add_child(model)

		# The GLB's embedded mixer is not authoritative; the shared humanoid
		# library is.  This mirrors the guard in player_controller.gd.
		for child in model.find_children("*", "AnimationPlayer", true, false):
			var embedded := child as AnimationPlayer
			embedded.stop()
			embedded.autoplay = ""
			if embedded.get_parent() != null:
				embedded.get_parent().remove_child(embedded)
			embedded.queue_free()

		var skeleton := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
		var animator := AnimationPlayer.new()
		animator.name = "PreviewIdle"
		holder.add_child(animator)
		animator.root_node = animator.get_path_to(model)
		var animated := HumanoidAnimation.rebind(animator, model, skeleton)
		if animated:
			animator.speed_scale = 0.85
			animator.play("humanoid/Idle")

		var bounds := _model_bounds(model)
		model.position.y -= float(bounds["min_y"])
		_previews.append({
			"profile": profile,
			"holder": holder,
			"model": model,
			"animator": animator,
			"height": float(bounds["height"]),
		})


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 5
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Legibility wash behind the copy.  It fades out to the right so the
	# studio and rider stay clean.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.015, 0.028, 0.020, 0.96),
		Color(0.015, 0.028, 0.020, 0.76),
		Color(0.015, 0.028, 0.020, 0.0),
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.5)
	gradient_texture.fill_to = Vector2(1.0, 0.5)
	gradient_texture.width = 256
	gradient_texture.height = 4
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.texture = gradient_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var left := VBoxContainer.new()
	left.name = "Copy"
	left.position = Vector2(64.0, 54.0)
	left.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	left.add_theme_constant_override("separation", 9)
	root.add_child(left)

	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	left.add_child(brand)

	_brand_bar = ColorRect.new()
	_brand_bar.custom_minimum_size = Vector2(4.0, 18.0)
	_brand_bar.color = PROFILES[0].accent
	_brand_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(_brand_bar)

	var brand_label := _label(brand, "GROOM   /   THE SCHOOLING YARD", 15, DIM_COLOR)
	brand_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var headline := _label(left, "Who rides today?", 48, TEXT_COLOR)
	headline.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	var subline := _label(
		left,
		"The same green horse, the same schooling round. Pick the seat that feels right.",
		16,
		DIM_COLOR
	)
	subline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subline.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(spacer)

	for i in range(PROFILES.size()):
		var profile: PlayerModelProfile = PROFILES[i]
		var card := Button.new()
		card.name = profile.display_name + "Card"
		card.text = "%s   ·   %s" % [profile.display_name, profile.role]
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size = Vector2(PANEL_WIDTH, 70.0)
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_theme_font_size_override("font_size", 20)
		card.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.01, 0.9))
		card.add_theme_constant_override("outline_size", 4)
		card.pressed.connect(_select.bind(i))
		left.add_child(card)
		_card_buttons.append(card)

	var selected_gap := Control.new()
	selected_gap.custom_minimum_size = Vector2(0.0, 4.0)
	selected_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(selected_gap)

	_role_label = _label(left, "", 14, PROFILES[0].accent)
	_blurb_label = _label(left, "", 16, DIM_COLOR)
	_blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_label.custom_minimum_size = Vector2(PANEL_WIDTH, 44.0)

	var start_gap := Control.new()
	start_gap.custom_minimum_size = Vector2(0.0, 8.0)
	start_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(start_gap)

	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "Ride out   ›"
	_start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_button.custom_minimum_size = Vector2(PANEL_WIDTH, 58.0)
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_start_button.add_theme_font_size_override("font_size", 22)
	_start_button.pressed.connect(_start_ride)
	left.add_child(_start_button)

	var hint := _label(
		left,
		Device.pick("A / D  or  ← / →   choose      ·      Enter   ride out      ·      drag   turn", "Swipe turn   ·   tap a rider   ·   tap Ride out"),
		14,
		DIM_COLOR
	)
	hint.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	_index_label = _label(root, "", 38, Color(0.92, 0.95, 0.84, 0.62))
	_index_label.anchor_left = 1.0
	_index_label.anchor_right = 1.0
	_index_label.offset_left = -280.0
	_index_label.offset_right = -64.0
	_index_label.offset_top = 78.0
	_index_label.offset_bottom = 142.0
	_index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var drag_hint := _label(root, Device.pick("DRAG TO TURN", "SWIPE TO TURN"), 14, Color(0.86, 0.90, 0.82, 0.58))
	drag_hint.anchor_left = 1.0
	drag_hint.anchor_right = 1.0
	drag_hint.anchor_top = 1.0
	drag_hint.anchor_bottom = 1.0
	drag_hint.offset_left = -260.0
	drag_hint.offset_right = -64.0
	drag_hint.offset_top = -52.0
	drag_hint.offset_bottom = -24.0
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var logo := LiveryLogoButton.new()
	logo.name = "LiveryLogoButton"
	root.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	logo.offset_left = -24.0 - LiveryLogoButton.BASE_SIZE.x
	logo.offset_right = -24.0
	logo.offset_top = 18.0
	logo.offset_bottom = 18.0 + LiveryLogoButton.BASE_SIZE.y



func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.01, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _select(index: int, initial := false) -> void:
	if _previews.is_empty():
		return
	_selected = wrapi(index, 0, _previews.size())
	var profile: PlayerModelProfile = _previews[_selected]["profile"]

	for i in range(_previews.size()):
		var preview: Dictionary = _previews[i]
		var active := i == _selected
		(preview["holder"] as Node3D).visible = active
		var animator: AnimationPlayer = preview["animator"]
		if active:
			if not animator.is_playing():
				animator.play("humanoid/Idle")
		else:
			animator.stop()

	_role_label.text = profile.role.to_upper()
	_role_label.add_theme_color_override("font_color", profile.accent)
	_blurb_label.text = profile.blurb
	_index_label.text = "%02d / %02d" % [_selected + 1, _previews.size()]
	_brand_bar.color = profile.accent

	_ring_material.albedo_color = profile.accent
	_ring_material.emission = profile.accent
	_rim_light.light_color = profile.accent.lerp(Color(0.78, 0.88, 0.96, 1.0), 0.35)

	for i in range(_card_buttons.size()):
		_style_card(_card_buttons[i], PROFILES[i], i == _selected)

	_update_camera(float(_previews[_selected]["height"]))
	if not initial:
		_turntable.rotation.y = -0.32
		_name_pulse()


func _style_card(card: Button, profile: PlayerModelProfile, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(16)
	normal.content_margin_left = 20
	normal.bg_color = Color(
		profile.accent.r * 0.10 + 0.03,
		profile.accent.g * 0.10 + 0.045,
		profile.accent.b * 0.10 + 0.035,
		0.92 if selected else 0.48
	)
	normal.border_color = profile.accent if selected else Color(0.58, 0.64, 0.54, 0.22)
	normal.set_border_width_all(1)
	normal.border_width_left = 4 if selected else 1

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(
		profile.accent.r * 0.16 + 0.035,
		profile.accent.g * 0.16 + 0.05,
		profile.accent.b * 0.16 + 0.04,
		0.98
	)
	hover.border_color = profile.accent

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = hover.bg_color.darkened(0.10)

	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", pressed)
	card.add_theme_color_override("font_color", TEXT_COLOR if selected else DIM_COLOR)
	card.add_theme_color_override("font_hover_color", TEXT_COLOR)
	card.add_theme_color_override("font_pressed_color", TEXT_COLOR)

	if selected:
		var start_normal := StyleBoxFlat.new()
		start_normal.set_corner_radius_all(10)
		start_normal.set_content_margin_all(14)
		start_normal.bg_color = profile.accent.darkened(0.35)
		start_normal.border_color = profile.accent
		start_normal.set_border_width_all(1)
		var start_hover := start_normal.duplicate() as StyleBoxFlat
		start_hover.bg_color = profile.accent.darkened(0.20)
		var start_pressed := start_hover.duplicate() as StyleBoxFlat
		start_pressed.bg_color = profile.accent.darkened(0.32)
		_start_button.add_theme_stylebox_override("normal", start_normal)
		_start_button.add_theme_stylebox_override("hover", start_hover)
		_start_button.add_theme_stylebox_override("pressed", start_pressed)
		_start_button.add_theme_color_override("font_color", Color(0.05, 0.07, 0.04, 1.0))
		_start_button.add_theme_color_override("font_hover_color", Color(0.03, 0.05, 0.02, 1.0))
		_start_button.add_theme_color_override("font_pressed_color", Color(0.03, 0.05, 0.02, 1.0))


func _name_pulse() -> void:
	_role_label.modulate.a = 0.0
	_blurb_label.modulate.a = 0.25
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_role_label, "modulate:a", 1.0, 0.22)
	tween.tween_property(_blurb_label, "modulate:a", 1.0, 0.30)


func _update_camera(height: float) -> void:
	var focus_y := maxf(height * 0.54, 0.75)
	var distance := maxf(2.8, height * 1.85 + 0.10)
	_camera_target_position = Vector3(0.0, focus_y + height * 0.08, distance)
	_camera_target_look = Vector3(-0.58, focus_y, 0.0)
	if _camera_look == Vector3.ZERO:
		_camera_look = _camera_target_look
		_camera.position = _camera_target_position
		_camera.look_at(_camera_look, Vector3.UP)


func _select_next() -> void:
	_select(_selected + 1)


func _select_previous() -> void:
	_select(_selected - 1)


## Stores the one-shot handoff state.  Kept separate from the transition so the
## headless check can verify exactly what main.tscn will receive.
func _commit_selection() -> void:
	GameState.choose_character(PROFILES[_selected], true)


func _start_ride() -> void:
	if _starting:
		return
	_starting = true
	_start_button.disabled = true
	for card in _card_buttons:
		card.disabled = true
	_commit_selection()

	var fade := get_node_or_null("/root/SceneFade")
	if fade != null and fade.has_method("change_scene"):
		fade.change_scene(MAIN_SCENE, 0.42)
	else:
		var err := get_tree().change_scene_to_file(MAIN_SCENE)
		if err != OK:
			push_error("CharacterSelect: cannot open the game (error %d)" % err)


func _model_bounds(model: Node3D) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var to_model := model.global_transform.affine_inverse()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for corner in [
			Vector3(box.position.x, box.position.y, box.position.z),
			Vector3(box.end.x, box.position.y, box.position.z),
			Vector3(box.position.x, box.end.y, box.position.z),
			Vector3(box.end.x, box.end.y, box.position.z),
			Vector3(box.position.x, box.position.y, box.end.z),
			Vector3(box.end.x, box.position.y, box.end.z),
			Vector3(box.position.x, box.end.y, box.end.z),
			Vector3(box.end.x, box.end.y, box.end.z),
		]:
			var point: Vector3 = to_model * (mesh_instance.global_transform * corner)
			lo = lo.min(point)
			hi = hi.max(point)
	return {"height": hi.y - lo.y, "min_y": lo.y}
