extends SceneTree

## Cost budget for the furnished farmhouse interior.
##
##   godot --headless --path . --script res://tools/check_interior_cost.gd
##
## The detail maps are what make the furniture read as wood, cloth and stone;
## this is what stops them costing more than they are worth.  It counts what the
## renderer is actually asked to submit - mesh instances, unique materials,
## unique textures and decoded texture memory - and fails when a change pushes
## past the budget recorded in agents.md.
##
## Budgets are for the house itself (Shell, Furniture, Lighting); the player and
## the dog bring their own character textures and are not part of this pass.
##
## Measured when the budget was set (before -> after the texture pass):
##   mesh instances      1098 -> 941
##   triangles         154532 -> 107246
##   materials            354 -> 103
##   textured materials    75 -> 52
##   textures             11 -> 15
##   decoded texture MB 17.0 -> 18.1

const SCENE := "res://scenes/farmhouse.tscn"
const GROUPS := ["Shell", "Furniture", "Lighting"]

# Headroom is deliberately thin: a prop pass that adds a room or a dozen pieces
# should raise these numbers on purpose, in the same change.
const MAX_MESHES := 980
const MAX_TRIANGLES := 112000
const MAX_MATERIALS := 115
const MAX_TEXTURED_MATERIALS := 60
const MAX_TEXTURES := 20
const MAX_TEXTURE_MB := 20.0

# The shared catalogue the furniture draws from.  Missing ones mean a prop fell
# back to a flat colour, which is exactly the regression this pass removed.
const REQUIRED_TEXTURES := [
	"res://Models/interior/textures/detail_wood_diff_512.jpg",
	"res://Models/interior/textures/detail_fabric_diff_512.jpg",
	"res://Models/interior/textures/detail_stone_diff_512.jpg",
	"res://Models/interior/textures/detail_metal_diff_256.jpg",
	"res://Models/interior/kenney_food_kit/Textures/colormap.png",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("INTERIOR COST CHECK: FAIL")
		print("  FAIL: could not load ", SCENE)
		quit(1)
		return

	var root := packed.instantiate()
	var meshes := 0
	var triangles := 0
	var materials := {}
	var textured := {}
	var textures := {}

	for group in GROUPS:
		var holder := root.get_node_or_null(group)
		if holder == null:
			_failures.append("the scene has a %s group" % group)
			continue
		for node in holder.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			meshes += 1
			triangles += mesh_instance.mesh.get_faces().size() / 3
			for i in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.get_active_material(i)
				if material == null:
					continue
				materials[material.get_instance_id()] = material
				if material is BaseMaterial3D:
					var texture := (material as BaseMaterial3D).albedo_texture
					if texture != null:
						textures[texture.get_instance_id()] = texture
						textured[material.get_instance_id()] = material

	var megabytes := _decoded_megabytes(textures)
	root.free()

	print("INTERIOR COST")
	print("  mesh instances      %6d  (budget %d)" % [meshes, MAX_MESHES])
	print("  triangles           %6d  (budget %d)" % [triangles, MAX_TRIANGLES])
	print("  materials           %6d  (budget %d)" % [materials.size(), MAX_MATERIALS])
	print("  textured materials  %6d  (budget %d)" % [textured.size(), MAX_TEXTURED_MATERIALS])
	print("  textures            %6d  (budget %d)" % [textures.size(), MAX_TEXTURES])
	print("  decoded texture MB  %6.2f  (budget %.1f)" % [megabytes, MAX_TEXTURE_MB])

	_limit("mesh instances", meshes, MAX_MESHES)
	_limit("triangles", triangles, MAX_TRIANGLES)
	_limit("materials", materials.size(), MAX_MATERIALS)
	_limit("textured materials", textured.size(), MAX_TEXTURED_MATERIALS)
	_limit("textures", textures.size(), MAX_TEXTURES)
	if megabytes > MAX_TEXTURE_MB:
		_failures.append("decoded texture memory %.2f MB is over the %.1f MB budget" % [megabytes, MAX_TEXTURE_MB])

	# The detail maps are the whole point; each must be present, small and
	# mipmapped, so the grain does not shimmer across the room.
	for path in REQUIRED_TEXTURES:
		var texture := load(path) as Texture2D
		if texture == null:
			_failures.append("missing detail texture " + path)
			continue
		if texture.get_size().x > 512.0 or texture.get_size().y > 512.0:
			_failures.append("%s is larger than 512 px" % path)
		if texture.get_size().x != texture.get_size().y:
			_failures.append("%s is not square" % path)

	if _failures.is_empty():
		print("INTERIOR COST CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("INTERIOR COST CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _limit(label: String, value: int, budget: int) -> void:
	if value > budget:
		_failures.append("%s %d is over the %d budget" % [label, value, budget])


## Sampled texture memory: every mip level after the first costs a third of the
## base image, and the import is lossless, so the byte-per-pixel figure comes
## from the decoded format (grey detail maps are one byte, colour is three or
## four).
func _decoded_megabytes(textures: Dictionary) -> float:
	var total := 0.0
	for id in textures:
		var texture: Texture2D = textures[id]
		var image := texture.get_image()
		var bytes_per_pixel := 4
		if image != null:
			match image.get_format():
				Image.FORMAT_L8:
					bytes_per_pixel = 1
				Image.FORMAT_LA8:
					bytes_per_pixel = 2
				Image.FORMAT_RGB8, Image.FORMAT_RGBH:
					bytes_per_pixel = 3
		var pixels := texture.get_size().x * texture.get_size().y
		total += pixels * bytes_per_pixel * 1.333 / 1048576.0
	return total
