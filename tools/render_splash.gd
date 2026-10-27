extends SceneTree

## Renders the loading screen's hero image: the livery horse in full tack,
## three-quarter on, with the level hidden behind it so the splash can fade the
## horse in over its own background instead of showing a rectangle of world.
##
##   xvfb-run -a -s "-screen 0 2400x1600x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 2400x1600 --script res://tools/render_splash.gd
##
## Rendered far bigger than it is shown: the splash draws the horse up to about
## 32 rem wide at a 2x device pixel ratio, so the source wants ~1100 px of horse,
## and the horse only fills the middle of the frame.
##
## Writes res://tools/web_shell/art/livery-render.png (transparent background).
## tools/prepare_splash_art.py trims and sizes that into the file the shell
## ships, res://tools/web_shell/art/livery-splash.png.  Run both when the horse,
## the tack or the yard lighting changes: the splash shows the real game art, so
## it should be re-rendered rather than hand-drawn.
##
## The camera is placed from the horse's own transform, so moving the horse in
## the level cannot leave this tool pointing at empty yard.

const MAIN := "res://scenes/main.tscn"
const RAW := "res://tools/web_shell/art/livery-render.png"

## Everything in the level is hidden except these: the horse (and the tack
## parented under it) and the sun that lights it.
const KEEP := ["Horse", "Sun", "WorldEnvironment"]

## A side-on showpiece with a little front bias, eye level with the barrel.  The
## framing is built from the horse's own basis (a node faces its -Z), so the shot
## survives the horse being turned in the level.
const CAMERA_AHEAD := 1.15
const CAMERA_SIDE := 3.95
const CAMERA_HEIGHT := 1.5
const LOOK_AT_HEIGHT := 1.14
const SETTLE_FRAMES := 60

## The idle clip's own time for the pose to be captured at.  Pinning it means
## two renders of the same horse are the same picture: a frame count would not
## be, because this machine renders far faster than 60 fps.  Override it while
## choosing a pose with SPLASH_POSE=<seconds> and SPLASH_OUT=<path>.
const POSE_SECONDS := 1.4
const RENDER_SIZE := Vector2i(2400, 1600)

var _frame := 0
var _world: Node3D
var _horse: Node3D


func _initialize() -> void:
	root.transparent_bg = true
	root.size = RENDER_SIZE
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/web_shell/art"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_stage()
	elif _frame == SETTLE_FRAMES:
		_pose()
	elif _frame >= SETTLE_FRAMES + 2:
		_capture()
		return true
	return false


## Holds the idle animation at a chosen time so the capture is reproducible.
func _pose() -> void:
	var player: AnimationPlayer = null
	for node in _horse.find_children("*", "AnimationPlayer", true, false):
		var candidate := node as AnimationPlayer
		print("[splash] player %s -> %s" % [candidate.name, candidate.current_animation])
		if player == null and String(candidate.current_animation) != "":
			player = candidate
	if player == null:
		print("[splash] no idle animation to pose")
		return
	var clip := String(player.current_animation)
	player.seek(_pose_seconds(), true)
	player.pause()
	print("[splash] posed %s at %.2f s" % [clip, _pose_seconds()])


func _pose_seconds() -> float:
	var override := OS.get_environment("SPLASH_POSE")
	return override.to_float() if override != "" else POSE_SECONDS


func _stage() -> void:
	_horse = _world.get_node_or_null("Horse") as Node3D
	if _horse == null:
		push_error("the level has no Horse node")
		quit(1)
		return

	for child in _world.get_children():
		if not KEEP.has(child.name):
			(child as Node).visible = false

	# The horse's own prompts would hang in the frame the way they hang over the
	# yard in game.
	for label in _horse.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false

	var environment := _world.get_node_or_null("WorldEnvironment/") as WorldEnvironment
	if environment == null:
		environment = _world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment != null and environment.environment != null:
		var settings: Environment = environment.environment.duplicate()
		# The sky is what is behind the horse in game; on the splash the page is
		# behind it, so the background is left transparent and the horse is lit by
		# a fixed warm ambient instead of by the sky it can no longer see.
		settings.background_mode = Environment.BG_CLEAR_COLOR
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color(0.98, 0.93, 0.85)
		settings.ambient_light_energy = 0.62
		settings.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.environment = settings

	var camera := Camera3D.new()
	camera.name = "SplashCamera"
	camera.fov = 42.0
	camera.far = 80.0
	# Into the tree first: a node outside it has no global transform to set.
	root.add_child(camera)
	var origin := _horse.global_transform.origin
	var forward := -_horse.global_transform.basis.z.normalized()
	var right := _horse.global_transform.basis.x.normalized()
	camera.global_position = (
		origin
		+ forward * CAMERA_AHEAD
		+ right * CAMERA_SIDE
		+ Vector3.UP * CAMERA_HEIGHT
	)
	camera.look_at(origin + Vector3(0.0, LOOK_AT_HEIGHT, 0.0), Vector3.UP)
	camera.current = true
	print("[splash] horse at %s, forward %s, right %s" % [origin, forward, right])


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
