extends Node

## The muck-out session: the bed at the middle bay, the pitchfork and the barrow.
##
## The bed's state is the player's progress, so it lives in `HorseState`; this
## node owns only the working view of it - a fixed camera at the bay, the heaps
## on the bed, the fork and the session HUD.  Following `grooming_session.gd`, it
## parks the player's own camera, hides the gameplay HUD and the player body, and
## restores every saved piece of state on exit, which is also where the work is
## recorded and saved.
##
## The bed is the apron at the mouth of the middle bay: the five bays sit inside
## the building's box collider, so the part of the stall a player can see and
## work from the yard is the apron in front of the opening.

const MuckHUD := preload("res://scripts/muck_hud.gd")

const BED_CENTRE := Vector3(-7.0, 0.0, -22.35)
const BED_HALF := Vector2(1.5, 0.75)
const BED_LAYER_Y := 0.012
const BED_FRESH := Color(0.70, 0.62, 0.43, 1.0)
const BED_SOILED := Color(0.26, 0.20, 0.12, 1.0)
## Heaps at a full bed.  Each heap is one scoop, so the chore is a dozen seconds
## of work rather than a bar to grind.
const CLUMP_COUNT := 8
## Heaps per row of the bed's grid, and how much of the bed the grid spans.
const GRID_COLUMNS := 4
const GRID_SPREAD := 0.82
const CLUMP_SEED := 20261026
## How close the scoop ray has to pass a heap's centre to pick it.
const CLUMP_PICK_RADIUS := 0.28
const MAX_PICK_DISTANCE := 9.0
## Fixed camera: the whole apron in frame with the bay behind it, so the bed is
## legible on a phone without any orbiting.
const CAMERA_POSITION := Vector3(-7.0, 2.0, -19.2)
const CAMERA_TARGET := Vector3(-7.0, 0.05, -22.35)
const FORK_POSITION := Vector3(0.30, -0.24, -0.72)
const FORK_ROTATION := Vector3(-16.0, -18.0, 14.0)
## Reward for a bed mucked from full to clean, paid against the mess that was
## there when the session started, so re-scooping a clean bed pays nothing.
const TRUST_PER_MUCK := 0.06
const HAPPINESS_PER_MUCK := 0.10
const SWING_TIME := 0.22

var active := false
var finished := false

var _horse: Node3D
var _player: Node3D
var _hud
var _normal_hud: CanvasLayer

var _camera: Camera3D
var _fork: Node3D
var _ring: MeshInstance3D
var _bed: MeshInstance3D
var _clump_root: Node3D
var _bed_material: StandardMaterial3D
var _clump_material: StandardMaterial3D
var _straw_material: StandardMaterial3D
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_tween: Tween

var _clumps: Array[Node3D] = []
var _clump_total := 0
var _muck_at_entry := 0.0
var _swing := 0.0
var _hint_cooldown := 0.0
var _exit_in_progress := false
var _result := {}

var _saved_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _saved_controls := true
var _saved_model_visible := true
var _saved_hud_visible := true
var _saved_camera_current := true
var _saved_course_visible := true


func _ready() -> void:
	_build_nodes()
	set_process(false)
	set_process_unhandled_input(false)


func _build_nodes() -> void:
	_camera = Camera3D.new()
	_camera.name = "MuckCamera"
	_camera.fov = 44.0
	_camera.near = 0.05
	_camera.far = 60.0
	_camera.current = false
	add_child(_camera)
	_build_fork()

	_bed_material = StandardMaterial3D.new()
	_bed_material.albedo_color = BED_SOILED
	_bed_material.roughness = 1.0
	_bed = MeshInstance3D.new()
	_bed.name = "Bed"
	var slab := BoxMesh.new()
	slab.size = Vector3(BED_HALF.x * 2.0, 0.02, BED_HALF.y * 2.0)
	_bed.mesh = slab
	_bed.material_override = _bed_material
	_bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bed.visible = false
	add_child(_bed)
	_bed.global_position = BED_CENTRE + Vector3(0.0, BED_LAYER_Y, 0.0)

	_clump_root = Node3D.new()
	_clump_root.name = "MuckHeaps"
	add_child(_clump_root)

	_clump_material = StandardMaterial3D.new()
	_clump_material.albedo_color = Color(0.25, 0.19, 0.12, 1.0)
	_clump_material.roughness = 0.95
	_straw_material = StandardMaterial3D.new()
	_straw_material.albedo_color = Color(0.72, 0.63, 0.42, 1.0)
	_straw_material.roughness = 1.0

	_build_ring()

	_hud = MuckHUD.new()
	add_child(_hud)
	_hud.visible = false
	_hud.finish_requested.connect(_on_finish_requested)
	_hud.return_requested.connect(_on_return_requested)

	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 40
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)


## The fork the player works with, held low in the frame like the grooming
## brush, so the camera reads as the player's own hands.
func _build_fork() -> void:
	_fork = Node3D.new()
	_fork.name = "Pitchfork"
	_fork.position = FORK_POSITION
	_fork.rotation_degrees = FORK_ROTATION
	_fork.scale = Vector3.ONE * 0.62
	_fork.visible = false
	_camera.add_child(_fork)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.27, 0.14, 1.0)
	wood.roughness = 0.85

	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.016
	shaft.height = 0.48
	shaft.radial_segments = 10
	handle.mesh = shaft
	handle.material_override = wood
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fork.add_child(handle)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var bar := BoxMesh.new()
	bar.size = Vector3(0.19, 0.026, 0.03)
	head.mesh = bar
	head.position = Vector3(0, 0.245, 0)
	head.material_override = wood
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fork.add_child(head)

	for offset in [-0.075, 0.0, 0.075]:
		var tine := MeshInstance3D.new()
		tine.name = "Tine"
		var spike := BoxMesh.new()
		spike.size = Vector3(0.014, 0.13, 0.014)
		tine.mesh = spike
		tine.position = Vector3(offset, 0.30, 0)
		tine.material_override = wood
		tine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fork.add_child(tine)


## Cursor for the heap under the pointer.  It reads at a glance on pale bedding,
## so it is an always-on-top rim rather than a thin coat-coloured outline.
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "ScoopRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.26
	torus.rings = 24
	torus.ring_segments = 8
	_ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 10
	material.albedo_color = Color(0.55, 1.0, 0.60, 0.95)
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


# --- session ----------------------------------------------------------------

## Starts the chore.  Refuses when the bed is clean, the player is mounted, the
## scene has no horse, or another care session already owns the player.
func enter() -> bool:
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
	if not HorseState.needs_mucking():
		return false
	if not bool(_horse.call("begin_mucking")):
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
	if player_model != null:
		player_model.visible = false
	# The player keeps processing while the session is up, and its own camera
	# rule would otherwise turn the body back on a frame later.
	_player.call("set_model_hidden", true)
	if player_camera != null:
		player_camera.current = false
	if _normal_hud != null:
		_normal_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The touch layer's "groom" mode is really "a session is up": strokes and
	# orbit, no stick and no cluster.  That is exactly what the muck-out needs,
	# so it is reused rather than duplicating the routing.
	TouchControls.set_mode("groom")

	_muck_at_entry = clampf(HorseState.stall_muck, 0.0, 1.0)
	finished = false
	_result = {}
	_swing = 0.0
	_hint_cooldown = 0.0
	_bed.visible = true
	_fork.visible = true
	_ring.visible = false
	_build_clumps()
	_write_muck()
	_hud.reset_for_session()
	_hud.visible = true
	_update_hud()

	_camera.current = true
	_update_camera()
	active = true
	set_process(true)
	set_process_unhandled_input(true)
	_fade.color.a = 1.0
	_fade_to(0.0, 0.30)
	_hud.show_toast("Scoop every heap into the barrow.", 3.0)
	return true


func exit_session() -> void:
	if not active or _exit_in_progress:
		return
	_exit_in_progress = true
	# Leaving early still keeps the work that was done: what was scooped is
	# recorded, and only the mess that was actually removed pays.
	if not finished:
		_finish_mucking()
	_ring.visible = false
	_fork.visible = false
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
	if _player != null:
		_player.call("set_model_hidden", false)
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
	TouchControls.set_mode("ride")
	_hud.visible = false
	if _horse != null:
		_horse.call("end_mucking")
	_bed.visible = false
	_clear_clumps()
	active = false
	set_process(false)
	set_process_unhandled_input(false)
	_fade_to(0.0, 0.28)
	# The bed's value changes without a signal of its own, so leaving is an
	# explicit save point: the horse is recorded first, then the slot is written.
	if _horse != null:
		HorseState.record_from(_horse)
	SaveGame.save_now("muck")
	_exit_in_progress = false


func _process(delta: float) -> void:
	if not active:
		return
	_swing = maxf(0.0, _swing - delta)
	_update_fork()
	if _hint_cooldown > 0.0:
		_hint_cooldown = maxf(0.0, _hint_cooldown - delta)
	if finished:
		_ring.visible = false
		return
	if Device.is_touch():
		_update_touch_gestures()
	else:
		_update_cursor(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if finished:
			exit_session()
		else:
			_finish_mucking()
		return
	if finished or Device.is_touch():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _hud.is_pointer_over_ui():
			get_viewport().set_input_as_handled()
			scoop_at_screen(button.position)


func _update_camera() -> void:
	if _camera == null:
		return
	_camera.global_position = CAMERA_POSITION
	_camera.look_at(CAMERA_TARGET, Vector3.UP)


func _update_fork() -> void:
	if _fork == null:
		return
	var swing := clampf(_swing / SWING_TIME, 0.0, 1.0)
	_fork.rotation_degrees = FORK_ROTATION + Vector3(-54.0 * swing, 0.0, -16.0 * swing)
	_fork.position = FORK_POSITION + Vector3(0.0, -0.04 * swing, -0.05 * swing)


func _on_finish_requested() -> void:
	if finished:
		exit_session()
	else:
		_finish_mucking()


func _on_return_requested() -> void:
	exit_session()


func _update_touch_gestures() -> void:
	# The heap is a big target, so touch scoops where the finger lands.  The
	# grooming brush lifts its point above the thumb because it paints
	# continuously; a scoop is a discrete tap and the lift would lie about it.
	_ring.visible = false
	if TouchControls.is_painting():
		scoop_at_screen(TouchControls.paint_position())


func _update_cursor(screen_position: Vector2) -> void:
	var index := clump_at_screen(screen_position)
	if index < 0:
		_ring.visible = false
		return
	_ring.global_position = _clumps[index].global_position + Vector3(0.0, 0.03, 0.0)
	_ring.visible = true


# --- the bed -----------------------------------------------------------------

## Heaps are laid out on a jittered grid rather than by rejection sampling: the
## bed holds eight at 0.6 m spacing, and a sampler with that exclusion radius
## quietly placed fewer than it was asked for, which is a bed that can never be
## cleared.  The count is what the bed's mess asks for, and every one of them is
## placed.
func _build_clumps() -> void:
	_clear_clumps()
	var count := clampi(int(round(CLUMP_COUNT * _muck_at_entry)), 1, CLUMP_COUNT)
	var rng := RandomNumberGenerator.new()
	rng.seed = CLUMP_SEED
	var rows := int(ceil(float(count) / float(GRID_COLUMNS)))
	for i in range(count):
		var column := i % GRID_COLUMNS
		var row := i / GRID_COLUMNS
		# Cell centres across the bed, then a few centimetres of jitter so the
		# grid does not read as a grid.
		var spot := Vector2(
			((float(column) + 0.5) / float(GRID_COLUMNS) - 0.5) * BED_HALF.x * 2.0 * GRID_SPREAD
				+ rng.randf_range(-0.05, 0.05),
			((float(row) + 0.5) / float(rows) - 0.5) * BED_HALF.y * 2.0 * GRID_SPREAD
				+ rng.randf_range(-0.04, 0.04)
		)
		_clumps.append(_make_clump(spot, rng))
	_clump_total = _clumps.size()


func _make_clump(spot: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "MuckHeap"
	_clump_root.add_child(root)
	root.global_position = BED_CENTRE + Vector3(spot.x, 0.09, spot.y)
	root.rotation.y = rng.randf_range(0.0, TAU)

	var heap := MeshInstance3D.new()
	heap.name = "Heap"
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.17
	sphere.radial_segments = 12
	sphere.rings = 6
	heap.mesh = sphere
	heap.material_override = _clump_material
	heap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(heap)

	for i in range(3):
		var straw := MeshInstance3D.new()
		straw.name = "Straw%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.012, 0.03)
		straw.mesh = box
		straw.position = Vector3(
			rng.randf_range(-0.12, 0.12), 0.075, rng.randf_range(-0.12, 0.12)
		)
		straw.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 180.0), rng.randf_range(-12.0, 12.0))
		straw.material_override = _straw_material
		straw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(straw)
	return root


func _clear_clumps() -> void:
	for clump in _clumps:
		if is_instance_valid(clump):
			clump.queue_free()
	_clumps.clear()
	_clump_total = 0


func _current_muck() -> float:
	if _clump_total <= 0:
		return _muck_at_entry
	return _muck_at_entry * float(_clumps.size()) / float(_clump_total)


## Mirrors the bed into the state owner and the horse, and repaints the bed, so
## a session that is left part-way through really is part-way through.
func _write_muck() -> void:
	var muck := clampf(_current_muck(), 0.0, 1.0)
	HorseState.set_stall_muck(muck)
	if _horse != null:
		_horse.set("stall_muck", muck)
	if _bed_material != null:
		_bed_material.albedo_color = BED_FRESH.lerp(BED_SOILED, muck)


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.set_progress(_current_muck(), _clump_total - _clumps.size(), _clump_total)


# --- picking -----------------------------------------------------------------

func clumps_remaining() -> int:
	return _clumps.size()


func clump_total() -> int:
	return _clump_total


func clump_position(index: int) -> Vector3:
	if index < 0 or index >= _clumps.size():
		return Vector3.ZERO
	return _clumps[index].global_position


## The nearest heap the ray through `screen_position` passes through, or -1.
func clump_at_screen(screen_position: Vector2) -> int:
	if _camera == null or _clumps.is_empty():
		return -1
	var from := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var best := -1
	var best_distance := 0.0
	for i in range(_clumps.size()):
		var clump := _clumps[i]
		if clump == null or not is_instance_valid(clump):
			continue
		var hit := _ray_sphere(from, direction, clump.global_position, CLUMP_PICK_RADIUS)
		if hit < 0.0 or hit > MAX_PICK_DISTANCE:
			continue
		if best < 0 or hit < best_distance:
			best = i
			best_distance = hit
	return best


## One scoop: the heap leaves the bed for the barrow.  Returns true when a heap
## was picked up, so a caller (or a check) can tell a scoop from a miss.
func scoop_at_screen(screen_position: Vector2) -> bool:
	if not active or finished:
		return false
	var index := clump_at_screen(screen_position)
	if index < 0:
		_hint("Nothing to pick up there.")
		return false
	var clump := _clumps[index]
	_clumps.remove_at(index)
	if is_instance_valid(clump):
		clump.queue_free()
	_swing = SWING_TIME
	_write_muck()
	_update_hud()
	_ring.visible = false
	if _clumps.is_empty():
		_finish_mucking()
	return true


func _hint(text: String) -> void:
	if _hint_cooldown > 0.0 or _hud == null:
		return
	_hint_cooldown = 1.0
	_hud.show_toast(text, 1.4)


## Payments are made against the mess that was in the bed at the start, so the
## same clean bed cannot be scooped for trust twice.
func _finish_mucking() -> void:
	if finished:
		return
	var cleaned := clampf(_muck_at_entry - _current_muck(), 0.0, 1.0)
	var trust_gain := 0.0
	var happiness_gain := 0.0
	if cleaned > 0.0 and _horse != null:
		trust_gain = TRUST_PER_MUCK * cleaned
		happiness_gain = HAPPINESS_PER_MUCK * cleaned
		_horse.set("trust", minf(1.0, float(_horse.get("trust")) + trust_gain))
		_horse.set("happiness", minf(1.0, float(_horse.get("happiness")) + happiness_gain))
	_result = {
		"cleaned": cleaned,
		"scoops": _clump_total - _clumps.size(),
		"total_scoops": _clump_total,
		"trust_gain": trust_gain,
		"happiness_gain": happiness_gain,
		"complete": _clumps.is_empty(),
	}
	finished = true
	if _hud != null:
		_hud.show_result(_result)


func _fade_to(target: float, seconds: float) -> void:
	if _fade == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", target, seconds)


## Ray against a sphere, returning the distance to the near hit or -1.
static func _ray_sphere(origin: Vector3, direction: Vector3, centre: Vector3, radius: float) -> float:
	var offset := origin - centre
	var b := offset.dot(direction)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var near := -b - root
	if near < 0.0:
		near = -b + root
	return near if near > 0.0 else -1.0
