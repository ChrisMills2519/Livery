extends SceneTree

## Debug harness for the footprint shader.
##
## Captures two images of the same scene from the same camera: one with the
## print mesh visible and one with it hidden.  Because the world is frozen,
## anything that differs between them comes from the prints alone.  Diff
## counting is far more reliable than the subjectively-named "with/without"
## comparison the previous harness attempted, and it does not depend on the
## evaluator being able to read the image.

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _trail: Node3D
var _camera: Camera3D
var _mesh: MultiMeshInstance3D
var _frame := 0
var _done := false


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_trail = _world.get_node("Footprints") as Node3D
	_mesh = _trail.get_node_or_null("FootprintMesh") as MultiMeshInstance3D
	for n in _world.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.name = "DbgCam"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 200.0
	root.add_child(_camera)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	match _frame:
		4:
			_trail.call("clear")
			for i in range(6):
				_trail.call(
					"stamp",
					Vector3(-1.0 + i * 0.32, 0.0, -0.55),
					0.0,
					0,
					Vector2(0.13, 0.16),
					1.0
				)
				_trail.call(
					"stamp",
					Vector3(-1.0 + i * 0.32, 0.0, -0.20),
					0.0,
					1,
					Vector2(0.11, 0.30),
					1.0
				)
			_world.process_mode = Node.PROCESS_MODE_DISABLED
			_camera.global_position = Vector3(-0.05, 1.05, -0.375)
			_camera.look_at(Vector3(-0.05, 0.0, -0.374), Vector3(0.0, 0.0, -1.0))
			_camera.current = true
		5:
			if _mesh != null:
				_mesh.visible = false
		6:
			_save("artifacts/_dbg_fp_without.png")
		7:
			if _mesh != null:
				_mesh.visible = true
		8:
			_save("artifacts/_dbg_fp_with.png")
			_do_diff()
			quit(0)
			_done = true
			return true
	return false


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)


func _do_diff() -> void:
	var a := Image.new()
	var b := Image.new()
	a.load(ProjectSettings.globalize_path("res://artifacts/_dbg_fp_with.png"))
	b.load(ProjectSettings.globalize_path("res://artifacts/_dbg_fp_without.png"))
	var w := a.get_width()
	var h := a.get_height()
	var changed := 0
	var min_y := h
	var max_y := 0
	for y in range(h):
		for x in range(w):
			var ra := a.get_pixel(x, y)
			var rb := b.get_pixel(x, y)
			var d := absf(ra.r - rb.r) + absf(ra.g - rb.g) + absf(ra.b - rb.b)
			if d > 12.0:
				changed += 1
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	print("A/B diff pixels (>12): %d / %d" % [changed, w * h])
	if changed > 0:
		print("affected rows y: %d..%d" % [min_y, max_y])
		print("A/B DIFF: PRINTS VISIBLE")
	else:
		print("A/B DIFF: NO VISIBLE PRINTS")
