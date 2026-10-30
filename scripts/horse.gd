extends CharacterBody3D

signal landed
signal jumped
signal training_awarded(new_skill: float, new_fitness: float)

## Stick movement below this is a resting thumb, not a throttle: the steering
## axes are renormalised past it so a small push is still a slow walk.
const STEER_DEADZONE := 0.15

## Gait speeds matched to the clip library's own measured ground speed, so the
## hooves stay planted instead of sliding: Walk/Trot/Run cruise at 1.74/1.95/4.98 m/s.
@export var walk_speed := 1.74
@export var trot_speed := 1.95
@export var canter_speed := 4.98
@export var turn_speed := 4.0
@export var gravity := 20.0
@export var mount_range := 2.2

@export_group("Riding")
## How long the rider has to hold run before the horse moves up from trot to
## canter.  Walk is the default gait, run alone reaches trot, and holding run
## for this long asks for the canter.
@export var gait_hold_time := 0.9
@export var acceleration := 4.5
@export var deceleration := 7.0
## Dismounting is a short, firm settle rather than a long coast through trot
## and walk: the horse is stopped over this time and then forced into Idle.
@export var dismount_settle_time := 0.2
@export var dismount_deceleration := 24.0
## Ridden turning is a yaw rate in radians per second, not a lerp factor, so
## the turn has weight: a canter turns in a wide arc instead of pivoting on the
## spot.  The stick's left/right axis asks for this rate; the camera never does.
@export var ridden_turn_rate_walk := 2.6
@export var ridden_turn_rate_canter := 1.5
@export var ridden_turn_rate_in_place := 1.3

@export_group("Leading")
## How far the handler can be from the horse when the lead is taken.
@export var lead_range := 3.4
## Where the horse's body centre sits relative to the handler while led:
## slightly to their right (+X) and behind them (+Z, since forward is -Z).
@export var lead_offset := Vector3(0.95, 0.0, 1.15)
## Inside this distance the horse stops and settles beside the handler.
@export var lead_stop_distance := 0.45
@export var lead_acceleration := 6.0

@export_group("Jumping")
@export var jump_velocity := 9.0
@export var jump_training_bonus := 0.15
@export var max_jumping_skill := 10.0

@export_group("Training")
var jumping_skill := 1.0
var fitness := 1.0

@export_group("Needs")
## Daily needs, 1.0 = content.  Hunger takes a little over an hour of play to
## empty, so a session ends with a horse that still looks cared for and a
## skipped day is noticeable rather than punishing.  Nothing here is a fail
## state: the horse keeps working at zero, and health only drifts.
var hunger := 1.0
var energy := 1.0
var health := 1.0
@export var hunger_per_minute := 0.011
@export var energy_rest_per_minute := 0.05
@export var energy_ride_per_minute := 0.04
@export var health_per_minute := 0.02
## How much of the bowl one bale fills.  Two bales take a hungry horse to full.
@export var hay_feed_gain := 0.5
## Seconds between need values being mirrored into `HorseState`.
@export var needs_report_seconds := 1.0
var _needs_report := 0.0

@export_group("Stable")
## How soiled the bed is, 0.0 fresh to 1.0 a full muck-out.  It soils on the
## clock the player is playing on - a little while the horse is in the world at
## all, and faster while it is standing about the yard rather than being ridden,
## because a horse spends that time in or beside its stall.  A boarded horse is
## frozen by `board()` and does not tick, so its bed stops soiling while it is
## put away.
var stall_muck := 0.0
@export var stall_muck_per_minute := 0.02
@export var stall_muck_standing_per_minute := 0.06
## True while the muck session owns the player.  The bed does not soil during
## the chore: the session is removing exactly what is in it, and a rate running
## underneath would fight the scoop.
var mucking := false

## Saddle socket. The marker is placed on the back surface in the scene and
## this script makes it follow the animated spine so the rider rises and
## pitches with the gait instead of hovering at a fixed height.
const SEAT_BONE := "spine_3"
const SEAT_BONE_FALLBACK := "spine_2"
const HEAD_BONE := "head"
## Rest_Pose is the asset's square, symmetric standing frame.  Idle is only a
## fallback: its camped stance (one fore and one hind foot forward) reads as a
## mid-step pose and makes the horse look awkward while it is groomed.
const GROOM_POSE := "Rest_Pose"
const GROOM_POSE_FALLBACK := "Idle"

@onready var rider_seat: Marker3D = $RiderSeat
@onready var model: Node3D = $Model
@onready var collision: CollisionShape3D = $Collision
@onready var gallop: AudioStreamPlayer3D = $Gallop
@onready var neigh: AudioStreamPlayer3D = $Neigh
@onready var fsm: Node = $AnimStateMachine
@onready var mount_prompt: Label3D = $MountPrompt
@onready var jump_pose: Node = $JumpPose
@onready var tack: Node3D = $Tack
@onready var saddle: Node3D = $Tack/Saddle
@onready var bridle: Node3D = $Tack/Bridle
@onready var groom_surface: Node = $GroomSurface

var rider: Node3D = null
## The player holding the lead rope while both are on foot.  A led horse walks
## to a point beside the handler instead of being ridden.
var leader: Node3D = null
var airborne := false
var air_phase := 0.0
## A boarded horse is stabled: hidden, inert and not mountable until the
## player fetches it from the stable door.
var boarded := false
## Stations such as the stable own the E prompt while the player stands at
## their anchor, so the horse's own mount prompt stays out of the way.
var mount_prompt_suppressed := false

## Care state.  These live on the horse so the coat changes survive leaving
## the grooming bay; they reset only when the run is reloaded.
var grooming := false
var cleanliness := 0.0
var grooming_polish := 0.0
var hooves_cleaned := 0
## Best care score already rewarded, so brushing the same clean patch over and
## over cannot farm trust.  Only new progress pays out.
var care_reward_score := 0.0
var groomed_hooves := [false, false, false, false]
var trust := 0.0
var happiness := 0.5

var _skeleton: Skeleton3D = null
var _seat_bone := -1
var _seat_offset := Transform3D.IDENTITY
var _head_bone := -1
var _spine_rest := Transform3D.IDENTITY
var _head_rest := Transform3D.IDENTITY
var _saddle_rest := Transform3D.IDENTITY
var _bridle_rest := Transform3D.IDENTITY
var _seat_in_saddle := Transform3D.IDENTITY
var _ride_speed := 0.0
var _gait_hold := 0.0
var _air_time := 0.0
var _jump_air_time := 0.8
var _settle_time := 0.0
var groom_pose_clip := GROOM_POSE


func _ready() -> void:
	add_to_group("horse")
	add_to_group("touch_context")
	# Duplicate so the loop flag does not mutate the imported resource.
	if gallop.stream:
		gallop.stream = gallop.stream.duplicate()
		gallop.stream.loop = true
	gallop.volume_db = -6.0
	neigh.volume_db = -4.0
	_setup_seat()
	_setup_tack()
	# Once the GLB ships a real Jump clip, the FSM owns the airborne pose and
	# this overlay stands down.
	if jump_pose != null and fsm != null and fsm.has_air_clip():
		jump_pose.active = false
	# The horse is a scene node and every door is a full scene change, so this
	# spawn starts from the progress the player actually earned rather than from
	# the defaults above.
	HorseState.apply_to(self)
	_restore_rosette()


func _process(delta: float) -> void:
	if mount_prompt != null:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var can_mount_now := player != null and can_mount(player)
		var can_lead_now := player != null and can_lead(player)
		var release_now := leader != null and player != null
		mount_prompt.visible = rider == null and not mount_prompt_suppressed and (can_mount_now or can_lead_now or release_now)
		if leader != null:
			mount_prompt.text = Device.pick("E  MOUNT\nF  RELEASE", "TAP  MOUNT\nLEAD  RELEASE")
		elif can_mount_now and can_lead_now:
			mount_prompt.text = Device.pick("E  MOUNT\nF  LEAD", "TAP  MOUNT\nLEAD  TAKE ROPE")
		elif can_lead_now:
			mount_prompt.text = Device.pick("F  LEAD", "LEAD")
		else:
			mount_prompt.text = Device.pick("E  MOUNT", "TAP  MOUNT")
	# The jump pose must be written after the AnimationPlayer has posed the
	# skeleton, so it runs here rather than in physics.
	if jump_pose != null:
		jump_pose.apply(air_phase, airborne)


func _setup_seat() -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Horse: no Skeleton3D found; RiderSeat stays static")
		return
	_skeleton = skeletons[0] as Skeleton3D
	_seat_bone = _skeleton.find_bone(SEAT_BONE)
	if _seat_bone < 0:
		_seat_bone = _skeleton.find_bone(SEAT_BONE_FALLBACK)
	if _seat_bone < 0:
		push_warning("Horse: seat bone not found; RiderSeat stays static")
		return
	var bone_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(_seat_bone)
	_seat_offset = bone_global.affine_inverse() * rider_seat.global_transform


func _update_seat() -> void:
	if _skeleton == null or _seat_bone < 0:
		return
	var bone_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(_seat_bone)
	rider_seat.global_transform = bone_global * _seat_offset


## The tack is authored in the same model space as the horse, so both pieces
## start fitted and then ride the spine and head bones for the rest of the
## game. Offsets are captured once, at rest, rather than re-fitting per frame.
func _setup_tack() -> void:
	if _skeleton == null:
		return
	if _seat_bone >= 0 and saddle != null:
		_spine_rest = _skeleton.global_transform * _skeleton.get_bone_global_pose(_seat_bone)
		_saddle_rest = saddle.global_transform
		_seat_in_saddle = saddle.global_transform.affine_inverse() * rider_seat.global_transform
	_head_bone = _skeleton.find_bone(HEAD_BONE)
	if _head_bone >= 0 and bridle != null:
		_head_rest = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
		_bridle_rest = bridle.global_transform


func _update_tack() -> void:
	if _skeleton == null:
		return
	if _seat_bone >= 0 and saddle != null:
		var spine_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(_seat_bone)
		var stable := _stable_delta(spine_global, _spine_rest)
		saddle.global_transform = _pivot_transform(
			spine_global.origin, _spine_rest.origin, stable, _saddle_rest.basis, _saddle_rest.origin
		)
		rider_seat.global_transform = saddle.global_transform * _seat_in_saddle
	if _head_bone >= 0 and bridle != null:
		var head_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
		var stable := _stable_delta(head_global, _head_rest)
		bridle.global_transform = _pivot_transform(
			head_global.origin, _head_rest.origin, stable, _bridle_rest.basis, _bridle_rest.origin
		)


## Bone rotations in this rig carry a large arbitrary roll around the spine and
## head axes.  A rigid saddle or bridle bolted to the full pose twists with that
## roll, so keep the bone's yaw and pitch and discard the roll.
func _stable_delta(now: Transform3D, rest: Transform3D) -> Basis:
	var horse_basis := global_transform.basis
	var delta := horse_basis.inverse() * (now.basis * rest.basis.inverse()) * horse_basis
	var euler := delta.get_euler(EULER_ORDER_YXZ)
	var stable_local := Basis.from_euler(Vector3(euler.x, euler.y, 0.0), EULER_ORDER_YXZ)
	return horse_basis * stable_local * horse_basis.inverse()


## Places a rest-authored prop so it rides its bone: the prop's rest offset from
## the bone is rotated about the bone, and the bone's translation is followed.
##
## The old form was `(now - rest)`, the bone's displacement from its rest pose,
## which is the prop's absolute position only while the horse stands at the world
## origin.  As soon as a scene placed the horse off the origin the saddle (and
## the rider seat inside it) sat at the world origin instead of on the horse,
## which silently broke `can_mount()`'s seat distance and the live reins.
func _pivot_transform(
	now: Vector3, rest: Vector3, rotation: Basis, rest_basis: Basis, rest_origin: Vector3
) -> Transform3D:
	var origin := now + rotation * (rest_origin - rest)
	return Transform3D(rotation * rest_basis, origin)


## Bit ring in world space.  side is "L" or "R"; falls back to the head so a
## missing bridle can never crash the reins.
func get_bit_anchor(side: String) -> Vector3:
	if bridle != null:
		var anchor := bridle.find_child("BitAnchor_" + side, true, false) as Node3D
		if anchor != null:
			return anchor.global_position
	if _skeleton != null and _head_bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone) * Vector3(0, -0.2, -1.0)
	return global_position


## CONTEXT offer on foot: MOUNT when the saddle is in reach.  Leading and the
## stable have their own offers.
func touch_context() -> Dictionary:
	if rider != null:
		return {}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and can_mount(player):
		return {"action": "interact", "label": "MOUNT", "priority": 1}
	return {}


func can_mount(p: Node3D) -> bool:
	if rider != null or airborne or grooming or boarded:
		return false
	var to := rider_seat.global_position - p.global_position
	to.y = 0.0
	return to.length() < mount_range


## The lead rope can be taken from a little further out than the saddle, so a
## handler who has just dismounted does not have to walk into the horse.
func can_lead(p: Node3D) -> bool:
	if p == null or rider != null or leader != null or airborne or grooming or boarded:
		return false
	var to := global_position - p.global_position
	to.y = 0.0
	return to.length() < lead_range


func set_leader(p: Node3D) -> void:
	if p == null or not can_lead(p):
		return
	leader = p
	if neigh.stream:
		neigh.play()


func clear_leader() -> void:
	leader = null


func set_rider(p: Node3D) -> void:
	rider = p
	_settle_time = 0.0
	if neigh.stream:
		neigh.play()


func clear_rider() -> void:
	rider = null
	_ride_speed = 0.0
	_gait_hold = 0.0
	# Stop over a short, firm settle and then go straight to Idle instead of
	# letting the speed-driven FSM walk down through canter/trot/walk.
	_settle_time = maxf(dismount_settle_time, 0.0)
	if _settle_time <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_finish_dismount()


func _finish_dismount() -> void:
	_settle_time = 0.0
	if fsm != null and fsm.has_method("force_idle"):
		fsm.force_idle()


## Stirrup length is a per-rider fit: the treads rise for a shorter leg so the
## boots stay in the irons.  The saddle caches its rest pose and ignores
## repeated calls with the same lift.
func _apply_rider_stirrups() -> void:
	if saddle == null or not saddle.has_method("set_stirrup_lift"):
		return
	var lift := 0.0
	if rider != null:
		var profile = rider.get("character_profile")
		if profile != null:
			lift = profile.stirrup_lift
	saddle.set_stirrup_lift(lift)


func get_rider_seat_position() -> Vector3:
	return rider_seat.global_position


func get_rider_seat_transform() -> Transform3D:
	return rider_seat.global_transform


func is_airborne() -> bool:
	return airborne


func get_jump_velocity() -> float:
	var bonus := minf(jumping_skill, max_jumping_skill) * jump_training_bonus
	return jump_velocity + bonus


## A struck rail is light wood, not a wall.  Shed a little pace on impact so
## the hit registers, but keep the horse travelling through the gap instead
## of stopping dead at the fence.
func apply_fence_impact(speed_keep := 0.85) -> void:
	if airborne:
		return
	var keep := clampf(speed_keep, 0.0, 1.0)
	_ride_speed *= keep
	velocity.x *= keep
	velocity.z *= keep


## Stable handover.  Boarding hides the horse in place and parks its physics
## until release_from_stable() puts it back at the stall.  The player never
## leads or follows the horse, so this is the only way in and out of the yard.
func board() -> bool:
	if boarded or rider != null or grooming or mucking:
		return false
	clear_leader()
	boarded = true
	velocity = Vector3.ZERO
	_ride_speed = 0.0
	_gait_hold = 0.0
	_settle_time = 0.0
	airborne = false
	air_phase = 0.0
	set_physics_process(false)
	set_process(false)
	if mount_prompt != null:
		mount_prompt.visible = false
	if collision != null:
		collision.set_deferred("disabled", true)
	visible = false
	return true


func release_from_stable(anchor: Transform3D) -> void:
	if not boarded:
		return
	global_transform = anchor
	velocity = Vector3.ZERO
	_ride_speed = 0.0
	_gait_hold = 0.0
	_settle_time = 0.0
	airborne = false
	air_phase = 0.0
	boarded = false
	visible = true
	if collision != null:
		collision.set_deferred("disabled", false)
	set_physics_process(true)
	set_process(true)
	if fsm != null and fsm.player != null:
		fsm.player.speed_scale = 1.0
		if fsm.player.has_animation("Idle"):
			fsm.player.play("Idle", 0.2)
		else:
			fsm.player.play()
		fsm.set("current_state", "idle")


## Leaves the ground when the horse is mounted, grounded and not already in
## the air.  Returns true when the jump actually started.
func jump() -> bool:
	if airborne or grooming or not is_on_floor():
		return false
	velocity.y = get_jump_velocity()
	_jump_air_time = 2.0 * velocity.y / gravity
	_air_time = 0.0
	air_phase = 0.0
	airborne = true
	fsm.set_airborne(true)
	jumped.emit()
	return true


func award_training(jump_xp: float, fitness_xp: float) -> void:
	jumping_skill = minf(jumping_skill + jump_xp, max_jumping_skill)
	fitness = minf(fitness + fitness_xp, max_jumping_skill)
	HorseState.record_from(self)
	training_awarded.emit(jumping_skill, fitness)


## Needs decay over real minutes and are mirrored into `HorseState` once a
## second, so a doorway, a reload or a save carries them along.  The mirror is a
## plain write rather than a `record_from()`: the latter emits `changed`, and a
## save queued every second is not what any of this is for.
func _tick_needs(delta: float) -> void:
	var minutes := delta / 60.0
	hunger = maxf(0.0, hunger - hunger_per_minute * minutes)
	var working := rider != null and absf(_ride_speed) > 0.2
	if working:
		energy = maxf(0.0, energy - energy_ride_per_minute * minutes)
	elif boarded or absf(_ride_speed) < 0.05:
		energy = minf(1.0, energy + energy_rest_per_minute * minutes)
	# The bed soils whether the horse is ridden or not, faster while it is
	# standing about.  Riding does not soil it, because the horse is not in it.
	if not mucking:
		var muck_rate := stall_muck_per_minute
		if not working and absf(_ride_speed) < 0.05:
			muck_rate = stall_muck_standing_per_minute
		stall_muck = minf(1.0, stall_muck + muck_rate * minutes)
	# Health drifts toward what the horse's care adds up to, and a soiled bed is
	# the one thing that holds it back.  It cannot be lost in a hurry and neglect
	# alone does not take it to zero.
	var target := clampf(
		0.35 + 0.30 * cleanliness + 0.15 * trust + 0.1 * hunger + 0.1 * (1.0 - stall_muck),
		0.0, 1.0
	)
	health = move_toward(health, target, health_per_minute * minutes)
	_needs_report += delta
	if _needs_report >= needs_report_seconds:
		_needs_report = 0.0
		HorseState.set_needs(hunger, energy, health)
		HorseState.set_stall_muck(stall_muck)


## Eats one bale from the yard's supplies.  The trough consumes the bale when
## this answers ok, so a full horse cannot waste one.
func feed() -> Dictionary:
	if hunger >= 0.995:
		return {"ok": false, "message": "Your horse is not hungry."}
	var before := hunger
	hunger = minf(1.0, hunger + hay_feed_gain)
	energy = minf(1.0, energy + 0.1)
	happiness = minf(1.0, happiness + 0.05)
	trust = minf(1.0, trust + 0.02)
	HorseState.record_from(self)
	return {
		"ok": true,
		"hunger_gain": hunger - before,
		"message": "Your horse eats the hay and settles.",
	}


## Freeze the horse in a quiet standing pose at the bay.  The grooming mask
## is baked against the posed skeleton, so the mask zones and the picker must
## both see the same pose.
func begin_grooming(anchor: Transform3D) -> bool:
	if grooming or rider != null or boarded or mucking:
		return false
	clear_leader()
	grooming = true
	set_physics_process(false)
	set_process(false)
	velocity = Vector3.ZERO
	_settle_time = 0.0
	_ride_speed = 0.0
	_gait_hold = 0.0
	if gallop != null:
		gallop.stop()
	if mount_prompt != null:
		mount_prompt.visible = false
	if tack != null:
		tack.visible = false
	global_transform = anchor
	if fsm != null and fsm.player != null:
		fsm.player.speed_scale = 1.0
		groom_pose_clip = GROOM_POSE if fsm.player.has_animation(GROOM_POSE) else GROOM_POSE_FALLBACK
		if fsm.player.has_animation(groom_pose_clip):
			fsm.player.play(groom_pose_clip, 0.0)
			fsm.player.seek(0.0, true)
			# Hold the first frame.  pause() clears current_animation in 4.7,
			# so a zero playback speed keeps the clip visible and frozen.
			fsm.player.speed_scale = 0.0
		fsm.set("current_state", "idle")
	if _skeleton != null:
		_skeleton.force_update_all_bone_transforms()
	if groom_surface != null:
		groom_surface.call("prepare_for_grooming")
	return true


## The muck session works the stall rather than the horse, so nothing is frozen
## and no pose changes: the horse keeps standing wherever it is, and only the
## soiling pauses.  The mount prompt is left alone, because the stable door
## already suppresses it for anyone standing at that end of the yard.
func begin_mucking() -> bool:
	if mucking or grooming:
		return false
	mucking = true
	return true


func end_mucking() -> void:
	mucking = false


func end_grooming() -> void:
	if not grooming:
		return
	grooming = false
	if tack != null:
		tack.visible = true
	set_physics_process(true)
	set_process(true)
	if fsm != null and fsm.player != null:
		fsm.player.speed_scale = 1.0
		if fsm.player.has_animation("Idle"):
			fsm.player.play("Idle", 0.2)
		else:
			fsm.player.play()
		fsm.set("current_state", "idle")


## Hoof state lives on the horse so a partial groom survives leaving the bay.
## index order is front-left, front-right, hind-left, hind-right.
func mark_hoof(index: int) -> bool:
	if index < 0 or index >= groomed_hooves.size():
		return false
	if groomed_hooves[index]:
		return false
	groomed_hooves[index] = true
	hooves_cleaned = 0
	for done in groomed_hooves:
		if done:
			hooves_cleaned += 1
	HorseState.record_from(self)
	return true


## Called by the session when the player finishes or leaves.  Cleanliness is
## monotonic across visits; a full groom also clears the dirt shader.
func apply_grooming_result(clean: float, polish: float, hooves: int, complete: bool) -> Dictionary:
	cleanliness = 1.0 if complete else maxf(cleanliness, clampf(clean, 0.0, 1.0))
	grooming_polish = maxf(grooming_polish, clampf(polish, 0.0, 1.0))
	hooves_cleaned = maxi(hooves_cleaned, clampi(hooves, 0, 4))
	var score := 0.60 * cleanliness + 0.25 * grooming_polish + 0.15 * (float(hooves_cleaned) / 4.0)
	var new_progress := maxf(0.0, score - care_reward_score)
	care_reward_score = maxf(care_reward_score, score)
	var trust_gain := 0.08 * new_progress
	var happiness_gain := 0.14 * new_progress
	trust = minf(1.0, trust + trust_gain)
	happiness = minf(1.0, happiness + happiness_gain)
	if groom_surface != null:
		var dirt := 0.0 if complete else clampf(1.0 - cleanliness, 0.0, 1.0)
		groom_surface.call("set_dirt_level", dirt)
	HorseState.record_from(self)
	return {
		"clean": cleanliness,
		"polish": grooming_polish,
		"hooves": hooves_cleaned,
		"score": score,
		"complete": complete,
		"trust_gain": trust_gain,
		"happiness_gain": happiness_gain,
	}


## Pins a rosette at the withers.  Returns false when one is already there, so a
## re-spawn cannot stack two.  This lives on the horse because the horse is what
## wears it: the show class used to build the node itself, which meant the
## rosette disappeared with the next scene change.
func attach_rosette(colour: String) -> bool:
	if get_node_or_null("ShowRosette") != null:
		return false
	var colours := {
		"red": Color(0.55, 0.09, 0.07),
		"blue": Color(0.09, 0.18, 0.50),
		"yellow": Color(0.80, 0.58, 0.09),
	}
	var body := StandardMaterial3D.new()
	body.albedo_color = colours.get(colour, Color(0.8, 0.8, 0.8))
	body.roughness = 0.6
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.72, 0.55, 0.18)
	gold.metallic = 0.7
	gold.roughness = 0.35

	var rosette := Node3D.new()
	rosette.name = "ShowRosette"
	rosette.position = Vector3(0.16, 1.66, 0.14)
	rosette.rotation = Vector3(0.0, -0.6, 0.25)
	add_child(rosette)

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.055
	disc_mesh.bottom_radius = 0.055
	disc_mesh.height = 0.012
	disc_mesh.radial_segments = 16
	disc.mesh = disc_mesh
	disc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	disc.material_override = body
	rosette.add_child(disc)

	var centre := MeshInstance3D.new()
	var centre_mesh := SphereMesh.new()
	centre_mesh.radius = 0.018
	centre_mesh.height = 0.036
	centre.mesh = centre_mesh
	centre.position = Vector3(0.0, 0.0, 0.01)
	centre.material_override = gold
	rosette.add_child(centre)

	for side in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.030, 0.10, 0.008)
		tail.mesh = tail_mesh
		tail.position = Vector3(side * 0.018, -0.085, 0.0)
		tail.rotation = Vector3(0.0, 0.0, side * 0.22)
		tail.material_override = body
		rosette.add_child(tail)
	return true


## Rosettes are recorded on GameState, which survives a scene change; the pin
## itself was a child of the horse and did not.  Wearing the last one won is how
## the showground door stops undressing the horse.
func _restore_rosette() -> void:
	if GameState.rosettes.is_empty():
		return
	var last: Dictionary = GameState.rosettes[GameState.rosettes.size() - 1]
	attach_rosette(str(last.get("colour", "")))


func _face(dir: Vector3, delta: float, rate: float = -1.0) -> void:
	# Godot forward is -Z. The model is rotated 180 degrees on its Model node
	# so that its head points along -Z like every other forward in Godot.
	var target_yaw := atan2(-dir.x, -dir.z)
	var turn_rate := turn_speed if rate < 0.0 else rate
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_rate * delta)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	_tick_needs(delta)
	if rider != null:
		_ride(delta)
	elif leader != null:
		_lead(delta)
	else:
		_stand(delta)

	move_and_slide()

	var was_airborne := airborne
	airborne = not is_on_floor()
	if was_airborne and not airborne:
		_on_landed()
	if airborne:
		_air_time += delta
		air_phase = clampf(_air_time / maxf(_jump_air_time, 0.01), 0.0, 1.0)

	_update_seat()
	_update_tack()
	_apply_rider_stirrups()

	var speed := Vector2(velocity.x, velocity.z).length()
	_update_animation(speed)


func _ride(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		jump()

	var input := TouchControls.get_move_input()
	var turn := clampf(input.x, -1.0, 1.0)
	var throttle := absf(input.y)

	# The horse steers in its own frame: left/right is a turn rate, up/down is
	# throttle.  Nothing in this path reads the camera, so a look drag can never
	# re-aim the horse - the camera-relative spin loop is impossible here rather
	# than guarded against.
	if throttle <= STEER_DEADZONE:
		_gait_hold = 0.0
		# Turning in place: the heading can still be lined up before moving off,
		# at the slower rate.  A standing horse never pivots to face the camera.
		rotation.y -= turn * ridden_turn_rate_in_place * delta
		if not airborne:
			_ride_speed = move_toward(_ride_speed, 0.0, deceleration * delta)
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		return

	rotation.y -= turn * _ridden_turn_rate() * delta

	# Airborne steering is limited to body rotation; the horse keeps the
	# momentum it left the ground with.
	if airborne:
		return

	var running := Input.is_action_pressed("run")
	if running:
		_gait_hold += delta
	else:
		_gait_hold = 0.0

	var target := walk_speed
	if running:
		target = trot_speed if _gait_hold < gait_hold_time else canter_speed
	_ride_speed = move_toward(_ride_speed, target, acceleration * delta)
	_travel()


## The ridden turn rate for the current ground speed: a walk turns tightly, a
## canter carves a wide arc.  Turning in place uses its own, slower rate.
func _ridden_turn_rate() -> float:
	var speed := Vector2(velocity.x, velocity.z).length()
	var span := maxf(canter_speed - walk_speed, 0.001)
	var weight := clampf((speed - walk_speed) / span, 0.0, 1.0)
	return lerpf(ridden_turn_rate_walk, ridden_turn_rate_canter, weight)


## Moves along the direction the horse actually faces, not the raw stick
## direction, or it slides sideways while the model is still turning.
func _travel() -> void:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
		velocity.x = forward.x * _ride_speed
		velocity.z = forward.z * _ride_speed


## A riderless horse is not a dog: it waits where it was left instead of
## trailing the player.  Dismounting at speed still settles to a stop.
func _stand(delta: float) -> void:
	if _settle_time > 0.0:
		_settle_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, dismount_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, dismount_deceleration * delta)
		if _settle_time <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
			_finish_dismount()
		return
	velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)


## A led horse walks to the handler's shoulder position and stops there,
## turning to face the same way so it is ready to be ridden or led on.  The
## offset is relative to the handler, so turning the handler swings the horse
## around rather than dragging it by the nose.
func _lead(delta: float) -> void:
	if leader == null or not is_instance_valid(leader):
		leader = null
		_stand(delta)
		return
	var target := leader.global_transform * lead_offset
	target.y = global_position.y
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= lead_stop_distance:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		var heading := -leader.global_transform.basis.z
		heading.y = 0.0
		if heading.length_squared() > 0.001:
			_face(heading.normalized(), delta)
		return
	var dir := to_target / distance
	# Walk when the handler walks, trot to close a gap, and never break into a
	# canter on the rope.
	var speed := clampf(distance * 1.8, 0.6, trot_speed)
	_face(dir, delta)
	# Travel along the direction the horse actually faces, not the raw path to
	# the handler's shoulder, or it slides sideways across the ground while the
	# body is still swinging round.  A sharp turn becomes a pivot on the spot and
	# then a walk, which is how a horse turns on a rope.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()
	var throttle := clampf((forward.dot(dir) - 0.2) / 0.6, 0.0, 1.0)
	var goal := speed * throttle
	velocity.x = move_toward(velocity.x, forward.x * goal, lead_acceleration * delta)
	velocity.z = move_toward(velocity.z, forward.z * goal, lead_acceleration * delta)


func _on_landed() -> void:
	air_phase = 0.0
	fsm.set_airborne(false)
	landed.emit()


func _update_animation(speed: float) -> void:
	if fsm != null:
		fsm.set_airborne(airborne)
		fsm.update_for_speed(speed)
	_update_gallop(speed)


func _update_gallop(speed: float) -> void:
	if gallop.stream == null:
		return
	if airborne or speed <= 0.4:
		gallop.stop()
		return
	if not gallop.playing:
		gallop.play()
	# Faster gait -> higher pitch, so a trot sounds quicker than a walk.
	gallop.pitch_scale = clampf(0.85 + speed * 0.06, 0.85, 1.3)

