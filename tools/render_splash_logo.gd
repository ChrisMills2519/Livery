extends SceneTree

## Renders the loading screen's hero image: the Livery logo plaque, front-on,
## on a transparent background.  Sibling of render_splash.gd, which renders the
## horse; the splash shows this logo instead.
##
##   xvfb-run -a -s "-screen 0 2400x1600x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 2400x1600 --script res://tools/render_splash_logo.gd
##
## Writes res://tools/web_shell/art/livery-render.png (transparent background).
## tools/prepare_splash_art.py trims and sizes that into the file the shell
## ships, res://tools/web_shell/art/livery-splash.png.

const LOGO := "res://Models/livery_logo.glb"
const RAW := "res://tools/web_shell/art/livery-render.png"

## The plaque faces +Z in Godot (see tools/make_livery_logo.py), so the camera
## sits in front of it and looks straight at it.
const CAMERA_DISTANCE := 3.2
const FOV := 30.0
const SETTLE_FRAMES := 8
const RENDER_SIZE := Vector2i(2400, 1600)

var _frame := 0
var _logo: Node3D


func _initialize() -> void:
	root.transparent_bg = true
	root.size = RENDER_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/web_shell/art"))
	var packed := load(LOGO) as PackedScene
	if packed == null:
		push_error("could not load " + LOGO)
		quit(1)
		return
	_logo = packed.instantiate() as Node3D
	root.add_child(_logo)


func _process(_delta: float) -> bool:
	_frame += 1
	# Staging waits for the first frame: global transforms are only valid once
	# the nodes are inside the live tree.
	if _frame == 1:
		_stage()
	if _frame >= SETTLE_FRAMES:
		_capture()
		return true
	return false


func _stage() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.98, 0.93, 0.85)
	settings.ambient_light_energy = 0.9
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.environment = settings
	root.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.rotation_degrees = Vector3(-35.0, -20.0, 0.0)
	root.add_child(sun)

	# Frame the plaque from its own bounds, so the shot survives a change to
	# the model's size.
	var bounds := _bounds_of(_logo)
	var centre := bounds.get_center()
	var camera := Camera3D.new()
	camera.name = "LogoCamera"
	camera.fov = FOV
	camera.far = 80.0
	root.add_child(camera)
	camera.global_position = centre + Vector3(0.0, 0.0, CAMERA_DISTANCE)
	camera.look_at(centre, Vector3.UP)
	camera.current = true
	print("[splash-logo] bounds %s centre %s" % [bounds, centre])


func _bounds_of(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var box := instance.global_transform * instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _capture() -> void:
	var image := root.get_texture().get_image()
	var target := OS.get_environment("SPLASH_OUT")
	var path := ProjectSettings.globalize_path(RAW if target == "" else target)
	var err := image.save_png(path)
	if err != OK:
		push_error("failed to save " + path)
		quit(1)
		return
	print("saved ", path, " ", image.get_size())
	quit(0)
