extends SceneTree

## Renders review views of the farmhouse interior.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_farmhouse.gd
##
## Output: artifacts/farmhouse_*.png
##
## Add view names after `--` to render only those, e.g. `-- landing bathroom`.

const SCENE := "res://scenes/farmhouse.tscn"

const VIEWS := [
	{"name": "sitting", "eye": Vector3(1.85, 1.66, -0.85), "look": Vector3(-6.8, 1.10, -4.50)},
	{"name": "kitchen", "eye": Vector3(1.70, 1.66, 2.95), "look": Vector3(-7.4, 1.00, 5.90)},
	{"name": "hall", "eye": Vector3(3.15, 1.70, 2.95), "look": Vector3(7.90, 1.15, -1.20)},
	{"name": "bedroom", "eye": Vector3(1.85, 4.42, -1.00), "look": Vector3(-6.6, 3.50, -4.50)},
	{"name": "landing", "eye": Vector3(3.10, 4.42, 1.15), "look": Vector3(7.60, 3.25, -3.05)},
	{"name": "bathroom", "eye": Vector3(3.20, 4.42, 4.35), "look": Vector3(8.30, 3.40, 6.85)},
	# Layout review: the ceilings and the storey above are hidden so the plan
	# of each floor can be checked in one frame.
	# Upper first: each plan view hides parts of the scene, and the ground view
	# hides the upper storey for good.  Rendering the upper plan first keeps
	# its furniture from being hidden by the previous frame.
	{"name": "plan_upper", "eye": Vector3(0.0, 14.0, 0.0), "look": Vector3(0.0, 2.72, -0.01), "plan": 1},
	{"name": "plan_ground", "eye": Vector3(0.0, 14.0, 0.0), "look": Vector3(0.0, 0.0, -0.01), "plan": 0},
]

# Shell node name prefixes that sit above the floor a plan view is looking at.
const PLAN_HIDE := [
	["GroundCeiling", "UpperFloor", "UpperCeiling", "WallSouthUpper", "WallNorthUpper",
		"WallWestUpper", "WallEastUpper", "PartBedroomsUpper", "PartBedroomsDivide", "PartBathUpper"],
	["UpperCeiling"],
]

var _scene: Node3D
var _camera: Camera3D
var _frame := 0
var _index := 0
var _shot_frames := 0
var _views: Array = []
# Plan views hide whole groups for one frame.  Remember what was visible when
# the scene loaded so a second plan view can put it all back before hiding the
# other storey.
var _base_visibility := {}


func _initialize() -> void:
	# Optionally render only some views: pass view names after `--`.
	var wanted := OS.get_cmdline_user_args()
	for view in VIEWS:
		if wanted.is_empty() or String(view["name"]) in wanted:
			_views.append(view)

	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.far = 120.0
	root.add_child(_camera)
	_camera.current = true
	for group in ["Shell", "Lighting", "Furniture", "Seats"]:
		var parent := _scene.get_node_or_null(group)
		if parent == null:
			continue
		for child in parent.get_children():
			if child is Node3D:
				_base_visibility[child] = (child as Node3D).visible
	var player := _scene.get_node_or_null("Player") as Node3D
	if player != null:
		var player_camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
		if player_camera != null:
			player_camera.current = false
		# The rooms are the subject, not the rider standing in the hall.  Park the
		# player away from the doors and mute the prompts so nothing floats in the
		# review frames.
		player.visible = false
		player.set("controls_enabled", false)
		player.global_position = Vector3(-3.50, 0.05, -3.90)


func _hide_above(floor_index: int) -> void:
	for node in _base_visibility:
		(node as Node3D).visible = bool(_base_visibility[node])
	var shell := _scene.get_node("Shell")
	for prefix in PLAN_HIDE[floor_index]:
		for child in shell.get_children():
			if String(child.name).begins_with(String(prefix)):
				(child as Node3D).visible = false
	# Pendants and lamps that belong to the storey above would hang in the way.
	var limit := 2.6
	if floor_index == 1:
		limit = 5.0
	for light in _scene.get_node("Lighting").get_children():
		if light is Node3D and (light as Node3D).position.y > limit:
			(light as Node3D).visible = false
	# The furniture and seats of the other storey would read as clutter on top
	# of this floor's plan.
	var floor_y := 0.0 if floor_index == 0 else 2.72
	for group in ["Furniture", "Seats"]:
		var parent := _scene.get_node_or_null(group)
		if parent == null:
			continue
		for child in parent.get_children():
			if child is Node3D and absf((child as Node3D).position.y - floor_y) > 0.5:
				(child as Node3D).visible = false


func _process(_delta: float) -> bool:
	_frame += 1
	if _index >= _views.size():
		quit(0)
		return true
	var view: Dictionary = _views[_index]
	if _shot_frames == 0:
		if _frame < 25:
			return false
		if view.has("plan"):
			_hide_above(int(view["plan"]))
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			# The clear plan is 19.05 x 15.59 m; 18.5 vertical leaves a margin at
			# 16:9 instead of cropping the north and south rooms.
			_camera.size = 18.5
		else:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.global_position = view["eye"]
		_camera.look_at(view["look"], Vector3.UP if not view.has("plan") else Vector3.FORWARD)
		_shot_frames = 1
		_frame = 0
		return false
	if _frame < 6:
		return false
	var image := root.get_texture().get_image()
	var target := "res://artifacts/farmhouse_%s.png" % view["name"]
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return true
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
	_index += 1
	_shot_frames = 0
	_frame = 0
	return false
