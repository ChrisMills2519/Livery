extends SceneTree

## Renders a handful of review screenshots of the rebuilt main scene.
##
## Run with (software GL works on the dev machine):
##     xvfb-run -a -s "-screen 0 1280x720x24" \
##         godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##         --resolution 1280x720 --script res://tools/screenshot_scene.gd
##
## Output: artifacts/overview.png, artifacts/stable_yard.png,
##         artifacts/arena_course.png

const SHOTS := [
	{"file": "overview", "pos": Vector3(88, 58, 96), "look": Vector3(0, 0, -14)},
	{"file": "stable_yard", "pos": Vector3(24, 11, 18), "look": Vector3(0, 1, -22)},
	{"file": "arena_course", "pos": Vector3(10, 24, 58), "look": Vector3(-32, 1, 0)},
	{"file": "player_view", "pos": Vector3(0, 1.7, 8), "look": Vector3(0, 1.1, -20)},
	{"file": "jump_closeup", "pos": Vector3(-13.5, 2.4, 4.5), "look": Vector3(-22.0, 0.9, -1.5)},
	{"file": "yard_props", "pos": Vector3(7.5, 4.5, -9.0), "look": Vector3(-4.0, 0.8, -22.0)},
]

var _frame := 0
var _shot := 0
var _camera: Camera3D
var _pending_shot := true


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("cannot load main scene")
		quit(1)
		return
	var world := packed.instantiate()
	get_root().add_child(world)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.fov = 60.0
	_camera.far = 800.0
	get_root().add_child(_camera)
	_camera.current = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _apply_shot() -> void:
	var shot: Dictionary = SHOTS[_shot]
	_camera.global_position = shot["pos"]
	_camera.look_at(shot["look"], Vector3.UP)


func _process(_delta: float) -> bool:
	# The root window is not inside the tree during _initialize, so the camera
	# placement has to happen on the first processed frame.
	if _pending_shot:
		_apply_shot()
		_pending_shot = false
	_frame += 1
	# Give materials/shadows a few frames to settle before capturing.
	if _frame < 12:
		return false
	var image := get_root().get_texture().get_image()
	var target := "res://artifacts/%s.png" % String(SHOTS[_shot]["file"])
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return true
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return true
	_apply_shot()
	_frame = 0
	return false
