extends SceneTree

## Builds the competition showground as an ordinary static scene.
##
##   godot --headless --path . --script res://tools/build_arena.gd
##
## Outputs:
##   res://scenes/competition_arena.tscn   venue, actors, HUD and show class
##   res://scenes/show_course.tscn         the ten-fence course it instances
##
## Layout is deliberately flat (y = 0) like the rest of the project.  The ring
## is 60 x 30 m with the gate on the east rail; the grandstand runs down the
## west side, the judges' box sits at the north-west corner, and the warm-up
## ring, lorry park and trade stands fill the ground east of the ring.
##
## Re-running overwrites both scenes.  Edit the tables here rather than the
## generated scenes if you want a change to survive.

const OUT := "res://scenes/competition_arena.tscn"
const COURSE_OUT := "res://scenes/show_course.tscn"
const JUMP_SCENE := "res://scenes/jump_obstacle.tscn"
const HORSE_SCENE := "res://scenes/horse.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const HUD_SCRIPT := "res://scripts/hud.gd"
const SHOW_SCRIPT := "res://scripts/show_class.gd"
const SECRETARY_SCRIPT := "res://scripts/show_secretary.gd"
const BOARD_SCRIPT := "res://scripts/arena_scoreboard.gd"
const DOOR_SCRIPT := "res://scripts/scene_door.gd"
const BELL := "res://assets/sounds/ui/arena_bell.wav"
const CROWD_DIR := "res://Models/props/crowd/"
const PROP_DIR := "res://Models/props/"

const RING_MIN := Vector2(-30.0, -15.0)
const RING_MAX := Vector2(30.0, 15.0)
const GATE_Z0 := -2.0
const GATE_Z1 := 2.0
const RAIL_H := 1.25

const STAND_FRONT := -32.5
const STAND_BACK := -40.0
const STAND_HALF_Z := 12.0
const TIER_DEPTH := 1.5
const TIER_RISE := 0.45
const TIER_COUNT := 5
const ROOF_Y := 4.35

const WARM_MIN := Vector2(40.0, -6.0)
const WARM_MAX := Vector2(62.0, 14.0)
const ENTRANCE := Vector3(34.0, 0.0, 6.0)
## The yard side of the showground gate: just north of the arch on the south
## lane, facing back up the lane toward the stable.
const EXIT_SPAWN_MAIN := Vector3(1.5, 0.05, 22.4)

const CROWD_SCENES := [
	"spectator_seated_a", "spectator_seated_b", "spectator_seated_c",
	"spectator_child", "spectator_standing_a", "spectator_standing_b",
]

const COURSE := [
	{"pos": Vector3(20, 0, -9), "yaw": 0.0, "type": 0, "tier": 2},
	{"pos": Vector3(8, 0, -11), "yaw": 90.0, "type": 3, "tier": 2},
	{"pos": Vector3(-4, 0, -10), "yaw": 0.0, "type": 4, "tier": 1},
	{"pos": Vector3(-18, 0, -8), "yaw": 90.0, "type": 5, "tier": 2},
	{"pos": Vector3(-24, 0, 2), "yaw": 0.0, "type": 6, "tier": 1},
	{"pos": Vector3(-20, 0, 11), "yaw": 90.0, "type": 7, "tier": 2},
	{"pos": Vector3(-6, 0, 10), "yaw": 0.0, "type": 0, "tier": 2},
	{"pos": Vector3(4, 0, 10), "yaw": 0.0, "type": 3, "tier": 2},
	{"pos": Vector3(14, 0, 8), "yaw": 90.0, "type": 4, "tier": 2},
	{"pos": Vector3(22, 0, 2), "yaw": 0.0, "type": 0, "tier": 2},
]

const SPONSORS := [
	"LIVERY", "THE FARRIER'S FORGE", "FEED & SEED", "OAKFIELD STUD",
	"SADDLERY", "HEDGEHOG HOLLOW", "SHOWGROUND", "COPPERFIELD",
]

var _root: Node3D
var _venue: Node3D
var _mats := {}
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 20261023

	var course_root := _build_course()
	_own(course_root, course_root)
	var course_pack := PackedScene.new()
	if course_pack.pack(course_root) != OK:
		push_error("could not pack the show course")
		quit(1)
		return
	if ResourceSaver.save(course_pack, COURSE_OUT) != OK:
		push_error("could not write %s" % COURSE_OUT)
		quit(1)
		return
	print("wrote %s" % COURSE_OUT)

	_root = Node3D.new()
	_root.name = "CompetitionArena"
	_venue = _named(_root, "Venue")

	_build_environment()
	_build_ground()
	_build_ring()
	_build_stand()
	_build_judge_box()
	_build_entrance()
	_build_boards()
	_build_bunting()
	_build_warmup()
	_build_lorry_park()
	_build_marquees()
	_build_scatter()
	_build_crowd()

	var saved_course := ResourceLoader.load(COURSE_OUT, "PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var course := (saved_course if saved_course != null else course_pack).instantiate()
	course.name = "ShowCourse"
	_root.add_child(course)

	_build_show_class()
	_build_scoreboard()
	_build_actors()
	_build_door()

	_own(_root, _root)
	var packed := PackedScene.new()
	if packed.pack(_root) != OK:
		push_error("could not pack the competition arena")
		quit(1)
		return
	if ResourceSaver.save(packed, OUT) != OK:
		push_error("could not write %s" % OUT)
		quit(1)
		return
	print("wrote %s" % OUT)
	quit(0)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		# Instanced scenes keep their own file as the source of their subtree.
		if child.scene_file_path.is_empty():
			_own(child, owner_node)


func _named(parent: Node, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


func _mat(key: String, colour: Color, roughness := 0.92, metallic := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	mat.metallic = metallic
	_mats[key] = mat
	return mat


func _box(parent: Node3D, node_name: String, centre: Vector3, size: Vector3,
		mat: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.transform = Transform3D(basis, centre)
	parent.add_child(instance)
	return instance


func _cyl(parent: Node3D, node_name: String, centre: Vector3, radius: float,
		height: float, mat: Material, sides := 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = centre
	parent.add_child(instance)
	return instance


func _plane(parent: Node3D, node_name: String, centre: Vector3, size: Vector2,
		mat: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = centre
	parent.add_child(instance)
	return instance


func _collider(parent: Node3D, node_name: String, centre: Vector3, size: Vector3,
		basis := Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(basis, centre)
	parent.add_child(body)
	return body


func _beam(parent: Node3D, node_name: String, a: Vector3, b: Vector3,
		width: float, height: float, mat: Material, collide := false) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.001:
		return
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var centre := (a + b) * 0.5
	_box(parent, node_name, centre, Vector3(width, height, length), mat, basis)
	if collide:
		_collider(parent, node_name + "Col", centre + Vector3(0, height * 0.0, 0),
			Vector3(width, height, length), basis)


func _label(parent: Node3D, text: String, pos: Vector3, size: int, colour: Color,
		pixel := 0.005, yaw := 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.05, 0.04, 1.0)
	label.rotation.y = yaw
	parent.add_child(label)
	return label


func _prop(name: String, path: String, pos: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("missing prop %s" % path)
		return null
	var node := packed.instantiate() as Node3D
	node.name = name
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	_venue.add_child(node)
	return node


# ---------------------------------------------------------------------------
# course
# ---------------------------------------------------------------------------

func _build_course() -> Node3D:
	var root := Node3D.new()
	root.name = "ShowCourse"
	var jumps := _named(root, "ShowJumps")
	var packed_jump := load(JUMP_SCENE) as PackedScene
	for i in range(COURSE.size()):
		var entry: Dictionary = COURSE[i]
		var jump := packed_jump.instantiate() as Node3D
		jump.name = "Jump_%02d" % (i + 1)
		jump.position = entry["pos"]
		jump.rotation.y = deg_to_rad(float(entry["yaw"]))
		jump.set("jump_type", int(entry["type"]))
		jump.set("height_tier", int(entry["tier"]))
		jump.set("course_number", i + 1)
		jumps.add_child(jump)
	return root


# ---------------------------------------------------------------------------
# ground and environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.23, 0.42, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.81, 0.88)
	sky_mat.ground_bottom_color = Color(0.18, 0.20, 0.16)
	sky_mat.ground_horizon_color = Color(0.55, 0.60, 0.52)
	sky_mat.ground_curve = 0.03
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.03
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	_root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	_root.add_child(sun)


func _build_ground() -> void:
	var ground := _named(_root, "Ground")
	var grass := _mat("grass", Color(0.30, 0.42, 0.22), 0.96)
	_plane(ground, "Grass", Vector3(0, 0, 0), Vector2(190, 190), grass)
	_collider(ground, "GroundCol", Vector3(0, -0.5, 0), Vector3(190, 1, 190))

	var sand := _mat("sand", Color(0.62, 0.54, 0.39), 0.98)
	_plane(ground, "RingSand", Vector3(0, 0.02, 0), Vector2(RING_MAX.x - RING_MIN.x, RING_MAX.y - RING_MIN.y), sand)

	var warm_sand := _mat("warm_sand", Color(0.58, 0.50, 0.36), 0.98)
	_plane(ground, "WarmSand", Vector3((WARM_MIN.x + WARM_MAX.x) * 0.5, 0.02, (WARM_MIN.y + WARM_MAX.y) * 0.5),
		Vector2(WARM_MAX.x - WARM_MIN.x, WARM_MAX.y - WARM_MIN.y), warm_sand)

	var gravel := _mat("gravel", Color(0.52, 0.50, 0.44), 0.98)
	_plane(ground, "EntranceApron", Vector3(39, 0.015, 6), Vector2(13, 9), gravel)
	_plane(ground, "LorryApron", Vector3(75, 0.015, -11), Vector2(24, 18), gravel)

	# Harrow lines across the ring, a cheap read of a freshly worked surface.
	var harrow := _mat("harrow", Color(0.55, 0.47, 0.33), 0.98)
	for i in range(7):
		var z := -12.0 + i * 4.0
		_box(ground, "Harrow%d" % i, Vector3(0, 0.028, z), Vector3(59.0, 0.01, 0.07), harrow)


# ---------------------------------------------------------------------------
# ring rail, letters and boards
# ---------------------------------------------------------------------------

func _rail_side(parent: Node3D, name: String, a: Vector2, b: Vector2) -> void:
	var post := _mat("post", Color(0.42, 0.29, 0.17), 0.92)
	var rail := _mat("rail", Color(0.62, 0.50, 0.32), 0.92)
	var dir := b - a
	var length := dir.length()
	var steps := int(round(length / 3.0))
	for i in range(steps + 1):
		var t := float(i) / float(maxi(steps, 1))
		var p := a.lerp(b, t)
		_cyl(parent, "%sPost%d" % [name, i], Vector3(p.x, RAIL_H * 0.5, p.y), 0.075, RAIL_H,
			post, 7)
	for height in [0.55, 1.10]:
		_beam(parent, "%sRail%d" % [name, int(height * 100)],
			Vector3(a.x, height, a.y), Vector3(b.x, height, b.y), 0.06, 0.10, rail)
	var centre := Vector3((a.x + b.x) * 0.5, RAIL_H * 0.5, (a.y + b.y) * 0.5)
	var basis := Basis.looking_at(Vector3(b.x - a.x, 0, b.y - a.y).normalized(), Vector3.UP)
	_collider(parent, name + "Body", centre, Vector3(0.14, RAIL_H, length), basis)


func _build_ring() -> void:
	var ring := _named(_venue, "Ring")
	_rail_side(ring, "RailNorth", Vector2(RING_MIN.x, RING_MIN.y), Vector2(RING_MAX.x, RING_MIN.y))
	_rail_side(ring, "RailSouth", Vector2(RING_MIN.x, RING_MAX.y), Vector2(RING_MAX.x, RING_MAX.y))
	_rail_side(ring, "RailWest", Vector2(RING_MIN.x, RING_MIN.y), Vector2(RING_MIN.x, RING_MAX.y))
	_rail_side(ring, "RailEastN", Vector2(RING_MAX.x, RING_MIN.y), Vector2(RING_MAX.x, GATE_Z0))
	_rail_side(ring, "RailEastS", Vector2(RING_MAX.x, GATE_Z1), Vector2(RING_MAX.x, RING_MAX.y))

	# Gate standards, taller than the rail so the entrance reads from a distance.
	var post := _mat("gate_post", Color(0.34, 0.22, 0.13), 0.9)
	var white := _mat("paint_white", Color(0.88, 0.86, 0.78), 0.7)
	for z in [GATE_Z0, GATE_Z1]:
		_box(ring, "GatePost%d" % int(z * 10), Vector3(RING_MAX.x, 1.6, z), Vector3(0.26, 3.2, 0.26), post)
		_box(ring, "GateCap%d" % int(z * 10), Vector3(RING_MAX.x, 3.28, z), Vector3(0.36, 0.12, 0.36), white)
	var start := _label(ring, "START", Vector3(RING_MAX.x + 0.02, 3.55, 0.0), 64, Color(1.0, 0.95, 0.80), 0.006, PI * 0.5)
	start.no_depth_test = true

	# Arena letter markers around the rail.
	var letters := {"A": Vector2(0, RING_MIN.y + 0.6), "K": Vector2(-22, RING_MIN.y + 0.6),
		"E": Vector2(-RING_MAX.x + 0.6, 0), "H": Vector2(-22, RING_MAX.y - 0.6),
		"C": Vector2(0, RING_MAX.y - 0.6), "M": Vector2(22, RING_MAX.y - 0.6),
		"B": Vector2(22, RING_MIN.y + 0.6)}
	for key in letters:
		var p: Vector2 = letters[key]
		_box(ring, "LetterPost" + key, Vector3(p.x, 0.45, p.y), Vector3(0.08, 0.9, 0.08), post)
		_box(ring, "LetterBoard" + key, Vector3(p.x, 0.98, p.y), Vector3(0.62, 0.62, 0.06), white)
		_label(ring, key, Vector3(p.x, 0.98, p.y), 72, Color(0.16, 0.18, 0.14), 0.0045)


# ---------------------------------------------------------------------------
# grandstand
# ---------------------------------------------------------------------------

func _build_stand() -> void:
	var stand := _named(_venue, "Grandstand")
	var timber := _mat("stand_timber", Color(0.46, 0.33, 0.20), 0.9)
	var seat := _mat("stand_seat", Color(0.62, 0.48, 0.30), 0.88)
	var dark := _mat("stand_dark", Color(0.28, 0.20, 0.12), 0.92)
	var roof := _mat("stand_roof", Color(0.42, 0.16, 0.12), 0.9)
	var white := _mat("paint_white", Color(0.88, 0.86, 0.78), 0.7)

	for i in range(TIER_COUNT):
		var top := TIER_RISE * float(i + 1)
		var front := STAND_FRONT - TIER_DEPTH * float(i)
		var centre := Vector3(front - TIER_DEPTH * 0.5, top * 0.5, 0.0)
		_box(stand, "Tier%d" % i, centre, Vector3(TIER_DEPTH, top, STAND_HALF_Z * 2.0), timber)
		_collider(stand, "Tier%dCol" % i, centre, Vector3(TIER_DEPTH, top, STAND_HALF_Z * 2.0))
		var seat_z := 0.0
		_box(stand, "Bench%d" % i, Vector3(front + 0.22, top + 0.42, seat_z),
			Vector3(0.46, 0.09, STAND_HALF_Z * 2.0 - 0.4), seat)
		for z in [-STAND_HALF_Z + 0.4, 0.0, STAND_HALF_Z - 0.4]:
			_box(stand, "BenchLeg%d_%d" % [i, int(z)], Vector3(front + 0.22, top + 0.21, z),
				Vector3(0.35, 0.42, 0.09), dark)

	# Front rail, so nobody walks off the bottom tier into the ring.
	for i in range(9):
		var z := -STAND_HALF_Z + 1.5 + i * 3.0
		_cyl(stand, "FrontPost%d" % i, Vector3(STAND_FRONT + 0.15, 0.55, z), 0.055, 1.10, white, 6)
	_beam(stand, "FrontRail", Vector3(STAND_FRONT + 0.15, 1.05, -STAND_HALF_Z),
		Vector3(STAND_FRONT + 0.15, 1.05, STAND_HALF_Z), 0.07, 0.09, white, true)

	# Roof and posts.
	_box(stand, "Roof", Vector3((STAND_FRONT + STAND_BACK) * 0.5, ROOF_Y, 0),
		Vector3(STAND_FRONT - STAND_BACK + 0.8, 0.24, STAND_HALF_Z * 2.0 + 1.2), roof)
	_box(stand, "RoofFascia", Vector3(STAND_FRONT + 0.35, ROOF_Y - 0.22, 0),
		Vector3(0.16, 0.42, STAND_HALF_Z * 2.0 + 1.2), white)
	for iz in range(7):
		var z := -STAND_HALF_Z + iz * (STAND_HALF_Z * 2.0 / 6.0)
		_cyl(stand, "RoofPost%d" % iz, Vector3(STAND_BACK + 0.35, ROOF_Y * 0.5, z), 0.11,
			ROOF_Y, dark, 8)
		_cyl(stand, "RoofPostFront%d" % iz, Vector3(STAND_FRONT + 0.3, ROOF_Y * 0.5, z), 0.10,
			ROOF_Y, dark, 8)

	# A ramp up the south end so the stand can be walked.
	var ramp_start := Vector3(STAND_FRONT + 0.2, 0.02, STAND_HALF_Z + 1.3)
	var ramp_end := Vector3(STAND_BACK + 0.2, TIER_RISE * TIER_COUNT, STAND_HALF_Z + 1.3)
	var ramp_len := ramp_start.distance_to(ramp_end)
	var pitch := atan2(ramp_end.y - ramp_start.y, ramp_end.x - ramp_start.x)
	var ramp_basis := Basis(Vector3(0, 0, 1), -pitch)
	_box(stand, "Ramp", (ramp_start + ramp_end) * 0.5 + Vector3(0, 0.04, 0),
		Vector3(ramp_len, 0.10, 1.5), seat, ramp_basis)
	_collider(stand, "RampCol", (ramp_start + ramp_end) * 0.5,
		Vector3(ramp_len, 0.10, 1.5), ramp_basis)


# ---------------------------------------------------------------------------
# judges' box and scoreboard
# ---------------------------------------------------------------------------

func _build_judge_box() -> void:
	var box := _named(_venue, "JudgesBox")
	var timber := _mat("judge_timber", Color(0.40, 0.28, 0.16), 0.9)
	var deck := _mat("judge_deck", Color(0.55, 0.42, 0.26), 0.9)
	var white := _mat("paint_white", Color(0.88, 0.86, 0.78), 0.7)
	var roof := _mat("judge_roof", Color(0.40, 0.17, 0.12), 0.9)
	var centre := Vector3(-35.5, 0, -19.5)

	_box(box, "Deck", centre + Vector3(0, 0.55, 0), Vector3(6.0, 1.10, 4.0), deck)
	_collider(box, "DeckCol", centre + Vector3(0, 0.55, 0), Vector3(6.0, 1.10, 4.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(box, "Leg%d%d" % [int(sx), int(sz)], centre + Vector3(sx * 2.6, 0.55, sz * 1.6),
				Vector3(0.16, 1.10, 0.16), timber)
	# Ramp up the ring side.
	var ramp_start := centre + Vector3(0, 0.02, 3.6)
	var ramp_end := centre + Vector3(0, 1.10, 2.0)
	var pitch := atan2(ramp_end.y - ramp_start.y, ramp_end.z - ramp_start.z)
	var basis := Basis(Vector3(1, 0, 0), pitch)
	_box(box, "Ramp", (ramp_start + ramp_end) * 0.5, Vector3(1.4, 0.10, 1.8), deck, basis)
	_collider(box, "RampCol", (ramp_start + ramp_end) * 0.5, Vector3(1.4, 0.10, 1.8), basis)

	# Desk, bell, papers and a canopy.
	_box(box, "Desk", centre + Vector3(0, 1.55, 0.4), Vector3(3.0, 0.10, 1.0), deck)
	for sx in [-1.0, 1.0]:
		_box(box, "DeskLeg%d" % int(sx), centre + Vector3(sx * 1.35, 1.32, 0.4),
			Vector3(0.12, 0.55, 0.85), timber)
	_box(box, "Paper", centre + Vector3(-0.6, 1.62, 0.35), Vector3(0.35, 0.02, 0.5), white)
	var bell_path := PROP_DIR + "arena/judge_bell.glb"
	_prop("JudgeBell", bell_path, centre + Vector3(0.15, 1.60, 0.4), deg_to_rad(20.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(box, "CanopyPost%d%d" % [int(sx), int(sz)], centre + Vector3(sx * 2.7, 2.15, sz * 1.7),
				0.08, 4.2, timber, 6)
	_box(box, "Canopy", centre + Vector3(0, 4.25, 0), Vector3(6.4, 0.18, 4.4), roof)

	# Rosette presentation table in front of the box.
	_box(box, "RosetteTable", centre + Vector3(2.4, 0.75, 2.4), Vector3(1.4, 0.08, 0.8), deck)
	for sx in [-1.0, 1.0]:
		_box(box, "RosetteTableLeg%d" % int(sx), centre + Vector3(2.4 + sx * 0.55, 0.37, 2.4),
			Vector3(0.10, 0.74, 0.7), timber)
	var rosette_node := Node3D.new()
	rosette_node.name = "RosetteStand"
	rosette_node.position = centre + Vector3(0.4, 0, 3.1)
	rosette_node.set_script(load(SECRETARY_SCRIPT))
	rosette_node.set("mode", "rosette")
	rosette_node.set("prompt_label", "COLLECT ROSETTE")
	box.add_child(rosette_node)


func _build_scoreboard() -> void:
	var board := Node3D.new()
	board.name = "Scoreboard"
	board.position = Vector3(-35.5, 2.55, -22.4)
	board.set_script(load(BOARD_SCRIPT))
	_venue.add_child(board)

	var face := _mat("board_face", Color(0.14, 0.20, 0.15), 0.9)
	var frame := _mat("board_frame", Color(0.44, 0.30, 0.17), 0.9)
	var white := _mat("paint_white", Color(0.88, 0.86, 0.78), 0.7)
	_box(board, "BoardFace", Vector3(0, 0, 0), Vector3(4.6, 2.5, 0.12), face)
	for sx in [-1.0, 1.0]:
		_box(board, "BoardPost%d" % int(sx), Vector3(sx * 2.2, -1.35, 0), Vector3(0.18, 2.7, 0.18), frame)
	_box(board, "BoardTop", Vector3(0, 1.32, 0), Vector3(4.8, 0.16, 0.2), white)
	var accent := _mat("board_accent", Color(0.52, 0.10, 0.08), 0.8)
	_box(board, "BoardHeader", Vector3(0, 1.05, 0.07), Vector3(4.4, 0.26, 0.03), accent)

	# A second, hand-lettered class board beside the ring.
	var class_board := Node3D.new()
	class_board.name = "ClassBoard"
	class_board.position = Vector3(31.6, 0, 11.5)
	class_board.rotation.y = deg_to_rad(-90.0)
	_venue.add_child(class_board)
	_box(class_board, "Stand", Vector3(0, 0.75, 0), Vector3(1.9, 1.5, 0.12), frame)
	_box(class_board, "Face", Vector3(0, 0.75, 0.08), Vector3(1.7, 1.3, 0.03), _mat("paper", Color(0.86, 0.84, 0.74), 0.95))
	_label(class_board, "CLASS 1\n1.05 m OPEN\n10 fences", Vector3(0, 0.80, 0.10), 30,
		Color(0.14, 0.15, 0.12), 0.004)


# ---------------------------------------------------------------------------
# entrance, sponsors, flags and bunting
# ---------------------------------------------------------------------------

func _build_entrance() -> void:
	var gate := _named(_venue, "Entrance")
	var timber := _mat("entrance_timber", Color(0.38, 0.25, 0.14), 0.9)
	var white := _mat("paint_white", Color(0.88, 0.86, 0.78), 0.7)
	var red := _mat("paint_red", Color(0.52, 0.10, 0.08), 0.8)
	_box(gate, "ArchLeft", ENTRANCE + Vector3(0, 2.0, -2.6), Vector3(0.30, 4.0, 0.30), timber)
	_box(gate, "ArchRight", ENTRANCE + Vector3(0, 2.0, 2.6), Vector3(0.30, 4.0, 0.30), timber)
	_box(gate, "ArchBeam", ENTRANCE + Vector3(0, 4.15, 0), Vector3(0.34, 0.34, 5.9), timber)
	_box(gate, "Banner", ENTRANCE + Vector3(0, 4.62, 0), Vector3(0.12, 0.72, 4.6), red)
	_box(gate, "SubBanner", ENTRANCE + Vector3(0, 3.72, 0), Vector3(0.10, 0.52, 4.2), red)
	# Same banner on both faces: riders see it from the ring, spectators from the
	# warm-up side, and neither view shows mirrored lettering.
	var west_title := _label(gate, "SHOWGROUND", ENTRANCE + Vector3(-0.09, 4.66, 0), 96,
		Color(0.98, 0.94, 0.82), 0.0058, -PI * 0.5)
	west_title.double_sided = false
	var west_subtitle := _label(gate, "SUMMER SHOW  ·  CLASS 1 TODAY", ENTRANCE + Vector3(-0.09, 3.72, 0), 44,
		Color(0.98, 0.94, 0.82), 0.0048, -PI * 0.5)
	west_subtitle.double_sided = false
	var east_title := _label(gate, "SHOWGROUND", ENTRANCE + Vector3(0.09, 4.66, 0), 96,
		Color(0.98, 0.94, 0.82), 0.0058, PI * 0.5)
	east_title.double_sided = false
	var east_subtitle := _label(gate, "SUMMER SHOW  ·  CLASS 1 TODAY", ENTRANCE + Vector3(0.09, 3.72, 0), 44,
		Color(0.98, 0.94, 0.82), 0.0048, PI * 0.5)
	east_subtitle.double_sided = false
	for sx in [-1.0, 1.0]:
		_box(gate, "ArchFoot%d" % int(sx), ENTRANCE + Vector3(0, 0.12, sx * 2.6),
			Vector3(0.42, 0.24, 0.42), white)

	# Flag poles either side of the arch.
	for i in range(2):
		var p := ENTRANCE + Vector3(-1.0, 0, -4.6 + i * 9.2)
		_cyl(gate, "FlagPole%d" % i, p + Vector3(0, 3.2, 0), 0.06, 6.4, white, 6)
		var pennant := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.95, 1.5, 0.04)
		pennant.mesh = mesh
		pennant.material_override = red if i == 0 else _mat("paint_blue", Color(0.10, 0.17, 0.36), 0.8)
		pennant.position = p + Vector3(0, 5.85, 0.5)
		pennant.rotation = Vector3(0, 0, 0)
		gate.add_child(pennant)

	# Secretary's desk beside the entrance.
	var desk := _named(gate, "EntriesDesk")
	desk.position = Vector3(37.4, 0, 10.4)
	_box(desk, "Table", Vector3(0, 0.78, 0), Vector3(2.0, 0.10, 0.9), timber)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(desk, "Leg%d%d" % [int(sx), int(sz)], Vector3(sx * 0.85, 0.39, sz * 0.35),
				Vector3(0.10, 0.78, 0.10), timber)
	_box(desk, "Ledger", Vector3(-0.35, 0.85, 0.05), Vector3(0.55, 0.04, 0.38), white)
	_box(desk, "Sign", Vector3(0, 1.15, -0.4), Vector3(1.5, 0.55, 0.06), _mat("paper", Color(0.86, 0.84, 0.74), 0.95))
	_label(desk, "ENTRIES", Vector3(0, 1.15, -0.36), 46, Color(0.16, 0.17, 0.12), 0.0042)
	# Local to the desk: the desk already sits at x 37.4, z 10.4.
	var secretary := Node3D.new()
	secretary.name = "Secretary"
	secretary.position = Vector3(0.0, 0.0, -0.9)
	secretary.set_script(load(SECRETARY_SCRIPT))
	secretary.set("mode", "entry")
	secretary.set("prompt_label", "ENTER CLASS")
	desk.add_child(secretary)


func _build_boards() -> void:
	var boards := _named(_venue, "SponsorBoards")
	var frame := _mat("board_frame", Color(0.44, 0.30, 0.17), 0.9)
	var colours := [
		Color(0.20, 0.30, 0.44), Color(0.50, 0.14, 0.10), Color(0.16, 0.28, 0.20),
		Color(0.44, 0.34, 0.12), Color(0.30, 0.20, 0.34),
	]
	var spots := []
	for i in range(6):
		spots.append({"pos": Vector3(-22.0 + i * 9.0, 1.05, 16.4), "yaw": PI})
	for i in range(2):
		spots.append({"pos": Vector3(31.9, 1.05, -10.0 + i * 17.0), "yaw": -PI * 0.5})
	for i in range(spots.size()):
		var spot: Dictionary = spots[i]
		var board := _named(boards, "Board%d" % (i + 1))
		board.position = spot["pos"]
		board.rotation.y = spot["yaw"]
		_box(board, "Face", Vector3(0, 0, 0), Vector3(3.2, 1.05, 0.08),
			_mat("sponsor_%d" % (i % colours.size()), colours[i % colours.size()], 0.85))
		_box(board, "FrameTop", Vector3(0, 0.57, 0), Vector3(3.36, 0.10, 0.14), frame)
		_box(board, "FrameBottom", Vector3(0, -0.57, 0), Vector3(3.36, 0.10, 0.14), frame)
		for sx in [-1.0, 1.0]:
			_box(board, "BoardPost%d" % int(sx), Vector3(sx * 1.5, -0.55, 0),
				Vector3(0.10, 1.1, 0.10), frame)
		_label(board, SPONSORS[i % SPONSORS.size()], Vector3(0, 0.05, 0.07), 54,
			Color(0.97, 0.95, 0.86), 0.0058)


func _build_bunting() -> void:
	var bunting := _named(_venue, "Bunting")
	var colours := [
		_mat("paint_white", Color(0.88, 0.86, 0.78), 0.7),
		_mat("paint_red", Color(0.52, 0.10, 0.08), 0.8),
		_mat("paint_blue", Color(0.10, 0.17, 0.36), 0.8),
	]
	var lines := [
		[Vector3(STAND_FRONT + 0.4, 3.95, -STAND_HALF_Z), Vector3(STAND_FRONT + 0.4, 3.95, STAND_HALF_Z)],
		[Vector3(ENTRANCE.x - 1.0, 5.55, ENTRANCE.z - 4.6), Vector3(ENTRANCE.x - 1.0, 5.55, ENTRANCE.z + 4.6)],
	]
	for line_index in range(lines.size()):
		var a: Vector3 = lines[line_index][0]
		var b: Vector3 = lines[line_index][1]
		var count := 14
		for i in range(count):
			var t := (float(i) + 0.5) / float(count)
			var p := a.lerp(b, t)
			p.y -= sin(t * PI) * 0.35
			var flag := MeshInstance3D.new()
			var mesh := PrismMesh.new()
			mesh.size = Vector3(0.30, 0.44, 0.02)
			flag.mesh = mesh
			flag.material_override = colours[i % colours.size()]
			flag.position = p
			flag.rotation = Vector3(0, 0, PI)
			bunting.add_child(flag)


# ---------------------------------------------------------------------------
# warm-up ring, lorry park, trade stands
# ---------------------------------------------------------------------------

func _build_warmup() -> void:
	var warm := _named(_venue, "WarmUp")
	_rail_side(warm, "RailNorth", Vector2(WARM_MIN.x, WARM_MIN.y), Vector2(WARM_MAX.x, WARM_MIN.y))
	_rail_side(warm, "RailSouth", Vector2(WARM_MIN.x, WARM_MAX.y), Vector2(WARM_MAX.x, WARM_MAX.y))
	_rail_side(warm, "RailEast", Vector2(WARM_MAX.x, WARM_MIN.y), Vector2(WARM_MAX.x, WARM_MAX.y))
	_rail_side(warm, "RailWestN", Vector2(WARM_MIN.x, WARM_MIN.y), Vector2(WARM_MIN.x, 2.0))
	_rail_side(warm, "RailWestS", Vector2(WARM_MIN.x, 6.0), Vector2(WARM_MIN.x, WARM_MAX.y))

	var packed_jump := load(JUMP_SCENE) as PackedScene
	for i in range(2):
		var jump := packed_jump.instantiate() as Node3D
		jump.name = "Practice_%02d" % (i + 1)
		jump.position = Vector3(45.0 + i * 8.0, 0, 2.0 + i * 4.0)
		jump.rotation.y = deg_to_rad(90.0)
		jump.set("jump_type", 0 if i == 0 else 3)
		jump.set("height_tier", 0 if i == 0 else 1)
		warm.add_child(jump)

	_prop("MountingBlock", PROP_DIR + "stable/mounting_block.glb", Vector3(40.8, 0, 0.0), deg_to_rad(90.0))
	_prop("HitchingPost", PROP_DIR + "stable/hitching_post.glb", Vector3(41.0, 0, 17.0), 0.0)
	_prop("WaterTrough", PROP_DIR + "stable/water_trough.glb", Vector3(63.0, 0, 0.0), deg_to_rad(90.0))
	_prop("HayRound", PROP_DIR + "stable/hay_round.glb", Vector3(64.0, 0, 17.0), 0.0)


func _build_lorry_park() -> void:
	var park := _named(_venue, "LorryPark")
	var body := _mat("lorry_body", Color(0.72, 0.72, 0.68), 0.8)
	var stripe := _mat("lorry_stripe", Color(0.24, 0.34, 0.42), 0.8)
	var tyre := _mat("tyre", Color(0.07, 0.07, 0.07), 0.95)
	for i in range(3):
		var x := 68.0 + i * 6.0
		var trailer := _named(park, "Trailer%d" % (i + 1))
		trailer.position = Vector3(x, 0, -11.0)
		_box(trailer, "Body", Vector3(0, 1.75, 0), Vector3(5.4, 2.2, 2.3), body)
		_box(trailer, "Stripe", Vector3(0, 1.30, 0), Vector3(5.42, 0.28, 2.32), stripe)
		_box(trailer, "Chassis", Vector3(0, 0.62, 0), Vector3(5.6, 0.22, 1.8), tyre)
		_box(trailer, "Drawbar", Vector3(3.2, 0.72, 0), Vector3(1.2, 0.12, 0.14), tyre)
		for sx in [-1.0, 1.0]:
			for dz in [-1.6, 1.6]:
				var wheel := _cyl(trailer, "Wheel%d%d" % [int(sx), int(dz)], Vector3(sx * 1.8, 0.52, dz),
					0.52, 0.24, tyre, 12)
				wheel.rotation.z = PI * 0.5
		_collider(park, "Trailer%dCol" % (i + 1), Vector3(x, 1.2, -11.0), Vector3(5.4, 2.4, 2.3))


func _build_marquees() -> void:
	var stands := _named(_venue, "TradeStands")
	var canvas := _mat("marquee_canvas", Color(0.86, 0.82, 0.70), 0.95)
	var stripe := _mat("marquee_stripe", Color(0.52, 0.10, 0.08), 0.9)
	var timber := _mat("stall_timber", Color(0.44, 0.30, 0.17), 0.9)
	for i in range(3):
		var stall := _named(stands, "Stall%d" % (i + 1))
		stall.position = Vector3(42.0 + i * 8.0, 0, 24.0)
		_box(stall, "Back", Vector3(0, 1.1, -2.4), Vector3(6.0, 2.2, 0.12), canvas)
		for sx in [-1.0, 1.0]:
			_box(stall, "Side%d" % int(sx), Vector3(sx * 2.9, 1.1, 0), Vector3(0.10, 2.2, 4.8), canvas)
			_cyl(stall, "PostA%d" % int(sx), Vector3(sx * 2.9, 1.2, 2.35), 0.08, 2.4, timber, 6)
		_box(stall, "FrontBeam", Vector3(0, 2.42, 2.3), Vector3(6.0, 0.16, 0.16), timber)
		# Striped awning, alternating panels.
		for j in range(6):
			var mat := stripe if j % 2 == 0 else canvas
			_box(stall, "Awning%d" % j, Vector3(-2.5 + j * 1.0, 2.62, 1.1),
				Vector3(1.0, 0.08, 2.6), mat, Basis(Vector3(1, 0, 0), deg_to_rad(-9.0)))
		_box(stall, "Table", Vector3(0, 0.78, 1.0), Vector3(4.6, 0.10, 0.8), timber)
		for sx in [-1.0, 1.0]:
			_box(stall, "TableLeg%d" % int(sx), Vector3(sx * 2.0, 0.39, 1.0),
				Vector3(0.10, 0.78, 0.7), timber)
		_prop("StallCrate%d" % i, PROP_DIR + "yard/crate.glb", stall.position + Vector3(2.2, 0, -1.8), 0.3)
		_prop("StallBench%d" % i, PROP_DIR + "yard/bench.glb", stall.position + Vector3(0, 0, 3.8), 0.0)


# ---------------------------------------------------------------------------
# planting and crowd
# ---------------------------------------------------------------------------

func _build_scatter() -> void:
	var scatter := _named(_venue, "Planting")
	var trees := ["tree_oak_02", "tree_birch", "tree_pine_02", "tree_oak_autumn", "tree_willow"]
	var bushes := ["bush_large", "bush_round", "bush_flower"]
	for i in range(9):
		var x := -44.0 + i * 5.0
		var name: String = trees[i % trees.size()]
		_prop("Tree%d" % i, PROP_DIR + "trees/" + name + ".glb", Vector3(x, 0, -30.0),
			deg_to_rad(_rng.randf_range(0, 360)))
	for i in range(8):
		var z := -24.0 + i * 7.0
		_prop("EastTree%d" % i, PROP_DIR + "trees/" + trees[(i + 2) % trees.size()] + ".glb",
			Vector3(88.0, 0, z), deg_to_rad(_rng.randf_range(0, 360)))
	for i in range(10):
		var x := -40.0 + i * 8.0
		_prop("Bush%d" % i, PROP_DIR + "bushes/" + bushes[i % bushes.size()] + ".glb",
			Vector3(x, 0, 31.5), deg_to_rad(_rng.randf_range(0, 360)))
	# Planters and lamps dress the entrance and the judges' box.
	_prop("PlanterA", PROP_DIR + "yard/flower_planter.glb", Vector3(31.6, 0, 4.0), 0.0)
	_prop("PlanterB", PROP_DIR + "yard/flower_planter.glb", Vector3(31.6, 0, 8.0), 0.0)
	_prop("PlanterC", PROP_DIR + "yard/flower_planter.glb", Vector3(-31.4, 0, -13.0), 0.0)
	_prop("LanternA", PROP_DIR + "yard/lantern_post.glb", Vector3(32.2, 0, 12.5), 0.0)
	_prop("LanternB", PROP_DIR + "yard/lantern_post.glb", Vector3(32.2, 0, -0.5), 0.0)


func _build_crowd() -> void:
	var crowd := _named(_venue, "Crowd")
	var scenes := []
	for key in CROWD_SCENES:
		scenes.append(load(CROWD_DIR + key + ".glb") as PackedScene)

	var seated := [0, 1, 2, 3]
	var index := 0
	for tier in range(TIER_COUNT):
		var top := TIER_RISE * float(tier + 1)
		var front := STAND_FRONT - TIER_DEPTH * float(tier)
		var row_z := -STAND_HALF_Z + 1.2
		while row_z < STAND_HALF_Z - 1.0:
			if _rng.randf() > 0.18:
				var key: int = seated[_rng.randi_range(0, seated.size() - 1)]
				var packed: PackedScene = scenes[key]
				var figure := packed.instantiate() as Node3D
				figure.name = "Seated%d" % index
				figure.position = Vector3(front + 0.22, top + 0.46, row_z)
				figure.rotation.y = deg_to_rad(-90.0)
				crowd.add_child(figure)
				index += 1
			row_z += 2.1

	# A few people standing at the rail and by the entrance.
	var standing := [4, 5]
	var spots := [
		Vector3(-31.4, 0, -8.0), Vector3(-31.4, 0, 2.5), Vector3(-31.4, 0, 9.0),
		Vector3(31.4, 0, 12.0), Vector3(31.4, 0, -6.0), Vector3(35.4, 0, 12.6),
		Vector3(-33.0, 0, -14.2),
	]
	for i in range(spots.size()):
		var packed: PackedScene = scenes[standing[i % standing.size()]]
		var figure := packed.instantiate() as Node3D
		figure.name = "Standing%d" % i
		figure.position = spots[i]
		figure.rotation.y = deg_to_rad(_rng.randf_range(-180, 180))
		crowd.add_child(figure)


# ---------------------------------------------------------------------------
# show class, actors and the door home
# ---------------------------------------------------------------------------

func _build_show_class() -> void:
	var node := Node3D.new()
	node.name = "ShowClass"
	node.set_script(load(SHOW_SCRIPT))
	node.set("jumps_root_path", NodePath("../ShowCourse/ShowJumps"))
	node.set("class_label", "CLASS 1 · 1.05 m OPEN")
	node.set("entry_fee", 20)
	_root.add_child(node)

	var bell := AudioStreamPlayer.new()
	bell.name = "BellAudio"
	if ResourceLoader.exists(BELL):
		bell.stream = load(BELL)
	bell.volume_db = -2.0
	node.add_child(bell)


func _build_actors() -> void:
	var horse_packed := load(HORSE_SCENE) as PackedScene
	var horse := horse_packed.instantiate() as Node3D
	horse.name = "Horse"
	horse.position = Vector3(32.0, 0, 11.0)
	horse.rotation.y = deg_to_rad(90.0)
	_root.add_child(horse)

	var player_packed := load(PLAYER_SCENE) as PackedScene
	var player := player_packed.instantiate() as Node3D
	player.name = "Player"
	player.position = Vector3(31.0, 0, 6.5)
	player.rotation.y = deg_to_rad(90.0)
	_root.add_child(player)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load(HUD_SCRIPT))
	_root.add_child(hud)


func _build_door() -> void:
	var door := Node3D.new()
	door.name = "ExitDoor"
	door.position = ENTRANCE
	door.set_script(load(DOOR_SCRIPT))
	door.set("target_scene", "res://scenes/main.tscn")
	door.set("prompt_label", "EXIT SHOWGROUND")
	door.set("prompt_height", 2.6)
	door.set("reach", 2.4)
	door.set("spawn_position", EXIT_SPAWN_MAIN)
	door.set("spawn_yaw_degrees", 0.0)
	_root.add_child(door)
