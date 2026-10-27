extends Node

## Stamps hoof and boot prints into the shared footprint trail.
##
## The node sits on a character and watches a handful of rig bones.  A print is
## laid when a bone reaches the bottom of its stride: the bone's world height
## dips to a local minimum, which is exactly the frame the animation plants the
## hoof or foot.  That keeps prints in sync with walk, trot, canter and both
## player bodies without hard-coding clip timing or stride lengths.
##
## The detector is deliberately rig-agnostic: it learns each bone's own contact
## height from the lowest point it has seen, so it needs no per-model tuning
## beyond the bone names and the print size.

const TRAIL_GROUP := "footprint_trail"

@export_group("Print")
## 0 = hoof (horse), 1 = boot (character).
@export var kind := 0
## Metres: width across the print, length along it.
@export var print_size := Vector2(0.13, 0.16)
## Shifts the print along the body's forward axis, for bones that sit behind
## the sole (an ankle bone needs a few centimetres of lead).
@export var forward_offset := 0.0
## Toe-out on alternating feet, in degrees.
@export var toe_angle_degrees := 3.0

@export_group("Bones")
@export var bone_names := PackedStringArray([
	"front_leg_foot_l", "front_leg_foot_r", "back_leg_toe_l", "back_leg_toe_r",
])
## Optional per-bone size multiplier, in `bone_names` order.
@export var bone_size_scales := PackedFloat32Array()

@export_group("Contact")
## Below this ground speed no prints are laid, so a standing animal leaves none.
@export var min_speed := 0.25
## How far above the bone's lowest-seen height still counts as a contact.
@export var contact_margin := 0.035
## Minimum time between two prints from the same bone.
@export var cooldown := 0.18
## Minimum travel between two prints from the same bone.
@export var min_gap := 0.10
## Ground speed at which a print reaches full strength.
@export var full_strength_speed := 4.0

var _body: Node3D
var _skeleton: Skeleton3D
var _bones: PackedInt32Array = PackedInt32Array()
var _trail: Node
var _prev := PackedFloat32Array()
var _prev2 := PackedFloat32Array()
var _rest := PackedFloat32Array()
var _waited := PackedFloat32Array()
var _last := PackedVector3Array()
var _resolved_for: Skeleton3D
var _warned := false


func _ready() -> void:
	_body = get_parent() as Node3D
	_resolve()


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if not _can_stamp():
		return
	var trail := _get_trail()
	if trail == null:
		return
	var skeleton := _resolve()
	if skeleton == null:
		return

	var speed := _ground_speed()
	var strength := clampf(0.45 + 0.75 * (speed / maxf(full_strength_speed, 0.01)), 0.45, 1.0)
	# The player root carries the view yaw, so the print follows the body's own
	# facing when the body exposes it.  The horse has no such property and keeps
	# using its root, which is already the direction it travels.
	var facing := _body.global_rotation.y
	if _body.has_method("facing_yaw"):
		facing = float(_body.call("facing_yaw"))
	var yaw := facing + PI
	var forward := Vector3(-sin(facing), 0.0, -cos(facing))

	for i in range(_bones.size()):
		_waited[i] = maxf(0.0, _waited[i] - delta)
		var index := _bones[i]
		if index < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		var height := world.y
		_rest[i] = minf(_rest[i], height)
		if _prev2[i] == INF or _prev[i] == INF:
			_prev2[i] = _prev[i]
			_prev[i] = height
			continue
		if is_contact(_prev2[i], _prev[i], height, _rest[i], contact_margin):
			var last := _last[i]
			var travelled := Vector2(world.x - last.x, world.z - last.z).length()
			if _waited[i] <= 0.0 and travelled >= min_gap:
				var position := Vector3(world.x, 0.0, world.z) + forward * forward_offset
				var side := -1.0 if i % 2 == 0 else 1.0
				var size := print_size
				if i < bone_size_scales.size() and bone_size_scales[i] > 0.0:
					size *= bone_size_scales[i]
				trail.call(
					"stamp",
					position,
					yaw + deg_to_rad(toe_angle_degrees) * side,
					kind,
					size,
					strength
				)
				_waited[i] = cooldown
				_last[i] = world
		_prev2[i] = _prev[i]
		_prev[i] = height


## True when `prev` is the bottom of a stride: lower than both neighbours and at
## or below the contact band.  Exposed as a static so the headless check can run
## it against heights recorded from the real animation clips.
static func is_contact(prev2: float, prev: float, now_y: float, rest: float, margin: float) -> bool:
	if prev2 == INF or prev == INF:
		return false
	return prev < prev2 and prev <= now_y and prev <= rest + margin


## Re-resolves the skeleton and bone names.  Called after a player body swap.
func rebind() -> void:
	_resolved_for = null
	_resolve(true)


func _can_stamp() -> bool:
	if not is_instance_valid(_body) or not _body.is_visible_in_tree():
		return false
	# A stabled horse is hidden and inert; a groomed one is frozen; a mounted
	# player is not walking.
	if _flag("boarded") or _flag("grooming"):
		return false
	if _flag("mounted"):
		return false
	if _flag("airborne"):
		return false
	var character := _body as CharacterBody3D
	if character != null and not character.is_on_floor():
		return false
	return _ground_speed() >= min_speed


## Reads an optional bool property from the body.  Not every body has every
## flag (only the horse has `boarded`, only the player has `mounted`), and
## `bool(null)` is an error in GDScript, so the lookup is explicit.
func _flag(property: StringName) -> bool:
	var value = _body.get(property)
	return value is bool and value


func _ground_speed() -> float:
	var character := _body as CharacterBody3D
	if character == null:
		return 0.0
	return Vector2(character.velocity.x, character.velocity.z).length()


func _get_trail() -> Node:
	if _trail != null and is_instance_valid(_trail):
		return _trail
	var tree := get_tree()
	if tree == null:
		return null
	_trail = tree.get_first_node_in_group(TRAIL_GROUP)
	return _trail


func _resolve(force := false) -> Skeleton3D:
	if not force and _skeleton != null and is_instance_valid(_skeleton) and _bones.size() > 0:
		if not _skeleton.is_queued_for_deletion() and _skeleton.is_inside_tree():
			return _skeleton
	if _body == null:
		return null
	var skeletons := _body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		if not _warned:
			_warned = true
			push_warning("FootprintEmitter: no skeleton under %s" % _body.name)
		return null
	_skeleton = skeletons[0] as Skeleton3D
	if _skeleton == _resolved_for and not force:
		return _skeleton
	_resolved_for = _skeleton
	_bones = PackedInt32Array()
	for name in bone_names:
		var index := _skeleton.find_bone(name)
		if index < 0:
			index = _find_bone_containing(_skeleton, name)
		if index < 0 and not _warned:
			_warned = true
			push_warning("FootprintEmitter: bone '%s' not found on %s" % [name, _body.name])
		_bones.append(index)
	_prev.resize(_bones.size())
	_prev2.resize(_bones.size())
	_rest.resize(_bones.size())
	_waited.resize(_bones.size())
	_last.resize(_bones.size())
	for i in range(_bones.size()):
		_prev[i] = INF
		_prev2[i] = INF
		_rest[i] = INF
		_waited[i] = 0.0
		_last[i] = Vector3.ZERO
	return _skeleton


func _find_bone_containing(skeleton: Skeleton3D, part: String) -> int:
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).contains(part):
			return i
	return -1
