extends SceneTree

## Renders grooming review shots.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_grooming.gd
##
## Output: artifacts/grooming_glow.png, grooming_face_glow.png, grooming_dirty.png,
##         grooming_brushed.png, grooming_mask.png, grooming_clean.png,
##         grooming_result.png

var _world: Node3D
var _horse: Node3D
var _session
var _surface
var _frame := 0
var _stage := 0
var _started := false


func _initialize() -> void:
	_world = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if not _started:
		if _frame < 15:
			return false
		_started = true
		_frame = 0
		var bay := _world.get_node("GroomingBay")
		var player := _world.get_node("Player")
		_horse = _world.get_node("Horse")
		_session = bay.get_node("Session")
		_surface = _horse.get("groom_surface")
		var horse_anchor := bay.get_node("HorseAnchor") as Node3D
		var groomer_anchor := bay.get_node("GroomerAnchor") as Node3D
		player.global_position = groomer_anchor.global_position
		_horse.global_position = horse_anchor.global_position
		_session.call("enter", horse_anchor.global_transform, groomer_anchor.global_transform)
		_session.call("set_tool", 1)
		return false
	match _stage:
		0:
			if _frame < 12:
				return false
			_save("grooming_glow")
			_surface.call("clear_tool_highlight")
			_stage = 8
			_frame = 0
		8:
			if _frame < 20:
				return false
			_save("grooming_dirty")
			# The face brush lights a much smaller area than the body tools,
			# so it gets its own review shot.
			_session.call("set_tool", 3)
			_stage = 9
			_frame = 0
		9:
			if _frame < 4:
				return false
			_save("grooming_face_glow")
			_session.call("set_tool", 1)
			_stage = 6
			_frame = 0
		6:
			# Park the brush cursor over the barrel so a review shot exists for
			# the on-horse ring and its valid/invalid tint.  The session's own
			# per-frame cursor update would overwrite it, so pause it first.
			if _frame < 4:
				return false
			_session.set_process(false)
			_session.call("_update_cursor", Vector2(640, 380))
			print("ring visible=", (_session.get("_ring") as Node3D).visible)
			_stage = 7
			_frame = 0
		7:
			if _frame < 4:
				return false
			_save("grooming_cursor")
			_session.set_process(true)
			_session.call("set_tool", 4)
			_stage = 5
			_frame = 0
		5:
			if _frame < 4:
				return false
			_save("grooming_hooves")
			print("stage: brushing")
			_brush_demo()
			print("stage: brushed")
			_stage = 1
			_frame = 0
		1:
			if _frame < 20:
				return false
			_save("grooming_brushed")
			print("stage: mask")
			_session.call("_on_mask_toggled", true)
			_stage = 2
			_frame = 0
		2:
			if _frame < 12:
				return false
			_save("grooming_mask")
			_session.call("_on_mask_toggled", false)
			_surface.call("debug_fill", 1.0, 0.85)
			for i in range(4):
				_session.call("mark_hoof", i)
			_session.call("_update_progress")
			_stage = 3
			_frame = 0
		3:
			if _frame < 12:
				return false
			_save("grooming_clean")
			_session.call("finish_grooming")
			_stage = 4
			_frame = 0
		4:
			if _frame < 12:
				return false
			_save("grooming_result")
			quit(0)
			return true
	return false


func _brush_demo() -> void:
	# Sweep the visible side of the horse in a screen-space grid.  The grid is
	# wider than the brush so the review shot shows a real brushed coat rather
	# than a couple of stamps on the flank.
	var size := root.get_visible_rect().size
	var points := []
	var y := int(size.y * 0.27)
	while y < int(size.y * 0.65):
		var x := int(size.x * 0.27)
		while x < int(size.x * 0.66):
			points.append(Vector2(x, y))
			x += 24
		y += 24
	var tools := [0, 1, 2]
	var painted := [0, 0, 0]
	for pass_index in range(tools.size()):
		_session.call("set_tool", tools[pass_index])
		for p in points:
			if bool(_session.call("paint_at_screen", p)):
				painted[pass_index] += 1
	_session.call("set_tool", 1)
	_session.call("_update_progress")
	print("demo grid=", points.size(), " painted=", painted, " coverage=", _surface.call("coverage"))


func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % label
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
