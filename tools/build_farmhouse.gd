extends SceneTree

## Builds the two-storey farmhouse interior as an ordinary static scene.
##
##   godot --headless --path . --script res://tools/build_farmhouse.gd
##
## Output: res://scenes/farmhouse.tscn
##
## The shell (floors, walls with real window and door openings, ceilings,
## stairs, trim) comes from the plan below.  Furniture is instanced from
## Kenney's CC0 Furniture Kit in Models/interior/kenney_furniture_kit/ and
## placed from the PROP table.  Every prop is measured, centred on its
## footprint and dropped onto its floor, so the kit's baked pivots cannot
## leave a chair floating.
##
## Windows and doors are declared once in WINDOWS / DOORS: the wall openings
## and the frames, glass and leaves are both derived from those tables, so they
## cannot drift apart.
##
## Re-running overwrites scenes/farmhouse.tscn.  Edit the tables here rather
## than the generated scene if you want the change to survive.

const OUT := "res://scenes/farmhouse.tscn"
const KIT := "res://Models/interior/kenney_furniture_kit/"
const TEX_FLOOR := "res://Models/interior/textures/wood_floor_diff_1k.jpg"
const TEX_WALL := "res://Models/interior/textures/painted_plaster_wall_diff_1k.jpg"
const PLAYER := "res://scenes/player.tscn"
const SPOT := "res://scripts/interior_spot.gd"
const DOOR := "res://scripts/scene_door.gd"
## Outside spawn in main.tscn, just in front of the fantasy house's front door.
const HOUSE_DOOR_SPAWN := Vector3(36.978477, 0.05, -30.9)
const HOUSE_DOOR_SPAWN_YAW := 180.0

# Plan.  Room rectangles below are the clear space between wall faces.
const X0 := -5.5
const X1 := 5.5
const Z0 := -4.5
const Z1 := 4.5
const GROUND_CEIL := 2.60
const GROUND_SLAB := 2.66
const UPPER_FLOOR := 2.72
const UPPER_CEIL := 5.06
const UPPER_TOP := 5.12
const WALL_T := 0.30
const PART_T := 0.12
const FLOOR_T := 0.30

# Stair: an L-shaped flight in the hall's south-east corner.  The lower flight
# climbs south along the east wall to a quarter landing, then the upper flight
# turns west along the south wall and finishes on the gallery floor in front of
# the bedroom doors.  The foot faces north into the hall, so it is walked into
# end-on; the top opens onto real floor rather than the wall.
const STAIR_WIDTH := 1.00
const STAIR_RISERS := 15
const RISER := UPPER_FLOOR / float(STAIR_RISERS)
const STAIR_X0 := 4.35
const STAIR_X1 := 5.35
const STAIR_CX := (STAIR_X0 + STAIR_X1) * 0.5
const LOWER_Z_BOTTOM := 0.85
const LOWER_Z_TOP := -1.14
const LOWER_RISERS := 6
const LANDING_TOP := RISER * float(LOWER_RISERS)
const UPPER_Z0 := -2.14
const UPPER_Z1 := -1.14
const STAIR_Z_MID := (UPPER_Z0 + UPPER_Z1) * 0.5
const UPPER_X_START := 4.35
const UPPER_X_END := 2.36
const UPPER_RISERS := 9
const STAIR_GUARD_HEIGHT := 0.96

const GROUND_SILL := 0.95
const GROUND_HEAD := 2.10
const UPPER_SILL := UPPER_FLOOR + 0.95

# Each entry: name, axis the wall runs along, the plane it sits in, the centre
# along that axis, plus the opening.  "base" is the floor the window serves.
const WINDOWS := [
	{"name": "SittingSouthA", "axis": "x", "plane": Z0, "centre": -3.95, "width": 1.25, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingSouthB", "axis": "x", "plane": Z0, "centre": -1.35, "width": 1.25, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "StudySouth", "axis": "x", "plane": Z0, "centre": 4.15, "width": 1.20, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenNorth", "axis": "x", "plane": Z1, "centre": -4.35, "width": 1.25, "sill": GROUND_SILL + 0.15, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingWest", "axis": "z", "plane": X0, "centre": -1.05, "width": 1.05, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenWest", "axis": "z", "plane": X0, "centre": 2.65, "width": 1.05, "sill": GROUND_SILL + 0.10, "head": GROUND_HEAD, "base": 0.0},
	{"name": "StudyEast", "axis": "z", "plane": X1, "centre": -3.50, "width": 0.90, "sill": GROUND_SILL + 0.20, "head": GROUND_HEAD, "base": 0.0},
	{"name": "HallEast", "axis": "z", "plane": X1, "centre": 0.10, "width": 0.95, "sill": GROUND_SILL + 0.25, "head": GROUND_HEAD, "base": 0.0},
	{"name": "BootEast", "axis": "z", "plane": X1, "centre": 3.30, "width": 0.85, "sill": GROUND_SILL + 0.25, "head": GROUND_HEAD, "base": 0.0},
	{"name": "MainBedSouthA", "axis": "x", "plane": Z0, "centre": -3.85, "width": 1.15, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "MainBedSouthB", "axis": "x", "plane": Z0, "centre": -1.25, "width": 1.15, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "LandingSouth", "axis": "x", "plane": Z0, "centre": 4.15, "width": 1.15, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "SecondBedNorth", "axis": "x", "plane": Z1, "centre": -3.90, "width": 1.15, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "BathNorth", "axis": "x", "plane": Z1, "centre": 4.35, "width": 0.85, "sill": UPPER_FLOOR + 1.15, "head": UPPER_FLOOR + 1.85, "base": UPPER_FLOOR},
	{"name": "MainBedWest", "axis": "z", "plane": X0, "centre": -1.20, "width": 1.05, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "SecondBedWest", "axis": "z", "plane": X0, "centre": 2.40, "width": 1.05, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "GalleryEast", "axis": "z", "plane": X1, "centre": 0.90, "width": 1.00, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
	{"name": "LandingEast", "axis": "z", "plane": X1, "centre": -3.40, "width": 0.95, "sill": UPPER_SILL, "head": UPPER_FLOOR + 1.95, "base": UPPER_FLOOR},
]

# Doors and openings.  "leaf" true adds a closed exterior door.
const DOORS := [
	{"name": "SittingHall", "axis": "z", "plane": 1.4, "centre": -0.60, "width": 0.95, "head": 2.05, "base": 0.0, "leaf": false},
	{"name": "KitchenHall", "axis": "z", "plane": 1.4, "centre": 1.00, "width": 0.95, "head": 2.05, "base": 0.0, "leaf": false},
	{"name": "SittingKitchen", "axis": "x", "plane": 0.0, "centre": -2.20, "width": 1.45, "head": 2.30, "base": 0.0, "leaf": false},
	{"name": "StudyHall", "axis": "x", "plane": -2.2, "centre": 2.50, "width": 0.95, "head": 2.05, "base": 0.0, "leaf": false},
	{"name": "BootHall", "axis": "x", "plane": 2.2, "centre": 4.20, "width": 0.95, "head": 2.05, "base": 0.0, "leaf": false},
	{"name": "MainBed", "axis": "z", "plane": 1.4, "centre": -1.30, "width": 0.95, "head": UPPER_FLOOR + 2.05, "base": UPPER_FLOOR, "leaf": false},
	{"name": "SecondBed", "axis": "z", "plane": 1.4, "centre": 0.60, "width": 0.95, "head": UPPER_FLOOR + 2.05, "base": UPPER_FLOOR, "leaf": false},
	{"name": "Bath", "axis": "x", "plane": 2.2, "centre": 4.20, "width": 0.90, "head": UPPER_FLOOR + 2.05, "base": UPPER_FLOOR, "leaf": false},
	{"name": "FrontDoor", "axis": "z", "plane": X1, "centre": 1.55, "width": 1.05, "head": 2.15, "base": 0.0, "leaf": true},
	{"name": "BackDoor", "axis": "x", "plane": Z1, "centre": 3.10, "width": 0.95, "head": 2.10, "base": 0.0, "leaf": true},
]

# The kit's upholstery colour.  Everything the PROP table marks as "fabric"
# swaps this pink for a colour that suits the house; wood, metal and porcelain
# surfaces keep the kit's own colours.
const KIT_FABRIC := Color(0.9747, 0.6399, 0.6202)
const FABRIC_GREEN := Color(0.40, 0.45, 0.36)
const FABRIC_CREAM := Color(0.88, 0.85, 0.78)
const FABRIC_TERRACOTTA := Color(0.53, 0.35, 0.28)

var _root: Node3D
var _shell: Node3D
var _structure: StaticBody3D
var _furniture: Node3D
var _spots: Node3D
var _lighting: Node3D
var _materials := {}
var _kit := {}


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Farmhouse"
	_shell = _named(_root, "Shell")
	_structure = StaticBody3D.new()
	_structure.name = "Structure"
	_structure.collision_layer = 1
	_shell.add_child(_structure)
	_furniture = _named(_root, "Furniture")
	_spots = _named(_root, "Seats")
	_lighting = _named(_root, "Lighting")

	_build_floors()
	_build_walls()
	_build_openings()
	_build_stairs()
	_build_fireplace()
	_build_furniture()
	_build_seats()
	_build_lighting()
	_build_player()
	_build_exit_door()

	_root.set_meta("rooms", _rooms())
	_own(_root)

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	if err != OK:
		push_error("could not write %s (error %d)" % [OUT, err])
		quit(1)
		return
	print("wrote %s" % OUT)
	quit(0)


func _named(parent: Node, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


func _own_tree(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		_own_tree(child)


func _own(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		# Instanced kit models keep their own internal ownership.
		if String(child.scene_file_path).is_empty():
			_own(child)


# --- materials --------------------------------------------------------------

func _texture(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("missing texture " + path)
	return tex


func _plaster() -> StandardMaterial3D:
	if _materials.has("plaster"):
		return _materials["plaster"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _texture(TEX_WALL)
	mat.albedo_color = Color(0.95, 0.93, 0.89)
	mat.roughness = 0.92
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
	_materials["plaster"] = mat
	return mat


func _floor_wood() -> StandardMaterial3D:
	if _materials.has("floor"):
		return _materials["floor"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _texture(TEX_FLOOR)
	mat.albedo_color = Color(0.74, 0.62, 0.50)
	mat.roughness = 0.72
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.42, 0.42, 0.42)
	_materials["floor"] = mat
	return mat


func _plain(key: String, colour: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	mat.metallic = metallic
	_materials[key] = mat
	return mat


func _wood_trim() -> StandardMaterial3D:
	return _plain("trim", Color(0.46, 0.31, 0.20), 0.6)


func _worktop() -> StandardMaterial3D:
	return _plain("worktop", Color(0.28, 0.26, 0.24), 0.45)


func _dark_wood() -> StandardMaterial3D:
	return _plain("dark_wood", Color(0.20, 0.13, 0.09), 0.55)


func _stone() -> StandardMaterial3D:
	return _plain("stone", Color(0.47, 0.45, 0.42), 0.95)


func _glass() -> StandardMaterial3D:
	if _materials.has("glass"):
		return _materials["glass"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.82, 0.88, 0.20)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials["glass"] = mat
	return mat


func _embers() -> StandardMaterial3D:
	if _materials.has("embers"):
		return _materials["embers"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.10)
	mat.emission_energy_multiplier = 1.1
	mat.roughness = 1.0
	_materials["embers"] = mat
	return mat


# --- shell ------------------------------------------------------------------

func _mesh_box(parent: Node, node_name: String, centre: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.position = centre
	parent.add_child(node)
	return node


func _collide_box(centre: Vector3, size: Vector3, parent: Node = null) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = centre
	(parent if parent != null else _structure).add_child(node)


func _slab(node_name: String, min2: Vector2, max2: Vector2, y_bottom: float, y_top: float, mat: Material, collide := true) -> void:
	var size := Vector3(max2.x - min2.x, y_top - y_bottom, max2.y - min2.y)
	var centre := Vector3((min2.x + max2.x) * 0.5, (y_bottom + y_top) * 0.5, (min2.y + max2.y) * 0.5)
	_mesh_box(_shell, node_name, centre, size, mat)
	if collide:
		_collide_box(centre, size)


func _build_floors() -> void:
	_slab("GroundFloor", Vector2(X0 - WALL_T, Z0 - WALL_T), Vector2(X1 + WALL_T, Z1 + WALL_T), -FLOOR_T, 0.0, _floor_wood())
	_floor_with_holes("GroundCeiling", _stair_holes(), GROUND_CEIL, GROUND_SLAB, _plaster())
	_floor_with_holes("UpperFloor", _stair_holes(), GROUND_SLAB, UPPER_FLOOR, _floor_wood())
	_slab("UpperCeiling", Vector2(X0 - WALL_T, Z0 - WALL_T), Vector2(X1 + WALL_T, Z1 + WALL_T), UPPER_CEIL, UPPER_TOP, _plaster())
	# A boarded edge around both openings, so the slab ends read as joinery.
	_hole_trim("CeilingTrim", _stair_holes(), GROUND_CEIL - 0.01, 0.06, _wood_trim())
	_hole_trim("FloorTrim", _stair_holes(), UPPER_FLOOR - 0.045, 0.07, _wood_trim())


func _hole_trim(node_name: String, holes: Array, y: float, thick: float, mat: Material) -> void:
	var index := 0
	for hole in holes:
		var min2: Vector2 = hole.position
		var max2: Vector2 = hole.end
		for z in [min2.y, max2.y]:
			_mesh_box(_shell, "%s%d" % [node_name, index], Vector3((min2.x + max2.x) * 0.5, y, z), Vector3(max2.x - min2.x + 0.10, thick, 0.10), mat)
			index += 1
		for x in [min2.x, max2.x]:
			_mesh_box(_shell, "%s%d" % [node_name, index], Vector3(x, y, (min2.y + max2.y) * 0.5), Vector3(0.10, thick, max2.y - min2.y), mat)
			index += 1


## Openings for the two flights and the quarter landing.  Rect2(x, z, width, depth).
func _stair_holes() -> Array:
	return [
		Rect2(STAIR_X0, UPPER_Z0, STAIR_WIDTH, LOWER_Z_BOTTOM - UPPER_Z0),
		Rect2(UPPER_X_END, UPPER_Z0, UPPER_X_START - UPPER_X_END, STAIR_WIDTH),
	]


## Lays a floor around any number of rectangular holes.  The slab is cut into
## x strips at the hole edges, and each strip is filled between the holes that
## cross it, so an L-shaped stairwell needs no hand-written rectangles.
func _floor_with_holes(node_name: String, holes: Array, y_bottom: float, y_top: float, mat: Material) -> void:
	var min2 := Vector2(X0 - WALL_T, Z0 - WALL_T)
	var max2 := Vector2(X1 + WALL_T, Z1 + WALL_T)
	var edges := [min2.x, max2.x]
	for hole in holes:
		edges.append(hole.position.x)
		edges.append(hole.end.x)
	edges.sort()
	var strips: Array = []
	for edge in edges:
		if strips.is_empty() or absf(float(edge) - float(strips[strips.size() - 1])) > 0.001:
			strips.append(edge)

	var index := 0
	for i in range(strips.size() - 1):
		var xa: float = strips[i]
		var xb: float = strips[i + 1]
		if xb - xa < 0.001:
			continue
		var spans: Array = []
		for hole in holes:
			if hole.position.x < xb - 0.001 and hole.end.x > xa + 0.001:
				spans.append(Vector2(hole.position.y, hole.end.y))
		spans.sort_custom(func(a, b): return a.x < b.x)
		var cursor := min2.y
		for span in spans:
			if span.x > cursor + 0.001:
				_slab("%s%d" % [node_name, index], Vector2(xa, cursor), Vector2(xb, span.x), y_bottom, y_top, mat)
				index += 1
			cursor = maxf(cursor, span.y)
		if cursor < max2.y - 0.001:
			_slab("%s%d" % [node_name, index], Vector2(xa, cursor), Vector2(xb, max2.y), y_bottom, y_top, mat)
			index += 1


## Wall openings that belong to this wall, as distances along it from `from`.
func _openings_for(axis: String, plane: float, base: float, from: float, to: float) -> Array:
	var low := minf(from, to)
	var high := maxf(from, to)
	var openings := []
	for table in [WINDOWS, DOORS]:
		for entry in table:
			if String(entry["axis"]) != axis:
				continue
			if absf(float(entry["plane"]) - plane) > 0.001:
				continue
			if absf(float(entry["base"]) - base) > 0.001:
				continue
			var centre: float = entry["centre"]
			if centre < low or centre > high:
				continue
			openings.append({
				"at": centre - low,
				"width": float(entry["width"]),
				"bottom": float(entry.get("sill", 0.0)) - base,
				"top": float(entry["head"]) - base,
			})
	return openings


func _build_walls() -> void:
	var ext := WALL_T
	var part := PART_T

	_wall("WallSouth", Vector2(X0 - ext * 0.5, Z0), Vector2(X1 + ext * 0.5, Z0), 0.0, GROUND_CEIL, ext)
	_wall("WallSouthUpper", Vector2(X0 - ext * 0.5, Z0), Vector2(X1 + ext * 0.5, Z0), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, ext)
	_wall("WallNorth", Vector2(X0 - ext * 0.5, Z1), Vector2(X1 + ext * 0.5, Z1), 0.0, GROUND_CEIL, ext)
	_wall("WallNorthUpper", Vector2(X0 - ext * 0.5, Z1), Vector2(X1 + ext * 0.5, Z1), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, ext)
	_wall("WallWest", Vector2(X0, Z0 - ext * 0.5), Vector2(X0, Z1 + ext * 0.5), 0.0, GROUND_CEIL, ext)
	_wall("WallWestUpper", Vector2(X0, Z0 - ext * 0.5), Vector2(X0, Z1 + ext * 0.5), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, ext)
	_wall("WallEast", Vector2(X1, Z0 - ext * 0.5), Vector2(X1, Z1 + ext * 0.5), 0.0, GROUND_CEIL, ext)
	_wall("WallEastUpper", Vector2(X1, Z0 - ext * 0.5), Vector2(X1, Z1 + ext * 0.5), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, ext)

	# Ground floor partitions.
	_wall("PartHallWest", Vector2(1.4, Z0), Vector2(1.4, Z1), 0.0, GROUND_CEIL, part)
	_wall("PartSittingKitchen", Vector2(X0, 0.0), Vector2(1.4, 0.0), 0.0, GROUND_CEIL, part)
	_wall("PartStudy", Vector2(1.4, -2.2), Vector2(X1, -2.2), 0.0, GROUND_CEIL, part)
	_wall("PartBoot", Vector2(1.4, 2.2), Vector2(X1, 2.2), 0.0, GROUND_CEIL, part)

	# First floor: the east side is one open landing around the stairwell, so
	# only the bedroom wall and the bathroom wall are needed.
	_wall("PartBedroomsUpper", Vector2(1.4, Z0), Vector2(1.4, Z1), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)
	_wall("PartBedroomsDivide", Vector2(X0, 0.0), Vector2(1.4, 0.0), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)
	_wall("PartBathUpper", Vector2(1.4, 2.2), Vector2(X1, 2.2), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)


func _wall(node_name: String, a: Vector2, b: Vector2, base_y: float, height: float, thickness: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	_shell.add_child(body)

	var delta := b - a
	var length := delta.length()
	var dir := delta / length
	var axis := "x" if absf(dir.x) > 0.5 else "z"
	var plane := a.y if axis == "x" else a.x
	var from := a.x if axis == "x" else a.y
	var to := b.x if axis == "x" else b.y
	var marks := _openings_for(axis, plane, base_y, from, to)
	marks.sort_custom(func(x, y): return x["at"] < y["at"])

	var cursor := 0.0
	for mark in marks:
		var span_start: float = float(mark["at"]) - float(mark["width"]) * 0.5
		var span_end: float = float(mark["at"]) + float(mark["width"]) * 0.5
		if span_start > cursor + 0.001:
			_wall_box(body, a, dir, cursor, span_start, base_y, base_y + height, thickness)
		if float(mark["bottom"]) > 0.01:
			_wall_box(body, a, dir, span_start, span_end, base_y, base_y + float(mark["bottom"]), thickness)
		if float(mark["top"]) < height - 0.01:
			_wall_box(body, a, dir, span_start, span_end, base_y + float(mark["top"]), base_y + height, thickness)
		cursor = maxf(cursor, span_end)
	if cursor < length - 0.001:
		_wall_box(body, a, dir, cursor, length, base_y, base_y + height, thickness)


func _wall_box(body: StaticBody3D, a: Vector2, dir: Vector2, span_start: float, span_end: float, y0: float, y1: float, thickness: float) -> void:
	var run := span_end - span_start
	if run <= 0.001 or y1 - y0 <= 0.001:
		return
	var mid := a + dir * ((span_start + span_end) * 0.5)
	var size := Vector3(thickness, y1 - y0, run) if absf(dir.y) > 0.5 else Vector3(run, y1 - y0, thickness)
	var centre := Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _plaster()
	node.position = centre
	body.add_child(node)
	_collide_box(centre, size, body)


# --- windows and doors ------------------------------------------------------

func _build_openings() -> void:
	for window in WINDOWS:
		_frame_window(window)
	for door in DOORS:
		_door_casing(door)
		if bool(door["leaf"]):
			_door_leaf(door)


func _frame_window(window: Dictionary) -> void:
	var along_x := String(window["axis"]) == "x"
	var centre := Vector3(window["centre"], 0.0, float(window["plane"])) if along_x else Vector3(float(window["plane"]), 0.0, window["centre"])
	var width: float = window["width"]
	var sill: float = window["sill"]
	var head: float = window["head"]
	var base: float = window["base"]
	var depth := WALL_T
	var trim := 0.07
	var jamb_t := 0.07
	var height := head - sill
	var mid_y := (sill + head) * 0.5
	var node_name := "Win" + String(window["name"])

	var glass := Vector3(width - 0.06, height - 0.06, 0.02) if along_x else Vector3(0.02, height - 0.06, width - 0.06)
	_mesh_box(_shell, node_name + "Glass", Vector3(centre.x, mid_y, centre.z), glass, _glass())

	for side in [-1.0, 1.0]:
		var offset: float = width * 0.5 * float(side)
		var pos := Vector3(centre.x + offset, mid_y, centre.z) if along_x else Vector3(centre.x, mid_y, centre.z + offset)
		var size := Vector3(jamb_t, height + 0.02, depth) if along_x else Vector3(depth, height + 0.02, jamb_t)
		_mesh_box(_shell, node_name + "Jamb", pos, size, _wood_trim())

	var head_size := Vector3(width + trim * 2.0, trim, depth) if along_x else Vector3(depth, trim, width + trim * 2.0)
	_mesh_box(_shell, node_name + "Head", Vector3(centre.x, head, centre.z), head_size, _wood_trim())

	var sill_size := Vector3(width + 0.22, 0.07, depth + 0.08) if along_x else Vector3(depth + 0.08, 0.07, width + 0.22)
	_mesh_box(_shell, node_name + "SillBoard", Vector3(centre.x, sill - 0.035, centre.z), sill_size, _wood_trim())

	var mullion := Vector3(0.06, height - 0.04, 0.10) if along_x else Vector3(0.10, height - 0.04, 0.06)
	_mesh_box(_shell, node_name + "Mullion", Vector3(centre.x, mid_y, centre.z), mullion, _wood_trim())

	var transom := Vector3(width - 0.10, 0.05, 0.08) if along_x else Vector3(0.08, 0.05, width - 0.10)
	_mesh_box(_shell, node_name + "Transom", Vector3(centre.x, base + sill, centre.z) if false else Vector3(centre.x, sill + height * 0.66, centre.z), transom, _wood_trim())


func _door_casing(door: Dictionary) -> void:
	var along_x := String(door["axis"]) == "x"
	var centre := Vector3(door["centre"], 0.0, float(door["plane"])) if along_x else Vector3(float(door["plane"]), 0.0, door["centre"])
	var width: float = door["width"]
	var head: float = door["head"]
	var base: float = door["base"]
	var trim := 0.08
	var node_name := "Door" + String(door["name"])

	for side in [-1.0, 1.0]:
		var offset: float = width * 0.5 * float(side)
		var pos := Vector3(centre.x + offset, base + (head - base) * 0.5, centre.z) if along_x else Vector3(centre.x, base + (head - base) * 0.5, centre.z + offset)
		var size := Vector3(trim, head - base, PART_T + 0.03) if along_x else Vector3(PART_T + 0.03, head - base, trim)
		_mesh_box(_shell, node_name + "Jamb", pos, size, _wood_trim())

	var head_size := Vector3(width + trim * 2.0, trim, PART_T + 0.03) if along_x else Vector3(PART_T + 0.03, trim, width + trim * 2.0)
	_mesh_box(_shell, node_name + "Head", Vector3(centre.x, head + trim * 0.5, centre.z), head_size, _wood_trim())


func _door_leaf(door: Dictionary) -> void:
	var along_x := String(door["axis"]) == "x"
	var centre := Vector3(door["centre"], 0.0, float(door["plane"])) if along_x else Vector3(float(door["plane"]), 0.0, door["centre"])
	var width: float = door["width"]
	var head: float = door["head"]
	var base: float = door["base"]
	var size := Vector3(width - 0.06, head - base - 0.04, 0.06) if along_x else Vector3(0.06, head - base - 0.04, width - 0.06)
	_mesh_box(_shell, "Leaf" + String(door["name"]), Vector3(centre.x, base + (head - base) * 0.5, centre.z), size, _dark_wood())


# --- stairs -----------------------------------------------------------------

func _build_stairs() -> void:
	var body := StaticBody3D.new()
	body.name = "StairCollision"
	body.collision_layer = 1
	_shell.add_child(body)

	# Lower flight: up from the hall, climbing south along the east wall.
	var lower_run := (LOWER_Z_BOTTOM - LOWER_Z_TOP) / float(LOWER_RISERS)
	for i in range(LOWER_RISERS):
		var top := RISER * float(i + 1)
		var z_front := LOWER_Z_BOTTOM - lower_run * float(i)
		_mesh_box(_shell, "LowerTread%02d" % i, Vector3(STAIR_CX, top - 0.03, z_front - lower_run * 0.5), Vector3(STAIR_WIDTH, 0.06, lower_run), _floor_wood())
		_mesh_box(_shell, "LowerRiser%02d" % i, Vector3(STAIR_CX, top - RISER * 0.5, z_front), Vector3(STAIR_WIDTH, RISER, 0.04), _wood_trim())

	# Quarter landing at the turn, a square metre at LANDING_TOP.
	var landing_centre := Vector3(STAIR_CX, LANDING_TOP - 0.09, (LOWER_Z_TOP + UPPER_Z0) * 0.5)
	var landing_size := Vector3(STAIR_WIDTH, 0.18, LOWER_Z_TOP - UPPER_Z0)
	_mesh_box(_shell, "QuarterLanding", landing_centre, landing_size, _floor_wood())
	_collide_box(landing_centre, landing_size, body)

	# Upper flight: turns west along the south wall, finishing on the gallery.
	var upper_run := (UPPER_X_START - UPPER_X_END) / float(UPPER_RISERS)
	for i in range(UPPER_RISERS):
		var top := LANDING_TOP + RISER * float(i + 1)
		var x_east := UPPER_X_START - upper_run * float(i)
		_mesh_box(_shell, "UpperTread%02d" % i, Vector3(x_east - upper_run * 0.5, top - 0.03, STAIR_Z_MID), Vector3(upper_run, 0.06, STAIR_WIDTH), _floor_wood())
		_mesh_box(_shell, "UpperRiser%02d" % i, Vector3(x_east, top - RISER * 0.5, STAIR_Z_MID), Vector3(0.04, RISER, STAIR_WIDTH), _wood_trim())

	# The treads are decoration.  Each flight has one solid ramp as its walking
	# surface, because the controller has no step-up logic; the pitches are
	# 28.7 and 39.4 degrees, inside its 45 degree floor limit.
	_walk_ramp(body, Vector3(STAIR_CX, 0.0, LOWER_Z_BOTTOM), Vector3(STAIR_CX, LANDING_TOP, LOWER_Z_TOP), STAIR_WIDTH)
	_walk_ramp(body, Vector3(UPPER_X_START, LANDING_TOP, STAIR_Z_MID), Vector3(UPPER_X_END, UPPER_FLOOR, STAIR_Z_MID), STAIR_WIDTH)

	# Guards, each with its own collision: the open side of each flight, the
	# landing, and the three edges of the well on the gallery floor.  The fourth
	# edge is the top step, which has to stay open.
	# The quarter landing needs no rail: walls on two sides, the lower flight
	# on the third and the upper flight on the fourth.
	_guard_raked(body, Vector3(STAIR_X0 + 0.05, 0.0, LOWER_Z_BOTTOM), Vector3(STAIR_X0 + 0.05, LANDING_TOP, LOWER_Z_TOP))
	_guard_raked(body, Vector3(UPPER_X_START, LANDING_TOP, UPPER_Z1 - 0.06), Vector3(3.35, 1.91, UPPER_Z1 - 0.06))
	_guard_level(body, Vector3(UPPER_X_END, UPPER_FLOOR, UPPER_Z1 + 0.06), Vector3(UPPER_X_START, UPPER_FLOOR, UPPER_Z1 + 0.06))
	_guard_level(body, Vector3(STAIR_X0, UPPER_FLOOR, UPPER_Z1 + 0.06), Vector3(STAIR_X0, UPPER_FLOOR, 0.36))
	_guard_level(body, Vector3(STAIR_X0, UPPER_FLOOR, 0.36), Vector3(STAIR_X1, UPPER_FLOOR, 0.36))

	_newel(Vector3(STAIR_X0 + 0.05, 0.0, LOWER_Z_BOTTOM))
	_newel(Vector3(UPPER_X_END, UPPER_FLOOR, UPPER_Z1 + 0.06))
	_newel(Vector3(STAIR_X0, UPPER_FLOOR, 0.36))


func _add_mesh_box(node_name: String, centre: Vector3, size: Vector3, mat: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.transform = Transform3D(basis, centre)
	_shell.add_child(node)
	return node


func _add_collision_box(body: StaticBody3D, centre: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = Transform3D(basis, centre)
	body.add_child(node)


## A solid walkable ramp from `start` to `end` (both on the walking surface).
func _walk_ramp(body: StaticBody3D, start: Vector3, end: Vector3, width: float, thickness := 0.12) -> void:
	var delta := end - start
	var flat := Vector2(delta.x, delta.z).length()
	if flat < 0.01:
		return
	var length := sqrt(flat * flat + delta.y * delta.y)
	var angle := atan2(delta.y, flat)
	var along_z := absf(delta.z) > absf(delta.x)
	var basis := Basis(Vector3.RIGHT, angle) if along_z else Basis(Vector3.BACK, -angle)
	var size := Vector3(width, thickness, length) if along_z else Vector3(length, thickness, width)
	_add_collision_box(body, (start + end) * 0.5 - Vector3.UP * thickness * 0.5, size, basis)


## A level balustrade on a floor or landing: an invisible solid barrier for the
## collision and open joinery (shoe, spindles, handrail) for the eye.
func _guard_level(body: StaticBody3D, a: Vector3, b: Vector3, height := STAIR_GUARD_HEIGHT) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.05:
		return
	var along_z := absf(delta.z) > absf(delta.x)
	var centre := (a + b) * 0.5 + Vector3.UP * height * 0.5
	var size := Vector3(0.10, height, length) if along_z else Vector3(length, height, 0.10)
	_add_collision_box(body, centre, size)
	_balustrade_parts(a, b, height, Basis.IDENTITY)


## A balustrade following a flight, standing `height` above the walking line.
func _guard_raked(body: StaticBody3D, start: Vector3, end: Vector3, height := STAIR_GUARD_HEIGHT) -> void:
	var delta := end - start
	var flat := Vector2(delta.x, delta.z).length()
	if flat < 0.01:
		return
	var length := sqrt(flat * flat + delta.y * delta.y)
	var angle := atan2(delta.y, flat)
	var along_z := absf(delta.z) > absf(delta.x)
	var basis := Basis(Vector3.RIGHT, angle) if along_z else Basis(Vector3.BACK, -angle)
	# A raked barrier: the panel is perpendicular to the flight, so it is made a
	# little taller to keep the same vertical protection.
	var barrier_height := height / maxf(cos(angle), 0.5)
	var centre := (start + end) * 0.5 + Vector3.UP * height * 0.5
	var size := Vector3(0.10, barrier_height, length) if along_z else Vector3(length, barrier_height, 0.10)
	_add_collision_box(body, centre, size, basis)
	_balustrade_parts(start, end, height, basis)


## The visible half of a balustrade: shoe rail, vertical spindles, handrail.
func _balustrade_parts(a: Vector3, b: Vector3, height: float, basis: Basis) -> void:
	var delta := b - a
	var along_z := absf(delta.z) > absf(delta.x)
	var length := Vector2(delta.x, delta.z).length()
	if length < 0.05:
		return
	var mid := (a + b) * 0.5
	var shoe_size := Vector3(0.09, 0.12, length) if along_z else Vector3(length, 0.12, 0.09)
	_add_mesh_box("GuardShoe", mid + Vector3.UP * 0.06, shoe_size, _wood_trim(), basis)
	var rail_size := Vector3(0.13, 0.08, length + 0.04) if along_z else Vector3(length + 0.04, 0.08, 0.13)
	_add_mesh_box("GuardRail", mid + Vector3.UP * (height - 0.04), rail_size, _dark_wood(), basis)

	var span := height - 0.20
	var count := maxi(2, int(round(length / 0.34)))
	for i in range(count + 1):
		var t := float(i) / float(count)
		var p := a.lerp(b, t)
		_add_mesh_box("Spindle", Vector3(p.x, p.y + 0.12 + span * 0.5, p.z), Vector3(0.04, span, 0.04), _wood_trim())


func _newel(pos: Vector3, height := STAIR_GUARD_HEIGHT + 0.10) -> void:
	_add_mesh_box("Newel", pos + Vector3.UP * height * 0.5, Vector3(0.11, height, 0.11), _dark_wood())


# --- fireplace --------------------------------------------------------------

func _build_fireplace() -> void:
	var centre_z := -2.2
	var breast_depth := 0.42
	var breast_w := 2.10
	var breast_centre := Vector3(X0 + breast_depth * 0.5, GROUND_CEIL * 0.5, centre_z)
	_mesh_box(_shell, "ChimneyBreast", breast_centre, Vector3(breast_depth, GROUND_CEIL, breast_w), _stone())
	_collide_box(breast_centre, Vector3(breast_depth, GROUND_CEIL, breast_w))

	# A dark firebox with stone jambs and a lintel around it, rather than a
	# flat panel across the breast.
	_mesh_box(_shell, "FireRecess", Vector3(X0 + breast_depth + 0.01, 0.50, centre_z), Vector3(0.08, 1.00, 1.05), _plain("soot", Color(0.05, 0.045, 0.04), 1.0))
	for side in [-1.0, 1.0]:
		_mesh_box(_shell, "FireJamb", Vector3(X0 + breast_depth + 0.05, 0.55, centre_z + 0.63 * float(side)), Vector3(0.10, 1.10, 0.22), _stone())
	_mesh_box(_shell, "FireLintel", Vector3(X0 + breast_depth + 0.05, 1.08, centre_z), Vector3(0.10, 0.16, 1.48), _stone())
	_mesh_box(_shell, "Mantel", Vector3(X0 + breast_depth + 0.12, 1.22, centre_z), Vector3(0.30, 0.09, 2.10), _wood_trim())
	_mesh_box(_shell, "Hearth", Vector3(X0 + breast_depth + 0.30, 0.03, centre_z), Vector3(0.60, 0.06, 2.20), _stone())
	_mesh_box(_shell, "Embers", Vector3(X0 + breast_depth + 0.01, 0.10, centre_z), Vector3(0.07, 0.16, 0.80), _embers())
	_mesh_box(_shell, "LogBasket", Vector3(X0 + breast_depth + 0.45, 0.16, centre_z - 1.35), Vector3(0.42, 0.32, 0.42), _wood_trim())


# --- furniture --------------------------------------------------------------

## opts: name, scale, collide (default true), mode ("floor" or "wall").
func _prop(file: String, pos: Vector3, yaw_deg: float, opts := {}) -> Node3D:
	if not _kit.has(file):
		_kit[file] = load(KIT + file + ".glb") as PackedScene
	var packed: PackedScene = _kit[file]
	if packed == null:
		push_error("missing kit model " + file)
		return null
	var wrapper := Node3D.new()
	wrapper.name = String(opts.get("name", file))
	var model := packed.instantiate() as Node3D
	wrapper.add_child(model)
	_furniture.add_child(wrapper)

	var box := _model_aabb(model)
	var scale_value: Variant = opts.get("scale", 1.0)
	var scale: Vector3 = scale_value if scale_value is Vector3 else Vector3.ONE * float(scale_value)
	var on_floor := String(opts.get("mode", "floor")) == "floor"
	var centre_x := box.position.x + box.size.x * 0.5
	var centre_z := box.position.z + box.size.z * 0.5
	model.position = Vector3(-centre_x, -box.position.y if on_floor else 0.0, -centre_z)
	if opts.has("fabric"):
		_recolour_fabric(model, opts["fabric"])
		# Surface overrides live on nodes inside the instanced GLB.  Those nodes
		# belong to the GLB's own scene, so the packer would drop the overrides;
		# handing them to the farmhouse root saves them with the scene.
		_own_tree(model)
	wrapper.position = pos
	wrapper.rotation.y = deg_to_rad(yaw_deg)
	wrapper.scale = scale

	if bool(opts.get("collide", true)) and on_floor:
		var body := StaticBody3D.new()
		body.name = "Collision"
		# Furniture sits on its own layer so geometry probes (and any future
		# navmesh work) can tell walls from chairs.
		body.collision_layer = 4
		var shape := BoxShape3D.new()
		# The wrapper's scale applies to this child too, so the shape is kept in
		# model units and the wrapper sizes it.
		shape.size = Vector3(box.size.x * 0.92, box.size.y, box.size.z * 0.92)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(0.0, box.size.y * 0.5, 0.0)
		body.add_child(collision)
		wrapper.add_child(body)
	return wrapper


## Replaces only the kit's upholstery material, so legs, frames and fittings
## keep their own wood and metal colours.
func _recolour_fabric(node: Node, colour: Color) -> int:
	var changed := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.get_active_material(i)
				# glTF imports arrive as ORMMaterial3D, so this must not test for
				# StandardMaterial3D.
				if not (material is BaseMaterial3D):
					continue
				var standard := material as BaseMaterial3D
				if not _same_colour(standard.albedo_color, KIT_FABRIC):
					continue
				var copy := standard.duplicate() as BaseMaterial3D
				copy.albedo_color = colour
				mesh_instance.set_surface_override_material(i, copy)
				changed += 1
	for child in node.get_children():
		changed += _recolour_fabric(child, colour)
	return changed


func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _model_aabb(node: Node, xform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var any := false
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result = (xform * mesh_instance.transform) * mesh_instance.mesh.get_aabb()
			any = true
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var nested := _model_aabb(child, xform * (child as Node3D).transform)
		if nested.size == Vector3.ZERO:
			continue
		result = nested if not any else result.merge(nested)
		any = true
	return result


func _build_furniture() -> void:
	# The kit is modelled at roughly half life size, so most pieces are scaled
	# up here; the tall items (fridge, bathtub) are overridden per prop.
	var S := 2.0

	# --- sitting room: the fire on the west wall, seating facing it ---
	_prop("rugRectangle", Vector3(-3.3, 0.0, -2.2), 0.0, {"scale": 1.4, "collide": false, "fabric": FABRIC_TERRACOTTA})
	_prop("loungeSofa", Vector3(-1.85, 0.0, -2.2), 90.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("loungeChair", Vector3(-4.05, 0.0, -0.65), 120.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("loungeChair", Vector3(-4.05, 0.0, -3.75), 60.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("tableCoffee", Vector3(-3.35, 0.0, -2.2), 0.0, {"scale": S})
	_prop("bookcaseClosedWide", Vector3(-4.55, 0.0, -0.32), 180.0, {"scale": S})
	_prop("sideTableDrawers", Vector3(-0.80, 0.0, -3.70), 0.0, {"scale": S})
	_prop("lampRoundTable", Vector3(-0.80, 0.78, -3.70), 0.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("lampRoundFloor", Vector3(-0.75, 0.0, -2.60), 0.0, {"scale": S})
	_prop("pottedPlant", Vector3(0.70, 0.0, -0.55), 0.0, {"scale": S})

	# --- kitchen: a run of units along the west wall under one worktop ---
	_prop("kitchenCabinet", Vector3(-5.15, 0.0, 0.85), 90.0, {"scale": S})
	_prop("kitchenCabinetDrawer", Vector3(-5.15, 0.0, 1.55), 90.0, {"scale": S})
	_prop("kitchenStove", Vector3(-5.15, 0.0, 2.40), 90.0, {"scale": S})
	_prop("kitchenCabinet", Vector3(-5.15, 0.0, 3.20), 90.0, {"scale": S})
	_prop("kitchenSink", Vector3(-4.30, 0.0, 4.10), 0.0, {"scale": S})
	_prop("kitchenFridge", Vector3(-5.18, 0.0, 0.20), 90.0, {"scale": 1.15})
	_mesh_box(_furniture, "Worktop", Vector3(-5.20, 0.92, 2.05), Vector3(0.64, 0.08, 3.30), _worktop())
	_collide_box(Vector3(-5.20, 0.92, 2.05), Vector3(0.64, 0.08, 3.30))
	_prop("kitchenCabinetUpper", Vector3(-5.18, 1.85, 1.20), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCabinetUpper", Vector3(-5.18, 1.85, 2.00), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCabinetUpperDouble", Vector3(-5.18, 1.85, 3.20), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCoffeeMachine", Vector3(-4.95, 0.96, 1.05), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("toaster", Vector3(-4.95, 0.96, 1.70), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("table", Vector3(-2.45, 0.0, 2.20), 0.0, {"scale": S})
	_prop("chair", Vector3(-3.35, 0.0, 2.20), 90.0, {"scale": S})
	_prop("chair", Vector3(-1.55, 0.0, 2.20), 270.0, {"scale": S})
	_prop("chair", Vector3(-2.45, 0.0, 3.10), 180.0, {"scale": S})
	_prop("chair", Vector3(-2.45, 0.0, 1.30), 0.0, {"scale": S})
	_prop("plantSmall2", Vector3(-4.50, 1.20, 4.30), 0.0, {"mode": "wall", "collide": false, "scale": S})

	# --- study ---
	_prop("desk", Vector3(4.15, 0.0, -3.90), 180.0, {"scale": 1.6})
	_prop("chairDesk", Vector3(4.15, 0.0, -3.05), 0.0, {"scale": 1.3})
	_prop("laptop", Vector3(4.10, 0.92, -3.90), 180.0, {"mode": "wall", "collide": false, "scale": 1.6})
	_prop("bookcaseOpen", Vector3(1.72, 0.0, -3.10), 90.0, {"scale": S})
	_prop("bookcaseOpenLow", Vector3(1.72, 0.0, -4.05), 90.0, {"scale": S})
	_prop("rugSquare", Vector3(3.6, 0.0, -3.3), 0.0, {"collide": false, "scale": 1.4})
	_prop("lampSquareTable", Vector3(4.90, 0.92, -4.10), 0.0, {"mode": "wall", "collide": false, "scale": 1.4})

	# --- boot room ---
	_prop("bench", Vector3(2.35, 0.0, 4.05), 180.0, {"scale": 1.6})
	_prop("coatRackStanding", Vector3(1.90, 0.0, 2.70), 0.0, {"scale": S})
	_prop("rugDoormat", Vector3(3.10, 0.0, 4.05), 0.0, {"collide": false, "scale": 1.6})
	_prop("trashcan", Vector3(5.05, 0.0, 2.55), 0.0, {"scale": S})

	# --- hall ---
	_prop("rugDoormat", Vector3(4.60, 0.0, 1.55), 0.0, {"collide": false, "scale": 1.6})
	# North of the stair foot: the old spot is now the quarter landing.
	_prop("sideTable", Vector3(3.55, 0.0, 1.85), 180.0, {"scale": S})
	_prop("lampRoundTable", Vector3(3.55, 0.78, 1.85), 0.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("coatRack", Vector3(2.90, 1.55, 2.08), 180.0, {"mode": "wall", "collide": false, "scale": 1.6})
	_prop("plantSmall1", Vector3(1.85, 0.0, 1.90), 0.0, {"scale": S})

	# --- main bedroom ---
	_prop("bedDouble", Vector3(-4.10, UPPER_FLOOR, -2.10), 270.0, {"scale": Vector3(1.2, 1.0, 1.6), "fabric": FABRIC_CREAM})
	_prop("bookcaseClosed", Vector3(-2.45, UPPER_FLOOR, -0.32), 180.0, {"scale": S})
	_prop("cabinetBedDrawer", Vector3(-5.15, UPPER_FLOOR, -0.85), 270.0, {"scale": S})
	_prop("cabinetBedDrawer", Vector3(-5.15, UPPER_FLOOR, -3.35), 270.0, {"scale": S})
	_prop("rugRectangle", Vector3(-2.40, UPPER_FLOOR, -2.30), 0.0, {"scale": 1.2, "collide": false, "fabric": FABRIC_TERRACOTTA})
	_prop("benchCushion", Vector3(-1.80, UPPER_FLOOR, -2.10), 90.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("lampRoundTable", Vector3(-5.10, UPPER_FLOOR + 0.80, -0.85), 0.0, {"mode": "wall", "collide": false, "scale": S})

	# --- second bedroom ---
	_prop("bedSingle", Vector3(-4.10, UPPER_FLOOR, 2.30), 270.0, {"scale": Vector3(0.9, 1.0, 1.6), "fabric": FABRIC_CREAM})
	_prop("desk", Vector3(-1.30, UPPER_FLOOR, 4.05), 180.0, {"scale": 1.6})
	_prop("chairDesk", Vector3(-1.30, UPPER_FLOOR, 3.30), 0.0, {"scale": 1.3})
	_prop("bookcaseOpenLow", Vector3(0.95, UPPER_FLOOR, 1.45), 90.0, {"scale": S})
	_prop("rugRound", Vector3(-3.20, UPPER_FLOOR, 3.00), 0.0, {"collide": false, "scale": 1.6, "fabric": FABRIC_TERRACOTTA})
	_prop("pottedPlant", Vector3(0.90, UPPER_FLOOR, 3.90), 0.0, {"scale": S})

	# --- bathroom ---
	_prop("bathtub", Vector3(4.55, UPPER_FLOOR, 3.55), 270.0, {"scale": 1.35})
	_prop("bathroomSink", Vector3(1.80, UPPER_FLOOR, 2.95), 90.0, {"scale": 1.4})
	_prop("bathroomCabinet", Vector3(1.55, UPPER_FLOOR + 1.90, 2.95), 90.0, {"mode": "wall", "collide": false, "scale": 1.4})
	_prop("bathroomCabinetDrawer", Vector3(1.85, UPPER_FLOOR, 3.85), 90.0, {"scale": 1.2})
	_prop("toilet", Vector3(1.90, UPPER_FLOOR, 3.75), 90.0, {"scale": 0.9})
	_prop("bathroomMirror", Vector3(1.52, UPPER_FLOOR + 1.12, 2.95), 90.0, {"mode": "wall", "collide": false, "scale": 1.4})
	_prop("rugDoormat", Vector3(3.40, UPPER_FLOOR, 2.45), 0.0, {"collide": false, "scale": 1.4})
	_prop("rugDoormat", Vector3(3.90, UPPER_FLOOR, 3.55), 0.0, {"collide": false, "scale": 1.2})
	_prop("plantSmall2", Vector3(4.95, UPPER_FLOOR, 2.62), 0.0, {"scale": S, "collide": false})

	# --- landing and gallery ---
	_prop("bookcaseClosed", Vector3(5.12, UPPER_FLOOR, -2.50), 270.0, {"scale": S})
	_prop("chairRounded", Vector3(2.15, UPPER_FLOOR, -2.70), 0.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("rugDoormat", Vector3(4.10, UPPER_FLOOR, -3.10), 0.0, {"collide": false, "scale": 1.4})
	_prop("plantSmall3", Vector3(4.95, UPPER_FLOOR, -2.50), 0.0, {"scale": S})
	_prop("bench", Vector3(5.10, UPPER_FLOOR, 1.20), 270.0, {"scale": 1.6})


# --- seats ------------------------------------------------------------------

func _seat(node_name: String, kind: String, pos: Vector3, yaw_deg: float, eye: float, opts := {}) -> void:
	var node := Node3D.new()
	node.name = node_name
	node.set_script(load(SPOT))
	node.set("kind", kind)
	node.set("eye_height", eye)
	node.set("look_pitch", float(opts.get("pitch", 0.0)))
	node.set("stand_offset", Vector3(opts.get("stand_offset", Vector3(0.0, 0.0, 0.9))))
	node.set("prompt_label", String(opts.get("label", "SIT")))
	_spots.add_child(node)
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)


func _build_seats() -> void:
	_seat("SofaSeat", "seat", Vector3(-1.85, 0.46, -2.20), 90.0, 1.12, {"stand_offset": Vector3(0.9, 0.0, 0.0)})
	_seat("ChairSeatSouth", "seat", Vector3(-4.05, 0.46, -0.68), 120.0, 1.10)
	_seat("ChairSeatNorth", "seat", Vector3(-4.05, 0.46, -3.72), 60.0, 1.10)
	_seat("KitchenSeatWest", "seat", Vector3(-3.33, 0.47, 2.20), 90.0, 1.15, {"stand_offset": Vector3(-0.9, 0.0, 0.0)})
	_seat("KitchenSeatEast", "seat", Vector3(-1.57, 0.47, 2.20), 270.0, 1.15, {"stand_offset": Vector3(0.9, 0.0, 0.0)})
	_seat("KitchenSeatNorth", "seat", Vector3(-2.45, 0.47, 3.08), 180.0, 1.15)
	_seat("KitchenSeatSouth", "seat", Vector3(-2.45, 0.47, 1.32), 0.0, 1.15, {"stand_offset": Vector3(0.0, 0.0, -0.9)})
	_seat("StudySeat", "seat", Vector3(4.15, 0.50, -3.08), 0.0, 1.18)
	_seat("LandingSeat", "seat", Vector3(2.15, 0.46, -2.72), 0.0, 1.12)
	_seat("MainBedRest", "bed", Vector3(-4.20, UPPER_FLOOR + 0.48, -2.10), 90.0, 0.82, {"pitch": -22.0, "label": "REST", "stand_offset": Vector3(1.3, 0.0, 0.0)})
	_seat("SecondBedRest", "bed", Vector3(-4.20, UPPER_FLOOR + 0.46, 2.30), 90.0, 0.80, {"pitch": -22.0, "label": "REST", "stand_offset": Vector3(1.3, 0.0, 0.0)})


# --- light and player -------------------------------------------------------

func _lamp(node_name: String, pos: Vector3, colour: Color, energy: float, light_range: float, shadows := false) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.light_specular = 0.2
	_lighting.add_child(light)
	if shadows == false:
		_pendant(pos)


## A shaded pendant hanging from the ceiling over the light, so the pool of
## light on the ceiling reads as a fixture rather than a floating glow.
func _pendant(pos: Vector3) -> void:
	var ceiling := GROUND_CEIL if pos.y < UPPER_FLOOR else UPPER_CEIL
	var shade := MeshInstance3D.new()
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.055
	shade_mesh.bottom_radius = 0.21
	shade_mesh.height = 0.20
	shade.mesh = shade_mesh
	shade.material_override = _plain("shade", Color(0.93, 0.88, 0.77), 0.65)
	shade.position = pos + Vector3(0.0, 0.16, 0.0)
	_lighting.add_child(shade)

	var cord := MeshInstance3D.new()
	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.012
	cord_mesh.bottom_radius = 0.012
	cord_mesh.height = maxf(ceiling - (pos.y + 0.26), 0.04)
	cord.mesh = cord_mesh
	cord.material_override = _dark_wood()
	cord.position = Vector3(pos.x, ceiling - cord_mesh.height * 0.5, pos.z)
	_lighting.add_child(cord)


func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.35, 0.52)
	sky_material.sky_horizon_color = Color(0.86, 0.66, 0.48)
	sky_material.ground_bottom_color = Color(0.22, 0.20, 0.18)
	sky_material.ground_horizon_color = Color(0.58, 0.48, 0.38)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.54, 0.58, 0.68)
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	_lighting.add_child(world)

	# Evening sun low in the south-west, so the south and west windows throw
	# light across the floors.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-32.0, 205.0, 0.0)
	sun.light_color = Color(1.0, 0.83, 0.62)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	_lighting.add_child(sun)

	_lamp("LampSitting", Vector3(-3.0, 2.18, -2.2), Color(1.0, 0.80, 0.56), 2.5, 7.2)
	_lamp("LampKitchen", Vector3(-3.0, 2.18, 2.2), Color(1.0, 0.86, 0.64), 2.4, 7.2)
	_lamp("LampStudy", Vector3(4.1, 2.18, -3.3), Color(1.0, 0.84, 0.60), 1.8, 5.5)
	_lamp("LampHall", Vector3(3.6, 2.18, 0.0), Color(1.0, 0.82, 0.58), 2.2, 7.0)
	_lamp("LampBoot", Vector3(3.2, 2.18, 3.3), Color(1.0, 0.84, 0.62), 1.6, 5.0)
	_lamp("LampMainBed", Vector3(-3.6, 4.66, -2.2), Color(1.0, 0.82, 0.62), 2.2, 7.0)
	_lamp("LampSecondBed", Vector3(-3.6, 4.66, 2.2), Color(1.0, 0.82, 0.62), 2.0, 6.5)
	_lamp("LampLanding", Vector3(3.6, 4.66, -3.3), Color(1.0, 0.84, 0.62), 1.8, 5.5)
	_lamp("LampBath", Vector3(3.4, 4.66, 3.3), Color(1.0, 0.88, 0.72), 1.7, 5.0)
	_lamp("LampGallery", Vector3(3.6, 4.66, 0.0), Color(1.0, 0.84, 0.62), 1.9, 6.2)
	_lamp("Firelight", Vector3(X0 + 0.62, 0.42, -2.2), Color(1.0, 0.52, 0.20), 2.2, 4.8, true)


func _build_player() -> void:
	var packed := load(PLAYER) as PackedScene
	if packed == null:
		push_error("missing player scene")
		return
	var player := packed.instantiate() as CharacterBody3D
	player.name = "Player"
	_root.add_child(player)
	player.position = Vector3(4.35, 0.05, 0.55)
	player.rotation.y = deg_to_rad(105.0)
	# Layer 1 is the shell, layer 4 the furniture: the player walks into both.
	player.collision_mask = 1 | 4


## The front door back out to the yard, plus a collider for its closed leaf so
## the player cannot walk through into the empty exterior.
func _build_exit_door() -> void:
	var link := Node3D.new()
	link.name = "FrontDoorExit"
	link.set_script(load(DOOR))
	link.position = Vector3(X1 - 0.60, 0.0, 1.55)
	link.set("target_scene", "res://scenes/main.tscn")
	link.set("prompt_label", "GO OUTSIDE")
	link.set("prompt_height", 2.35)
	link.set("reach", 2.20)
	link.set("spawn_position", HOUSE_DOOR_SPAWN)
	link.set("spawn_yaw_degrees", HOUSE_DOOR_SPAWN_YAW)
	_root.add_child(link)

	var body := StaticBody3D.new()
	body.name = "FrontDoorCollision"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, 2.11, 0.99)
	shape.shape = box
	body.position = Vector3(X1, 1.075, 1.55)
	body.add_child(shape)
	_root.add_child(body)


func _rooms() -> Array:
	return [
		{"name": "sitting", "min": [X0, Z0], "max": [1.4, 0.0], "floor": 0},
		{"name": "kitchen", "min": [X0, 0.0], "max": [1.4, Z1], "floor": 0},
		{"name": "hall", "min": [1.4, -2.2], "max": [X1, 2.2], "floor": 0},
		{"name": "study", "min": [1.4, Z0], "max": [X1, -2.2], "floor": 0},
		{"name": "boot", "min": [1.4, 2.2], "max": [X1, Z1], "floor": 0},
		{"name": "main_bed", "min": [X0, Z0], "max": [1.4, 0.0], "floor": 1},
		{"name": "second_bed", "min": [X0, 0.0], "max": [1.4, Z1], "floor": 1},
		{"name": "landing", "min": [1.4, Z0], "max": [X1, -2.2], "floor": 1},
		{"name": "bath", "min": [1.4, 2.2], "max": [X1, Z1], "floor": 1},
		{"name": "gallery", "min": [1.4, -2.2], "max": [X1, 2.2], "floor": 1},
	]
