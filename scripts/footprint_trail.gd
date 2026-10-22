extends Node3D

## The shared footprint trail.
##
## Every hoof and boot landing becomes one instance of a tiny ground quad.  The
## whole trail lives in a single MultiMesh (one draw call) with a fixed ring
## buffer of slots, so leaving prints costs no allocation, no texture upload and
## no per-frame CPU work beyond the shader clock.  When the ring wraps, the
## oldest print is reused, which is exactly the fade budget: at a hand canter
## the horse lays about five prints a second.
##
## The quads are multiplied into the ground by res/shaders/footprint.gdshader
## (see that file for why multiply blending was chosen over decals).
##
## Other nodes find the trail through the "footprint_trail" group; the emitters
## on the horse and the player are the only writers in normal play.

const TRAIL_GROUP := "footprint_trail"
const MAX_PRINTS := 192
## Quads sit just above the flat ground plane; the render mode never writes
## depth, so this only has to beat z-precision, not z-fighting between prints.
const GROUND_OFFSET := 0.012
## The play area the trail can reach.  The MultiMesh keeps a fixed AABB so the
## trail is never culled in the middle of the yard.
const TRAIL_BOUNDS := AABB(Vector3(-100.0, -1.0, -100.0), Vector3(200.0, 4.0, 200.0))

## Seconds a print takes to fade out completely.
@export var print_lifetime := 40.0
## How strongly a fresh print stains the ground (max alpha).
@export var tint_strength := 0.5
@export var print_tint := Color(0.20, 0.16, 0.12, 1.0)

var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _next := 0
var _time := 0.0
var _stamped := 0
## CPU-side mirror of the ring buffer.  The MultiMesh data lives on the
## rendering server, which the headless renderer does not store, so the trail
## keeps its own copy of what it laid.  That is what get_slot() reports and it
## lets game code and the check read the trail without a renderer.
var _slots: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(TRAIL_GROUP)
	_build()


func _build() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.subdivide_width = 0
	quad.subdivide_depth = 0

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_PRINTS
	for i in range(MAX_PRINTS):
		_slots.append({})

	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10.0, 0.0))
	for i in range(MAX_PRINTS):
		_multimesh.set_instance_transform(i, parked)
		_multimesh.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))

	_instance = MultiMeshInstance3D.new()
	_instance.name = "FootprintMesh"
	_instance.multimesh = _multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = TRAIL_BOUNDS
	add_child(_instance)

	var source := load("res://resources/materials/footprint.tres") as ShaderMaterial
	if source == null:
		push_warning("FootprintTrail: footprint material missing")
		return
	# Duplicate so tuning one trail never edits the shared resource or another
	# trail in the same scene.
	_material = source.duplicate() as ShaderMaterial
	_material.set_shader_parameter("lifetime", print_lifetime)
	_material.set_shader_parameter("tint", print_tint)
	_material.set_shader_parameter("tint_strength", tint_strength)
	_material.set_shader_parameter("now", _time)
	_instance.material_override = _material


func _process(delta: float) -> void:
	_time += delta
	if _material != null:
		_material.set_shader_parameter("now", _time)


## Leaves one print on the ground.
##
## `position` is only read on X and Z: the trail is authored for the flat ground
## plane, and `size` is metres (width across the print, length along it).  `yaw`
## is the body heading, so the print's toe points the way the animal is facing.
func stamp(position: Vector3, yaw: float, kind: int, size: Vector2, strength := 1.0) -> void:
	if _multimesh == null:
		return
	if is_nan(yaw) or is_nan(position.x) or is_nan(position.z):
		return
	var placement := Vector3(position.x, GROUND_OFFSET, position.z)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(maxf(size.x, 0.01), 1.0, maxf(size.y, 0.01)))
	_multimesh.set_instance_transform(_next, Transform3D(basis, placement))
	var seed := randf()
	_multimesh.set_instance_custom_data(
		_next,
		Color(_time, clampf(strength, 0.0, 1.0), float(kind), seed)
	)
	_slots[_next] = {
		"position": placement,
		"scale": Vector3(maxf(size.x, 0.01), 1.0, maxf(size.y, 0.01)),
		"yaw": yaw,
		"birth": _time,
		"strength": clampf(strength, 0.0, 1.0),
		"kind": kind,
		"seed": seed,
	}
	_next = (_next + 1) % MAX_PRINTS
	_stamped += 1


## Clears the trail.  The check tool uses this between scenarios.
func clear() -> void:
	if _multimesh == null:
		return
	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10.0, 0.0))
	for i in range(MAX_PRINTS):
		_multimesh.set_instance_transform(i, parked)
		_multimesh.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
		_slots[i] = {}
	_next = 0
	_stamped = 0


func clock() -> float:
	return _time


func slot_count() -> int:
	return MAX_PRINTS


func next_slot() -> int:
	return _next


func stamped_count() -> int:
	return _stamped


func get_material() -> ShaderMaterial:
	return _material


## Snapshot of one slot, for the headless check and for debugging a trail that
## does not look right in game.  Empty once the slot has been cleared or has
## never been used.
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	return (_slots[index] as Dictionary).duplicate()
