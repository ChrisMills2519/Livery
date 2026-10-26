extends SceneTree

## Renders the main level's layout for review.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_layout.gd
##
## Output: artifacts/layout_yard_from_lane.png, layout_junction.png,
##         layout_yard_wide.png,
##         layout_lane_south.png, layout_paddock.png,
##         layout_arena_approach.png, layout_school.png,
##         layout_house_drive.png, layout_overview.png
##
## The point of the pass is route and depth, so every shot is an eye-level view
## from somewhere the player can stand, except the overview that shows the
## whole site at once.

const MAIN := "res://scenes/main.tscn"
const PLAYER_PARK := Vector3(14.0, 0.0, 4.0)

const SHOTS := [
	{"file": "layout_yard_from_lane", "pos": Vector3(1.6, 1.9, -10.8), "look": Vector3(-8, 1.0, -21.5), "fov": 62.0},
	{"file": "layout_junction", "pos": Vector3(8, 1.9, 9), "look": Vector3(0.5, 1.6, 1.5), "fov": 60.0},
	{"file": "layout_yard_wide", "pos": Vector3(8, 3.4, -13.5), "look": Vector3(-8, 0.9, -21), "fov": 60.0},
	{"file": "layout_lane_south", "pos": Vector3(0, 1.75, 6), "look": Vector3(1.5, 2.2, 25), "fov": 60.0},
	{"file": "layout_paddock", "pos": Vector3(-4.5, 2.6, -0.5), "look": Vector3(-9, 0.7, 13), "fov": 60.0},
	{"file": "layout_arena_approach", "pos": Vector3(-3.5, 1.7, -1.5), "look": Vector3(-16, 1.0, -1.5), "fov": 60.0},
	{"file": "layout_school", "pos": Vector3(11.5, 1.75, 10.5), "look": Vector3(32, 0.9, 3), "fov": 60.0},
	{"file": "layout_house_drive", "pos": Vector3(20, 1.8, -27.5), "look": Vector3(37, 1.3, -31.2), "fov": 60.0},
	{"file": "layout_overview", "pos": Vector3(34, 26, 34), "look": Vector3(-2, 0, -12), "fov": 55.0},
]

var _frame := 0
var _shot := 0
var _camera: Camera3D
var _world: Node3D


func _initialize() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		push_error("cannot load main scene")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	_camera = Camera3D.new()
	_camera.name = "LayoutReviewCamera"
	_camera.far = 600.0
	root.add_child(_camera)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _apply_shot() -> void:
	var shot: Dictionary = SHOTS[_shot]
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = float(shot["fov"])
	_camera.global_position = shot["pos"]
	_camera.look_at(shot["look"], Vector3.UP)


func _process(_delta: float) -> bool:
	if _frame == 0:
		# Park the player out of every framing; the horse stays in the yard
		# because its new start is part of what is being reviewed.
		var player := _world.get_node_or_null("Player") as Node3D
		if player != null:
			player.global_position = PLAYER_PARK
		_apply_shot()
	_frame += 1
	if _frame < 12:
		return false
	var image := root.get_texture().get_image()
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
	_frame = 0
	return false
