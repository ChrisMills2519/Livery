extends CharacterBody3D

signal state_changed(from_state: String, to_state: String)
signal petted

enum State {
	IDLE,
	ALERT,
	GREET,
	WANDER,
	FOLLOW,
	RETURN,
	SIT,
	LIE,
	SLEEP,
	EAT,
	PET,
	SHAKE,
}

const STATE_NAMES := [
	"idle", "alert", "greet", "wander", "follow", "return",
	"sit", "lie", "sleep", "eat", "pet", "shake",
]
const LOCKED_STATES := [
	State.ALERT, State.GREET, State.LIE, State.SLEEP,
	State.EAT, State.PET, State.SHAKE,
]
const ACTIVE_STATES := [
	State.WANDER, State.FOLLOW, State.RETURN, State.GREET, State.EAT,
]

@export_group("Movement")
## Gait speeds (m/s) matched to the stride of the Walk/Trot/Run clips, so the
## planted paws stay put.  They are the clips' measured ground speeds from
## tools/build_chihuahua.py; the animator references must stay in step.
@export var walk_speed := 0.73
@export var trot_speed := 1.86
@export var run_speed := 3.26
@export var acceleration := 7.0
@export var deceleration := 10.0
@export var turn_speed := 8.0
@export var gravity := 20.0

@export_group("Home")
@export var home_radius := 9.0
@export var home_leash := 22.0

@export_group("Following")
@export var follow_radius := 12.0
@export var follow_stop_distance := 1.15
@export var heel_offset := Vector3(0.8, 0.0, 1.0)
@export var sit_after_seconds := 2.5
@export var interest_threshold := 0.6
@export var interest_gain := 0.22
@export var interest_decay := 0.08
@export var follow_max_time := 14.0
@export var follow_cooldown_min := 25.0
@export var follow_cooldown_max := 50.0
@export var greet_chance := 0.6
@export var sniff_radius := 2.0

@export_group("Greeting and petting")
@export var greet_radius := 10.5
@export var greet_distance := 1.25
@export var greet_time := 1.4
@export var pet_range := 2.4
@export var pet_time := 1.8

@export_group("Needs")
@export var hunger := 0.25
@export var energy := 0.7
@export var affection := 0.6
@export var boredom := 0.1
@export var hunger_rate := 0.002
@export var energy_drain := 0.0018
@export var energy_speed_drain := 0.0009
@export var affection_decay := 0.0002
@export var boredom_rate := 0.004
@export var sleep_recovery := 0.03
@export var eat_rate := 0.08

@export_group("Thresholds")
@export var eat_hunger := 0.72
@export var eat_done_hunger := 0.12
@export var lie_energy := 0.22
@export var wake_energy := 0.9
@export var wander_boredom := 0.55

@export_group("Timing")
@export var brain_interval := 0.35
@export var alert_time := 0.8
@export var lie_time := 1.8
@export var rest_time := 1.5
@export var shake_time := 1.1
@export var eat_timeout := 14.0
@export var wander_pause := 1.2

@onready var animator = $Animator
@onready var prompt: Label3D = $PetPrompt

var state: int = State.IDLE
var _state_time := 0.0
var _brain_timer := 0.2
var _prompt_timer := 0.0
var _idle_limit := 4.0
var _sit_limit := 6.0
var _settle_time := 0.0
var _wander_target := Vector3.ZERO
var _wander_arrived_at := -1.0
var _eat_elapsed := 0.0
var _home := Vector3.ZERO
var _bowl_spot: Node3D
var _player: Node3D
var _horse: Node3D
var _stimulus: Node3D
var _stimulus_is_player := false
var _player_was_near := false
var _greet_cooldown := 0.0
var _horse_alert_cooldown := 0.0
var _stuck_time := 0.0
var _interest := 0.0
var _follow_cooldown := 0.0
var _follow_elapsed := 0.0
var _greet_roll := true
var _wander_short := false
var _wander_pause_len := 1.2
var _last_player_pos := Vector3.ZERO
var _player_vel_est := Vector3.ZERO
var _desired_pose := ""
var _use_locomotion := false
var _avoid_dir := Vector3.ZERO
var _avoid_weight := 0.0
var _rng := RandomNumberGenerator.new()


## CONTEXT offer next to the dog: pet it while its prompt is showing.
func touch_context() -> Dictionary:
	if prompt != null and prompt.visible:
		return {"action": "pet", "label": "PET", "priority": 2}
	return {}


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("dog")
	_rng.randomize()
	_home = get_parent().global_position
	_bowl_spot = get_parent().get_node_or_null("BowlSpot") as Node3D
	if prompt != null:
		prompt.text = Device.pick("Q  ·  PET", "TAP  ·  PET")
		prompt.visible = false
	_enter_state(State.IDLE)
	call_deferred("_bind")
	call_deferred("_refresh_prompt")
	call_deferred("_add_feed_target")


func _process(delta: float) -> void:
	_prompt_timer -= delta
	if _prompt_timer <= 0.0:
		_prompt_timer = 0.1
		_refresh_prompt()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
	_measure_player(delta)
	_tick_timers(delta)
	_tick_needs(delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	_state_time += delta
	_brain_timer -= delta
	if _brain_timer <= 0.0:
		_brain_timer = brain_interval
		_think()
	_apply_horse_avoidance(delta)
	_update_state(delta)
	var before := global_position
	move_and_slide()
	_check_stuck(delta, before)
	_apply_animation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("pet"):
		return
	if _try_pet():
		get_viewport().set_input_as_handled()


func _bind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _horse == null or not is_instance_valid(_horse):
		_horse = get_tree().get_first_node_in_group("horse") as Node3D


func _tick_timers(delta: float) -> void:
	_greet_cooldown = maxf(0.0, _greet_cooldown - delta)
	_horse_alert_cooldown = maxf(0.0, _horse_alert_cooldown - delta)
	_follow_cooldown = maxf(0.0, _follow_cooldown - delta)
	_tick_interest(delta)


func _measure_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player_vel_est = Vector3.ZERO
		return
	var now := _player.global_position
	if delta > 0.0:
		var moved := now - _last_player_pos
		moved.y = 0.0
		var est := moved / delta
		# A jump this large is a teleport (scene reset or debug placement), not a walk.
		if est.length() > 8.0:
			est = Vector3.ZERO
		_player_vel_est = _player_vel_est.lerp(est, clampf(delta * 10.0, 0.0, 1.0))
	_last_player_pos = now


## Interest in the player builds while they walk nearby and fades otherwise.
## It is what makes the dog follow: a standing player never pulls it along.
func _tick_interest(delta: float) -> void:
	var near := _player_on_foot() and _player_distance() <= follow_radius
	if near and _player_speed() > 0.25:
		_interest = minf(1.0, _interest + interest_gain * delta)
	elif near:
		_interest = maxf(0.0, _interest - interest_decay * delta)
	else:
		_interest = maxf(0.0, _interest - interest_decay * 2.0 * delta)


## Stop following: the dog loses interest and cools off before it chases again.
func _end_follow(next_state: int) -> void:
	_follow_cooldown = _rng.randf_range(follow_cooldown_min, follow_cooldown_max)
	_interest = 0.0
	_change_state(next_state)


## After a greeting or petting a real dog usually settles near its person or
## goes back to its own business; it only chases if the walk really pulls it.
func _settle_after_visit() -> int:
	if _should_follow():
		return State.FOLLOW
	return State.SIT if _rng.randf() < 0.5 else State.IDLE


func _tick_needs(delta: float) -> void:
	if state == State.SLEEP:
		energy = minf(1.0, energy + sleep_recovery * delta)
		hunger = minf(1.0, hunger + hunger_rate * 0.5 * delta)
		return
	var speed := _planar_speed()
	energy = clampf(
		energy - (energy_drain + speed * energy_speed_drain) * delta, 0.0, 1.0
	)
	affection = clampf(affection - affection_decay * delta, 0.0, 1.0)
	if state != State.EAT:
		hunger = clampf(hunger + hunger_rate * delta, 0.0, 1.0)
	var bored := boredom_rate
	if speed > 0.15 or state in ACTIVE_STATES:
		bored *= 0.2
	boredom = clampf(boredom + bored * delta, 0.0, 1.0)


func _think() -> void:
	if _player == null:
		_bind()
	if state == State.RETURN:
		return
	if state in LOCKED_STATES:
		return
	if state == State.FOLLOW:
		if not _player_on_foot() or _distance_to_home() > home_leash:
			_change_state(State.RETURN)
			return
		if _follow_elapsed > follow_max_time or _interest < 0.05:
			_end_follow(State.IDLE)
			return
	if _check_player_arrival():
		_change_state(State.ALERT)
		return
	if _check_horse_alert():
		_change_state(State.ALERT)
		return
	if hunger >= eat_hunger:
		_change_state(State.EAT)
		return
	if energy <= lie_energy:
		_change_state(State.LIE)
		return
	if state != State.FOLLOW and _should_follow():
		_change_state(State.FOLLOW)
		return
	if state == State.IDLE and _state_time > _idle_limit and not _should_follow():
		var roll := _rng.randf()
		if roll < 0.25:
			_change_state(State.SIT)
		elif roll < 0.55:
			_wander_short = true
			_change_state(State.WANDER)
		else:
			_wander_short = false
			_change_state(State.WANDER)
		return
	if state != State.WANDER and boredom >= wander_boredom and not _should_follow():
		_change_state(State.WANDER)


func _check_player_arrival() -> bool:
	if _player == null:
		return false
	var near := _player_distance() <= greet_radius
	if not near:
		_player_was_near = false
		return false
	if _player_was_near:
		return false
	_player_was_near = true
	# A dog that is already following its player does not greet them again.
	if state == State.FOLLOW or _greet_cooldown > 0.0 or _player_mounted():
		return false
	_greet_roll = _rng.randf() < greet_chance
	_stimulus = _player
	_stimulus_is_player = true
	return true


func _check_horse_alert() -> bool:
	if _horse == null or _horse_alert_cooldown > 0.0:
		return false
	if _horse_distance() > 3.5 or _horse_speed() < 1.0:
		return false
	_stimulus = _horse
	_stimulus_is_player = false
	_horse_alert_cooldown = 12.0
	return true


func _update_state(delta: float) -> void:
	# Cleared every frame, not only on a state change: a state that stops this
	# frame has to hand the animator over to its own pose (Eat, TailWag, Sit)
	# instead of leaving the previous frame's gait in charge.
	_use_locomotion = false
	_desired_pose = ""
	match state:
		State.IDLE:
			_stop(delta)
			_desired_pose = "Idle"
		State.ALERT:
			_stop(delta)
			_desired_pose = "Idle_Alert"
			if _stimulus != null and is_instance_valid(_stimulus):
				_face_point(_stimulus.global_position, delta, 12.0)
			if _state_time >= alert_time:
				if _stimulus_is_player and _player_on_foot() and _greet_roll:
					_change_state(State.GREET)
				else:
					_change_state(State.IDLE)
		State.GREET:
			if _player == null or _player_mounted():
				_change_state(State.IDLE)
				return
			var player_gap := _player_distance()
			if player_gap > greet_distance:
				if _state_time > 5.0:
					_change_state(State.IDLE)
					return
				var greet_speed := walk_speed if player_gap < 2.5 else trot_speed
				_steer_to(_player.global_position, greet_speed, delta)
				_use_locomotion = true
			else:
				_stop(delta)
				_desired_pose = "TailWag"
				_face_point(_player.global_position, delta)
				if _state_time >= greet_time:
					affection = minf(1.0, affection + 0.06)
					_greet_cooldown = 45.0
					_change_state(_settle_after_visit())
		State.WANDER:
			var to_target := _wander_target - global_position
			to_target.y = 0.0
			var target_gap := to_target.length()
			if target_gap > 0.35:
				var wander_speed := walk_speed if target_gap < 2.0 else trot_speed
				wander_speed = minf(wander_speed, target_gap * 2.0 + 0.3)
				_steer_to(_wander_target, wander_speed, delta)
				_use_locomotion = true
				boredom = maxf(0.0, boredom - 0.02 * delta)
			else:
				_stop(delta)
				_desired_pose = "Idle"
				if _wander_arrived_at < 0.0:
					_wander_arrived_at = _state_time
				if _state_time - _wander_arrived_at >= _wander_pause_len:
					_change_state(State.IDLE)
		State.FOLLOW:
			_follow_elapsed += delta
			if _player == null or _player_mounted():
				_change_state(State.RETURN)
				return
			if _distance_to_home() > home_leash:
				_change_state(State.RETURN)
				return
			var target := _follow_target()
			var gap := _horizontal_distance(target)
			if gap <= follow_stop_distance and _player_speed() > 0.25:
				var player_velocity := _player_velocity()
				player_velocity.y = 0.0
				var match_speed := minf(player_velocity.length(), run_speed)
				if match_speed > 0.01:
					# Trotting at heel is a movement like any other: travel along the
					# dog's own nose, so it does not crab alongside the player.
					_move_along_facing(player_velocity, match_speed, delta)
				_use_locomotion = true
				_settle_time = 0.0
				return
			if gap > follow_stop_distance:
				var player_speed := _player_speed()
				# The player walks at 3 m/s, which is already the dog's full run, so
				# the pack speed decides the gait rather than the distance alone.
				var follow_speed := walk_speed
				if gap > 3.0 or player_speed > 2.4:
					follow_speed = run_speed
				elif gap > 1.3 or player_speed > 0.9:
					follow_speed = trot_speed
				follow_speed = minf(follow_speed, gap * 2.2 + 0.35)
				_steer_to(target, follow_speed, delta)
				_use_locomotion = true
				_settle_time = 0.0
				boredom = maxf(0.0, boredom - 0.015 * delta)
			else:
				_stop(delta)
				_desired_pose = "Idle"
				var heading := -_player.global_transform.basis.z
				_face_direction(heading, delta)
				if _player_speed() < 0.2:
					_settle_time += delta
				else:
					_settle_time = 0.0
				if _settle_time >= sit_after_seconds:
					_end_follow(State.SIT)
		State.RETURN:
			var home_gap := _distance_to_home()
			if home_gap > 0.4:
				var return_speed := walk_speed
				if home_gap > 7.0:
					return_speed = run_speed
				elif home_gap > 2.5:
					return_speed = trot_speed
				return_speed = minf(return_speed, home_gap * 1.8 + 0.4)
				_steer_to(_home, return_speed, delta)
				_use_locomotion = true
			else:
				_stop(delta)
				_desired_pose = "Idle"
				if _state_time > 1.0:
					_change_state(State.IDLE)
		State.SIT:
			_stop(delta)
			_desired_pose = "Sit"
			if _player != null and _player_distance() < 4.0:
				_face_point(_player.global_position, delta, 4.0)
			if _state_time > _sit_limit:
				_change_state(State.IDLE)
		State.LIE:
			_stop(delta)
			if _state_time >= lie_time:
				_desired_pose = "Rest_Pose"
			if _state_time >= lie_time + rest_time:
				_change_state(State.SLEEP)
			if (
				_player != null
				and _player_distance() < 1.3
				and energy > 0.3
				and _state_time > 1.0
			):
				_stimulus = _player
				_stimulus_is_player = true
				_change_state(State.ALERT)
		State.SLEEP:
			_stop(delta)
			_desired_pose = "Sleep"
			if _state_time > 2.0:
				if _player != null and _player_distance() < 1.5 and energy > 0.25:
					_stimulus = _player
					_stimulus_is_player = true
					_change_state(State.ALERT)
				elif energy >= wake_energy:
					_change_state(State.SHAKE)
		State.EAT:
			var bowl := _bowl_position()
			var bowl_gap := _horizontal_distance(bowl)
			if bowl_gap > 0.35 and _eat_elapsed <= 0.0:
				var eat_speed := walk_speed if bowl_gap < 2.0 else trot_speed
				eat_speed = minf(eat_speed, bowl_gap * 2.0 + 0.3)
				_steer_to(bowl, eat_speed, delta)
				_use_locomotion = true
			else:
				_stop(delta)
				_face_point(bowl, delta, 6.0)
				_desired_pose = "Eat"
				_eat_elapsed += delta
				hunger = maxf(0.0, hunger - eat_rate * delta)
				boredom = maxf(0.0, boredom - 0.02 * delta)
				if hunger <= eat_done_hunger or _eat_elapsed >= eat_timeout:
					_change_state(State.SHAKE)
		State.PET:
			_stop(delta)
			_desired_pose = "TailWag"
			if _player != null:
				_face_point(_player.global_position, delta, 10.0)
			if _state_time >= pet_time:
				if _player_on_foot():
					_change_state(_settle_after_visit())
				else:
					_change_state(State.IDLE)
		State.SHAKE:
			_stop(delta)
			if _state_time >= shake_time:
				_change_state(State.IDLE)


func _apply_animation() -> void:
	if animator == null:
		return
	# A pose only takes over once the dog has stopped rolling out of its gait.
	var moving := _use_locomotion or _planar_speed() > 0.15
	if moving:
		animator.set_locomotion(_planar_speed())
	elif _desired_pose != "":
		animator.set_pose(_desired_pose)


func _change_state(next_state: int) -> void:
	if next_state == state:
		return
	var previous := state
	state = next_state
	_state_time = 0.0
	_settle_time = 0.0
	_eat_elapsed = 0.0
	_wander_arrived_at = -1.0
	_use_locomotion = false
	_desired_pose = ""
	_enter_state(next_state)
	state_changed.emit(STATE_NAMES[previous], STATE_NAMES[next_state])


func _enter_state(next_state: int) -> void:
	match next_state:
		State.IDLE:
			_idle_limit = _rng.randf_range(2.5, 5.5)
			_desired_pose = "Idle"
		State.ALERT:
			_desired_pose = "Idle_Alert"
		State.FOLLOW:
			_follow_elapsed = 0.0
		State.WANDER:
			_pick_wander_target()
		State.SIT:
			_sit_limit = _rng.randf_range(5.0, 9.0)
			_desired_pose = "Sit"
		State.LIE:
			if animator != null:
				animator.play_action("Lie")
		State.SLEEP:
			_desired_pose = "Sleep"
		State.PET:
			_desired_pose = "TailWag"
		State.SHAKE:
			if animator != null:
				animator.play_action("Shake")


func _try_pet() -> bool:
	if _player == null or not _player_on_foot():
		return false
	if _player_distance() > pet_range:
		return false
	if not bool(_player.get("controls_enabled")):
		return false
	if state == State.PET:
		_state_time = 0.0
		affection = minf(1.0, affection + 0.05)
		return true
	_change_state(State.PET)
	affection = minf(1.0, affection + 0.15)
	boredom = maxf(0.0, boredom - 0.2)
	_greet_cooldown = maxf(_greet_cooldown, 5.0)
	petted.emit()
	return true


func _refresh_prompt() -> void:
	if prompt == null:
		return
	var show := (
		_player != null
		and _player_on_foot()
		and bool(_player.get("controls_enabled"))
		and _player_distance() <= pet_range
	)
	prompt.visible = show


func _pick_wander_target() -> void:
	# A sniff is a short wander around the dog's own spot; a roam covers the yard.
	_wander_pause_len = wander_pause * 2.5 if _wander_short else wander_pause
	var centre := global_position if _wander_short else _home
	var max_radius := sniff_radius if _wander_short else home_radius
	for attempt in range(10):
		var angle := _rng.randf() * TAU
		var radius := sqrt(_rng.randf()) * max_radius
		var candidate := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if Vector2(candidate.x - _home.x, candidate.z - _home.z).length() > home_radius:
			continue
		var ground := _ground_at(candidate)
		if ground.is_finite():
			_wander_target = ground
			return
	_wander_target = _home


func _ground_at(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var from := point + Vector3.UP * 2.0
	var to := point + Vector3.DOWN * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var ground: Vector3 = hit["position"]
	if ground.y < -0.1 or ground.y > 0.25:
		return Vector3.INF
	return ground


func _bowl_position() -> Vector3:
	if _bowl_spot != null and is_instance_valid(_bowl_spot):
		return _bowl_spot.global_position
	return _home + Vector3(1.0, 0.0, 0.6)


func _follow_target() -> Vector3:
	if _player == null:
		return global_position
	var target := _player.global_transform * heel_offset
	target.y = global_position.y
	return target


func _should_follow() -> bool:
	if not _player_on_foot():
		return false
	if _distance_to_home() > home_leash:
		return false
	if state == State.FOLLOW:
		return _interest > 0.05
	if _follow_cooldown > 0.0:
		return false
	if _player_distance() > follow_radius:
		return false
	return _interest >= interest_threshold and _player_speed() > 0.25


func _player_on_foot() -> bool:
	return _player != null and is_instance_valid(_player) and not _player_mounted()


func _player_mounted() -> bool:
	return _player != null and is_instance_valid(_player) and bool(_player.get("mounted"))


func _player_distance() -> float:
	if _player == null or not is_instance_valid(_player):
		return 999.0
	return _horizontal_distance(_player.global_position)


func _horse_distance() -> float:
	if _horse == null or not is_instance_valid(_horse):
		return 999.0
	return _horizontal_distance(_horse.global_position)


func _distance_to_home() -> float:
	return _horizontal_distance(_home)


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length()


func _player_speed() -> float:
	return Vector2(_player_vel_est.x, _player_vel_est.z).length()


func _player_velocity() -> Vector3:
	return _player_vel_est


func _horse_speed() -> float:
	if _horse is CharacterBody3D:
		var horse_velocity := (_horse as CharacterBody3D).velocity
		return Vector2(horse_velocity.x, horse_velocity.z).length()
	return 0.0


func _planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)


func _steer_to(target: Vector3, speed: float, delta: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	_move_along_facing(to_target, speed, delta)


## Travel where the nose points: turn toward `direction`, then move along the
## body's own heading.  Aiming the velocity straight at the target while the
## body was still swinging round is what made the dog slide sideways.
func _move_along_facing(direction: Vector3, speed: float, delta: float) -> void:
	var wanted := direction
	wanted.y = 0.0
	if wanted.length_squared() < 0.0001:
		_stop(delta)
		return
	wanted = wanted.normalized()
	if _avoid_weight > 0.1:
		wanted = (wanted + _avoid_dir * _avoid_weight * 1.6).normalized()
	_face_direction(wanted, delta)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		_stop(delta)
		return
	forward = forward.normalized()
	# Slow down while the body is still swinging round, and pivot on the spot
	# once the target sits well off the nose.
	var throttle := clampf((forward.dot(wanted) - 0.2) / 0.6, 0.0, 1.0)
	var goal := speed * throttle
	velocity.x = move_toward(velocity.x, forward.x * goal, acceleration * delta)
	velocity.z = move_toward(velocity.z, forward.z * goal, acceleration * delta)


func _face_point(point: Vector3, delta: float, rate := -1.0) -> void:
	_face_direction(point - global_position, delta, rate)


func _face_direction(direction: Vector3, delta: float, rate := -1.0) -> void:
	var flat := direction
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	var turn_rate := turn_speed if rate < 0.0 else rate
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_rate * delta, 0.0, 1.0))


## Stepping out of the horse's way is steering, not a shove: the outward
## direction is folded into the next movement so the dog still steps aside
## nose-first instead of being pushed sideways.
func _apply_horse_avoidance(delta: float) -> void:
	if _horse == null or not is_instance_valid(_horse):
		_avoid_weight = 0.0
		return
	var away := global_position - _horse.global_position
	away.y = 0.0
	var distance := away.length()
	if distance >= 1.8 or _horse_speed() <= 0.5:
		_avoid_weight = move_toward(_avoid_weight, 0.0, delta * 2.5)
		return
	if distance < 0.001:
		away = Vector3.RIGHT
	_avoid_dir = away.normalized()
	_avoid_weight = clampf((1.8 - distance) / 0.9, 0.0, 1.0)


func _check_stuck(delta: float, before: Vector3) -> void:
	var intended := _planar_speed()
	var moved := global_position.distance_to(before)
	# Judge progress against the ground this frame's speed should have covered.
	# A flat 2 cm threshold counted a 0.7 m/s walk (1.2 cm a frame) as stuck, so
	# the dog gave up while it was still walking home.
	if intended > 0.25 and delta > 0.0 and moved < intended * delta * 0.25:
		_stuck_time += delta
		if _stuck_time > 1.0:
			_stuck_time = 0.0
			if state == State.WANDER:
				_pick_wander_target()
			else:
				_change_state(State.IDLE)
	else:
		_stuck_time = 0.0


func get_state_name() -> String:
	return STATE_NAMES[state]


func get_home_position() -> Vector3:
	return _home


func is_prompt_visible() -> bool:
	return prompt != null and prompt.visible


func debug_force_state(state_name: String) -> bool:
	var index := STATE_NAMES.find(state_name.to_lower())
	if index < 0:
		return false
	if index == state:
		_state_time = 0.0
		_use_locomotion = false
		_desired_pose = ""
		_enter_state(state)
	else:
		_change_state(index)
	return true


func debug_set_needs(
	hunger_value := -1.0,
	energy_value := -1.0,
	affection_value := -1.0,
	boredom_value := -1.0
) -> void:
	if hunger_value >= 0.0:
		hunger = clampf(hunger_value, 0.0, 1.0)
	if energy_value >= 0.0:
		energy = clampf(energy_value, 0.0, 1.0)
	if affection_value >= 0.0:
		affection = clampf(affection_value, 0.0, 1.0)
	if boredom_value >= 0.0:
		boredom = clampf(boredom_value, 0.0, 1.0)


## A bowl the player can aim at and use to feed the dog.  Built beside the
## bowl spot so the aim ray meets a real collider (layer 4) on the bowl.
func _add_feed_target() -> void:
	if get_parent() == null or _bowl_spot == null:
		return
	var target := Node3D.new()
	target.name = "FeedTarget"
	target.set_script(load("res://scripts/interactable.gd"))
	target.set("prompt_label", "FEED")
	target.set("body_reach", 1.6)
	target.set("action_target", self)
	target.set("action_method", "feed")
	target.position = _bowl_spot.position + Vector3(0.0, 0.25, 0.0)
	var body := StaticBody3D.new()
	body.name = "FeedCollision"
	body.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.4, 0.45)
	shape.shape = box
	body.add_child(shape)
	target.add_child(body)
	get_parent().add_child(target)


## Fills the bowl: the dog comes to eat, as if it were hungry.
func feed() -> bool:
	if _player != null and _player_mounted():
		return false
	hunger = maxf(hunger, eat_hunger)
	_change_state(State.EAT)
	return true


func debug_think() -> void:
	_think()


func debug_set_interest(value: float) -> void:
	_interest = clampf(value, 0.0, 1.0)


func debug_set_follow_elapsed(seconds: float) -> void:
	_follow_elapsed = seconds
