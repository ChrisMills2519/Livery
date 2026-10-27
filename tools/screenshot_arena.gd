extends SceneTree

## Renders review screenshots of the competition arena.
##
## Run with (software GL works on the dev machine):
##     xvfb-run -a -s "-screen 0 1280x720x24" \
##         godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##         --resolution 1280x720 --script res://tools/screenshot_arena.gd
##
## Output: artifacts/arena_showground.png, artifacts/arena_ring.png,
##         artifacts/arena_grandstand.png, artifacts/arena_jump.png,
##         artifacts/arena_warmup.png, artifacts/arena_judges.png

const SHOTS := [
	{"file": "arena_showground", "pos": Vector3(58, 38, 54), "look": Vector3(-4, 0, -2)},
	{"file": "arena_ring", "pos": Vector3(40, 3.0, 9), "look": Vector3(-6, 1.4, 0)},
	{"file": "arena_grandstand", "pos": Vector3(-2, 4.2, 6), "look": Vector3(-34, 5.2, 0)},
	{"file": "arena_jump", "pos": Vector3(-11, 2.6, -3.2), "look": Vector3(-18.5, 1.2, -8)},
	{"file": "arena_warmup", "pos": Vector3(68, 7.5, 22), "look": Vector3(52, 0.8, 3)},
	{"file": "arena_judges", "pos": Vector3(-24, 3.4, -14), "look": Vector3(-35.5, 2.4, -20)},
]

var _frame := 0
var _shot := 0
var _camera: Camera3D
var _pending_shot := true


func _initialize() -> void:
	var packed := load("res://scenes/competition_arena.tscn") as PackedScene
	if packed == null:
		push_error("cannot load competition arena")
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
	if _pending_shot:
		_apply_shot()
		_pending_shot = false
	_frame += 1
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
