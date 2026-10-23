extends SceneTree

## Renders the player's own third-person camera at the tight spots the
## walkthrough measures.  Unlike screenshot_farmhouse.gd, this keeps the body
## visible and does not place a review camera: it shows what the player sees.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_camera.gd
##
## Output: artifacts/camera_sitting_corner.png, camera_study_desk.png,
## camera_bath.png and camera_landing.png.  Pass names after `--` to render
## only those.

const SCENE := "res://scenes/farmhouse.tscn"

const SPOTS := [
	# The check backs into this corner for 1.2 s before it measures; do the
	# same so the frame is the tight view, not the open spot beside it.
	{"name": "sitting_corner", "pos": Vector3(-8.80, 0.0, -6.90), "yaw": -45.0, "back": 72},
	{"name": "study_desk", "pos": Vector3(5.80, 0.0, -5.80), "yaw": 0.0},
	{"name": "bath", "pos": Vector3(6.00, 3.12, 5.80), "yaw": 180.0},
	{"name": "landing", "pos": Vector3(4.20, 3.12, -4.70), "yaw": 270.0},
]

const SETTLE_FRAMES := 55
const SHOT_FRAMES := 6


func _initialize() -> void:
	var wanted := OS.get_cmdline_user_args()
	var spots: Array = []
	for spot in SPOTS:
		if wanted.is_empty() or String(spot["name"]) in wanted:
			spots.append(spot)
	if spots.is_empty():
		push_error("no camera spots selected")
		quit(1)
		return
	var scene := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var player := scene.get_node("Player") as CharacterBody3D
	var pivot := player.get_node("CameraPivot") as Node3D
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	player.set("controls_enabled", true)
	camera.current = true
	await _frames(20)
	for spot in spots:
		player.global_position = spot["pos"]
		player.rotation.y = deg_to_rad(float(spot["yaw"]))
		player.velocity = Vector3.ZERO
		pivot.rotation.x = deg_to_rad(-10.0)
		if spot.has("back"):
			Input.action_press("move_back")
			await _frames(int(spot["back"]))
			Input.action_release("move_back")
		await _frames(SETTLE_FRAMES)
		await _frames(SHOT_FRAMES)
		var image := root.get_texture().get_image()
		var target := "res://artifacts/camera_%s.png" % spot["name"]
		var err := image.save_png(ProjectSettings.globalize_path(target))
		if err != OK:
			push_error("failed to save " + target)
			quit(1)
			return
		print("saved %s (boom %.2f m)" % [target, float(player.call("camera_boom_length"))])
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
