extends SceneTree

## Renders grooming review shots.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_grooming.gd
##
## Output: artifacts/grooming_glow.png, grooming_face_glow.png, grooming_dirty.png,
##         grooming_brushed.png, grooming_mask.png, grooming_head_before.png,
##         grooming_head_before_zoom.png, grooming_head_after.png,
##         grooming_head_after_zoom.png, grooming_clean.png, grooming_result.png
##
## The head pair is the evidence for the face sheen: the same frame geometry,
## clean and unpolished, then polished through the soft brush like a player
## would, with the luminance lift on the head and on the barrel printed so
## "the face shines harder than the coat" is a number rather than a claim.

var _world: Node3D
var _horse: Node3D
var _session
var _surface
var _frame := 0
var _stage := 0
var _started := false
var _landmarks := {}
var _luma_before := {}
var _before_image: Image = null


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
			# Clean and unpainted everywhere, head included: reset_mask clears
			# the face polish too, which debug_fill alone leaves behind.
			_surface.call("reset_mask")
			_surface.call("debug_fill", 1.0, 0.0)
			_stage = 14
			_frame = 0
		14:
			# The viewport texture holds the frame that was just drawn, so the
			# cursor has to be gone for a frame before the capture or the shot
			# still carries it.
			_landmarks = _landmark_points()
			print("landmarks head=", _landmarks["head"], " barrel=", _landmarks["barrel"])
			_prepare_capture()
			_stage = 15
			_frame = 0
		15:
			if _frame < 6:
				return false
			_prepare_capture()
			_before_image = _capture("grooming_head_before")
			_save_crop("grooming_head_before_zoom", _before_image, _landmarks["head"], 90)
			_luma_before = _luma_of(_before_image)
			print("probe before head: ", _probe(_landmarks["head"]))
			print("probe before barrel: ", _probe(_landmarks["barrel"]))
			_stage = 11
			_frame = 0
		11:
			if _frame < 4:
				return false
			_polish_demo()
			_stage = 12
			_frame = 0
		12:
			_prepare_capture()
			_stage = 13
			_frame = 0
		13:
			if _frame < 6:
				return false
			_prepare_capture()
			var after := _capture("grooming_head_after")
			_save_crop("grooming_head_after_zoom", after, _landmarks["head"], 90)
			_save_crop("grooming_coat_after_zoom", after, _landmarks["barrel"], 90)
			_save_pair("grooming_head_pair", _before_image, after, _landmarks["head"], 90)
			print("probe after head: ", _probe(_landmarks["head"]))
			print("probe after barrel: ", _probe(_landmarks["barrel"]))
			_report_sheen(_before_image, after)
			_session.set_process(true)
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


## Polish the head and the barrel the way a player does it: the soft brush,
## swept over each in screen space.  reset_mask + debug_fill left both clean
## and unpolished, so whatever lift this puts on screen is the polish itself.
func _polish_demo() -> void:
	_session.call("set_tool", 2)
	var head: Vector2 = _landmarks["head"]
	var barrel: Vector2 = _landmarks["barrel"]
	var painted := 0
	for _pass_index in range(3):
		for dy in range(-54, 55, 5):
			for dx in range(-40, 41, 5):
				if bool(_session.call("paint_at_screen", head + Vector2(dx, dy))):
					painted += 1
		for dy in range(-60, 61, 6):
			for dx in range(-72, 73, 6):
				if bool(_session.call("paint_at_screen", barrel + Vector2(dx, dy))):
					painted += 1
	_session.call("set_tool", 1)
	print("polish sweep painted=", painted)


## The polish actually under each measured box, read from the mask at the point
## the ray lands on.  The sheen comparison is only worth anything if both
## regions are polished to the same level, so this is the fairness check.
func _probe(screen_pos: Vector2) -> String:
	var camera := _session.call("get_camera") as Camera3D
	if camera == null:
		return "no camera"
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit = _surface.call("pick_ray", origin, direction)
	if not (hit is Dictionary) or (hit as Dictionary).is_empty():
		return "miss"
	var uv: Vector2 = (hit as Dictionary).get("uv", Vector2.ZERO)
	return "zone=%d clean=%.2f polish=%.2f" % [
		int((hit as Dictionary).get("zone", 0)),
		float(_surface.call("get_mask_value", uv, "clean")),
		float(_surface.call("get_mask_value", uv, "polish")),
	]


## Where the face and the barrel are on screen.  The bones are only a starting
## guess: the head bone projects onto the crest, which is coat, and measuring
## that would have compared coat with coat.  Each guess is refined to the centre
## of the screen points that actually pick the zone being measured.
func _landmark_points() -> Dictionary:
	var out := {"head": Vector2.ZERO, "barrel": Vector2.ZERO}
	var camera := _world.get_viewport().get_camera_3d()
	var skeleton := _horse.get("_skeleton") as Skeleton3D
	if camera == null or skeleton == null:
		push_warning("grooming shots: no camera or skeleton; head pair will be centred")
		return out
	var barrel_guess := _bone_screen(camera, skeleton, "spine_3")
	if barrel_guess == Vector2.ZERO:
		barrel_guess = _bone_screen(camera, skeleton, "spine_2")
	out["head"] = _zone_centre(_bone_screen(camera, skeleton, "head"), 3, 70)
	out["barrel"] = _zone_centre(barrel_guess, 1, 60)
	return out


## Centre of the screen points near `around` whose ray lands on `zone_id`.
## ZONE_FACE is 3 and ZONE_COAT is 1 in groom_surface.gd.
func _zone_centre(around: Vector2, zone_id: int, half: int) -> Vector2:
	var camera := _session.call("get_camera") as Camera3D
	if camera == null or around == Vector2.ZERO:
		return around
	var total := Vector2.ZERO
	var count := 0
	for dy in range(-half, half + 1, 6):
		for dx in range(-half, half + 1, 6):
			var point := around + Vector2(dx, dy)
			var hit = _surface.call("pick_ray", camera.project_ray_origin(point), camera.project_ray_normal(point))
			if not (hit is Dictionary) or (hit as Dictionary).is_empty():
				continue
			if int((hit as Dictionary).get("zone", 0)) != zone_id:
				continue
			total += point
			count += 1
	if count == 0:
		return around
	return total / float(count)


func _bone_screen(camera: Camera3D, skeleton: Skeleton3D, bone_name: String) -> Vector2:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector2.ZERO
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	return camera.unproject_position(pose.origin)


## Everything the pair must not be measuring: the cursor ring over the spot
## last painted, the dust puffs it emitted (they cannot be paused, so they are
## hidden), the tool glow that tints the whole paintable area, and the toast
## that reports a brush used on the wrong area.  All of it is painting feedback
## rather than horse, and all of it differs between the two frames.
func _prepare_capture() -> void:
	_session.set_process(false)
	var ring := _session.get("_ring") as Node3D
	if ring != null:
		ring.visible = false
	var dust := _session.get("_dust") as Node3D
	if dust != null:
		dust.visible = false
	if _surface != null and _surface.has_method("clear_tool_highlight"):
		_surface.call("clear_tool_highlight")
	var hud = _session.get("_hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", "", 0.0)


## One frame, saved whole and returned for measuring.  The head pair has to
## come from the same frame as its crop or the two are not the same picture.
func _capture(label: String) -> Image:
	var image := root.get_texture().get_image()
	var target := ProjectSettings.globalize_path("res://artifacts/%s.png" % label)
	var err := image.save_png(target)
	if err != OK:
		push_error("failed to save " + label)
		quit(1)
		return image
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
	return image


## The head is about 90 px tall at this framing, which is too small to judge a
## sheen on.  Crop and scale it up so the pair can be looked at.
func _save_crop(label: String, image: Image, centre: Vector2, half: int) -> void:
	var region := _crop_region(image, centre, half)
	var target := ProjectSettings.globalize_path("res://artifacts/%s.png" % label)
	var err := region.save_png(target)
	if err != OK:
		push_error("failed to save " + label)
		quit(1)
		return
	print("saved %s (%dx%d)" % [target, region.get_width(), region.get_height()])


## The face is a small area, so its box is smaller than the barrel's; both are
## kept inside their zone so the average is of that surface, not of its
## neighbours.
const BOX_HALF := {"head": 34, "barrel": 44}


## Unpolished on the left, polished on the right, same crop: the head pair is
## meant to be looked at, and two files side by side in a chat is not that.
func _save_pair(label: String, before: Image, after: Image, centre: Vector2, half: int) -> void:
	var left := _crop_region(before, centre, half)
	var right := _crop_region(after, centre, half)
	var pair := Image.create(left.get_width() * 2 + 6, left.get_height(), false, Image.FORMAT_RGB8)
	pair.fill(Color(0.12, 0.11, 0.10))
	pair.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	pair.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(left.get_width() + 6, 0))
	var target := ProjectSettings.globalize_path("res://artifacts/%s.png" % label)
	var err := pair.save_png(target)
	if err != OK:
		push_error("failed to save " + label)
		quit(1)
		return
	print("saved %s (%dx%d, unpolished left, polished right)" % [target, pair.get_width(), pair.get_height()])


func _crop_region(image: Image, centre: Vector2, half: int) -> Image:
	var rect := Rect2i(int(centre.x) - half, int(centre.y) - half, half * 2, half * 2)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var region := image.get_region(rect)
	region.convert(Image.FORMAT_RGB8)
	region.resize(region.get_width() * 3, region.get_height() * 3, Image.INTERPOLATE_CUBIC)
	return region


func _luma_of(image: Image) -> Dictionary:
	return {
		"head": _mean_luma(image, _landmarks["head"], BOX_HALF["head"]),
		"barrel": _mean_luma(image, _landmarks["barrel"], BOX_HALF["barrel"]),
	}


func _luma(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


func _mean_luma(image: Image, centre: Vector2, half: int) -> float:
	var x0 := maxi(0, int(centre.x) - half)
	var x1 := mini(image.get_width(), int(centre.x) + half)
	var y0 := maxi(0, int(centre.y) - half)
	var y1 := mini(image.get_height(), int(centre.y) + half)
	var total := 0.0
	var count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			total += _luma(image.get_pixel(x, y))
			count += 1
	return total / float(maxi(1, count))


## How much brighter the polished pixels got.  The two frames are the same
## camera and the same pose, so anything unchanged contributes nothing: "lift"
## averages only the pixels the polish moved, and "lit" is how much of the box
## that was.  Sky in the box dilutes "mean" but not "lift".
func _sheen_stats(before: Image, after: Image, centre: Vector2, half: int) -> Dictionary:
	var x0 := maxi(0, int(centre.x) - half)
	var x1 := mini(before.get_width(), int(centre.x) + half)
	var y0 := maxi(0, int(centre.y) - half)
	var y1 := mini(before.get_height(), int(centre.y) + half)
	var sum := 0.0
	var lit_sum := 0.0
	var lit := 0
	var count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var delta := _luma(after.get_pixel(x, y)) - _luma(before.get_pixel(x, y))
			sum += delta
			count += 1
			if delta > 0.002:
				lit_sum += delta
				lit += 1
	return {
		"mean": sum / float(maxi(1, count)),
		"lift": lit_sum / float(maxi(1, lit)),
		"lit": float(lit) / float(maxi(1, count)),
		"pixels": lit,
	}


func _report_sheen(before: Image, after: Image) -> void:
	var head := _sheen_stats(before, after, _landmarks["head"], BOX_HALF["head"])
	var barrel := _sheen_stats(before, after, _landmarks["barrel"], BOX_HALF["barrel"])
	print("sheen head: lift=%.4f lit=%.0f%% pixels=%d mean=%.4f" % [
		head["lift"], float(head["lit"]) * 100.0, head["pixels"], head["mean"]])
	print("sheen barrel: lift=%.4f lit=%.0f%% pixels=%d mean=%.4f" % [
		barrel["lift"], float(barrel["lit"]) * 100.0, barrel["pixels"], barrel["mean"]])
	if float(barrel["lift"]) > 0.0:
		print("sheen ratio head/barrel = %.2f" % [float(head["lift"]) / float(barrel["lift"])])
	print("luma before=", _luma_before)



