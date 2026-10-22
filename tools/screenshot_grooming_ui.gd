extends SceneTree

## Renders the per-area checklist shot.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_grooming_ui.gd
##
## The full grooming shots keep the whole yard, which does not fit in memory
## on a small machine, so this one drops the scenery and shows the areas
## panel on the horse alone.
##
## Output: artifacts/grooming_areas.png

var _world: Node3D
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
		var horse := _world.get_node("Horse")
		if not _has_skinned_mesh(horse):
			return false
		_started = true
		_frame = 0
		_drop_scenery()
		var bay := _world.get_node("GroomingBay")
		var player := _world.get_node("Player")
		_session = bay.get_node("Session")
		_surface = horse.get("groom_surface")
		var horse_anchor := bay.get_node("HorseAnchor") as Node3D
		var groomer_anchor := bay.get_node("GroomerAnchor") as Node3D
		player.global_position = groomer_anchor.global_position
		horse.global_position = horse_anchor.global_position
		_session.call("enter", horse_anchor.global_transform, groomer_anchor.global_transform)
		return false
	match _stage:
		0:
			if _frame < 20:
				return false
			# Clean the back and barrel so the list shows a mix of done areas
			# and areas still to do.
			_brush_band()
			_session.call("_update_progress")
			_stage = 1
			_frame = 0
		1:
			if _frame < 6:
				return false
			_save("grooming_areas")
			_session.call("_on_mask_toggled", true)
			_stage = 2
			_frame = 0
		2:
			if _frame < 6:
				return false
			_save("grooming_areas_mask")
			quit(0)
			return true
	return false


## The horse's mesh loads a frame or two after the scene, and the groom
## surface needs it to bake its zones; without this the shot can enter the
## bay before there is anything to groom.
func _has_skinned_mesh(horse: Node) -> bool:
	for node in horse.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			return true
	return false


## The yard scenery is the memory hog on a small machine, and this shot only
## needs the horse, the bay and the HUD.
func _drop_scenery() -> void:
	for node_name in ["Forest", "NatureProps", "ArenaFence", "Stable", "Dog", "ArenaCourse", "Terrain"]:
		var node := _world.get_node_or_null(node_name)
		if node != null:
			node.queue_free()
	var player := _world.get_node_or_null("Player")
	if player != null:
		var model := player.get("model") as Node3D
		if model != null:
			model.queue_free()


## Sweep the upper half of the horse, which covers the neck, back and barrel
## but leaves the legs and head for the player to finish.  Several passes are
## needed to push those areas over their completion threshold so the
## checklist shows a mix of finished and remaining work.
func _brush_band() -> void:
	var size := root.get_visible_rect().size
	var tools := [0, 1, 2]
	for pass_index in range(6):
		_session.call("set_tool", tools[pass_index % tools.size()])
		var y := int(size.y * 0.20)
		while y < int(size.y * 0.46):
			var x := int(size.x * 0.30)
			while x < int(size.x * 0.68):
				_session.call("paint_at_screen", Vector2(x, y))
				x += 16
			y += 16
	_session.call("set_tool", 1)
	_session.call("_update_progress")


func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % label
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
