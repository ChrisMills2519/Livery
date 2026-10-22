extends SceneTree

## Renders the blended ground for review.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_terrain.gd
##
## Output: artifacts/terrain_overhead.png, terrain_yard_edge.png,
##         terrain_path_end.png, terrain_training_edge.png,
##         terrain_arena_edge.png, terrain_gate.png

const MAIN := "res://scenes/main.tscn"

const SHOTS := [
	{"file": "terrain_topdown", "pos": Vector3(10, 80, -5), "look": Vector3(10, 0, -5), "fov": 55.0, "ortho": true},
	{"file": "terrain_overhead", "pos": Vector3(30, 95, 55), "look": Vector3(5, 0, -8), "fov": 55.0},
	{"file": "terrain_yard_edge", "pos": Vector3(22, 1.7, -22), "look": Vector3(0, 0.6, -22), "fov": 60.0},
	{"file": "terrain_path_end", "pos": Vector3(0, 1.6, 16), "look": Vector3(0, 0.5, 0), "fov": 60.0},
	{"file": "terrain_training_edge", "pos": Vector3(66, 1.7, 0), "look": Vector3(35, 0.5, 0), "fov": 60.0},
	{"file": "terrain_arena_edge", "pos": Vector3(-32.5, 1.7, 42), "look": Vector3(-32.5, 0.5, 0), "fov": 60.0},
	{"file": "terrain_gate", "pos": Vector3(-9, 1.5, 0), "look": Vector3(-17, 0.6, -1.5), "fov": 60.0},
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
	_camera.name = "TerrainReviewCamera"
	_camera.far = 600.0
	root.add_child(_camera)
	_camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _apply_shot() -> void:
	var shot: Dictionary = SHOTS[_shot]
	if shot.get("ortho", false):
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 140.0
		_camera.global_position = shot["pos"]
		_camera.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = float(shot["fov"])
		_camera.global_position = shot["pos"]
		_camera.look_at(shot["look"], Vector3.UP)


func _process(_delta: float) -> bool:
	if _frame == 0:
		var player := _world.get_node_or_null("Player") as Node3D
		if player != null:
			# Keep the rider out of the path-end and overhead framing.  The
			# node is only inside the tree once the first frame runs.
			player.global_position = Vector3(9, 0, 4)
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
