extends Node3D

## Live reins from the bit rings to the rider's hands.
##
## Both ends are animated independently (the horse's head and the rider's
## hands), so the leather is rebuilt as a thin ribbon every frame instead of
## being baked into either rig.  That keeps it attached through walk, trot,
## canter and the jump, and lets the hands shorten the rein naturally.

@export var width := 0.046
@export var segments := 9
@export var sag_ratio := 0.11
@export var min_sag := 0.03
@export var max_sag := 0.14
@export var leather_color := Color(0.13, 0.055, 0.022)

var _mesh: MeshInstance3D
var _immediate: ImmediateMesh
var _material: StandardMaterial3D
var _horse: Node3D
var _player: CharacterBody3D


func _ready() -> void:
	# The mesh vertices are rebuilt in world space, so the node must not
	# inherit the player's transform.  top_level preserves the global
	# transform it had at the call, which is the player's spawn point, so
	# clear that too or the reins render offset from the horse.
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 60
	_player = get_parent() as CharacterBody3D
	_horse = get_tree().get_first_node_in_group("horse") as Node3D

	_immediate = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.albedo_color = leather_color
	_material.roughness = 0.58
	_material.metallic_specular = 0.22
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = MeshInstance3D.new()
	_mesh.name = "ReinMesh"
	_mesh.mesh = _immediate
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)
	_mesh.visible = false


func _process(_delta: float) -> void:
	if _player == null or _horse == null:
		return
	var mounted: bool = _player.mounted
	var leading: bool = _player.get("leading") == true
	if (not mounted and not leading) or not _horse.has_method("get_bit_anchor"):
		_mesh.visible = false
		return
	_mesh.visible = true
	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	if mounted:
		_add_rein(_horse.get_bit_anchor("L"), _player.get_hand_anchor("Left"))
		_add_rein(_horse.get_bit_anchor("R"), _player.get_hand_anchor("Right"))
	else:
		_add_lead_rope()
	_immediate.surface_end()


## On foot the handler holds one rope.  Use the side whose hand and bit are
## closest, so the leather does not have to cross the horse's neck.
func _add_lead_rope() -> void:
	var bit_left: Vector3 = _horse.get_bit_anchor("L")
	var bit_right: Vector3 = _horse.get_bit_anchor("R")
	var hand_left: Vector3 = _player.get_hand_anchor("Left")
	var hand_right: Vector3 = _player.get_hand_anchor("Right")
	if bit_right.distance_to(hand_right) < bit_left.distance_to(hand_left):
		_add_rein(bit_right, hand_right)
	else:
		_add_rein(bit_left, hand_left)


func _add_rein(bit: Vector3, hand: Vector3) -> void:
	var span := bit.distance_to(hand)
	var sag := clampf(span * sag_ratio, min_sag, max_sag)
	# Quadratic Bezier: straight line between the bit and the fist, dropped
	# slightly at the midpoint so the leather hangs instead of cutting through
	# the horse's neck.
	var control := (bit + hand) * 0.5 - Vector3.UP * sag

	var points: Array[Vector3] = []
	var sides: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := _bezier(bit, control, hand, t)
		var tangent := _bezier_tangent(bit, control, hand, t)
		var side := tangent.cross(Vector3.UP)
		if side.length() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized() * (width * 0.5)
		var normal := side.cross(tangent).normalized()
		if normal.length() < 0.001:
			normal = Vector3.UP
		points.append(p)
		sides.append(side)
		normals.append(normal)

	for i in range(segments):
		_quad(
			points[i] - sides[i],
			points[i] + sides[i],
			points[i + 1] + sides[i + 1],
			points[i + 1] - sides[i + 1],
			normals[i]
		)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_tri(a, b, c, normal)
	_tri(a, c, d, normal)


func _tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for p in [a, b, c]:
		_immediate.surface_set_normal(normal)
		_immediate.surface_add_vertex(p)


func _bezier(a: Vector3, control: Vector3, b: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u) + control * (2.0 * u * t) + b * (t * t)


func _bezier_tangent(a: Vector3, control: Vector3, b: Vector3, t: float) -> Vector3:
	return (control - a) * (2.0 * (1.0 - t)) + (b - control) * (2.0 * t)
