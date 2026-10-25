extends Node3D

## An interior door that swings on a hinge.  Starts shut.  E (or CONTEXT on
## touch) opens or closes it.  The leaf collider is only solid while shut, so
## the doorway stays walkable once the door is open.
##
## The node sits on the hinge line.  The leaf extends from the hinge along the
## local +X axis, so the generator rotates the node to match the wall.

const OPEN_ANGLE := -95.0
const SWING_TIME := 0.45

## Leaf width along the wall, in metres.
@export var width := 0.9
## Leaf height, in metres.
@export var height := 2.0
## Leaf thickness, in metres.
@export var thickness := 0.05
## Starts open when true.
@export var start_open := false
## Reach measured from the player's body, so the aim finds a door from close by.
@export var body_reach := 1.6

var _pivot: Node3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _prompt: Label3D
var _open := false
var _tween: Tween


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("touch_context")
	add_to_group("interior_door")
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, thickness)
	leaf.mesh = mesh
	leaf.position = Vector3(width * 0.5, height * 0.5, 0.0)
	leaf.material_override = _wood()
	_pivot.add_child(leaf)

	_body = StaticBody3D.new()
	_body.name = "LeafCollision"
	_body.collision_layer = 1
	_pivot.add_child(_body)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	_shape.shape = box
	_shape.position = leaf.position
	_body.add_child(_shape)

	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
	_prompt.pixel_size = 0.005
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 36
	_prompt.outline_size = 9
	_prompt.outline_modulate = Color(0.04, 0.03, 0.02, 1.0)
	_prompt.modulate = Color(1.0, 0.94, 0.82, 1.0)
	_prompt.position = Vector3(width * 0.5, height + 0.25, 0.0)
	_prompt.visible = false
	add_child(_prompt)

	_open = start_open
	_pivot.rotation_degrees.y = OPEN_ANGLE if _open else 0.0
	_shape.disabled = _open


func is_open() -> bool:
	return _open


func show_prompt(show: bool) -> void:
	if _prompt == null:
		return
	_prompt.visible = show
	if show:
		var verb := "CLOSE" if _open else "OPEN"
		_prompt.text = Device.pick("E  ·  " + verb, "TAP  ·  " + verb)


## CONTEXT offer for touch players while the door is aimed at.
func touch_context() -> Dictionary:
	if _prompt != null and _prompt.visible:
		return {"action": "interact", "label": "CLOSE" if _open else "OPEN", "priority": 3}
	return {}


## Opens or closes the door.  The collider is released at the start of an
## opening and restored at the end of a closing, so the leaf never sits inside
## the player.
func use() -> bool:
	_open = not _open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _open:
		_shape.disabled = true
	_tween = create_tween()
	var target := OPEN_ANGLE if _open else 0.0
	_tween.tween_property(_pivot, "rotation_degrees:y", target, SWING_TIME)
	if not _open:
		_tween.tween_callback(func(): _shape.set_deferred("disabled", false))
	return true


## Opens with no swing, for checks and set-dressing: the leaf and its collider
## are placed at once, so a ray test in the same frame sees the doorway clear.
func open_now() -> void:
	_open = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_pivot.rotation_degrees.y = OPEN_ANGLE
	_shape.disabled = true


func _wood() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.13, 0.09)
	mat.roughness = 0.55
	return mat
