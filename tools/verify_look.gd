extends SceneTree

## Verifies the textured materials and the daylight environment.
##
## Run with:
##     godot --headless --path . --script res://tools/verify_look.gd
##
## Exits non-zero when a material is missing its albedo/normal map, a texture
## import is VRAM-compressed, the sky/ambient/tonemap setup regressed, or the
## ground blend lost a layer.

const TEXTURE_DIR := "res://assets/textures/ground"
const TEXTURE_FILES := [
	"grass_albedo.jpg", "grass_normal.jpg",
	"dirt_albedo.jpg", "dirt_normal.jpg",
	"path_albedo.jpg", "path_normal.jpg",
	"sand_albedo.jpg", "sand_normal.jpg",
	"terrain_control.png",
]

const TERRAIN_SHADER := "res://res/shaders/terrain_blend.gdshader"
const LAYER_PARAMS := [
	"grass_albedo", "grass_normal",
	"dirt_albedo", "dirt_normal",
	"path_albedo", "path_normal",
	"sand_albedo", "sand_normal",
	"control_map",
]

var _ok := true


func _initialize() -> void:
	print("=== VERIFY LOOK ===")
	_check_texture_imports()
	_check_main_scene()
	_check_terrain()
	print("=== %s ===" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check_texture_imports() -> void:
	print("-- texture imports")
	for f in TEXTURE_FILES:
		var image_path := TEXTURE_DIR.path_join(f)
		if not FileAccess.file_exists(image_path):
			_fail("missing texture " + image_path)
			continue
		var import_path := image_path + ".import"
		if not FileAccess.file_exists(import_path):
			_fail("missing import file " + import_path)
			continue
		var ini := FileAccess.open(import_path, FileAccess.READ)
		if ini == null:
			_fail("cannot read " + import_path)
			continue
		var lines := {}
		while not ini.eof_reached():
			var line := ini.get_line().strip_edges()
			var eq := line.find("=")
			if eq > 0:
				lines[line.substr(0, eq)] = line.substr(eq + 1)
		ini.close()
		var is_normal: bool = String(f).ends_with("_normal.jpg")
		var problems: Array = []
		if lines.get("compress/mode", "") != "0":
			problems.append("compress/mode=" + str(lines.get("compress/mode", "?")))
		if lines.get("detect_3d/compress_to", "") != "0":
			problems.append("detect_3d/compress_to=" + str(lines.get("detect_3d/compress_to", "?")))
		if lines.get("mipmaps/generate", "") != "true":
			problems.append("mipmaps/generate=" + str(lines.get("mipmaps/generate", "?")))
		var expected_normal := "1" if is_normal else "0"
		if lines.get("compress/normal_map", "") != expected_normal:
			problems.append("compress/normal_map=" + str(lines.get("compress/normal_map", "?")))
		if f == "terrain_control.png" and lines.get("process/fix_alpha_border", "") != "false":
			problems.append("process/fix_alpha_border=" + str(lines.get("process/fix_alpha_border", "?")))
		if problems.is_empty():
			print("  OK: " + f)
		else:
			_fail("%s: %s" % [f, ", ".join(problems)])


func _check_main_scene() -> void:
	print("-- main.tscn")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("cannot load main.tscn")
		return
	var main := packed.instantiate()

	if main.get_node_or_null("Ground/Mesh") != null:
		_fail("legacy Ground/Mesh still exists (the overlay planes should be gone)")
	else:
		print("  OK: no legacy ground overlay mesh")

	var terrain := main.get_node_or_null("Terrain")
	if terrain == null:
		_fail("missing Terrain instance")
	elif terrain.get_node_or_null("GroundBlend") == null:
		_fail("missing Terrain/GroundBlend")
	else:
		print("  OK: single Terrain/GroundBlend")

	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		_fail("missing WorldEnvironment environment")
	else:
		var env := world_env.environment
		if env.background_mode != 2:
			_fail("background mode is not Sky (%d)" % env.background_mode)
		if env.sky == null:
			_fail("environment has no sky")
		else:
			var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
			if sky_mat == null:
				_fail("sky has no ProceduralSkyMaterial")
			elif sky_mat.sky_energy_multiplier > 2.0:
				_fail("sky energy is blown out: %.2f" % sky_mat.sky_energy_multiplier)
			else:
				print("  OK: sky energy %.2f" % sky_mat.sky_energy_multiplier)
		if env.ambient_light_source != 3:
			_fail("ambient light source is not Sky (%d)" % env.ambient_light_source)
		else:
			print("  OK: ambient from sky, energy %.2f" % env.ambient_light_energy)
		if env.tonemap_mode != 3:
			_fail("tonemap is not ACES (%d)" % env.tonemap_mode)
		else:
			print("  OK: ACES tonemapping")
		if env.fog_enabled:
			_fail("fog is enabled")
		else:
			print("  OK: fog disabled")

	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		_fail("missing Sun")
	else:
		if not sun.shadow_enabled:
			_fail("sun shadows are disabled")
		if sun.light_energy < 0.5 or sun.light_energy > 3.0:
			_fail("sun energy out of range: %.2f" % sun.light_energy)
		else:
			print("  OK: sun energy %.2f, shadows on" % sun.light_energy)
	main.free()


func _check_terrain() -> void:
	print("-- terrain.tscn")
	var packed := load("res://scenes/terrain.tscn") as PackedScene
	if packed == null:
		_fail("cannot load terrain.tscn")
		return
	var terrain := packed.instantiate()
	for legacy in ["StableYard", "Path", "TrainingGround", "Arena"]:
		if terrain.get_node_or_null(legacy) != null:
			_fail("legacy overlay node still exists: " + legacy)
	var ground := terrain.get_node_or_null("GroundBlend") as MeshInstance3D
	if ground == null:
		_fail("GroundBlend mesh missing")
		terrain.free()
		return
	var plane := ground.mesh as PlaneMesh
	if plane == null or not plane.size.is_equal_approx(Vector2(200, 200)):
		_fail("GroundBlend is not a 200x200 PlaneMesh")
	else:
		print("  OK: 200x200 ground plane")
	var mat := ground.get_active_material(0) as ShaderMaterial
	if mat == null:
		_fail("GroundBlend has no ShaderMaterial")
	elif mat.shader == null or mat.shader.resource_path != TERRAIN_SHADER:
		_fail("GroundBlend does not use " + TERRAIN_SHADER)
	else:
		print("  OK: terrain blend shader")
		var missing: Array[String] = []
		for param in LAYER_PARAMS:
			if mat.get_shader_parameter(param) == null:
				missing.append(param)
		if missing.is_empty():
			print("  OK: all nine layer textures bound")
		else:
			_fail("unbound terrain textures: " + ", ".join(missing))
		var control := mat.get_shader_parameter("control_map") as Texture2D
		if control == null:
			_fail("control map is not a texture")
		elif control.get_width() != 2048 or control.get_height() != 2048:
			_fail("control map is %dx%d, expected 2048x2048" % [control.get_width(), control.get_height()])
		else:
			print("  OK: 2048x2048 control map")
		var center: Vector2 = mat.get_shader_parameter("control_center")
		var size: Vector2 = mat.get_shader_parameter("control_size")
		if not center.is_equal_approx(Vector2(10, -5)) or not size.is_equal_approx(Vector2(128, 128)):
			_fail("control rect is %s / %s, expected (10,-5) / (128,128)" % [center, size])
		else:
			print("  OK: control rect (10,-5) 128x128")
		var sharpness: float = mat.get_shader_parameter("blend_sharpness")
		if sharpness < 1.0 or sharpness > 3.0:
			_fail("blend sharpness out of range: %.2f" % sharpness)
		else:
			print("  OK: blend sharpness %.2f" % sharpness)
	terrain.free()


func _fail(message: String) -> void:
	_ok = false
	print("  FAIL: " + message)
