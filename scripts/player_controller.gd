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
@export var mouse_sensitivity := 0.003
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
const RIDE_CAMERA := Vector3(0.0, 0.0, 4.2)

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
var _camera_pivot_base := Vector3.ZERO
var _camera_base := Vector3.ZERO
var _jump_blend := 0.0
var _was_on_floor := true


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
	_camera_pivot_base = camera_pivot.position
	_camera_base = camera.position
	_apply_pending_spawn()
	_select_requested_profile()
	_apply_character_profile()
	_resolve_rig()
	if ride_pose != null:
		ride_pose.rebuild_for_skeleton(_skeleton)
	_play_state("idle", true)
	if GameState.consume_auto_mount():
		_begin_mounted_start.call_deferred()


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
	if mounted:
		pivot_target = RIDE_PIVOT
		camera_target = RIDE_CAMERA
		if character_profile != null:
			pivot_target = character_profile.ride_pivot
			camera_target = character_profile.ride_camera
		var horse := get_tree().get_first_node_in_group("horse") as Node3D
		if horse != null and horse.has_method("is_airborne") and horse.is_airborne():
			jump_target = 1.0
	var blend := 1.0 - exp(-6.0 * delta)
	camera_pivot.position = camera_pivot.position.lerp(pivot_target, blend)
	camera.position = camera.position.lerp(camera_target, blend)
	_jump_blend = move_toward(_jump_blend, jump_target, delta * 7.0)
	if mounted and ride_pose != null:
		var phase := 0.5 - 0.5 * cos(Time.get_ticks_msec() * 0.001 * TAU * RIDE_SWAY_HZ)
		ride_pose.apply(phase, _jump_blend)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled and not seated:
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
	rotate_y(-relative.x * mouse_sensitivity)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x - relative.y * mouse_sensitivity, -1.2, 0.4
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


## Stands the player back up at `where`, keeping the seat's facing.
func stand_up(where: Vector3, yaw: float) -> void:
	if not seated:
		return
	seated = false
	global_position = where
	rotation.y = yaw
	camera_pivot.position = _camera_pivot_base
	camera.position = _camera_base
	camera_pivot.rotation.x = 0.0
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
	if horse:
		horse.clear_rider()
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
	# The visible rider faces the horse, while the player root keeps the mouse
	# yaw that steers the horse.  Rotate first, then align the pelvis.
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

	if is_on_floor():
		if not _was_on_floor:
			_land_timer = landing_time
		velocity.y = 0.0
		if controls_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			_land_timer = 0.0
	else:
		velocity.y -= gravity * delta

	var input := Vector2.ZERO
	if controls_enabled:
		input = TouchControls.get_move_input()
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	var running := controls_enabled and Input.is_action_pressed("run")
	# A light touch on the stick walks slower; keys and full pushes are unchanged.
	var speed := (run_speed if running else walk_speed) * clampf(input.length(), 0.0, 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
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
