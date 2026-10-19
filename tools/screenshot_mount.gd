extends SceneTree

## Renders mounted review shots.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_mount.gd
##
## Output: artifacts/mount_side.png, artifacts/mount_front.png,
##         artifacts/mount_rider_cam.png

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _camera: Camera3D
var _frame := 0
var _shot := 0
var _settle := 0
var _mounted := false
var _output_prefix := ""

const SHOTS := [
	{"file": "mount_side", "offset": Vector3(4.2, 2.0, 0.6), "look": Vector3(0.0, 1.25, 0.0)},
	{"file": "mount_front", "offset": Vector3(2.8, 2.0, -3.4), "look": Vector3(0.0, 1.2, -0.2)},
	{"file": "mount_rear", "offset": Vector3(-2.6, 2.2, 3.2), "look": Vector3(0.0, 1.2, 0.0)},
	{"file": "mount_closeup", "offset": Vector3(2.2, 1.9, 0.9), "look": Vector3(0.0, 1.5, 0.0)},
	{"file": "mount_front_closeup", "offset": Vector3(1.6, 1.9, -2.2), "look": Vector3(0.0, 1.45, -0.1)},
]


func _initialize() -> void:
	var requested := OS.get_environment("GROOM_CHARACTER").strip_edges().to_lower()
	if not requested.is_empty():
		_output_prefix = requested + "_"
	var packed := load(MAIN) as PackedScene
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "MountReviewCamera"
	_camera.fov = 55.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 6:
		_player = _world.get_node("Player") as CharacterBody3D
		_horse = _world.get_node("Horse") as CharacterBody3D
		_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
		_player.velocity = Vector3.ZERO
	elif _frame == 9 and not _mounted:
		_mounted = true
		_player.try_mount()
		print("mounted=", _player.mounted, " seat=", _horse.get_rider_seat_position())
		_place_camera()
		return false
	if not _mounted:
		return false
	if _settle < 8:
		_settle += 1
		return false
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s%s.png" % [_output_prefix, String(SHOTS[_shot]["file"])]
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return true
	print("saved ", target)
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return true
	_place_camera()
	_settle = 0
	return false


func _place_camera() -> void:
	var shot: Dictionary = SHOTS[_shot]
	_camera.global_position = _horse.global_position + shot["offset"]
	_camera.look_at(_horse.global_position + shot["look"], Vector3.UP)
	_camera.current = true
