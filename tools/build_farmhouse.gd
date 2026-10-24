extends SceneTree

## Builds the two-storey farmhouse interior as an ordinary static scene.
##
##   godot --headless --path . --script res://tools/build_farmhouse.gd
##
## Output: res://scenes/farmhouse.tscn
##
## The shell (floors, walls with real window and door openings, ceilings,
## stairs, trim) comes from the plan below.  Furniture is instanced from
## Kenney's CC0 Furniture Kit, Quaternius's CC0 House Interior pack, Kenney's
## CC0 Food Kit and Shapespark's CC0 textiles, and placed from the PROP table.
## Every prop is measured, centred on its footprint and dropped onto its floor,
## so the kit's baked pivots cannot leave a chair floating.
##
## Windows and doors are declared once in WINDOWS / DOORS: the wall openings
## and the frames, glass and leaves are both derived from those tables, so they
## cannot drift apart.
##
## Re-running overwrites scenes/farmhouse.tscn.  Edit the tables here rather
## than the generated scene if you want the change to survive.
##
## The house is three times the floor area of the original 11 x 9 m plan:
## 19.06 x 15.58 m clear, with 3.0 m ground ceilings and 2.88 m upstairs.

const OUT := "res://scenes/farmhouse.tscn"
const KIT := "res://Models/interior/kenney_furniture_kit/"
const QUAT := "res://Models/interior/quaternius/"
const FOOD := "res://Models/interior/kenney_food_kit/"
const TEXTILE := "res://Models/interior/shapespark_textiles/"
const PROPS := "res://Models/props/"
const TEX_FLOOR := "res://Models/interior/textures/wood_floor_diff_1k.jpg"
const TEX_WALL := "res://Models/interior/textures/painted_plaster_wall_diff_1k.jpg"
const TEX_FOOD := "res://Models/interior/kenney_food_kit/Textures/colormap.png"

# Neutral-luminance detail maps, built by tools/make_interior_detail.py.  Every
# map sits at a 0.90 sRGB mean, so it only modulates the surface; the colours in
# the tables below still come from the kit and the FABRIC_* palette.
const DETAIL_MEAN := 0.90
const DETAIL_WOOD := "res://Models/interior/textures/detail_wood_diff_512.jpg"
const DETAIL_FABRIC := "res://Models/interior/textures/detail_fabric_diff_512.jpg"
const DETAIL_STONE := "res://Models/interior/textures/detail_stone_diff_512.jpg"
const DETAIL_METAL := "res://Models/interior/textures/detail_metal_diff_256.jpg"
const PLAYER := "res://scenes/player.tscn"
const SPOT := "res://scripts/interior_spot.gd"
const DOOR := "res://scripts/scene_door.gd"
const DOG := "res://scenes/dog.tscn"
## Outside spawn in main.tscn, just in front of the fantasy house's front door.
const HOUSE_DOOR_SPAWN := Vector3(36.978477, 0.05, -30.9)
const HOUSE_DOOR_SPAWN_YAW := 180.0

# Plan.  Room rectangles below are the clear space between wall faces.
const X0 := -9.53
const X1 := 9.53
const Z0 := -7.79
const Z1 := 7.79
const HALL_X := 2.43
const STUDY_Z := -3.81
const BOOT_Z := 3.81
const GROUND_CEIL := 3.00
const GROUND_SLAB := 3.06
const UPPER_FLOOR := 3.12
const UPPER_CEIL := 6.00
const UPPER_TOP := 6.06
const WALL_T := 0.30
const PART_T := 0.12
const FLOOR_T := 0.30

# Stair: an L-shaped flight in the hall's south-east corner.  The lower flight
# climbs south along the east wall to a quarter landing, then the upper flight
# turns west along the south wall and finishes on the gallery floor in front of
# the bedroom doors.  The foot faces north into the hall, so it is walked into
# end-on; the top opens onto real floor rather than the wall.
const STAIR_WIDTH := 1.20
const STAIR_RISERS := 17
const RISER := UPPER_FLOOR / float(STAIR_RISERS)
const STAIR_X0 := 8.18
const STAIR_X1 := 9.38
const STAIR_CX := (STAIR_X0 + STAIR_X1) * 0.5
const LOWER_Z_BOTTOM := 0.60
const LOWER_Z_TOP := -2.55
const LOWER_RISERS := 7
const LANDING_TOP := RISER * float(LOWER_RISERS)
const UPPER_Z0 := -3.75
const UPPER_Z1 := -2.55
const STAIR_Z_MID := (UPPER_Z0 + UPPER_Z1) * 0.5
const UPPER_X_START := 8.18
const UPPER_X_END := 4.58
const UPPER_RISERS := 10
const STAIR_GUARD_HEIGHT := 1.00

const GROUND_SILL := 0.95
const GROUND_HEAD := 2.55
const UPPER_SILL := UPPER_FLOOR + 0.95
const UPPER_HEAD := UPPER_FLOOR + 2.40

# Each entry: name, axis the wall runs along, the plane it sits in, the centre
# along that axis, plus the opening.  "base" is the floor the window serves.
const WINDOWS := [
	{"name": "SittingSouthA", "axis": "x", "plane": Z0, "centre": -7.60, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingSouthB", "axis": "x", "plane": Z0, "centre": -4.90, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingSouthC", "axis": "x", "plane": Z0, "centre": -2.20, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "StudySouthA", "axis": "x", "plane": Z0, "centre": 5.20, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "StudySouthB", "axis": "x", "plane": Z0, "centre": 7.80, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenNorthA", "axis": "x", "plane": Z1, "centre": -7.60, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenNorthB", "axis": "x", "plane": Z1, "centre": -4.90, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenNorthC", "axis": "x", "plane": Z1, "centre": -2.20, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "BootNorth", "axis": "x", "plane": Z1, "centre": 7.60, "width": 1.40, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingWestA", "axis": "z", "plane": X0, "centre": -6.50, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "SittingWestB", "axis": "z", "plane": X0, "centre": -1.20, "width": 1.50, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenWestA", "axis": "z", "plane": X0, "centre": 2.50, "width": 1.40, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "KitchenWestB", "axis": "z", "plane": X0, "centre": 5.50, "width": 1.40, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "StudyEast", "axis": "z", "plane": X1, "centre": -5.80, "width": 1.40, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "HallStairEast", "axis": "z", "plane": X1, "centre": -1.00, "width": 1.10, "sill": 1.75, "head": 2.75, "base": 0.0},
	{"name": "BootEast", "axis": "z", "plane": X1, "centre": 5.20, "width": 1.40, "sill": GROUND_SILL, "head": GROUND_HEAD, "base": 0.0},
	{"name": "MainBedSouthA", "axis": "x", "plane": Z0, "centre": -7.60, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "MainBedSouthB", "axis": "x", "plane": Z0, "centre": -4.90, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "MainBedSouthC", "axis": "x", "plane": Z0, "centre": -2.20, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "LandingSouth", "axis": "x", "plane": Z0, "centre": 7.00, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "SecondBedNorthA", "axis": "x", "plane": Z1, "centre": -7.60, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "SecondBedNorthB", "axis": "x", "plane": Z1, "centre": -4.90, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "SecondBedNorthC", "axis": "x", "plane": Z1, "centre": -2.20, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "BathNorthA", "axis": "x", "plane": Z1, "centre": 6.00, "width": 1.20, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "BathNorthB", "axis": "x", "plane": Z1, "centre": 8.20, "width": 1.20, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "MainBedWestA", "axis": "z", "plane": X0, "centre": -6.50, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "MainBedWestB", "axis": "z", "plane": X0, "centre": -1.20, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "SecondBedWestA", "axis": "z", "plane": X0, "centre": 2.50, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "SecondBedWestB", "axis": "z", "plane": X0, "centre": 5.50, "width": 1.50, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "LandingEast", "axis": "z", "plane": X1, "centre": -5.80, "width": 1.40, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "GalleryEast", "axis": "z", "plane": X1, "centre": 1.50, "width": 1.30, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
	{"name": "BathEast", "axis": "z", "plane": X1, "centre": 5.20, "width": 1.20, "sill": UPPER_SILL, "head": UPPER_HEAD, "base": UPPER_FLOOR},
]

# Doors and openings.  "leaf" true adds a closed exterior door.  Every interior
# opening is a wide cased opening with no leaf, so the house can be walked
# through without opening anything.
const DOORS := [
	{"name": "SittingHall", "axis": "z", "plane": HALL_X, "centre": -1.60, "width": 1.80, "head": 2.55, "base": 0.0, "leaf": false},
	{"name": "KitchenHall", "axis": "z", "plane": HALL_X, "centre": 1.60, "width": 1.80, "head": 2.55, "base": 0.0, "leaf": false},
	{"name": "SittingKitchen", "axis": "x", "plane": 0.0, "centre": -3.80, "width": 2.40, "head": 2.60, "base": 0.0, "leaf": false},
	{"name": "StudyHall", "axis": "x", "plane": STUDY_Z, "centre": 3.40, "width": 1.80, "head": 2.55, "base": 0.0, "leaf": false},
	{"name": "BootHall", "axis": "x", "plane": BOOT_Z, "centre": 4.00, "width": 1.80, "head": 2.55, "base": 0.0, "leaf": false},
	{"name": "MainBed", "axis": "z", "plane": HALL_X, "centre": -1.60, "width": 1.80, "head": UPPER_FLOOR + 2.35, "base": UPPER_FLOOR, "leaf": false},
	{"name": "SecondBed", "axis": "z", "plane": HALL_X, "centre": 1.60, "width": 1.80, "head": UPPER_FLOOR + 2.35, "base": UPPER_FLOOR, "leaf": false},
	{"name": "Bath", "axis": "x", "plane": BOOT_Z, "centre": 4.00, "width": 1.40, "head": UPPER_FLOOR + 2.35, "base": UPPER_FLOOR, "leaf": false},
	{"name": "FrontDoor", "axis": "z", "plane": X1, "centre": 2.68, "width": 1.30, "head": 2.55, "base": 0.0, "leaf": true},
	{"name": "BackDoor", "axis": "x", "plane": Z1, "centre": 5.40, "width": 1.20, "head": 2.50, "base": 0.0, "leaf": true},
]

# The farmhouse upholstery palette.  Everything the PROP table marks as
# "fabric" swaps the kit's own colour for one of these; wood, metal and
# porcelain surfaces keep the kit's own colours.
const FABRIC_GREEN := Color(0.40, 0.45, 0.36)
const FABRIC_CREAM := Color(0.88, 0.85, 0.78)
const FABRIC_TERRACOTTA := Color(0.53, 0.35, 0.28)
const FABRIC_MUSTARD := Color(0.62, 0.47, 0.25)
const FABRIC_BLUE := Color(0.33, 0.41, 0.46)

# One real material per category, shared by every surface that uses it.  "uv"
# is the tile size for the kit models, whose UVs are already per-face planar at
# 78.7 units per model unit; "world" is the tile size in metres for hand-built
# boxes and for the Quaternius models, which carry no UVs and need triplanar.
const SURFACES := {
	"wood": {"texture": DETAIL_WOOD, "roughness": 0.62, "metallic": 0.0, "uv": 0.085, "world": 2.6},
	"wood_dark": {"texture": DETAIL_WOOD, "roughness": 0.52, "metallic": 0.0, "uv": 0.105, "world": 3.2},
	"fabric": {"texture": DETAIL_FABRIC, "roughness": 0.92, "metallic": 0.0, "uv": 0.140, "world": 6.0},
	"metal": {"texture": DETAIL_METAL, "roughness": 0.36, "metallic": 0.25, "uv": 0.070, "world": 3.2},
	"stone": {"texture": DETAIL_STONE, "roughness": 0.88, "metallic": 0.0, "uv": 0.055, "world": 1.4},
	"ceramic": {"texture": DETAIL_STONE, "roughness": 0.26, "metallic": 0.0, "uv": 0.150, "world": 3.4},
}

# The kit's own material names, which are stable across its 140 models.  An
# empty entry keeps the source material, which is what the glass needs.
const KIT_SURFACE := {
	"wood": "wood",
	"woodDark": "wood_dark",
	"metal": "metal",
	"metalDark": "metal",
	"metalMedium": "metal",
	"metalLight": "metal",
	"carpet": "fabric",
	"carpetDarker": "fabric",
	"carpetWhite": "fabric",
	"carpetBlue": "fabric",
	"fur": "fabric",
	"lamp": "fabric",
	"_defaultMat": "ceramic",
	"plant": "",
	"glass": "",
}

var _root: Node3D
var _shell: Node3D
var _structure: StaticBody3D
var _furniture: Node3D
var _spots: Node3D
var _lighting: Node3D
var _materials := {}
# category + colour + space -> one shared StandardMaterial3D, so the 195 props
# in the house reference a few dozen materials instead of a copy each.
var _book := {}
# source material + tint -> one shared copy, for the Shapespark textiles.
var _tinted := {}
# merge group -> the surfaces that will become one mesh, see _flush_merges().
var _merges := {}
var _detail_gain := 1.0
var _kit := {}
var _trim_index := 0


func _initialize() -> void:
	# The detail maps are sRGB greys, so the shader samples them linearised.
	# Lifting the albedo by the reciprocal of the map's linear mean puts the
	# kit's own tone back; without it every textured surface would read a fifth
	# darker than the flat colour it replaced.
	_detail_gain = 1.0 / Color(DETAIL_MEAN, DETAIL_MEAN, DETAIL_MEAN).srgb_to_linear().r

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
	_build_beams()
	_build_fireplace()
	_build_furniture()
	_build_seats()
	_build_lighting()
	_build_player()
	_build_dog()
	_build_exit_door()

	_root.set_meta("rooms", _rooms())
	# Publish the opening plan so the checks test the openings that were actually
	# built, rather than a second hand-copied table that can drift.
	_root.set_meta("windows", WINDOWS)
	_root.set_meta("doors", DOORS)
	# The player reads this profile when it spawns: a shorter, higher boom for
	# interiors, while the yard keeps the full outdoor camera.  It walks up to
	# this metadata rather than using a group, because PackedScene does not save
	# groups added after the root was created.
	_root.set_meta("camera_max_boom", 2.35)
	_root.set_meta("camera_pivot_height", 1.62)
	_root.set_meta("camera_shoulder", 0.22)
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


## Copies a downloaded model into the prop's own node instead of instancing its
## GLB scene.  Instancing plus a surface override makes Godot save a duplicate
## clone of the mesh beside the instance, which renders twice and doubles the
## prop's triangles; flattening leaves one MeshInstance3D per model surface,
## sharing the same mesh resource between every copy of that model.
func _flatten_model(node: Node3D, parent: Node3D, parent_transform: Transform3D) -> void:
	var here := parent_transform * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var source := node as MeshInstance3D
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Surface" if parent.get_child_count() == 0 else "Surface%d" % parent.get_child_count()
		mesh_instance.mesh = source.mesh
		mesh_instance.transform = here
		mesh_instance.visible = source.visible
		parent.add_child(mesh_instance)
	for child in node.get_children():
		if child is Node3D:
			_flatten_model(child as Node3D, parent, here)


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


## A shared material for one real surface category.  `mode` "uv" follows the
## kit's per-face UVs, "tri" uses world-space triplanar for hand-built boxes
## and for the Quaternius models, which carry no UVs.  `roughness` overrides the
## category default when a piece needs it (the worktop is polished, say).
func _surface(category: String, base: Color, tint := Color.WHITE, mode := "uv", roughness := -1.0) -> StandardMaterial3D:
	var spec: Dictionary = SURFACES[category]
	var colour := Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)
	var key := "%s|%s|%s|%.2f" % [category, colour.to_html(), mode, roughness]
	if _book.has(key):
		return _book[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "surface_" + category
	mat.albedo_texture = _texture(String(spec["texture"]))
	mat.albedo_color = Color(
		colour.r * _detail_gain, colour.g * _detail_gain, colour.b * _detail_gain, colour.a)
	mat.roughness = roughness if roughness >= 0.0 else float(spec["roughness"])
	mat.metallic = float(spec["metallic"])
	if mode == "tri":
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * float(spec["world"])
	else:
		mat.uv1_scale = Vector3.ONE * float(spec["uv"])
	_book[key] = mat
	return mat


## A flat colour with no detail map, shared by every surface that wants it: the
## plants and the few kit materials with no believable texture of their own.
func _flat(base: Color, tint: Color) -> StandardMaterial3D:
	var colour := Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)
	var key := "flat|%s" % colour.to_html()
	if _book.has(key):
		return _book[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "surface_flat"
	mat.albedo_color = colour
	mat.roughness = 0.85
	_book[key] = mat
	return mat


## Upholstery and other soft goods that are built as plain boxes rather than
## kit models: same fabric detail, world-space so the weave keeps its size.
func _cloth(key: String, colour: Color, roughness := 0.9) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := _surface("fabric", colour, Color.WHITE, "tri", roughness)
	_materials[key] = mat
	return mat


## The Food Kit's palette atlas.  All 34 tableware and food models share this
## one texture and one material, which is why a whole place setting can merge
## into a single draw call.
func _food_material() -> StandardMaterial3D:
	if _materials.has("food"):
		return _materials["food"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _texture(TEX_FOOD)
	mat.roughness = 0.45
	# Every Food Kit material is double sided in its glTF.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials["food"] = mat
	return mat


## A tinted copy of a downloaded model's own material, shared between every
## prop that asks for the same colour.
func _tinted_copy(source: BaseMaterial3D, tint: Color) -> BaseMaterial3D:
	var key := "%d|%s" % [source.get_instance_id(), tint.to_html()]
	if _tinted.has(key):
		return _tinted[key]
	var copy := source.duplicate() as BaseMaterial3D
	copy.albedo_color = copy.albedo_color * tint
	_tinted[key] = copy
	return copy


func _wood_trim() -> StandardMaterial3D:
	return _surface("wood", Color(0.46, 0.31, 0.20), Color.WHITE, "tri")


func _trim_paint() -> StandardMaterial3D:
	return _plain("trim_paint", Color(0.86, 0.83, 0.76), 0.75)


func _worktop() -> StandardMaterial3D:
	return _surface("stone", Color(0.28, 0.26, 0.24), Color.WHITE, "tri", 0.45)


func _dark_wood() -> StandardMaterial3D:
	return _surface("wood_dark", Color(0.20, 0.13, 0.09), Color.WHITE, "tri")


func _stone() -> StandardMaterial3D:
	return _surface("stone", Color(0.47, 0.45, 0.42), Color.WHITE, "tri")


func _glass() -> StandardMaterial3D:
	if _materials.has("glass"):
		return _materials["glass"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.66, 0.74, 0.78, 0.92)
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


## Old oak beams across the two big ground rooms and both bedrooms.  They are
## above head height and carry no collision; they are the farmhouse's strongest
## character detail from the walk-through camera.
func _build_beams() -> void:
	for z in [-6.0, -3.8, -1.6]:
		_mesh_box(_shell, "BeamSitting", Vector3((X0 + HALL_X) * 0.5, GROUND_CEIL - 0.12, z), Vector3(HALL_X - X0, 0.20, 0.18), _dark_wood())
		_mesh_box(_shell, "BeamMainBed", Vector3((X0 + HALL_X) * 0.5, UPPER_CEIL - 0.12, z), Vector3(HALL_X - X0, 0.20, 0.18), _dark_wood())
	for z in [1.6, 3.8, 6.0]:
		_mesh_box(_shell, "BeamKitchen", Vector3((X0 + HALL_X) * 0.5, GROUND_CEIL - 0.12, z), Vector3(HALL_X - X0, 0.20, 0.18), _dark_wood())
		_mesh_box(_shell, "BeamSecondBed", Vector3((X0 + HALL_X) * 0.5, UPPER_CEIL - 0.12, z), Vector3(HALL_X - X0, 0.20, 0.18), _dark_wood())


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
	_wall("PartHallWest", Vector2(HALL_X, Z0), Vector2(HALL_X, Z1), 0.0, GROUND_CEIL, part)
	_wall("PartSittingKitchen", Vector2(X0, 0.0), Vector2(HALL_X, 0.0), 0.0, GROUND_CEIL, part)
	_wall("PartStudy", Vector2(HALL_X, STUDY_Z), Vector2(X1, STUDY_Z), 0.0, GROUND_CEIL, part)
	_wall("PartBoot", Vector2(HALL_X, BOOT_Z), Vector2(X1, BOOT_Z), 0.0, GROUND_CEIL, part)

	# First floor: the east side is one open landing around the stairwell, so
	# only the bedroom wall and the bathroom wall are needed.
	_wall("PartBedroomsUpper", Vector2(HALL_X, Z0), Vector2(HALL_X, Z1), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)
	_wall("PartBedroomsDivide", Vector2(X0, 0.0), Vector2(HALL_X, 0.0), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)
	_wall("PartBathUpper", Vector2(HALL_X, BOOT_Z), Vector2(X1, BOOT_Z), UPPER_FLOOR, UPPER_CEIL - UPPER_FLOOR, part)


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
	_skirting_for(a, b, base_y, thickness)


## A painted skirting board on both faces of a wall, interrupted only by
## doorways (windows sit above it).  It is the detail that makes the huge rooms
## read as rooms rather than boxes.
func _skirting_for(a: Vector2, b: Vector2, base_y: float, thickness: float) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.10:
		return
	var dir := delta / length
	var axis := "x" if absf(dir.x) > 0.5 else "z"
	var plane := a.y if axis == "x" else a.x
	var from := a.x if axis == "x" else a.y
	var to := b.x if axis == "x" else b.y
	var low := minf(from, to)
	var marks := _openings_for(axis, plane, base_y, from, to)
	marks.sort_custom(func(x, y): return x["at"] < y["at"])
	var gaps: Array = []
	for mark in marks:
		if float(mark["bottom"]) <= 0.01:
			gaps.append(Vector2(float(mark["at"]) - float(mark["width"]) * 0.5, float(mark["at"]) + float(mark["width"]) * 0.5))
	var segments: Array = []
	var cursor := 0.0
	for gap in gaps:
		if gap.x > cursor + 0.02:
			segments.append(Vector2(cursor, gap.x))
		cursor = maxf(cursor, gap.y)
	if cursor < length - 0.02:
		segments.append(Vector2(cursor, length))

	var half := thickness * 0.5 + 0.018
	for segment in segments:
		var run: float = segment.y - segment.x
		if run < 0.02:
			continue
		var along: float = (segment.x + segment.y) * 0.5
		for side in [-1.0, 1.0]:
			var offset: float = half * float(side)
			var centre := Vector3(low + along, base_y + 0.08, plane + offset) if axis == "x" else Vector3(plane + offset, base_y + 0.08, low + along)
			var size := Vector3(run, 0.16, 0.035) if axis == "x" else Vector3(0.035, 0.16, run)
			_mesh_box(_shell, "Skirting%04d" % _trim_index, centre, size, _trim_paint())
			_trim_index += 1


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
	var trim := 0.12
	var depth := WALL_T if bool(door["leaf"]) else PART_T
	var node_name := "Door" + String(door["name"])

	for side in [-1.0, 1.0]:
		var offset: float = width * 0.5 * float(side)
		var pos := Vector3(centre.x + offset, base + (head - base) * 0.5, centre.z) if along_x else Vector3(centre.x, base + (head - base) * 0.5, centre.z + offset)
		var size := Vector3(trim, head - base, depth + 0.04) if along_x else Vector3(depth + 0.04, head - base, trim)
		_mesh_box(_shell, node_name + "Jamb", pos, size, _wood_trim())

	var head_size := Vector3(width + trim * 2.0, trim, depth + 0.04) if along_x else Vector3(depth + 0.04, trim, width + trim * 2.0)
	_mesh_box(_shell, node_name + "Head", Vector3(centre.x, head + trim * 0.5, centre.z), head_size, _wood_trim())
	# A threshold board, so a cased opening reads as a finished doorway rather
	# than a hole in the plaster.
	var sill_size := Vector3(width, 0.03, depth + 0.06) if along_x else Vector3(depth + 0.06, 0.03, width)
	_mesh_box(_shell, node_name + "Threshold", Vector3(centre.x, base + 0.015, centre.z), sill_size, _wood_trim())


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

	# Guards, each with its own collision: the open side of each flight and the
	# three edges of the well on the gallery floor.  The fourth edge is the top
	# step, which has to stay open.
	# The quarter landing needs no rail: walls on two sides, the lower flight
	# on the third and the upper flight on the fourth.
	_guard_raked(body, Vector3(STAIR_X0 + 0.05, 0.0, LOWER_Z_BOTTOM), Vector3(STAIR_X0 + 0.05, LANDING_TOP, LOWER_Z_TOP))
	# The raked rail runs down the open side of the upper flight from the top;
	# the gallery edge above it has its own level balustrade.
	_guard_raked(body, Vector3(UPPER_X_START, LANDING_TOP, UPPER_Z1 - 0.06), Vector3(6.00, 2.40, UPPER_Z1 - 0.06))
	_guard_level(body, Vector3(UPPER_X_END, UPPER_FLOOR, UPPER_Z1 + 0.06), Vector3(UPPER_X_START, UPPER_FLOOR, UPPER_Z1 + 0.06))
	_guard_level(body, Vector3(STAIR_X0, UPPER_FLOOR, UPPER_Z1 + 0.06), Vector3(STAIR_X0, UPPER_FLOOR, LOWER_Z_BOTTOM + 0.05))
	_guard_level(body, Vector3(STAIR_X0, UPPER_FLOOR, LOWER_Z_BOTTOM + 0.05), Vector3(STAIR_X1, UPPER_FLOOR, LOWER_Z_BOTTOM + 0.05))

	_newel(Vector3(STAIR_X0 + 0.05, 0.0, LOWER_Z_BOTTOM))
	_newel(Vector3(UPPER_X_END, UPPER_FLOOR, UPPER_Z1 + 0.06))
	_newel(Vector3(STAIR_X0, UPPER_FLOOR, LOWER_Z_BOTTOM + 0.05))


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
	# The spindles share one material and never move, so they are built as a
	# single mesh: a balustrade costs one draw call instead of a dozen.
	var spindles := []
	for i in range(count + 1):
		var t := float(i) / float(count)
		var p := a.lerp(b, t)
		spindles.append({
			"centre": Vector3(p.x, p.y + 0.12 + span * 0.5, p.z),
			"size": Vector3(0.04, span, 0.04),
		})
	_merged_boxes("Spindle", spindles, _wood_trim())


## One mesh for several boxes that share a material.
func _merged_boxes(node_name: String, parts: Array, mat: Material, parent: Node = null) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var box := BoxMesh.new()
		box.size = part["size"]
		tool.append_from(box, 0, Transform3D(part.get("basis", Basis.IDENTITY), part["centre"]))
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = tool.commit()
	node.material_override = mat
	(parent if parent != null else _shell).add_child(node)
	return node


func _newel(pos: Vector3, height := STAIR_GUARD_HEIGHT + 0.10) -> void:
	_add_mesh_box("Newel", pos + Vector3.UP * height * 0.5, Vector3(0.11, height, 0.11), _dark_wood())


# --- fireplace --------------------------------------------------------------

func _build_fireplace() -> void:
	var centre_z := -3.80
	var breast_depth := 0.55
	var breast_w := 2.80
	var breast_centre := Vector3(X0 + breast_depth * 0.5, GROUND_CEIL * 0.5, centre_z)
	_mesh_box(_shell, "ChimneyBreast", breast_centre, Vector3(breast_depth, GROUND_CEIL, breast_w), _stone())
	_collide_box(breast_centre, Vector3(breast_depth, GROUND_CEIL, breast_w))

	# A dark firebox with stone jambs and a lintel around it, rather than a
	# flat panel across the breast.
	_mesh_box(_shell, "FireRecess", Vector3(X0 + breast_depth + 0.01, 0.58, centre_z), Vector3(0.10, 1.16, 1.35), _plain("soot", Color(0.05, 0.045, 0.04), 1.0))
	for side in [-1.0, 1.0]:
		_mesh_box(_shell, "FireJamb", Vector3(X0 + breast_depth + 0.06, 0.64, centre_z + 0.80 * float(side)), Vector3(0.12, 1.28, 0.26), _stone())
	_mesh_box(_shell, "FireLintel", Vector3(X0 + breast_depth + 0.06, 1.27, centre_z), Vector3(0.12, 0.18, 1.82), _stone())
	_mesh_box(_shell, "Mantel", Vector3(X0 + breast_depth + 0.14, 1.43, centre_z), Vector3(0.36, 0.10, 2.70), _wood_trim())
	_mesh_box(_shell, "Hearth", Vector3(X0 + breast_depth + 0.36, 0.035, centre_z), Vector3(0.72, 0.07, 2.90), _stone())
	_mesh_box(_shell, "Embers", Vector3(X0 + breast_depth + 0.02, 0.12, centre_z), Vector3(0.09, 0.18, 1.00), _embers())
	_mesh_box(_shell, "LogBasket", Vector3(X0 + breast_depth + 0.55, 0.19, centre_z - 1.75), Vector3(0.50, 0.38, 0.50), _wood_trim())


# --- furniture --------------------------------------------------------------

## A window entry from the plan, by name.
func _window(name: String) -> Dictionary:
	for window in WINDOWS:
		if String(window["name"]) == name:
			return window
	push_error("no window named " + name)
	return {}


## Floor-length curtains and a rod for one planned window.  The panel models
## are Shapespark's CC0 textiles, tinted to the farmhouse linen palette.
func _curtains_for(name: String) -> void:
	var window := _window(name)
	if window.is_empty():
		return
	var along_x := String(window["axis"]) == "x"
	var plane: float = window["plane"]
	var centre: float = window["centre"]
	var width: float = window["width"]
	var inside := 1.0 if (plane < 0.0 or (along_x and plane == Z0)) else -1.0
	if along_x:
		inside = 1.0 if plane == Z0 else -1.0
	else:
		inside = 1.0 if plane == X0 else -1.0
	var offset := width * 0.5 + 0.16
	for side in [-1.0, 1.0]:
		var pos: Vector3
		var yaw := 0.0
		if along_x:
			pos = Vector3(centre + offset * float(side), 0.02, plane + inside * 0.20)
			yaw = 90.0
		else:
			pos = Vector3(plane + inside * 0.20, 0.02, centre + offset * float(side))
			yaw = 0.0
		_prop("Curtain", pos, yaw, {
			"path": TEXTILE + "Textile_curtain_02.glb",
			"scale": 0.80,
			"mode": "wall",
			"collide": false,
			"tint": Color(1.0, 0.94, 0.84),
		})
	# Rod and finials.
	var rod_y := 2.86
	if along_x:
		_mesh_box(_furniture, "CurtainRod", Vector3(centre, rod_y, plane + inside * 0.22), Vector3(width + 2.0, 0.05, 0.05), _dark_wood())
	else:
		_mesh_box(_furniture, "CurtainRod", Vector3(plane + inside * 0.22, rod_y, centre), Vector3(0.05, 0.05, width + 2.0), _dark_wood())


var _picture_index := 0


## A framed picture hung on a wall.  The frame, mat and canvas are simple
## boxes, so the art adds colour without another texture download.
func _picture(centre: Vector3, along_x: bool, width: float, height: float, frame_colour: Color, canvas_colour: Color) -> void:
	var normal := Vector3.RIGHT if centre.x < 0.0 else Vector3.LEFT
	if not along_x:
		normal = Vector3.BACK if centre.z < 0.0 else Vector3.FORWARD
	var frame_size := Vector3(0.06, height, width) if along_x else Vector3(width, height, 0.06)
	var mat_size := Vector3(0.025, height - 0.10, width - 0.10) if along_x else Vector3(width - 0.10, height - 0.10, 0.025)
	var canvas_size := Vector3(0.015, height - 0.20, width - 0.20) if along_x else Vector3(width - 0.20, height - 0.20, 0.015)
	# Keyed by colour rather than by picture, so the frames and canvases that
	# share a tone share one material.
	var frame := _mesh_box(_furniture, "Picture%d" % _picture_index, centre, frame_size, _plain("frame_%s" % frame_colour.to_html(false), frame_colour, 0.65))
	_mesh_box(_furniture, "PictureMat%d" % _picture_index, centre + normal * 0.035, mat_size, _plain("mat", Color(0.90, 0.87, 0.79), 0.9))
	_mesh_box(_furniture, "PictureCanvas%d" % _picture_index, centre + normal * 0.052, canvas_size, _plain("canvas_%s" % canvas_colour.to_html(false), canvas_colour, 0.85))
	_picture_index += 1


## opts: name, scale, collide (default true), mode ("floor" or "wall"),
## path (a full res:// path to a downloaded model), tint (a colour multiplied
## over the model's own materials).
func _prop(file: String, pos: Vector3, yaw_deg: float, opts := {}) -> Node3D:
	var path := String(opts.get("path", KIT + file + ".glb"))
	if not _kit.has(path):
		_kit[path] = load(path) as PackedScene
	var packed: PackedScene = _kit[path]
	if packed == null:
		push_error("missing model " + path)
		return null
	var wrapper := Node3D.new()
	wrapper.name = String(opts.get("name", file))
	var model := packed.instantiate() as Node3D
	_furniture.add_child(wrapper)

	var box := _model_aabb(model)
	var scale_value: Variant = opts.get("scale", 1.0)
	var scale: Vector3 = scale_value if scale_value is Vector3 else Vector3.ONE * float(scale_value)
	var on_floor := String(opts.get("mode", "floor")) == "floor"
	var centre_x := box.position.x + box.size.x * 0.5
	var centre_z := box.position.z + box.size.z * 0.5
	model.position = Vector3(-centre_x, -box.position.y if on_floor else 0.0, -centre_z)
	_flatten_model(model, wrapper, Transform3D.IDENTITY)
	model.free()
	_apply_surfaces(wrapper, path, opts)
	wrapper.position = pos
	wrapper.rotation.y = deg_to_rad(yaw_deg)
	wrapper.scale = scale

	# Dressing that never moves can be folded into its neighbours, so a set table
	# is one draw call rather than one per plate.  Everything merged keeps its
	# own place and its own material; only the node count goes away.
	if opts.has("merge"):
		_collect_merge(String(opts["merge"]), wrapper, wrapper.transform)
		_furniture.remove_child(wrapper)
		wrapper.free()
		return null

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


## Walks one instanced model and gives every surface the shared material for
## its real category.  Kit materials are matched by name (they are stable
## across the 140 models); Quaternius names are matched by prefix; Shapespark
## textiles keep their own weave and only get a shared tint copy; Food Kit
## models all resolve to the single palette-atlas material.
func _apply_surfaces(model: Node, path: String, opts: Dictionary) -> void:
	var food := path.begins_with(FOOD)
	var textile := path.begins_with(TEXTILE)
	var quat := path.begins_with(QUAT)
	var fabric: Variant = opts.get("fabric", null)
	var tint: Color = opts.get("tint", Color.WHITE)
	_apply_surfaces_node(model, food, textile, quat, fabric, tint)


func _apply_surfaces_node(node: Node, food: bool, textile: bool, quat: bool, fabric: Variant, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var replacement := _surface_for(
					mesh_instance.get_active_material(i), food, textile, quat, fabric, tint)
				if replacement != null:
					mesh_instance.set_surface_override_material(i, replacement)
	for child in node.get_children():
		_apply_surfaces_node(child, food, textile, quat, fabric, tint)


func _surface_for(source: Material, food: bool, textile: bool, quat: bool, fabric: Variant, tint: Color) -> Material:
	if food:
		return _food_material()
	# glTF imports arrive as ORMMaterial3D, so this must not test for
	# StandardMaterial3D.
	if not (source is BaseMaterial3D):
		return null
	var standard := source as BaseMaterial3D
	if textile:
		return null if tint == Color.WHITE else _tinted_copy(standard, tint)
	var material_name := String(standard.resource_name)
	var category := _quat_surface(material_name) if quat else String(KIT_SURFACE.get(material_name, "flat"))
	if category.is_empty():
		# Glass keeps the model's own transparent material.
		return null
	var base := standard.albedo_color
	if category == "flat":
		return _flat(base, tint)
	if fabric != null and category == "fabric":
		base = fabric
	return _surface(category, base, tint, "tri" if quat else "uv")


## Quaternius's 28 models use per-model material names ("Wood.003",
## "Plant_Green.002"), so they are grouped by prefix rather than by name.
func _quat_surface(material_name: String) -> String:
	var key := material_name.to_lower()
	if key.begins_with("plant") or key.begins_with("darkgreen"):
		return "flat"
	if key.begins_with("wood") or key.begins_with("brown") or key.begins_with("lightorange"):
		return "wood"
	if key.begins_with("lightmetal") or key.begins_with("metal") or key.begins_with("black"):
		return "metal"
	if key.begins_with("marble") or key.begins_with("white") or key.begins_with("grey") or key.begins_with("light"):
		return "ceramic"
	if key.begins_with("couch") or key.begins_with("cushin"):
		return "fabric"
	return "flat"


## Records one prop's surfaces for a merge group once its transforms are final.
func _collect_merge(group: String, node: Node, xform: Transform3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			if not _merges.has(group):
				_merges[group] = []
			for i in range(mesh_instance.mesh.get_surface_count()):
				_merges[group].append({
					"mesh": mesh_instance.mesh,
					"surface": i,
					"transform": xform,
					"material": mesh_instance.get_active_material(i),
				})
	for child in node.get_children():
		if child is Node3D:
			_collect_merge(group, child, xform * (child as Node3D).transform)


## Commits every merge group as one mesh per material.  The node sits on the
## group's centroid, so the furniture-in-every-room check still knows where the
## pieces are, and its meta keeps the piece count the merge folded away.
func _flush_merges() -> void:
	for group in _merges:
		var by_material := {}
		for entry in _merges[group]:
			var material: Material = entry["material"]
			var key := str(material.get_instance_id()) if material != null else "none"
			if not by_material.has(key):
				by_material[key] = []
			by_material[key].append(entry)
		var index := 0
		for key in by_material:
			var parts: Array = by_material[key]
			var centre := Vector3.ZERO
			for entry in parts:
				centre += (entry["transform"] as Transform3D).origin
			centre /= float(parts.size())
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for entry in parts:
				tool.append_from(
					entry["mesh"] as Mesh, int(entry["surface"]),
					Transform3D(Basis.IDENTITY, -centre) * (entry["transform"] as Transform3D))
			var mesh := tool.commit()
			if mesh == null:
				continue
			var node := MeshInstance3D.new()
			node.name = group if by_material.size() == 1 else "%s_%d" % [group, index]
			node.mesh = mesh
			node.material_override = parts[0]["material"] as Material
			node.position = centre
			node.set_meta("merged_parts", parts.size())
			_furniture.add_child(node)
			index += 1
	_merges.clear()


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
	# The Kenney kit is modelled at roughly half life size, so most pieces are
	# scaled up here; the tall and unusually proportioned pieces (fridge,
	# bathtub, toilet) carry their own scales.  Every prop is still measured and
	# centred by _prop, so none of them float.
	var S := 2.0

	# --- sitting room: fire on the west wall, a conversation group in front ---
	_prop("rugMain", Vector3(-5.30, 0.015, -3.80), 0.0, {"path": TEXTILE + "Textile_rug_01.glb", "scale": 2.35, "collide": false, "tint": Color(1.0, 0.93, 0.84)})
	_prop("loungeSofa", Vector3(-3.75, 0.0, -3.80), 90.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("loungeChair", Vector3(-6.80, 0.0, -5.55), -90.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("loungeChair", Vector3(-6.80, 0.0, -2.05), -90.0, {"scale": S, "fabric": FABRIC_GREEN})
	_prop("tableCoffee", Vector3(-5.25, 0.0, -3.80), 0.0, {"scale": 2.2})
	_prop("bookcaseClosedWide", Vector3(-0.20, 0.0, -0.28), 180.0, {"scale": 2.2})
	_prop("bookcaseClosedWide", Vector3(1.55, 0.0, -0.28), 180.0, {"scale": 2.2})
	_prop("sideTable", Vector3(-3.10, 0.0, -5.55), 90.0, {"scale": S})
	_prop("sideTable", Vector3(-3.10, 0.0, -2.05), 90.0, {"scale": S})
	_prop("lampRoundTable", Vector3(-3.10, 0.78, -5.55), 0.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("lampRoundTable", Vector3(-3.10, 0.78, -2.05), 0.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("lampRoundFloor", Vector3(-8.55, 0.0, -0.55), 0.0, {"scale": 1.8})
	# A second, quieter seating nook in the north-east corner.
	_prop("rugNook", Vector3(0.50, 0.016, -6.15), 0.0, {"path": KIT + "rugRound.glb", "scale": 2.0, "collide": false, "tint": FABRIC_TERRACOTTA})
	_prop("loungeChair", Vector3(-1.05, 0.0, -6.55), 165.0, {"scale": 1.9, "fabric": FABRIC_MUSTARD})
	_prop("loungeChair", Vector3(1.55, 0.0, -6.55), 195.0, {"scale": 1.9, "fabric": FABRIC_MUSTARD})
	_prop("sideTable", Vector3(0.30, 0.0, -6.55), 0.0, {"scale": 1.7})
	_prop("lampRoundFloor", Vector3(2.10, 0.0, -7.05), 0.0, {"scale": 1.8})
	_prop("bookcaseOpen", Vector3(2.18, 0.0, -4.55), 270.0, {"scale": 2.2})
	_prop("Houseplant6", Vector3(-8.85, 0.0, -0.70), 0.0, {"path": QUAT + "Houseplant_6.glb", "scale": 1.15})
	_prop("Houseplant3", Vector3(1.85, 0.0, -7.15), 0.0, {"path": QUAT + "Houseplant_3.glb", "scale": 1.25})
	# A window seat under the middle south window.
	_mesh_box(_furniture, "WindowSeat", Vector3(-2.20, 0.23, -7.48), Vector3(2.30, 0.46, 0.52), _wood_trim())
	_collide_box(Vector3(-2.20, 0.23, -7.48), Vector3(2.30, 0.46, 0.52))
	_mesh_box(_furniture, "WindowSeatCushion", Vector3(-2.20, 0.51, -7.46), Vector3(2.18, 0.12, 0.50), _cloth("cushion_mustard", FABRIC_MUSTARD))
	_picture(Vector3(2.24, 1.85, -6.20), true, 0.95, 0.72, Color(0.42, 0.51, 0.48), Color(0.82, 0.74, 0.58))
	_picture(Vector3(-8.92, 2.18, -3.80), true, 1.55, 0.95, Color(0.55, 0.40, 0.30), Color(0.86, 0.79, 0.64))
	_picture(Vector3(-4.90, 1.90, -7.63), false, 1.05, 0.75, Color(0.34, 0.40, 0.46), Color(0.88, 0.82, 0.68))
	_picture(Vector3(0.60, 1.90, -7.63), false, 0.90, 0.68, Color(0.50, 0.45, 0.30), Color(0.83, 0.78, 0.66))
	# Curtains on the windows the eye lands on.
	_curtains_for("SittingSouthA")
	_curtains_for("SittingSouthB")
	_curtains_for("SittingSouthC")
	_curtains_for("SittingWestA")
	_curtains_for("SittingWestB")
	# Soft things: cushions and a throw on the sofa.
	_prop("SofaPillowA", Vector3(-3.72, 0.48, -4.65), 90.0, {"path": TEXTILE + "Textile_pillow_01.glb", "scale": 1.15, "mode": "wall", "collide": false, "tint": Color(1.0, 0.92, 0.82)})
	_prop("SofaPillowB", Vector3(-3.72, 0.48, -3.80), 90.0, {"path": TEXTILE + "Textile_pillow_02.glb", "scale": 1.05, "mode": "wall", "collide": false, "tint": Color(1.0, 0.94, 0.86)})
	_prop("SofaThrow", Vector3(-3.58, 0.50, -2.80), 90.0, {"path": TEXTILE + "Textile_blanket_01.glb", "scale": 1.0, "mode": "wall", "collide": false, "tint": Color(1.0, 0.90, 0.80)})
	_prop("CoffeeBooks", Vector3(-5.15, 0.51, -3.85), 20.0, {"path": KIT + "books.glb", "scale": 1.6, "mode": "wall", "collide": false})
	_prop("HeapLogs", Vector3(-8.45, 0.0, -6.85), 0.0, {"path": PROPS + "yard/firewood_stack.glb", "scale": 1.0})
	# A games corner on the open east side, so the enlarged room has somewhere
	# to sit that is not the fireplace group.
	_prop("SittingGamesRug", Vector3(0.80, 0.014, -3.70), 0.0, {"path": KIT + "rugRectangle.glb", "scale": 2.4, "collide": false, "tint": FABRIC_BLUE})
	_prop("SittingGamesTable", Vector3(0.80, 0.0, -3.70), 0.0, {"path": KIT + "table.glb", "scale": 1.75})
	_prop("SittingGamesChairA", Vector3(-0.05, 0.0, -3.05), 315.0, {"path": KIT + "loungeChair.glb", "scale": 1.7, "fabric": FABRIC_BLUE})
	_prop("SittingGamesChairB", Vector3(1.65, 0.0, -4.35), 135.0, {"path": KIT + "loungeChair.glb", "scale": 1.7, "fabric": FABRIC_BLUE})
	_prop("SittingConsole", Vector3(2.16, 0.0, -3.00), 270.0, {"path": KIT + "sideTable.glb", "scale": 1.8})
	_prop("SittingConsoleLamp", Vector3(2.16, 0.72, -3.00), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": 1.7})
	_prop("SittingPlantEast", Vector3(2.10, 0.0, -0.90), 0.0, {"path": QUAT + "Houseplant_1.glb", "scale": 1.1})
	_picture(Vector3(2.24, 1.85, -3.00), true, 1.05, 0.72, Color(0.44, 0.50, 0.40), Color(0.87, 0.81, 0.68))

	# --- kitchen: a long run on the west wall, island and a dining end ---
	for i in range(7):
		var row := ["kitchenCabinet", "kitchenCabinetDrawer", "kitchenCabinet", "kitchenCabinet", "kitchenStove", "kitchenCabinetDrawer", "kitchenCabinet"]
		_prop(row[i], Vector3(-9.12, 0.0, 0.85 + 0.86 * float(i)), 90.0, {"scale": S})
	_prop("kitchenFridge", Vector3(-9.12, 0.0, 6.55), 90.0, {"scale": 1.15})
	_mesh_box(_furniture, "Worktop", Vector3(-9.10, 0.92, 3.20), Vector3(0.66, 0.10, 5.55), _worktop())
	_collide_box(Vector3(-9.10, 0.92, 3.20), Vector3(0.66, 0.10, 5.55))
	_prop("kitchenSink", Vector3(-8.92, 0.0, 2.50), 90.0, {"scale": S})
	_prop("kitchenCabinetUpper", Vector3(-9.15, 2.55, 1.40), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCabinetUpper", Vector3(-9.15, 2.55, 2.20), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCabinetUpperDouble", Vector3(-9.15, 2.55, 3.40), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCabinetUpper", Vector3(-9.15, 2.55, 4.55), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("kitchenCoffeeMachine", Vector3(-8.85, 0.97, 1.15), 90.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("toaster", Vector3(-8.85, 0.97, 1.85), 90.0, {"mode": "wall", "collide": false, "scale": S})
	# Island and stools.
	_mesh_box(_furniture, "IslandBase", Vector3(-5.80, 0.45, 3.40), Vector3(2.70, 0.90, 1.05), _dark_wood())
	_collide_box(Vector3(-5.80, 0.45, 3.40), Vector3(2.70, 0.90, 1.05))
	_mesh_box(_furniture, "IslandTop", Vector3(-5.80, 0.95, 3.40), Vector3(2.90, 0.10, 1.22), _worktop())
	_collide_box(Vector3(-5.80, 0.95, 3.40), Vector3(2.90, 0.10, 1.22))
	_prop("stoolBar", Vector3(-4.10, 0.0, 2.95), 270.0, {"scale": S})
	_prop("stoolBar", Vector3(-4.10, 0.0, 3.55), 270.0, {"scale": S})
	_prop("stoolBar", Vector3(-4.10, 0.0, 4.15), 270.0, {"scale": S})
	# The farmhouse table, set for six.
	_prop("DiningTable", Vector3(-2.30, 0.0, 5.90), 0.0, {"path": KIT + "table.glb", "scale": 2.6, "fabric": FABRIC_TERRACOTTA})
	_prop("DiningCloth", Vector3(-2.30, 0.86, 5.90), 0.0, {"path": KIT + "tableCloth.glb", "scale": 2.6, "mode": "wall", "collide": false, "tint": Color(1.0, 0.96, 0.88)})
	for x in [-2.95, -2.30, -1.65]:
		_prop("chair", Vector3(x, 0.0, 4.95), 0.0, {"scale": S})
		_prop("chair", Vector3(x, 0.0, 6.85), 180.0, {"scale": S})
	_prop("chair", Vector3(-3.60, 0.0, 5.90), 90.0, {"scale": S})
	_prop("chair", Vector3(-1.00, 0.0, 5.90), 270.0, {"scale": S})
	# Table setting: warm, used, not a showroom.
	for x in [-2.95, -2.30, -1.65]:
		for z in [5.48, 6.32]:
			_prop("Plate", Vector3(x, 0.875, z), 0.0, {"path": FOOD + "plate-dinner.glb", "merge": "KitchenTableSetting", "mode": "wall", "collide": false, "scale": 1.0})
			_prop("Utensil", Vector3(x + 0.28, 0.875, z), 0.0, {"path": FOOD + "utensil-fork.glb", "merge": "KitchenTableSetting", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("Teapot", Vector3(-2.30, 0.875, 5.90), 0.0, {"path": FOOD + "bottle-oil.glb", "merge": "KitchenTableCentre", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("BreadBoard", Vector3(-2.30, 0.875, 5.90), 0.0, {"path": FOOD + "cutting-board-round.glb", "merge": "KitchenTableCentre", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("Bread", Vector3(-2.30, 0.90, 5.90), 25.0, {"path": FOOD + "bread.glb", "merge": "KitchenTableCentre", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("FruitBowl", Vector3(-6.10, 1.00, 3.40), 0.0, {"path": FOOD + "bowl.glb", "merge": "IslandFruit", "mode": "wall", "collide": false, "scale": 1.0})
	for offset in [Vector3(-0.12, 0.06, 0.0), Vector3(0.10, 0.06, 0.05), Vector3(0.0, 0.06, -0.12)]:
		_prop("Apple", Vector3(-6.10, 1.04, 3.40) + offset, 0.0, {"path": FOOD + "apple.glb", "merge": "IslandFruit", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("KitchenDresser", Vector3(2.10, 0.0, 5.55), 270.0, {"path": KIT + "cabinetTelevision.glb", "scale": 2.4})
	_prop("KitchenDresserLow", Vector3(2.10, 0.0, 6.75), 270.0, {"path": KIT + "cabinetTelevisionDoors.glb", "scale": 2.2})
	_prop("AppleBasket", Vector3(1.05, 0.0, 6.55), 0.0, {"path": PROPS + "yard/apple_basket.glb", "scale": 1.0})
	_prop("DresserPlates", Vector3(2.10, 1.26, 5.35), 270.0, {"path": FOOD + "plate-deep.glb", "merge": "DresserPlates", "mode": "wall", "collide": false, "scale": 1.0})
	_prop("DresserPlatesB", Vector3(2.10, 1.27, 5.70), 270.0, {"path": FOOD + "plate-deep.glb", "merge": "DresserPlates", "mode": "wall", "collide": false, "scale": 0.9})
	# A little round breakfast table in the north-west corner.
	_prop("BreakfastTable", Vector3(-7.70, 0.0, 6.45), 0.0, {"path": KIT + "table.glb", "scale": 1.75, "fabric": FABRIC_TERRACOTTA})
	_prop("BreakfastChairA", Vector3(-8.55, 0.0, 6.45), 90.0, {"path": KIT + "chair.glb", "scale": 1.75})
	_prop("BreakfastChairB", Vector3(-6.85, 0.0, 6.45), 270.0, {"path": KIT + "chair.glb", "scale": 1.75})
	# A window seat between the dining table and the breakfast nook, and a pantry
	# on the long east wall, so the middle of the kitchen is not bare floor.
	_mesh_box(_furniture, "KitchenWindowSeat", Vector3(-4.90, 0.23, 7.46), Vector3(2.10, 0.46, 0.52), _wood_trim())
	_collide_box(Vector3(-4.90, 0.23, 7.46), Vector3(2.10, 0.46, 0.52))
	_mesh_box(_furniture, "KitchenWindowSeatCushion", Vector3(-4.90, 0.51, 7.44), Vector3(1.98, 0.12, 0.50), _cloth("cushion_blue", FABRIC_BLUE))
	_prop("KitchenLarder", Vector3(2.14, 0.0, 3.00), 270.0, {"path": KIT + "bookcaseClosedWide.glb", "scale": 2.2})
	_prop("KitchenChair", Vector3(0.95, 0.0, 6.65), 250.0, {"path": KIT + "loungeChair.glb", "scale": 1.9, "fabric": FABRIC_GREEN})
	_prop("KitchenChairTable", Vector3(1.85, 0.0, 6.65), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.6})
	_prop("KitchenPlant", Vector3(1.90, 0.0, 3.95), 0.0, {"path": QUAT + "Houseplant_5.glb", "scale": 1.2})
	_prop("KitchenRunner", Vector3(-3.00, 0.014, 4.55), 0.0, {"path": KIT + "rugRectangle.glb", "scale": 2.2, "collide": false, "tint": FABRIC_BLUE})
	_prop("HerbPot", Vector3(-8.90, 1.00, 5.45), 0.0, {"path": QUAT + "Houseplant_2.glb", "scale": 1.4, "mode": "wall", "collide": false})
	_prop("Houseplant5", Vector3(1.85, 0.0, 0.55), 0.0, {"path": QUAT + "Houseplant_5.glb", "scale": 1.4})
	_picture(Vector3(2.24, 1.95, 3.40), true, 1.15, 0.78, Color(0.42, 0.49, 0.38), Color(0.86, 0.80, 0.66))
	_curtains_for("KitchenNorthA")
	_curtains_for("KitchenNorthB")

	# --- study ---
	_prop("desk", Vector3(6.20, 0.0, -7.05), 180.0, {"scale": 2.0})
	_prop("chairDesk", Vector3(6.20, 0.0, -6.25), 0.0, {"scale": 1.4})
	_prop("laptop", Vector3(6.15, 1.20, -7.05), 180.0, {"mode": "wall", "collide": false, "scale": 2.0})
	_prop("bookcaseOpen", Vector3(5.60, 0.0, -4.35), 0.0, {"scale": 2.4})
	_prop("bookcaseOpenLow", Vector3(7.80, 0.0, -4.35), 0.0, {"scale": 2.4})
	_prop("bookcaseClosed", Vector3(2.72, 0.0, -5.20), 90.0, {"scale": 2.4})
	_prop("rugSquare", Vector3(5.70, 0.015, -5.50), 0.0, {"collide": false, "scale": 2.8, "fabric": FABRIC_TERRACOTTA})
	_prop("lampSquareTable", Vector3(7.65, 1.20, -7.05), 0.0, {"mode": "wall", "collide": false, "scale": 1.6})
	_prop("loungeChair", Vector3(4.05, 0.0, -5.30), 55.0, {"scale": 1.9, "fabric": FABRIC_GREEN})
	_prop("sideTable", Vector3(3.60, 0.0, -6.10), 0.0, {"scale": 1.7})
	_prop("Houseplant1", Vector3(8.90, 0.0, -7.10), 0.0, {"path": QUAT + "Houseplant_1.glb", "scale": 1.1})
	_prop("StudyDeskLamp", Vector3(7.15, 1.20, -7.05), 0.0, {"path": KIT + "lampSquareTable.glb", "mode": "wall", "collide": false, "scale": 1.4})
	_prop("StudyPlant", Vector3(8.95, 0.0, -3.95), 0.0, {"path": QUAT + "Houseplant_5.glb", "scale": 1.2})
	_prop("StudyReadingChair", Vector3(3.25, 0.0, -6.85), 25.0, {"path": KIT + "loungeChair.glb", "scale": 1.8, "fabric": FABRIC_MUSTARD})
	_picture(Vector3(6.50, 1.95, -7.63), false, 0.95, 0.68, Color(0.38, 0.45, 0.50), Color(0.87, 0.80, 0.64))
	_curtains_for("StudySouthA")
	_curtains_for("StudySouthB")
	_curtains_for("StudyEast")

	# --- boot room ---
	_prop("bench", Vector3(3.30, 0.0, 7.32), 0.0, {"scale": 2.5})
	_prop("coatRackStanding", Vector3(2.88, 0.0, 6.25), 0.0, {"scale": 2.2})
	_prop("Cupboard", Vector3(9.04, 0.0, 6.35), 270.0, {"path": KIT + "bookcaseClosedWide.glb", "scale": 2.4})
	_prop("rugDoormat", Vector3(5.40, 0.02, 7.15), 0.0, {"collide": false, "scale": 2.2})
	_prop("MilkChurn", Vector3(8.92, 0.0, 4.45), 0.0, {"path": PROPS + "yard/milk_churn.glb", "scale": 1.0})
	_prop("BootCrate", Vector3(8.55, 0.0, 7.18), 15.0, {"path": PROPS + "yard/crate.glb", "scale": 0.9})
	_prop("Broom", Vector3(2.92, 0.0, 4.60), 20.0, {"path": PROPS + "stable/broom.glb", "scale": 1.0})
	_prop("Houseplant8", Vector3(2.80, 0.0, 7.35), 0.0, {"path": QUAT + "Houseplant_8.glb", "scale": 0.9})
	_prop("BootPlant", Vector3(8.90, 0.0, 3.95), 0.0, {"path": QUAT + "Houseplant_5.glb", "scale": 1.1})
	_picture(Vector3(3.30, 1.65, 7.60), false, 0.95, 0.72, Color(0.50, 0.42, 0.30), Color(0.85, 0.80, 0.68))
	_picture(Vector3(2.24, 1.85, 5.20), true, 0.80, 0.60, Color(0.50, 0.42, 0.30), Color(0.85, 0.80, 0.68))
	_curtains_for("BootNorth")

	# --- hall ---
	_prop("HallRunner", Vector3(5.00, 0.015, 0.30), 90.0, {"path": KIT + "rugRectangle.glb", "scale": 2.2, "collide": false, "fabric": FABRIC_TERRACOTTA})
	_prop("sideTable", Vector3(2.78, 0.0, 0.00), 90.0, {"scale": 2.0})
	_prop("lampRoundTable", Vector3(2.78, 0.76, 0.00), 0.0, {"mode": "wall", "collide": false, "scale": S})
	_prop("coatRack", Vector3(2.56, 1.95, 3.15), 90.0, {"mode": "wall", "collide": false, "scale": 1.8})
	_prop("bench", Vector3(2.78, 0.0, 3.15), 90.0, {"scale": 2.2})
	_prop("rugDoormat", Vector3(9.08, 0.02, 2.68), 90.0, {"collide": false, "scale": 2.2})
	_prop("Houseplant7", Vector3(7.20, 0.0, 1.00), 0.0, {"path": QUAT + "Houseplant_7.glb", "scale": 1.05})
	_prop("HallConsole", Vector3(6.60, 0.0, -3.35), 0.0, {"path": KIT + "sideTable.glb", "scale": 2.0})
	_prop("HallConsoleLamp", Vector3(6.60, 0.76, -3.35), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": 1.8})
	_picture(Vector3(6.60, 1.85, -3.62), false, 1.15, 0.78, Color(0.47, 0.42, 0.31), Color(0.88, 0.82, 0.68))
	_prop("StairMat", Vector3(8.78, 1.29, -3.15), 0.0, {"path": KIT + "rugRectangle.glb", "scale": 0.65, "mode": "wall", "collide": false, "tint": FABRIC_TERRACOTTA})
	_picture(Vector3(2.24, 1.95, -0.10), true, 1.05, 0.75, Color(0.47, 0.42, 0.31), Color(0.88, 0.82, 0.68))

	# --- main bedroom ---
	_prop("bedDouble", Vector3(-7.85, UPPER_FLOOR, -3.80), 270.0, {"scale": 2.0, "fabric": FABRIC_CREAM})
	_prop("MainBedRug", Vector3(-6.30, UPPER_FLOOR + 0.015, -3.80), 0.0, {"path": TEXTILE + "Textile_rug_02.glb", "scale": 2.6, "collide": false, "tint": Color(1.0, 0.91, 0.82)})
	_prop("Nightstand", Vector3(-8.90, UPPER_FLOOR, -5.75), 270.0, {"path": KIT + "cabinetBedDrawer.glb", "scale": S})
	_prop("NightstandB", Vector3(-8.90, UPPER_FLOOR, -1.85), 270.0, {"path": KIT + "cabinetBedDrawer.glb", "scale": S})
	_prop("BedLampA", Vector3(-8.90, UPPER_FLOOR + 0.78, -5.75), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": S})
	_prop("BedLampB", Vector3(-8.90, UPPER_FLOOR + 0.78, -1.85), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": S})
	_prop("BedBench", Vector3(-5.60, UPPER_FLOOR, -3.80), 90.0, {"path": KIT + "benchCushion.glb", "scale": 2.2, "fabric": FABRIC_GREEN})
	_prop("BedThrow", Vector3(-6.25, UPPER_FLOOR + 0.72, -3.80), 90.0, {"path": TEXTILE + "Textile_blanket_02.glb", "scale": 1.4, "mode": "wall", "collide": false, "tint": Color(1.0, 0.90, 0.78)})
	_prop("BedPillow", Vector3(-8.55, UPPER_FLOOR + 0.72, -4.70), 90.0, {"path": TEXTILE + "Textile_pillow_03.glb", "scale": 1.1, "mode": "wall", "collide": false, "tint": Color(1.0, 0.95, 0.88)})
	_prop("Dresser", Vector3(-3.30, UPPER_FLOOR, -0.35), 180.0, {"path": KIT + "sideTableDrawers.glb", "scale": 2.2})
	_prop("Armoire", Vector3(-1.20, UPPER_FLOOR, -0.35), 180.0, {"path": KIT + "bookcaseClosedWide.glb", "scale": 2.3})
	_prop("BedReadingRug", Vector3(0.20, UPPER_FLOOR + 0.015, -5.75), 0.0, {"path": KIT + "rugRound.glb", "scale": 1.3, "collide": false, "tint": FABRIC_BLUE})
	_prop("BedReadingChair", Vector3(0.20, UPPER_FLOOR, -6.35), 170.0, {"path": KIT + "loungeChair.glb", "scale": 1.9, "fabric": FABRIC_MUSTARD})
	_prop("BedReadingTable", Vector3(1.35, UPPER_FLOOR, -6.35), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.7})
	_prop("BedReadingLamp", Vector3(1.90, UPPER_FLOOR, -6.90), 0.0, {"path": QUAT + "Light_Floor2.glb", "scale": 1.1})
	_prop("Houseplant4", Vector3(1.85, UPPER_FLOOR, -0.65), 0.0, {"path": QUAT + "Houseplant_4.glb", "scale": 1.25})
	_prop("BedroomDesk", Vector3(1.55, UPPER_FLOOR, -5.15), 270.0, {"path": KIT + "desk.glb", "scale": 1.8})
	_prop("BedroomChaise", Vector3(1.20, UPPER_FLOOR, -3.10), 270.0, {"path": KIT + "loungeChair.glb", "scale": 2.1, "fabric": FABRIC_CREAM})
	_prop("BedroomChaiseTable", Vector3(1.20, UPPER_FLOOR, -4.05), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.5})
	_prop("BedroomChaiseRug", Vector3(0.40, UPPER_FLOOR + 0.015, -3.30), 0.0, {"path": KIT + "rugRound.glb", "scale": 1.8, "collide": false, "tint": FABRIC_BLUE})
	_mesh_box(_furniture, "BedroomWindowSeat", Vector3(-4.90, UPPER_FLOOR + 0.23, -7.46), Vector3(2.10, 0.46, 0.52), _wood_trim())
	_collide_box(Vector3(-4.90, UPPER_FLOOR + 0.23, -7.46), Vector3(2.10, 0.46, 0.52))
	_mesh_box(_furniture, "BedroomWindowSeatCushion", Vector3(-4.90, UPPER_FLOOR + 0.51, -7.44), Vector3(1.98, 0.12, 0.50), _cloth("cushion_cream", FABRIC_CREAM))
	_prop("BedroomDeskChair", Vector3(0.80, UPPER_FLOOR, -5.15), 90.0, {"path": KIT + "chairDesk.glb", "scale": 1.3})
	_prop("BedroomDeskLamp", Vector3(1.55, UPPER_FLOOR + 1.12, -5.15), 0.0, {"path": KIT + "lampSquareTable.glb", "mode": "wall", "collide": false, "scale": 1.4})
	_prop("BedroomPlant", Vector3(2.10, UPPER_FLOOR, -3.95), 0.0, {"path": QUAT + "Houseplant_4.glb", "scale": 1.2})
	_picture(Vector3(2.24, UPPER_FLOOR + 1.80, -5.15), true, 1.00, 0.72, Color(0.44, 0.50, 0.42), Color(0.88, 0.82, 0.68))
	_picture(Vector3(0.20, UPPER_FLOOR + 1.85, -7.63), false, 1.30, 0.86, Color(0.54, 0.43, 0.33), Color(0.86, 0.80, 0.68))
	_picture(Vector3(-8.05, UPPER_FLOOR + 1.75, -7.63), false, 1.10, 0.78, Color(0.44, 0.48, 0.42), Color(0.88, 0.82, 0.68))
	_picture(Vector3(-9.36, UPPER_FLOOR + 1.80, -0.80), true, 0.90, 0.66, Color(0.54, 0.43, 0.33), Color(0.86, 0.80, 0.68))
	_curtains_for("MainBedSouthA")
	_curtains_for("MainBedSouthB")
	_curtains_for("MainBedSouthC")
	_curtains_for("MainBedWestA")
	_curtains_for("MainBedWestB")

	# --- second bedroom ---
	_prop("bedSingle", Vector3(-7.80, UPPER_FLOOR, 2.10), 270.0, {"scale": 2.0, "fabric": FABRIC_CREAM})
	_prop("bedSingleB", Vector3(-7.80, UPPER_FLOOR, 5.50), 270.0, {"path": KIT + "bedSingle.glb", "scale": 2.0, "fabric": FABRIC_CREAM})
	_prop("SecondBedRug", Vector3(-5.30, UPPER_FLOOR + 0.015, 3.80), 0.0, {"path": KIT + "rugRound.glb", "scale": 2.2, "collide": false, "tint": FABRIC_TERRACOTTA})
	_prop("NightstandC", Vector3(-8.90, UPPER_FLOOR, 3.80), 270.0, {"path": KIT + "cabinetBedDrawer.glb", "scale": S})
	_prop("BedLampC", Vector3(-8.90, UPPER_FLOOR + 0.78, 3.80), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": S})
	_prop("desk", Vector3(-2.40, UPPER_FLOOR, 7.05), 180.0, {"scale": 2.0})
	_prop("chairDesk", Vector3(-2.40, UPPER_FLOOR, 6.25), 0.0, {"scale": 1.4})
	_prop("laptop", Vector3(-2.45, UPPER_FLOOR + 1.20, 7.05), 180.0, {"mode": "wall", "collide": false, "scale": 2.0})
	# Clear of the cased opening at z 0.70..2.50: a bookcase across the door
	# left only a squeeze between it and the side table.
	_prop("bookcaseOpenLow", Vector3(2.12, UPPER_FLOOR, 3.95), 270.0, {"scale": 2.3})
	_prop("Chest", Vector3(2.12, UPPER_FLOOR, 5.90), 270.0, {"path": KIT + "sideTableDrawers.glb", "scale": 2.2})
	_prop("Houseplant3B", Vector3(1.85, UPPER_FLOOR, 6.95), 0.0, {"path": QUAT + "Houseplant_3.glb", "scale": 1.25})
	_prop("SecondBedChair", Vector3(0.75, UPPER_FLOOR, 2.60), 250.0, {"path": KIT + "loungeChair.glb", "scale": 1.8, "fabric": FABRIC_BLUE})
	_prop("SecondBedTable", Vector3(1.65, UPPER_FLOOR, 2.60), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.5})
	_prop("SecondBedPlant", Vector3(2.10, UPPER_FLOOR, 7.15), 0.0, {"path": QUAT + "Houseplant_4.glb", "scale": 1.1})
	_picture(Vector3(-3.20, UPPER_FLOOR + 1.75, 7.63), false, 1.00, 0.72, Color(0.38, 0.44, 0.50), Color(0.88, 0.82, 0.68))
	_curtains_for("SecondBedNorthA")
	_curtains_for("SecondBedNorthB")
	_curtains_for("SecondBedNorthC")
	_curtains_for("SecondBedWestA")
	_curtains_for("SecondBedWestB")

	# --- bathroom ---
	_prop("bathtub", Vector3(7.35, UPPER_FLOOR, 6.95), 0.0, {"scale": 1.8})
	_prop("bathroomSink", Vector3(3.60, UPPER_FLOOR, 7.28), 0.0, {"scale": 1.4})
	_prop("bathroomSinkB", Vector3(5.05, UPPER_FLOOR, 7.28), 0.0, {"path": KIT + "bathroomSink.glb", "scale": 1.4})
	_prop("Vanity", Vector3(4.32, UPPER_FLOOR, 7.32), 0.0, {"path": KIT + "bathroomCabinetDrawer.glb", "scale": 2.0})
	_prop("bathroomMirror", Vector3(3.60, UPPER_FLOOR + 1.55, 7.56), 0.0, {"mode": "wall", "collide": false, "scale": 1.5})
	_prop("bathroomMirrorB", Vector3(5.05, UPPER_FLOOR + 1.55, 7.56), 0.0, {"path": KIT + "bathroomMirror.glb", "mode": "wall", "collide": false, "scale": 1.5})
	_prop("toilet", Vector3(3.10, UPPER_FLOOR, 5.35), 90.0, {"scale": 0.95})
	_prop("TowelRail", Vector3(9.20, UPPER_FLOOR + 1.15, 4.55), 270.0, {"path": QUAT + "Bathroom_Towel.glb", "scale": 1.25, "mode": "wall", "collide": false, "tint": Color(1.0, 0.94, 0.86)})
	_prop("BathRug", Vector3(5.40, UPPER_FLOOR + 0.015, 5.55), 0.0, {"path": KIT + "rugRectangle.glb", "collide": false, "scale": 2.6, "fabric": FABRIC_CREAM})
	_prop("BathPlant", Vector3(8.95, UPPER_FLOOR, 4.00), 0.0, {"path": QUAT + "Houseplant_5.glb", "scale": 1.25})
	_prop("BathStool", Vector3(8.95, UPPER_FLOOR, 5.95), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.4})
	_prop("BathLaundry", Vector3(2.75, UPPER_FLOOR, 4.40), 0.0, {"path": PROPS + "yard/crate.glb", "scale": 0.75})
	# Folded towels on the vanity and a bath tray across the tub.
	_mesh_box(_furniture, "BathTowelA", Vector3(4.32, UPPER_FLOOR + 1.02, 7.12), Vector3(0.52, 0.10, 0.34), _cloth("towel_cream", Color(0.92, 0.88, 0.80), 0.95))
	_mesh_box(_furniture, "BathTowelB", Vector3(4.32, UPPER_FLOOR + 1.12, 7.12), Vector3(0.46, 0.09, 0.30), _cloth("towel_blue", FABRIC_BLUE, 0.95))
	_mesh_box(_furniture, "BathTray", Vector3(7.35, UPPER_FLOOR + 0.66, 6.95), Vector3(1.35, 0.05, 0.30), _wood_trim())
	_picture(Vector3(2.24, UPPER_FLOOR + 1.65, 6.20), true, 0.75, 0.55, Color(0.48, 0.52, 0.50), Color(0.88, 0.84, 0.74))
	_curtains_for("BathNorthA")
	_curtains_for("BathNorthB")
	_curtains_for("BathEast")

	# --- landing and gallery ---
	_prop("LandingRug", Vector3(4.60, UPPER_FLOOR + 0.015, -5.80), 0.0, {"path": KIT + "rugRectangle.glb", "scale": 1.3, "collide": false, "tint": FABRIC_BLUE})
	_prop("LandingChairA", Vector3(3.90, UPPER_FLOOR, -6.40), 155.0, {"path": KIT + "loungeChair.glb", "scale": 1.9, "fabric": FABRIC_GREEN})
	_prop("LandingChairB", Vector3(5.30, UPPER_FLOOR, -6.40), 205.0, {"path": KIT + "loungeChair.glb", "scale": 1.9, "fabric": FABRIC_GREEN})
	_prop("LandingTable", Vector3(4.60, UPPER_FLOOR, -6.55), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.7})
	_prop("LandingLamp", Vector3(5.85, UPPER_FLOOR, -7.00), 0.0, {"path": QUAT + "Light_Floor1.glb", "scale": 1.15})
	_prop("LinenCupboard", Vector3(9.07, UPPER_FLOOR, -4.15), 270.0, {"path": KIT + "bookcaseClosedWide.glb", "scale": 2.4})
	_prop("LandingConsole", Vector3(9.00, UPPER_FLOOR, -7.15), 270.0, {"path": KIT + "sideTable.glb", "scale": 1.2})
	_prop("LandingConsoleLamp", Vector3(9.00, UPPER_FLOOR + 0.62, -7.15), 0.0, {"path": KIT + "lampRoundTable.glb", "mode": "wall", "collide": false, "scale": 1.3})
	_prop("Houseplant6B", Vector3(3.10, UPPER_FLOOR, -4.25), 0.0, {"path": QUAT + "Houseplant_6.glb", "scale": 1.1})
	_picture(Vector3(9.36, UPPER_FLOOR + 1.80, -6.70), true, 0.95, 0.70, Color(0.44, 0.50, 0.42), Color(0.87, 0.81, 0.67))
	_curtains_for("LandingSouth")
	_prop("GalleryBench", Vector3(2.78, UPPER_FLOOR, 2.80), 90.0, {"path": KIT + "bench.glb", "scale": 2.4})
	_prop("GalleryCushion", Vector3(2.78, UPPER_FLOOR + 0.48, 2.80), 90.0, {"path": KIT + "benchCushion.glb", "scale": S, "fabric": FABRIC_MUSTARD})
	_prop("GalleryBookcase", Vector3(2.72, UPPER_FLOOR, -2.80), 90.0, {"path": KIT + "bookcaseClosed.glb", "scale": 2.2})
	_prop("GalleryRug", Vector3(5.60, UPPER_FLOOR + 0.015, 1.90), 0.0, {"path": KIT + "rugRound.glb", "scale": 1.8, "collide": false, "tint": FABRIC_TERRACOTTA})
	_prop("GalleryPlant", Vector3(8.95, UPPER_FLOOR, 3.15), 0.0, {"path": QUAT + "Houseplant_7.glb", "scale": 1.1})
	_prop("GalleryChair", Vector3(7.30, UPPER_FLOOR, 3.10), 200.0, {"path": KIT + "loungeChair.glb", "scale": 2.0, "fabric": FABRIC_GREEN})
	_prop("GallerySideTable", Vector3(8.30, UPPER_FLOOR, 3.10), 0.0, {"path": KIT + "sideTable.glb", "scale": 1.7})
	_prop("GalleryConsole", Vector3(9.02, UPPER_FLOOR, 2.35), 270.0, {"path": KIT + "sideTable.glb", "scale": 1.6})
	_picture(Vector3(2.24, UPPER_FLOOR + 1.80, 0.80), true, 0.95, 0.70, Color(0.50, 0.44, 0.32), Color(0.88, 0.82, 0.68))

	_flush_merges()



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
	_seat("SofaSeat", "seat", Vector3(-3.75, 0.48, -3.80), 90.0, 1.15, {"stand_offset": Vector3(1.0, 0.0, 0.0)})
	_seat("ChairSeatSouth", "seat", Vector3(-6.80, 0.48, -5.55), -90.0, 1.12)
	_seat("ChairSeatNorth", "seat", Vector3(-6.80, 0.48, -2.05), -90.0, 1.12)
	_seat("NookChairSeatA", "seat", Vector3(-1.05, 0.48, -6.55), 165.0, 1.12)
	_seat("NookChairSeatB", "seat", Vector3(1.55, 0.48, -6.55), 195.0, 1.12)
	_seat("WindowSeat", "seat", Vector3(-2.20, 0.57, -7.42), 180.0, 1.10, {"stand_offset": Vector3(0.0, 0.0, 1.0)})
	_seat("KitchenSeatWest", "seat", Vector3(-2.95, 0.47, 4.95), 0.0, 1.15, {"stand_offset": Vector3(0.0, 0.0, -0.9)})
	_seat("KitchenSeatEast", "seat", Vector3(-1.65, 0.47, 4.95), 0.0, 1.15, {"stand_offset": Vector3(0.0, 0.0, -0.9)})
	_seat("KitchenSeatNorth", "seat", Vector3(-2.95, 0.47, 6.85), 180.0, 1.15)
	_seat("IslandSeatA", "seat", Vector3(-4.10, 0.86, 3.25), 270.0, 1.30, {"stand_offset": Vector3(0.9, 0.0, 0.0)})
	_seat("IslandSeatB", "seat", Vector3(-4.10, 0.86, 3.85), 270.0, 1.30, {"stand_offset": Vector3(0.9, 0.0, 0.0)})
	_seat("StudySeat", "seat", Vector3(6.20, 0.50, -6.25), 0.0, 1.18)
	_seat("LandingSeatA", "seat", Vector3(3.90, UPPER_FLOOR + 0.48, -6.40), 155.0, 1.12)
	_seat("LandingSeatB", "seat", Vector3(5.30, UPPER_FLOOR + 0.48, -6.40), 205.0, 1.12)
	_seat("GallerySeat", "seat", Vector3(2.78, UPPER_FLOOR + 0.50, 2.80), 90.0, 1.12, {"stand_offset": Vector3(0.9, 0.0, 0.0)})
	_seat("MainBedRest", "bed", Vector3(-7.85, UPPER_FLOOR + 0.52, -3.80), 90.0, 0.82, {"pitch": -22.0, "label": "REST", "stand_offset": Vector3(1.4, 0.0, 0.0)})
	_seat("SecondBedRestA", "bed", Vector3(-7.80, UPPER_FLOOR + 0.50, 2.10), 90.0, 0.80, {"pitch": -22.0, "label": "REST", "stand_offset": Vector3(1.4, 0.0, 0.0)})
	_seat("SecondBedRestB", "bed", Vector3(-7.80, UPPER_FLOOR + 0.50, 5.50), 90.0, 0.80, {"pitch": -22.0, "label": "REST", "stand_offset": Vector3(1.4, 0.0, 0.0)})


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
	shade.material_override = _cloth("shade", Color(0.93, 0.88, 0.77), 0.65)
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

	_lamp("LampSitting", Vector3(-5.30, 2.58, -3.80), Color(1.0, 0.80, 0.56), 2.6, 9.5)
	_lamp("LampSittingNook", Vector3(0.50, 2.58, -6.00), Color(1.0, 0.82, 0.58), 1.8, 6.5)
	_lamp("LampKitchen", Vector3(-5.80, 2.58, 3.40), Color(1.0, 0.86, 0.64), 2.5, 9.0)
	_lamp("LampDining", Vector3(-2.30, 2.58, 5.90), Color(1.0, 0.80, 0.56), 2.3, 8.0)
	_lamp("LampStudy", Vector3(6.20, 2.58, -5.80), Color(1.0, 0.84, 0.60), 2.0, 7.0)
	_lamp("LampHall", Vector3(5.20, 2.58, 0.20), Color(1.0, 0.82, 0.58), 2.2, 8.0)
	_lamp("LampBoot", Vector3(5.20, 2.58, 5.80), Color(1.0, 0.84, 0.62), 1.8, 6.0)
	_lamp("LampMainBed", Vector3(-6.00, 5.58, -3.80), Color(1.0, 0.82, 0.62), 2.4, 8.5)
	_lamp("LampSecondBed", Vector3(-6.00, 5.58, 3.80), Color(1.0, 0.82, 0.62), 2.2, 8.0)
	_lamp("LampLanding", Vector3(4.50, 5.58, -5.80), Color(1.0, 0.84, 0.62), 2.0, 6.5)
	_lamp("LampBath", Vector3(5.50, 5.58, 5.80), Color(1.0, 0.88, 0.72), 1.9, 6.0)
	_lamp("LampGallery", Vector3(5.50, 5.58, 0.80), Color(1.0, 0.84, 0.62), 2.0, 6.5)
	_lamp("Firelight", Vector3(X0 + 0.85, 0.42, -3.80), Color(1.0, 0.52, 0.20), 2.4, 5.5, true)


## The house dog, in the kitchen by his bowl.  Same scene as the yard dog, so
## the feeding and petting behaviour is shared.
func _build_dog() -> void:
	var packed := load(DOG) as PackedScene
	if packed == null:
		push_error("missing dog scene")
		return
	var dog := packed.instantiate() as Node3D
	dog.name = "Dog"
	dog.position = Vector3(0.0, 0.0, 6.85)
	dog.rotation.y = deg_to_rad(0.0)
	_root.add_child(dog)


func _build_player() -> void:
	var packed := load(PLAYER) as PackedScene
	if packed == null:
		push_error("missing player scene")
		return
	var player := packed.instantiate() as CharacterBody3D
	player.name = "Player"
	_root.add_child(player)
	player.position = Vector3(8.35, 0.05, 2.68)
	player.rotation.y = deg_to_rad(90.0)
	# Layer 1 is the shell, layer 4 the furniture: the player walks into both.
	player.collision_mask = 1 | 4


## The front door back out to the yard, plus a collider for its closed leaf so
## the player cannot walk through into the empty exterior.
func _build_exit_door() -> void:
	var link := Node3D.new()
	link.name = "FrontDoorExit"
	link.set_script(load(DOOR))
	link.position = Vector3(X1 - 0.60, 0.0, 2.68)
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
	box.size = Vector3(0.12, 2.55, 1.28)
	shape.shape = box
	body.position = Vector3(X1, 1.275, 2.68)
	body.add_child(shape)
	_root.add_child(body)


func _rooms() -> Array:
	return [
		{"name": "sitting", "min": [X0, Z0], "max": [HALL_X, 0.0], "floor": 0},
		{"name": "kitchen", "min": [X0, 0.0], "max": [HALL_X, Z1], "floor": 0},
		{"name": "hall", "min": [HALL_X, STUDY_Z], "max": [X1, BOOT_Z], "floor": 0},
		{"name": "study", "min": [HALL_X, Z0], "max": [X1, STUDY_Z], "floor": 0},
		{"name": "boot", "min": [HALL_X, BOOT_Z], "max": [X1, Z1], "floor": 0},
		{"name": "main_bed", "min": [X0, Z0], "max": [HALL_X, 0.0], "floor": 1},
		{"name": "second_bed", "min": [X0, 0.0], "max": [HALL_X, Z1], "floor": 1},
		{"name": "landing", "min": [HALL_X, Z0], "max": [X1, STUDY_Z], "floor": 1},
		{"name": "bath", "min": [HALL_X, BOOT_Z], "max": [X1, Z1], "floor": 1},
		{"name": "gallery", "min": [HALL_X, STUDY_Z], "max": [X1, BOOT_Z], "floor": 1},
	]
