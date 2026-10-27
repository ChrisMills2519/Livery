extends SceneTree

## Headless verification for the painted terrain blend.
##
##   godot --headless --path . --script res://tools/check_terrain_blend.gd
##
## Checks the control map channels against the world layout, proves the RGB
## channels survive next to alpha=0, samples a coarse grid for malformed
## weights, and confirms the legacy overlay planes are gone.

const TERRAIN := "res://scenes/terrain.tscn"
const CONTROL_SIZE := 2048
const CONTROL_CENTER := Vector2(10.0, -5.0)
const CONTROL_EXTENT := Vector2(128.0, 128.0)

var _ok := true


func _initialize() -> void:
	print("=== TERRAIN BLEND CHECK ===")
	var packed := load(TERRAIN) as PackedScene
	if packed == null:
		_fail("cannot load terrain.tscn")
		_finish()
		return
	var terrain := packed.instantiate()
	_check_scene(terrain)
	var ground := terrain.get_node_or_null("GroundBlend") as MeshInstance3D
	if ground == null:
		_fail("GroundBlend missing")
		terrain.free()
		_finish()
		return
	var mat := ground.get_active_material(0) as ShaderMaterial
	if mat == null:
		_fail("GroundBlend has no ShaderMaterial")
		terrain.free()
		_finish()
		return
	var control := mat.get_shader_parameter("control_map") as Texture2D
	if control == null:
		_fail("control_map is not bound")
		terrain.free()
		_finish()
		return
	_check_control(control)
	terrain.free()
	_finish()


func _check_scene(terrain: Node) -> void:
	for legacy in ["StableYard", "Path", "TrainingGround", "Arena"]:
		if terrain.get_node_or_null(legacy) != null:
			_fail("legacy overlay node still exists: " + legacy)
	var ground := terrain.get_node_or_null("GroundBlend") as MeshInstance3D
	if ground == null:
		_fail("GroundBlend missing")
	elif not (ground.mesh is PlaneMesh):
		_fail("GroundBlend mesh is not a PlaneMesh")
	else:
		print("  OK: one GroundBlend plane, no overlay nodes")


func _check_control(control: Texture2D) -> void:
	if control.get_width() != CONTROL_SIZE or control.get_height() != CONTROL_SIZE:
		_fail("control map is %dx%d, expected %d" % [control.get_width(), control.get_height(), CONTROL_SIZE])
		return
	var image := control.get_image()
	if image == null:
		_fail("cannot read control map image")
		return
	print("  OK: control map %dx%d" % [image.get_width(), image.get_height()])

	_expect_dominant(image, "stable yard", Vector2(0.0, -22.0), 0)
	_expect_dominant(image, "lane", Vector2(0.0, 14.0), 1)
	_expect_dominant(image, "training ground", Vector2(35.0, 0.0), 2)
	_expect_dominant(image, "arena", Vector2(-32.5, 0.0), 3)
	_expect_dominant(image, "house drive", Vector2(30.0, -30.0), 0)

	var grass := _sample(image, Vector2(70.0, 40.0))
	if grass.r + grass.g + grass.b + grass.a > 0.02:
		_fail("grass sample is not empty: %s" % grass)
	else:
		print("  OK: grass remainder is empty")

	# The stable yard's east edge at x=16 must feather into grass rather than
	# cut at a right angle.
	var edge := _sample(image, Vector2(16.0, -19.0))
	if edge.r < 0.03 or edge.r > 0.95:
		_fail("yard edge is not a blend: R=%.2f" % edge.r)
	else:
		print("  OK: yard edge blends (R=%.2f)" % edge.r)

	# Painted dirt wear at the arena gate, where horses actually cross.
	var gate := _sample(image, Vector2(-15.0, -1.5))
	if gate.r < 0.15 or gate.a < 0.15:
		_fail("gate wear missing: %s" % gate)
	else:
		print("  OK: gate wear blends dirt %.2f into arena %.2f" % [gate.r, gate.a])

	# The lane ends on worn hardstanding at the showground gate: both the dirt
	# patch and the gravel have to be readable there.
	_expect_blend(image, "showground hardstanding", Vector2(1.5, 25.0), 0, 1, 0.3)

	# Coarse sweep for out-of-range weights and to confirm the map is mostly
	# grass rather than accidentally painted solid.
	var step := 16
	var grasses := 0
	var samples := 0
	var worst_total := 0.0
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			samples += 1
			var total := c.r + c.g + c.b + c.a
			worst_total = maxf(worst_total, total)
			if total < 0.01:
				grasses += 1
			for channel in [c.r, c.g, c.b, c.a]:
				if channel < -0.001 or channel > 1.001:
					_fail("control channel out of range at %d,%d" % [x, y])
					return
			if total > 1.01:
				_fail("control weights sum to %.2f at %d,%d" % [total, x, y])
				return
	var grass_fraction := float(grasses) / float(samples)
	print("  sampled %d points, grass %.0f%%, max weight sum %.2f" % [samples, grass_fraction * 100.0, worst_total])
	if grass_fraction < 0.5:
		_fail("control map is only %.0f%% grass; expected mostly grass" % (grass_fraction * 100.0))
	else:
		print("  OK: map is mostly grass")


func _expect_dominant(image: Image, label: String, world: Vector2, channel: int) -> void:
	var c := _sample(image, world)
	var values := [c.r, c.g, c.b, c.a]
	if values[channel] < 0.8:
		_fail("%s is not dominant in its channel: %s" % [label, c])
		return
	var others := 0.0
	for i in range(4):
		if i != channel:
			others += values[i]
	if others > 0.15:
		_fail("%s overlaps another layer: %s" % [label, c])
	else:
		print("  OK: %s (channel %d = %.2f)" % [label, channel, values[channel]])


func _expect_blend(image: Image, label: String, world: Vector2, channel_a: int, channel_b: int, minimum: float) -> void:
	var c := _sample(image, world)
	var values := [c.r, c.g, c.b, c.a]
	if values[channel_a] < minimum or values[channel_b] < minimum:
		_fail("%s is not a two-layer blend: %s" % [label, c])
		return
	print("  OK: %s blends %.2f / %.2f" % [label, values[channel_a], values[channel_b]])


func _sample(image: Image, world: Vector2) -> Color:
	var local := (world - (CONTROL_CENTER - CONTROL_EXTENT * 0.5)) / CONTROL_EXTENT
	var x := clampi(int(local.x * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(local.y * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


func _fail(message: String) -> void:
	_ok = false
	print("  FAIL: " + message)


func _finish() -> void:
	print("=== %s ===" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
