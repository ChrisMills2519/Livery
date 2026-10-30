extends CharacterBody3D

const HumanoidAnimation := preload("res://scripts/humanoid_animation.gd")

const FOOTSTEP_SOUNDS := [
	preload("res://assets/sounds/footsteps/footstep_grass_000.ogg"),
	preload("res://assets/sounds/footsteps/footstep_grass_001.ogg"),
	preload("res://assets/sounds/footsteps/footstep_grass_002.ogg"),
	preload("res://assets/sounds/footsteps/footstep_grass_003.ogg"),
	preload("res://assets/sounds/footsteps/footstep_grass_004.ogg"),
]

@export var walk_speed := 3.0
@export var run_speed := 6.0
@export var jump_velocity := 6.0
@export var mouse_sensitivity := 0.0024
@export var gravity := 20.0
@export var step_interval_walk := 0.55
@export var step_interval_run := 0.34
@export var landing_time := 0.28
## Cleared during the character-select handoff so the player cannot walk or
## jump while the camera is still fading in.  Gravity stays active.
var controls_enabled := true

## The riding pose is applied directly to the skeleton each frame; the
## retargeted skeleton's local axes do not match the authored clip.
const RIDE_SWAY_HZ := 0.5

## Fallback camera offsets while mounted, used when no character profile is
## assigned.  Profiles can override them for shorter or taller bodies.
const RIDE_PIVOT := Vector3(0.0, 1.0, 0.0)

## Reach of the camera-centre interaction ray, in metres.
const INTERACT_REACH := 2.4

## Walls (layer 1) and furniture (layer 4) push the on-foot camera in.
## The boom is resolved with a sphere cast, clamped inward at once and eased
## back out, so a wall cannot drag the lens through itself.
const CAMERA_CLIP_MASK := 1 | 4
const CAMERA_CLIP_MARGIN := 0.10
const CAMERA_CLIP_RADIUS := 0.28
## The last-resort distance when every line is blocked.  The walkthrough
## expects the lateral solver to keep the camera well above this in the house;
## it is a safety clamp, not the normal tight-space answer.
const CAMERA_MIN_BOOM := 0.35
const CAMERA_RETURN_SPEED := 2.5
const CAMERA_MODEL_HIDE_BOOM := 0.58

## A blocked direct boom can usually be cleared by sliding the camera sideways
## along the wall, past a chair back or around a plant.  Each offset is metres
## from the normal shoulder line; the camera keeps the player's yaw, so the
## slide shifts the framing rather than turning the view.  The small cost stops
## a clear direct line from losing to a pointless offset.
const CAMERA_SLIDE_OFFSETS := [-1.40, -1.00, -0.70, -0.50, -0.35, 0.0, 0.35, 0.50, 0.70, 1.00, 1.40]
const CAMERA_SLIDE_COST := 0.25
## A slide only helps if the player stays in frame.  At 35 degrees the body is
## at the edge of a 68 degree vertical view, so wider offsets are not offered.
const CAMERA_SLIDE_MAX_ANGLE := 0.61
## When even a slide cannot get behind the player, the last usable view is a
## high look-down from above the head.  It is only offered while the normal
## boom is below a usable length, so a clear rear view never loses to it.
## A doorway head limits how high a look-down can sit, so the lift is tried at
## three heights; the clearest wins.  The lowest still clears the body and is
## only used where a deeper lift would hit the door head.
const CAMERA_OVERHEAD_LIFTS := [0.45, 0.60, 0.95]
const CAMERA_OVERHEAD_TRIGGER := 0.90
const CAMERA_OVERHEAD_OFFSETS := [-0.45, 0.0, 0.45]
const CAMERA_OVERHEAD_TILT := 1.26
const CAMERA_OVERHEAD_BLEND_SPEED := 8.0
## A clear side line is useless if the ease cannot cross the chair that blocks
## the direct line: it would stay pinned at the head.  When the chosen line is
## more than this far around from the current one, step onto it at a usable
## radius first, then ease outward along it.  The step changes direction, not
## distance, so it is a swing rather than a boom pop.
const CAMERA_SWING_ANGLE := 0.30
const CAMERA_SWING_RADIUS := 0.62
const CAMERA_PITCH_MIN := -1.0
const CAMERA_PITCH_MAX := 0.85
const RIDE_CAMERA := Vector3(0.0, 0.0, 5.2)

## Mounted look is an offset from the horse's heading rather than the root yaw.
## The horse steers in its own frame, so a drag looks around without ever
## re-aiming it - the camera-relative spin loop the devlog fought cannot come
## back through this path, because nothing the horse reads goes through here.
## After a moment without dragging the offset eases back to a rear view, which
## is the whole of the auto-recentre: no follow logic, no feedback loop.
const MOUNTED_PITCH_MIN := -0.85
const MOUNTED_PITCH_MAX := 0.60
const MOUNTED_PITCH_NEUTRAL := 0.12
const LOOK_RECENTRE_DELAY := 1.2
const LOOK_RECENTRE_RATE := 1.2
const LOOK_PITCH_RETURN_RATE := 0.6
## The boom and the pivot height are the character profile's walking pose plus
## this much at the canter, so the frame opens up as the horse speeds up.
const RIDE_BOOM_CANTER := 1.2
const RIDE_LIFT_CANTER := 0.55
const RIDE_POSE_RATE := 2.0
## Horse speeds the canter pose is measured between.  Below the first the frame
## is the walking one; above the second it is fully open.
const RIDE_CANTER_START := 3.2
const RIDE_CANTER_FULL := 5.6
## A mounted boom never comes in below this, so the rider's body stays in frame
## even with a fence directly behind the horse.
const MOUNTED_MIN_BOOM := 0.9
## A canter widens the lens a little, eased so a gait change never pops.
const CANTER_FOV := 78.0
const FOV_RATE := 2.0

## On foot the body has a little mass: it accelerates to a walk or a run
## instead of snapping there, and coasts to a stop once the stick is released.
const ON_FOOT_ACCEL := 24.0
const ON_FOOT_FRICTION := 30.0
const AIR_CONTROL := 6.0
## A jump asked for just after stepping off a ledge, or just before landing,
## still counts.  Both windows are short enough that a jump never fires by
## itself, and long enough that a thumb landing one frame late still gets it.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
## Letting go of jump early clips the rise to this fraction of the launch
## speed, so a tap is a hop and a hold is the full jump.
const JUMP_CUT := 0.45
## Jump-cut never applies to a rise faster than the launch itself.
const JUMP_RISE_EPSILON := 0.01
## How fast the body swings round to face the direction it is walking, in
## radians per second.  Fast enough to read as a turn rather than a slide, slow
## enough that reversing does not snap the model round.
const BODY_TURN_SPEED := 12.0

## The selectable body.  Both shipped characters are retargeted to the same
## humanoid skeleton; the profile carries the per-model saddle and hand fit.
@export var character_profile: PlayerModelProfile
@export var character_profiles: Array[PlayerModelProfile] = []

## Distance from the Hips bone to the point that contacts the saddle.  The
## horse's RiderSeat marker sits on the back surface, so the rider's hips are
## this far above it when seated.  Copied from the active profile.
@export var hips_to_seat := 0.10
@export var hand_anchor_offset := Vector3.ZERO

## Locomotion state -> clip inside the humanoid library.  The library's tracks
## are rebased onto the active skeleton in _rebind_animation_paths(), so the
## same clips play on either character rig.
const STATE_TO_CLIP := {
	"idle": "Idle",
	"walk": "Walk",
	"run": "Sprint",
	"air": "Jump",
	"land": "Jump_Land",
}

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_cast: ShapeCast3D = $CameraPivot/CameraCast
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var model: Node3D = $Model
@onready var seat_contact: Marker3D = $SeatContact
@onready var ride_pose: Node = $RidePose

var mounted := false
## True while the player is on foot holding the horse's lead rope.
var leading := false
## True while the player is sitting on a seat or lying on a bed.  The body is
## parked on the spot, collision and model are off, and the camera looks out
## from eye_height along the spot's facing.
var seated := false

var _step_timer := 0.0
var _land_timer := 0.0
var _current_anim_state := ""
var _skeleton: Skeleton3D = null
var _hips_bone := -1
var _model_base_yaw := 0.0
## World yaw the visible body faces.  The root carries the view yaw and the
## camera hangs off it, so the body keeps its own facing: walking sideways or
## backwards turns the character instead of sliding him across the ground.
var _body_yaw := 0.0
## Mounted look state.  The root follows the horse's yaw; these are the only
## things the rider's thumb steers.
var _look_offset_yaw := 0.0
var _look_pitch := MOUNTED_PITCH_NEUTRAL
var _look_idle := LOOK_RECENTRE_DELAY
## Eased 0..1 weight for the canter pose, so the boom opens with the gait.
var _ride_canter_weight := 0.0
## The scene's own lens at the walking camera pose; the canter opens from here.
var _fov_base := 75.0
var _camera_pivot_base := Vector3.ZERO
var _camera_base := Vector3.ZERO
var _camera_max_boom := 3.0
var _camera_shoulder := 0.0
var _boom_length := 3.0
var _camera_slide := 0.0
var _jump_blend := 0.0
var _was_on_floor := true
var _coyote := 0.0
var _jump_buffer := 0.0
## Yaw captured when the touch stick was last pushed.  While the thumb holds a
## direction the frame stays put, so the right thumb can look around without
## re-aiming the walk or the horse.
var _steer_frame_yaw := 0.0
var _stick_steering := false
## Set by the grooming session, which owns the body's visibility for the length
## of a visit; the camera rule below must not turn it back on.
var model_hidden := false


func _ready() -> void:
	add_to_group("player")
	add_to_group("touch_context")
	# The horse sits before the player in main.tscn, but make the order explicit:
	# the player's seat alignment must read the horse's pose after the horse has
	# moved and updated its saddle socket.
	process_physics_priority = 10
	TouchControls.set_mode("ride")
	_capture_mouse()
	# The window may not have focus yet when _ready runs after a scene change;
	# re-assert the capture once the new scene has drawn its first frame.
	call_deferred("_capture_mouse")
	footsteps.volume_db = -8.0
	if camera_cast != null:
		camera_cast.add_exception(self)
	_fov_base = camera.fov
	_camera_pivot_base = camera_pivot.position
	_camera_base = camera.position
	_apply_camera_profile()
	_boom_length = _camera_base.length()
	_apply_pending_spawn()
	_body_yaw = rotation.y
	_select_requested_profile()
	_apply_character_profile()
	_resolve_rig()
	if ride_pose != null:
		ride_pose.rebuild_for_skeleton(_skeleton)
	_play_state("idle", true)
	if GameState.consume_auto_mount():
		_begin_mounted_start.call_deferred()


## The farmhouse (and any future interior) marks its root with camera metadata:
## a shorter boom, a slightly higher pivot and a small shoulder offset.  The
## yard and arena keep the familiar 3 m outdoor camera.
func _apply_camera_profile() -> void:
	# The farmhouse root carries the profile as metadata.  Groups added by the
	# builder are not saved into the packed scene, so walk up to the scene that
	# owns the player rather than trusting a group lookup.
	var interior := get_tree().get_first_node_in_group("interior")
	if interior == null:
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor.has_meta("camera_max_boom"):
				interior = ancestor
				break
			ancestor = ancestor.get_parent()
	if interior == null:
		_camera_max_boom = _camera_base.length()
		_camera_shoulder = 0.0
		return
	_camera_max_boom = float(interior.get_meta("camera_max_boom", 2.35))
	_camera_shoulder = float(interior.get_meta("camera_shoulder", 0.20))
	_camera_pivot_base.y = float(interior.get_meta("camera_pivot_height", 1.62))
	_camera_base = Vector3(_camera_shoulder, 0.0, _camera_max_boom)
	camera_pivot.position = _camera_pivot_base


## A scene door leaves a spawn behind before changing scenes.  Move there on
## the first frame the player exists in the new scene, before physics runs.
func _apply_pending_spawn() -> void:
	var spawn := GameState.consume_player_spawn()
	if spawn.is_empty():
		return
	global_position = spawn["position"]
	rotation.y = deg_to_rad(float(spawn["yaw_degrees"]))
	velocity = Vector3.ZERO


## Dev/testing hook: GROOM_CHARACTER=liv launches the scene with Liv.  The
## shipped default is the profile chosen on the character-select screen.  The
## environment override still wins so headless tools can target either body.
func _select_requested_profile() -> void:
	var requested := OS.get_environment("GROOM_CHARACTER").strip_edges().to_lower()
	if not requested.is_empty():
		for profile in character_profiles:
			if profile != null and profile.display_name.to_lower() == requested:
				character_profile = profile
				return
		push_warning("Player: no character profile named " + requested)
		return
	if GameState.selected_character != null:
		character_profile = GameState.selected_character


## Mounts straight from the character-select handoff.  The screen fades to
## black while the player steps beside the horse, settles onto the ground and
## takes the saddle, so the first visible frame is the mounted game.
func _begin_mounted_start() -> void:
	var horse := get_tree().get_first_node_in_group("horse") as Node3D
	if horse == null:
		controls_enabled = true
		_capture_mouse()
		return
	controls_enabled = false
	var side := horse.global_transform.basis.x.normalized()
	global_position = horse.global_position + side * 1.2 + Vector3.UP * 0.05
	velocity = Vector3.ZERO
	for _i in range(20):
		await get_tree().physics_frame
		if is_on_floor():
			break
	try_mount()
	if not mounted:
		await get_tree().physics_frame
		try_mount()
	controls_enabled = true
	# The long synchronous world load can leave the cursor visible, which makes
	# every mouse-motion event fall through the mouse-look gate below.
	_capture_mouse()


## Instances the profile's GLB in the Model slot, replacing whatever model the
## scene shipped with.  The slot keeps the name "Model" so AnimationPlayer's
## root_node and the rest of the scene stay valid.
func _apply_character_profile() -> void:
	var profile := character_profile
	if profile == null or profile.scene == null:
		return
	var replacement := profile.scene.instantiate() as Node3D
	if replacement == null:
		push_error("Player: character profile has no Node3D scene")
		return
	replacement.name = "Model"
	replacement.rotation.y = deg_to_rad(profile.model_yaw_degrees)
	replacement.scale = Vector3.ONE * profile.model_scale
	var previous := get_node_or_null("Model")
	var index := 0
	if previous != null:
		index = previous.get_index()
		remove_child(previous)
		previous.free()
	add_child(replacement)
	move_child(replacement, index)
	# A model GLB may bring its own AnimationPlayer (older Liv imports did).
	# The shared humanoid library is authoritative, so drop any embedded player
	# instead of leaving an idle duplicate that a later scene change could wake.
	for child in replacement.find_children("*", "AnimationPlayer", true, false):
		var embedded := child as AnimationPlayer
		embedded.stop()
		embedded.autoplay = ""
		if embedded.get_parent() != null:
			embedded.get_parent().remove_child(embedded)
		embedded.queue_free()
	model = replacement
	# The two rigs have different proportions, so the saddle/hand fit is data.
	hips_to_seat = profile.hips_to_seat
	hand_anchor_offset = profile.hand_anchor_offset


func _resolve_rig() -> void:
	_skeleton = null
	if model == null:
		model = get_node_or_null("Model") as Node3D
	if model != null:
		_skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	_hips_bone = -1
	if _skeleton != null:
		_hips_bone = _skeleton.find_bone("Hips")
	_model_base_yaw = model.rotation.y if model != null else 0.0
	_rebind_animation_paths()
	# The footprint emitter watches the same skeleton, so it has to re-resolve its
	# bones whenever a profile swaps the body (Chris 52 bones, Liv 65).
	var footprints := get_node_or_null("Footprints")
	if footprints != null and footprints.has_method("rebind"):
		footprints.call("rebind")


## The shared humanoid library addresses %GeneralSkeleton.  Unique-name
## binding is scoped to the GLB subscene, not the player scene, so rebase each
## track onto the skeleton's real relative path.  This is what lets Chris's
## Armature/GeneralSkeleton and Liv's Node/GeneralSkeleton share one library.
func _rebind_animation_paths() -> void:
	if anim_player == null or _skeleton == null or model == null:
		return
	if not HumanoidAnimation.rebind(anim_player, model, _skeleton):
		push_warning("Player: humanoid animation library not found")


## Swaps the visible body without restarting the scene.  Used by the character
## profiles, the debug cycle key and the headless model check.
func set_character(profile: PlayerModelProfile) -> void:
	if profile == null or profile.scene == null:
		return
	var was_mounted := mounted
	if ride_pose != null:
		ride_pose.deactivate()
	character_profile = profile
	_apply_character_profile()
	_resolve_rig()
	if ride_pose != null:
		ride_pose.rebuild_for_skeleton(_skeleton)
	if was_mounted:
		if ride_pose != null:
			ride_pose.activate()
		var horse := get_tree().get_first_node_in_group("horse") as Node3D
		if horse != null:
			_align_to_seat(horse)
	else:
		_current_anim_state = ""
		_play_state("idle", true)


func _cycle_character() -> void:
	if character_profiles.size() < 2:
		return
	var index := character_profiles.find(character_profile)
	set_character(character_profiles[(index + 1) % character_profiles.size()])


func _process(delta: float) -> void:
	_track_steer_frame()
	_refresh_aim_prompt()
	if (controls_enabled or seated) and TouchControls.is_active():
		var look_delta := TouchControls.consume_look()
		if look_delta != Vector2.ZERO:
			_look(look_delta)
	# The seated camera is set by sit_at(); the blend below must not pull it back.
	if seated:
		return
	var pivot_target := _camera_pivot_base
	var camera_target := _camera_base
	var jump_target := 0.0
	var horse: Node3D = null
	if mounted:
		horse = get_tree().get_first_node_in_group("horse") as Node3D
		pivot_target = RIDE_PIVOT
		camera_target = RIDE_CAMERA
		if character_profile != null:
			pivot_target = character_profile.ride_pivot
			camera_target = character_profile.ride_camera
		_update_mounted_look(delta, horse)
		var canter := _update_canter_weight(delta, horse)
		pivot_target += Vector3(0.0, RIDE_LIFT_CANTER * canter, 0.0)
		camera_target += Vector3(0.0, 0.0, RIDE_BOOM_CANTER * canter)
		if horse != null and horse.has_method("is_airborne") and horse.is_airborne():
			jump_target = 1.0
	var blend := 1.0 - exp(-6.0 * delta)
	camera_pivot.position = camera_pivot.position.lerp(pivot_target, blend)
	if mounted:
		# The same four-case solver as on foot, so a fence behind the horse pulls
		# the boom in instead of letting the lens sit in the rails.  The mounted
		# call passes its own floor and refuses the overhead look-down, which is
		# an indoor answer and would frame the rider from above at a fence.
		var resolved := _resolve_camera_position(camera_target, delta, MOUNTED_MIN_BOOM, false)
		camera.position = resolved
		_boom_length = resolved.length()
		# A tilt left over from an indoor mount would otherwise stay on the lens.
		camera.rotation.x = 0.0
		_update_mounted_fov(delta)
		if model != null:
			model.visible = true
	else:
		var resolved := _resolve_camera_position(camera_target, delta)
		camera.position = resolved
		_boom_length = resolved.length()
		_camera_slide = resolved.x - _camera_shoulder
		_update_camera_tilt(delta)
		_update_model_visibility()
	_jump_blend = move_toward(_jump_blend, jump_target, delta * 7.0)
	if mounted and ride_pose != null:
		var phase := 0.5 - 0.5 * cos(Time.get_ticks_msec() * 0.001 * TAU * RIDE_SWAY_HZ)
		ride_pose.apply(phase, _jump_blend)


## Points the root and the camera pivot for a rider.  The root follows the
## horse, the pivot carries the look offset, and the offset eases back to a rear
## view once the thumb has been still for LOOK_RECENTRE_DELAY.
func _update_mounted_look(delta: float, horse: Node3D) -> void:
	_look_idle += delta
	if horse != null:
		rotation.y = horse.global_rotation.y
	if _look_idle >= LOOK_RECENTRE_DELAY:
		_look_offset_yaw = move_toward(_look_offset_yaw, 0.0, LOOK_RECENTRE_RATE * delta)
		_look_pitch = move_toward(_look_pitch, MOUNTED_PITCH_NEUTRAL, LOOK_PITCH_RETURN_RATE * delta)
	camera_pivot.rotation.y = _look_offset_yaw
	camera_pivot.rotation.x = _look_pitch


## 0 at the walking frame, 1 at the canter frame, eased so the boom opens and
## closes with the gait instead of stepping with it.
func _update_canter_weight(delta: float, horse: Node3D) -> float:
	var speed := 0.0
	if horse != null:
		speed = Vector2(horse.velocity.x, horse.velocity.z).length()
	var target := clampf(
		(speed - RIDE_CANTER_START) / maxf(RIDE_CANTER_FULL - RIDE_CANTER_START, 0.001), 0.0, 1.0
	)
	_ride_canter_weight = move_toward(_ride_canter_weight, target, RIDE_POSE_RATE * delta)
	return _ride_canter_weight


func _update_mounted_fov(delta: float) -> void:
	var target := lerpf(_fov_base, CANTER_FOV, _ride_canter_weight)
	camera.fov = lerpf(camera.fov, target, 1.0 - exp(-FOV_RATE * delta))


## Mounting always starts from a rear view, whatever the rider was looking at
## on foot.  The look layer's gain goes to its mounted value here.
func _reset_mounted_look() -> void:
	_look_offset_yaw = 0.0
	_look_pitch = MOUNTED_PITCH_NEUTRAL
	_look_idle = LOOK_RECENTRE_DELAY
	camera_pivot.rotation.y = 0.0
	camera_pivot.rotation.x = _look_pitch
	TouchControls.set_mounted(true)


## Shows the prompt on whichever interactable the camera is aimed at.
var _aimed: Node = null


func _refresh_aim_prompt() -> void:
	var target := aim_target()
	if _aimed != null and is_instance_valid(_aimed) and _aimed != target:
		_aimed.call("show_prompt", false)
	_aimed = target
	if target != null:
		target.call("show_prompt", true)


## The interactable under the crosshair, or null.  Uses the camera's centre
## ray so doors, furniture and the dog's bowl answer where the player looks.
func aim_target() -> Node:
	if mounted or seated or not controls_enabled:
		return null
	var origin := camera.global_position
	var end := origin - camera.global_transform.basis.z * INTERACT_REACH
	var query := PhysicsRayQueryParameters3D.create(origin, end, CAMERA_CLIP_MASK)
	var excluded: Array[RID] = [get_rid()]
	query.exclude = excluded
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var node: Node = hit["collider"]
		while node != null:
			if node.is_in_group("interactable"):
				return node
			node = node.get_parent()
	return _nearby_interactable()


## Fallback when the camera ray misses: an interactable within its own
## body_reach of the player, and roughly in the direction the view faces (the
## root yaw, not the body's), so a low target such as a bowl works without
## aiming the camera down.
func _nearby_interactable() -> Node:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return null
	forward = forward.normalized()
	var best: Node = null
	var best_facing := -INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var item := node as Node3D
		if item == null or not item.has_method("use"):
			continue
		var reach_value: Variant = item.get("body_reach")
		if reach_value == null:
			continue
		var reach: float = float(reach_value)
		if reach <= 0.0:
			continue
		var to_item := item.global_position - global_position
		to_item.y = 0.0
		var distance := to_item.length()
		if distance > reach or distance < 0.001:
			continue
		var facing := forward.dot(to_item / distance)
		if facing < 0.5:
			continue
		# Prefer the target the player is most squarely facing, not the nearest:
		# two doors can be inside reach at once, and the one in view should win.
		if facing > best_facing:
			best_facing = facing
			best = item
	return best


## A line can be clear at full length and still be unreachable from a camera
## on another line: the short arc between them crosses a door jamb.  Test the
## candidate at the current boom rather than trusting its full length.
func _line_reachable(candidate: Vector3) -> bool:
	if candidate.length() < 0.01 or camera.position.length() < 0.01:
		return true
	var radius := minf(maxf(camera.position.length(), CAMERA_SWING_RADIUS), candidate.length())
	var swing := candidate.normalized() * radius
	return _cast_safe_distance(swing) > radius - 0.05


## Resolves the on-foot camera position in four steps.
##  1. The direct shoulder line.
##  2. A lateral line, for a chair or desk the player has just backed into.
##     The line must keep the player inside 35 degrees of the view.
##  3. A look-down from above the head, for a wall corner with no usable rear
##     line.  It is offered only while the normal boom is below 0.90 m.
##  4. If the chosen line is around a blocker, step onto it at a usable radius
##     before easing out.  A plain ease would stay pinned at the head because
##     the straight path to the side crosses the very blocker being avoided.
## The final path is cast again, so a wall cannot be crossed between lines.
func _resolve_camera_position(
	target: Vector3, delta: float, floor: float = CAMERA_MIN_BOOM, allow_overhead: bool = true
) -> Vector3:
	var length := target.length()
	if length < 0.01 or camera_cast == null:
		return target
	var direct_safe := _cast_safe_distance(target)
	var desired := target.normalized() * maxf(direct_safe, floor)
	var best_score := maxf(direct_safe, floor)
	var overhead_position := Vector3.ZERO
	var overhead_length := 0.0
	var current_safe := _cast_safe_distance(camera.position) if camera.position.length() > 0.01 else 0.0
	var current_blocked := camera.position.length() > 0.01 and current_safe < camera.position.length() - 0.05
	# Only rescue a camera that has already fallen into the first-person clamp.
	# Rooms and corners that still have a third-person line keep their previous
	# lateral and overhead choices.
	var recovering := current_blocked and current_safe < CAMERA_OVERHEAD_TRIGGER
	if direct_safe < length - 0.05:
		for offset in CAMERA_SLIDE_OFFSETS:
			if is_zero_approx(offset):
				continue
			var candidate := target + Vector3(offset, 0.0, 0.0)
			var safe := _cast_safe_distance(candidate)
			var position := candidate.normalized() * maxf(safe, floor)
			if position.z < 0.15 or atan2(absf(position.x), position.z) > CAMERA_SLIDE_MAX_ANGLE:
				continue
			# A lateral line that is only clear further out cannot be reached
			# from a camera already on the other side of a door jamb.  Keep the
			# direct line rather than chasing it inward.  The overhead search
			# stays available for corners that genuinely have no rear line.
			if recovering and not _line_reachable(position):
				continue
			var score := position.length() - absf(offset) * CAMERA_SLIDE_COST
			if score > best_score + 0.001:
				best_score = score
				desired = position
		# No rear or side line keeps the body in view: look down from above
		# the head instead of pulling into it.  Either side of the head is
		# offered because a corner usually blocks one of them.
		for lift in CAMERA_OVERHEAD_LIFTS:
			for side in CAMERA_OVERHEAD_OFFSETS:
				var overhead := Vector3(side, lift, 0.0)
				var overhead_safe := _cast_safe_distance(overhead)
				var position := overhead.normalized() * maxf(overhead_safe, floor)
				if position.length() > overhead_length and (not recovering or _line_reachable(position)):
					overhead_length = position.length()
					overhead_position = position
		if allow_overhead and best_score < CAMERA_OVERHEAD_TRIGGER and overhead_length > best_score + 0.05:
			desired = overhead_position
	var proposed := camera.position.move_toward(desired, CAMERA_RETURN_SPEED * delta)
	if desired.length() > 0.01 and camera.position.length() > 0.01:
		var around := camera.position.angle_to(desired)
		# A blocked current point has to move even when the angle to the next
		# line is small: the straight ease between the two is inside the jamb.
		# This is what closes the study doorway without moving any room that
		# still has a third-person line.
		if around > CAMERA_SWING_ANGLE or current_blocked:
			var swing_length := minf(maxf(camera.position.length(), CAMERA_SWING_RADIUS), desired.length())
			var swing := desired.normalized() * swing_length
			if _cast_safe_distance(swing) > swing_length - 0.05:
				proposed = swing
	if proposed.length() < 0.01:
		proposed = desired.normalized() * floor if desired.length() > 0.01 else Vector3(0.0, 0.0, floor)
	var safe := _cast_safe_distance(proposed)
	# The floor is a floor on the result, not only a clamp when shortening;
	# otherwise the ease can keep walking the camera below it frame by frame.
	# Mounted it is MOUNTED_MIN_BOOM, which is what keeps the rider in frame.
	var final_length := maxf(minf(proposed.length(), safe), floor)
	return proposed.normalized() * final_length


## Distance along `local_target` at which the camera sphere stops.  The cast is
## a child of the pivot, so the target is in pivot space.
func _cast_safe_distance(local_target: Vector3) -> float:
	var length := local_target.length()
	if length < 0.01:
		return length
	camera_cast.target_position = local_target
	camera_cast.force_shapecast_update()
	if not camera_cast.is_colliding():
		return length
	var fraction := clampf(camera_cast.get_closest_collision_safe_fraction(), 0.0, 1.0)
	return maxf(0.0, length * fraction - CAMERA_CLIP_MARGIN)


## The high fallback looks down over the player rather than along the level
## boom.  The amount follows the camera's height and how little rear room it
## has, so the tilt eases in and out with the position instead of snapping
## when a candidate changes.
func _update_camera_tilt(delta: float) -> void:
	var height := clampf((camera.position.y - 0.10) / CAMERA_OVERHEAD_LIFTS[-1], 0.0, 1.0)
	var no_rear := 1.0 - clampf(camera.position.z / 0.80, 0.0, 1.0)
	var tilt := -CAMERA_OVERHEAD_TILT * height * no_rear
	var blend := 1.0 - exp(-CAMERA_OVERHEAD_BLEND_SPEED * delta)
	camera.rotation.x = lerp_angle(camera.rotation.x, tilt, blend)


## Hides the body and stops the camera rule from turning it back on.  The
## grooming session calls this for the length of a visit; it restores the
## previous visibility itself when the session ends.
func set_model_hidden(hidden: bool) -> void:
	model_hidden = hidden
	if hidden and model != null:
		model.visible = false


## Yaw the movement input is mapped through.  Keyboard and mouse keep the old
## behaviour (the camera is the frame); a pushed touch stick freezes the frame
## it was pushed in, so looking around no longer re-aims the character or the
## horse, which is what used to feel like spinning.
func steer_yaw() -> float:
	return _steer_frame_yaw if _stick_steering else rotation.y


## True while the frozen touch frame owns steering.  Tests and diagnostics.
func is_steering_with_stick() -> bool:
	return _stick_steering


func _track_steer_frame() -> void:
	var pushing := TouchControls.is_stick_pushing()
	if pushing and not _stick_steering:
		_steer_frame_yaw = rotation.y
	_stick_steering = pushing


## The body turns to face where it is walking while the root keeps the view
## yaw, so orbiting the camera no longer drags the character round with it and
## a sideways walk is a turn rather than a strafe.  Standing still leaves the
## body facing where it stopped.
func _turn_body(dir: Vector3, delta: float) -> void:
	if model == null:
		return
	if controls_enabled and dir.length_squared() > 0.0001:
		var want := atan2(-dir.x, -dir.z)
		_body_yaw = lerp_angle(_body_yaw, want, clampf(BODY_TURN_SPEED * delta, 0.0, 1.0))
	model.rotation.y = _model_base_yaw + wrapf(_body_yaw - rotation.y, -PI, PI)


## World yaw the visible body faces.  Prints and anything else that has to line
## up with the body read this, not the root, which carries the view.
func facing_yaw() -> float:
	return _body_yaw


## Only a true first-person clamp hides the body.  The lateral and overhead
## answers above keep the camera far enough out that the body stays in frame;
## a look-down sits above the head even when its distance is short, so height
## is checked as well as the boom.
func _update_model_visibility() -> void:
	if model == null or model_hidden:
		return
	if camera.position.y > 0.30:
		model.visible = true
		return
	model.visible = _boom_length > CAMERA_MODEL_HIDE_BOOM


## Current boom length, for the farmhouse camera checks.
func camera_boom_length() -> float:
	return _boom_length


## Sideways offset from the normal shoulder line, for the walkthrough.  Zero
## means the camera is on the direct line; positive means it slid right.
func camera_slide_length() -> float:
	return _camera_slide


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled and not seated:
		return
	if event.is_action_pressed("interact") and not mounted and not seated:
		var target := aim_target()
		if target != null and target.has_method("use") and target.use():
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Clicking the game window after a focus change should take the mouse
		# back; otherwise the camera is dead even though WASD still works.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_capture_mouse()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact"):
		if mounted:
			dismount()
		else:
			try_mount()
	elif event.is_action_pressed("lead"):
		_toggle_lead()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2 and OS.is_debug_build():
		_cycle_character()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN and controls_enabled:
		_capture_mouse()


func _capture_mouse() -> void:
	# A touch screen needs the pointer to stay visible; capturing it would hide
	# the emulated taps the HUD buttons rely on.
	if Device.is_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(relative: Vector2) -> void:
	if mounted:
		# Mounted, a drag is a camera offset from the horse, never a heading.
		_look_offset_yaw = wrapf(_look_offset_yaw - relative.x * mouse_sensitivity, -PI, PI)
		_look_pitch = clampf(
			_look_pitch - relative.y * mouse_sensitivity, MOUNTED_PITCH_MIN, MOUNTED_PITCH_MAX
		)
		_look_idle = 0.0
		return
	rotate_y(-relative.x * mouse_sensitivity)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x - relative.y * mouse_sensitivity, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX
	)


## Takes or drops the lead rope.  Mounting and leading are exclusive: taking
## the saddle releases the rope, and the rope can only be picked up on foot.
func _toggle_lead() -> void:
	if mounted:
		return
	var horse := get_tree().get_first_node_in_group("horse") as Node3D
	if horse == null:
		return
	if leading:
		if horse.has_method("clear_leader"):
			horse.clear_leader()
		leading = false
		return
	if horse.has_method("set_leader") and horse.has_method("can_lead") and horse.can_lead(self):
		horse.set_leader(self)
		leading = horse.get("leader") == self


## What the touch CONTEXT button does while the player is in the saddle.  The
## horse offers MOUNT on foot; this offers DISMOUNT.
func touch_context() -> Dictionary:
	if mounted:
		return {"action": "interact", "label": "DISMOUNT", "priority": 1}
	return {}


## Sits the player on a spot.  The body itself is not moved: the seat's
## transform is used for the eye, which keeps the seat script in charge of
## whether the spot is a chair, a sofa or a bed.
func sit_at(seat: Transform3D, eye_height: float, pitch_degrees: float) -> void:
	if seated or mounted:
		return
	seated = true
	controls_enabled = false
	velocity = Vector3.ZERO
	$Collision.set_deferred("disabled", true)
	footsteps.stop()
	if model != null:
		model.visible = false
	# The body follows the seat so the camera pivot can stay a child of it.
	global_position = seat.origin
	rotation.y = seat.basis.get_euler().y
	camera_pivot.position = Vector3(0.0, eye_height, 0.0)
	camera_pivot.rotation.x = deg_to_rad(pitch_degrees)
	camera.position = Vector3.ZERO
	camera.rotation.x = 0.0


## Stands the player back up at `where`, keeping the seat's facing.
func stand_up(where: Vector3, yaw: float) -> void:
	if not seated:
		return
	seated = false
	global_position = where
	rotation.y = yaw
	_body_yaw = yaw
	camera_pivot.position = _camera_pivot_base
	camera.position = _camera_base
	_boom_length = _camera_base.length()
	camera.rotation.x = 0.0
	camera_pivot.rotation.x = 0.0
	camera_pivot.rotation.y = 0.0
	if model != null:
		model.visible = true
	$Collision.set_deferred("disabled", false)
	controls_enabled = true
	velocity = Vector3.ZERO


func try_mount() -> void:
	if not is_on_floor():
		return
	var horse := get_tree().get_first_node_in_group("horse") as Node3D
	if horse == null or not horse.has_method("can_mount") or not horse.can_mount(self):
		return
	if horse.has_method("clear_leader"):
		horse.clear_leader()
	leading = false
	mounted = true
	horse.set_rider(self)
	$Collision.disabled = true
	velocity = Vector3.ZERO
	footsteps.stop()
	# The boom is cast from the saddle, so the horse's own body would otherwise
	# block it and pull the lens into the rider.
	if camera_cast != null:
		var mounted_body := horse as CollisionObject3D
		if mounted_body != null:
			camera_cast.add_exception(mounted_body)
	_reset_mounted_look()
	# Stop the locomotion mixer so it cannot overwrite the riding overlay.
	anim_player.stop()
	_current_anim_state = "ride"
	_jump_blend = 0.0
	if ride_pose != null:
		ride_pose.activate()
	_align_to_seat(horse)


func dismount() -> void:
	var horse := get_tree().get_first_node_in_group("horse") as Node3D
	mounted = false
	_jump_blend = 0.0
	_look_offset_yaw = 0.0
	_look_pitch = MOUNTED_PITCH_NEUTRAL
	_look_idle = LOOK_RECENTRE_DELAY
	_ride_canter_weight = 0.0
	camera_pivot.rotation.y = 0.0
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	camera.fov = _fov_base
	TouchControls.set_mounted(false)
	if horse:
		horse.clear_rider()
		if camera_cast != null:
			var mounted_body := horse as CollisionObject3D
			if mounted_body != null:
				camera_cast.remove_exception(mounted_body)
		# Step off on the horse's left side, then find the ground below that
		# point so the player does not get left floating or inside the horse.
		var side := -horse.global_transform.basis.x.normalized()
		var start := horse.global_position + side * 1.6 + Vector3.UP * 3.0
		var query := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * 8.0)
		var excluded: Array[RID] = [get_rid()]
		var horse_body := horse as CollisionObject3D
		if horse_body != null:
			excluded.append(horse_body.get_rid())
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var landing := start
		if not hit.is_empty():
			landing = hit["position"] + Vector3.UP * 0.05
		else:
			landing.y = horse.global_position.y
		global_position = landing
	model.rotation.y = _model_base_yaw
	_body_yaw = rotation.y
	if ride_pose != null:
		ride_pose.deactivate()
	$Collision.disabled = false
	velocity = Vector3.ZERO
	_land_timer = 0.0
	_current_anim_state = ""
	_play_state("idle", true)
	_was_on_floor = true


## World-space fist position used by the reins.  The humanoid library names the
## hand bones LeftHand/RightHand; fall back to a point beside the saddle if the
## retargeted rig ever changes.
func get_hand_anchor(side: String) -> Vector3:
	if _skeleton == null:
		return global_position + Vector3(0, 1.7, 0)
	var idx := _skeleton.find_bone(side + "Hand")
	if idx < 0:
		idx = _skeleton.find_bone("Hand" + side)
	if idx < 0:
		return global_position + Vector3(0, 1.7, 0)
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)
	return hand * Vector3(0.0, 0.05, 0.0) + hand_anchor_offset


func _align_to_seat(horse: Node3D) -> void:
	if _skeleton == null or _hips_bone < 0:
		if horse.has_method("get_rider_seat_position"):
			global_position = horse.get_rider_seat_position()
		return
	# The visible rider faces the horse, while the player root follows it while
	# mounted.  Rotate first, then align the pelvis.
	model.rotation.y = _model_base_yaw + wrapf(horse.global_rotation.y - rotation.y, -PI, PI)
	var hips_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hips_bone).origin
	var contact := hips_world - Vector3.UP * hips_to_seat
	seat_contact.global_position = contact
	global_position += horse.get_rider_seat_position() - contact


func _physics_process(delta: float) -> void:
	if seated:
		velocity = Vector3.ZERO
		return
	if mounted:
		# Position is driven by the horse while riding.  Align the pelvis to
		# the saddle, not the feet, so the rider sits instead of standing on
		# the horse's back.
		var horse := get_tree().get_first_node_in_group("horse") as Node3D
		if horse:
			_align_to_seat(horse)
		footsteps.stop()
		velocity = Vector3.ZERO
		return

	# The rope can be taken away by the stable (stabling) or by a grooming
	# session, so stop leading the moment the horse lets go.
	if leading:
		var led_horse := get_tree().get_first_node_in_group("horse") as Node3D
		if led_horse == null or led_horse.get("leader") == null:
			leading = false

	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		_land_timer = landing_time
	# Coyote time and a jump buffer.  Both count down every frame whichever way
	# the body is going, so the window is measured in seconds, not frames.
	_coyote = COYOTE_TIME if grounded else maxf(_coyote - delta, 0.0)
	if controls_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_land_timer = 0.0
		_jump_buffer = 0.0
		_coyote = 0.0
	elif grounded:
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	# Jump cut: releasing early clips the rise.  Only an upward velocity is cut,
	# so falling is never softened by letting go.
	if not grounded and velocity.y > JUMP_RISE_EPSILON and not Input.is_action_pressed("jump"):
		velocity.y = minf(velocity.y, jump_velocity * JUMP_CUT)

	var input := Vector2.ZERO
	if controls_enabled:
		input = TouchControls.get_move_input()
	# Camera-relative movement.  Godot's forward is -Z and Input.get_vector puts
	# forward on the negative Y axis, so the raw (x, 0, y) already points where
	# the player wants to go; only the frame comes from the steering yaw.  A yaw
	# basis also keeps the camera's pitch out of the walk, so nothing needs
	# flattening.  Never multiply a forward vector by input.y here: that negates
	# the convention the input already carries and swaps W and S.
	var dir := Basis(Vector3.UP, steer_yaw()) * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	_turn_body(dir, delta)
	var running := controls_enabled and Input.is_action_pressed("run")
	# A light touch on the stick walks slower; keys and full pushes are unchanged.
	var speed := (run_speed if running else walk_speed) * clampf(input.length(), 0.0, 1.0)
	if grounded:
		# The heading turns with the input at once and the speed ramps after it,
		# rather than accelerating the whole velocity vector.  Starting and
		# stopping have weight; momentum never carries the body sideways into a
		# doorway while the direction catches up.  A reversal starts from rest,
		# so backing out of a corner is a plant and turn, not a slide.
		if dir.length_squared() < 0.0001:
			var coast := Vector2(velocity.x, velocity.z).move_toward(
				Vector2.ZERO, ON_FOOT_FRICTION * delta
			)
			velocity.x = coast.x
			velocity.z = coast.y
		else:
			var along := maxf(Vector2(velocity.x, velocity.z).dot(Vector2(dir.x, dir.z)), 0.0)
			var next := move_toward(along, speed, ON_FOOT_ACCEL * delta)
			velocity.x = dir.x * next
			velocity.z = dir.z * next
	else:
		# Airborne the body keeps the momentum it left the ground with and only
		# steers a little, so a jump cannot be redirected in mid-air.
		velocity.x = move_toward(velocity.x, dir.x * speed, AIR_CONTROL * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, AIR_CONTROL * delta)
	move_and_slide()

	_land_timer = maxf(0.0, _land_timer - delta)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_locomotion(planar_speed, running)

	_update_footsteps(delta, input.length() > 0.1 and is_on_floor(), running)
	_was_on_floor = is_on_floor()


func _update_footsteps(delta: float, moving: bool, running: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return

	_step_timer -= delta
	if _step_timer > 0.0:
		return

	_step_timer = step_interval_run if running else step_interval_walk
	footsteps.stream = FOOTSTEP_SOUNDS[randi() % FOOTSTEP_SOUNDS.size()]
	footsteps.pitch_scale = randf_range(0.92, 1.08)
	footsteps.play()


func _update_locomotion(planar_speed: float, running: bool) -> void:
	if not is_on_floor():
		_play_state("air")
		return
	if _land_timer > 0.0:
		_play_state("land")
		return
	if planar_speed < 0.25:
		_play_state("idle")
	elif running or planar_speed > 4.5:
		_play_state("run")
	else:
		_play_state("walk")


func _play_state(state_name: String, force := false) -> void:
	if state_name == _current_anim_state and not force:
		return
	var clip: String = STATE_TO_CLIP.get(state_name, "")
	if clip.is_empty():
		return
	if anim_player == null or not anim_player.has_animation("humanoid/" + clip):
		return
	_current_anim_state = state_name
	anim_player.play("humanoid/" + clip, 0.15)
