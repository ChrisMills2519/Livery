extends CanvasLayer

## On-screen touch layer for phones and tablets.
##
## Godot's touch-to-mouse emulation only follows the first finger, so this layer
## tracks every finger itself.  That is what lets a left thumb hold the stick
## while a right thumb taps JUMP.  Touches that land on a real Control (tool row,
## DONE, character cards, ...) are left alone so Godot's emulated click reaches
## the button.
##
## Gameplay reads the state through getters instead of Input actions, because
## the stick is analog and the project's move_* actions use a 0.5 deadzone.  The
## cluster buttons and run do dispatch real InputEventAction presses, so the
## existing _unhandled_input handlers keep working unchanged.
##
## Modes: "off", "ride" (stick, look and cluster), "groom" (gestures only),
## "select" (swipe only).

const STICK_RADIUS := 120.0
## These two only gate the on-foot sprint now.  The horse's gait comes from the
## stick's magnitude and the gallop button, never from the ring's run threshold.
const RUN_ENTER := 0.80
const RUN_EXIT := 0.70
## Kept in step with horse.gd's STEER_DEADZONE and TROT_NOTCH: the ring shows
## the gait the ride will actually take, through the same classifier.
const GAIT_DEADZONE := 0.15
const TROT_NOTCH := 0.70
## How near the canonical thumb rest a landing has to be before the stick snaps
## to it.  The ring then sits where the thumb naturally rests instead of
## wherever the first touch of the session happened to land, which is what made
## a slightly-high press bias every push.  A landing further away keeps its own
## point: the ownership rules in agents.md depend on knowing where that finger
## went down, and a cancelled iOS touch has to stay claimable there.
const STICK_SNAP := 28.0
## Fraction of the mouse look rate a finger drag applies.  On foot movement is
## camera-relative, so at 1:1 dragging to look also re-aims the character's
## heading and the view spins; that is why the walking gain is damped.
const LOOK_GAIN := 0.55
## Mounted, a drag only moves a look offset that decays back behind the horse
## (PlayerController._look), so it can run at the full mouse rate.  The damped
## value is what made looking around from the saddle feel sluggish.
const LOOK_GAIN_MOUNTED := 1.0
## How far the stick finger may sit from its anchor and still count as resting
## (a palm, or a thumb that has not pushed yet).
const STICK_REST := 10.0
const ORBIT_GAIN := 0.5
const CONTEXT_REFRESH := 0.1
const BUTTON_SLOP := 8.0
## How far the thumb must push before the stick counts as steering.  Below this
## it is a resting finger, not a direction.
const STICK_PUSH := 0.12
## How long a stick holder may go without reporting before another thumb may take
## the stick from it.  iOS Safari cancels a touch instead of ending it (the edge
## back-swipe, its toolbar moving, a system gesture, palm rejection) and Godot's
## web input has no event for that, so the touch-up never arrives: the finger is
## gone while `_stick_index` still points at it.  Without this window that stale
## holder locks every later left-half press out of the stick for the rest of the
## scene, which is the "left stick does nothing" fault on the phone.
const STICK_STALE_MS := 250
## A two-finger gesture only zooms once the gap has changed by this fraction
## from where the second finger landed.  Below it the gesture is pure orbit, so
## wrist wobble cannot drag the camera in and out while turning the horse.
const PINCH_TRIGGER := 0.10

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.86, 0.90, 0.80, 0.42)
const ACCENT := Color(0.72, 1.0, 0.62, 1.0)
const RUN_COLOR := Color(1.0, 0.82, 0.36, 1.0)
const BUTTON_FILL := Color(0.06, 0.09, 0.06, 0.62)
const DISABLED_TEXT := Color(0.8, 0.8, 0.8, 0.35)

var mode := "off"

var _overlay: Control
var _fingers: Dictionary = {}
## Index of the finger that owns the stick.  Only meaningful while `_stick_owned`
## is true: iOS Safari's touch identifiers keep climbing for the life of the page
## and overflow into a negative int32 (a real device reported -410517893), so the
## value itself says nothing about ownership.
var _stick_index := -1
## True while a finger actually owns the stick.  The id alone cannot carry that
## meaning: `-1` is not the only "no stick" value a device can produce, so
## `_stick_index < 0` was true for a live stick on iOS, which made
## `get_move_input()` return bare keyboard input and left the walk and the horse
## with nothing to move on.
var _stick_owned := false
var _stick_base := Vector2.ZERO
var _stick_offset := Vector2.ZERO
## When the stick holder last claimed or dragged, in msec.  A holder that has
## gone quiet is not necessarily dead (a thumb can hold a straight line without
## moving), so this is only trusted together with a new press, and the takeover
## it allows is a re-anchor, not a turn.
var _stick_seen_ms := 0
var _move := Vector2.ZERO
var _running := false
## True while the player is in the saddle, which is when the look drag is an
## offset rather than a heading and the full gain is safe.
var _mounted := false
var _look_accum := Vector2.ZERO
var _orbit_accum := Vector2.ZERO
var _pinch_ratio := 1.0
var _pair_distance := 0.0
var _pair_start := 0.0
var _pinching := false
var _swipe_accum := 0.0
var _paint_active := false
var _paint_pos := Vector2.ZERO
var _paint_started := false
var _held_buttons: Dictionary = {}
var _context := {"action": "", "label": "—", "priority": -1}
var _context_timer := 0.0


func _ready() -> void:
	layer = 30
	_overlay = Control.new()
	_overlay.name = "TouchOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	Device.mode_changed.connect(_on_mode_changed)
	visible = false


func _process(delta: float) -> void:
	if not is_active():
		return
	# A stick index whose finger is no longer tracked can only be a stale holder.
	# Dropping it here means no lost event can leave the stick pointed at nothing.
	if _stick_owned and not _fingers.has(_stick_index):
		_reset_stick()
	_context_timer -= delta
	if _context_timer <= 0.0:
		_context_timer = CONTEXT_REFRESH
		_refresh_context()
	if mode == "groom":
		# Sampled once a frame, after both thumbs have reported, so moving them
		# one after the other is not mistaken for a squeeze.
		_update_pinch()
	_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if feed_touch(touch.index, touch.position, touch.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if feed_drag(drag.index, drag.position, drag.relative):
			get_viewport().set_input_as_handled()


## True when the layer is steering input: a touch device and a mode other than
## "off".
func is_active() -> bool:
	return Device.is_touch() and mode != "off"


func set_mode(new_mode: String) -> void:
	mode = new_mode
	_release_all()
	visible = is_active()


# --- Public state read by gameplay -------------------------------------------

## Keyboard axis plus the analog stick, clamped to unit length.  The stick is
## only live in "ride" mode.
func get_move_input() -> Vector2:
	var keys := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if not is_active() or not _stick_owned:
		return keys
	return (keys + _move).limit_length(1.0)


## Accumulated look drag since the last call, in the same pixel units as a mouse
## motion event.
func consume_look() -> Vector2:
	var out := _look_accum * (LOOK_GAIN_MOUNTED if _mounted else LOOK_GAIN)
	_look_accum = Vector2.ZERO
	return out


## Set by the player on mounting and dismounting: the mounted camera takes a
## look offset instead of a heading, so its drag can run at the mouse rate.
func set_mounted(value: bool) -> void:
	_mounted = value
	_look_accum = Vector2.ZERO


func consume_orbit() -> Vector2:
	var out := _orbit_accum
	_orbit_accum = Vector2.ZERO
	return out


## Multiplicative zoom factor from a pinch since the last call.  Above 1 means
## the camera should pull back; below 1 means it should come in.
func consume_pinch() -> float:
	var out := _pinch_ratio
	_pinch_ratio = 1.0
	return out


func consume_swipe() -> float:
	var out := _swipe_accum
	_swipe_accum = 0.0
	return out


## True once for each new single-finger paint stroke, so the caller can break
## the stroke before painting again.
func consume_paint_started() -> bool:
	var out := _paint_started
	_paint_started = false
	return out


func is_painting() -> bool:
	return _paint_active


## True while a finger is dragging the select-screen turntable.
func is_swiping() -> bool:
	for index in _fingers:
		if String(_fingers[index]["role"]) == "swipe":
			return true
	return false


func paint_position() -> Vector2:
	return _paint_pos


func is_stick_active() -> bool:
	return _stick_owned


## True once the thumb has actually pushed the stick away from its anchor.  A
## finger that merely owns the stick has not asked for a direction yet.
func is_stick_pushing() -> bool:
	return _stick_owned and _move.length() > STICK_PUSH


func is_running() -> bool:
	return _running


## The gait a movement input asks for.  The ride and the on-screen ring both go
## through this one classifier, so the ring cannot promise a gait the horse will
## not take.  `stick_driving` is true while a thumb owns the stick, which is when
## the input's magnitude - rather than a key - decides walk or trot.
func gait_for(input: Vector2, stick_driving: bool, keyboard_trot: bool, gallop: bool) -> String:
	var forward := -input.y
	if forward <= GAIT_DEADZONE:
		return "halt"
	if gallop:
		return "canter"
	if stick_driving:
		var magnitude := clampf((forward - GAIT_DEADZONE) / (1.0 - GAIT_DEADZONE), 0.0, 1.0)
		return "trot" if magnitude > TROT_NOTCH else "walk"
	return "trot" if keyboard_trot else "walk"


## What the stick is asking for right now, for the ring and the debug readout.
func stick_gait() -> String:
	if not _stick_owned:
		return "halt"
	return gait_for(_move, true, false, Input.is_action_pressed("gallop"))


## Current context action and label shown on the big CONTEXT button.
func context_action() -> String:
	return String(_context.get("action", ""))


func context_label() -> String:
	return String(_context.get("label", ""))


# --- Finger routing ----------------------------------------------------------

## Returns true when the touch belongs to the layer and must not reach the GUI
## or gameplay input.
func feed_touch(index: int, pos: Vector2, pressed: bool) -> bool:
	if not is_active():
		return false
	if pressed:
		return _touch_down(index, pos)
	return _touch_up(index)


## Returns true when the drag belongs to the layer.
func feed_drag(index: int, pos: Vector2, relative: Vector2) -> bool:
	if not is_active() or not _fingers.has(index):
		return false
	var finger: Dictionary = _fingers[index]
	finger["pos"] = pos
	match String(finger["role"]):
		"stick":
			_update_stick(pos)
		"look":
			_look_accum += relative
		"paint":
			_paint_pos = pos
		"orbit":
			_orbit_accum += relative * ORBIT_GAIN
		"swipe":
			_swipe_accum += relative.x
		"idle":
			_try_push_reclaim(index, pos)
		_:
			pass
	return true


func _touch_down(index: int, pos: Vector2) -> bool:
	if _fingers.has(index):
		# The release for this finger was lost (app switch, a dropped event).
		# The new press wins instead of leaving a stale role wedged in place.
		_touch_up(index)
	var button: Dictionary = _button_at(pos) if mode == "ride" else {}
	if not button.is_empty():
		var action := _action_for(String(button["id"]))
		_fingers[index] = {"role": "button", "id": button["id"], "action": action, "pos": pos}
		_held_buttons[String(button["id"])] = true
		if not action.is_empty():
			_send_action(action, true)
		return true
	if _is_ui_at(pos):
		return false
	match mode:
		"ride":
			if pos.x < get_viewport().get_visible_rect().size.x * 0.5:
				if _stick_is_available():
					# No holder, a holder that never pushed, or one whose touch-up
					# was lost, so the thumb that just landed takes the stick.
					_claim_stick(index, pos)
				else:
					# A live thumb owns the stick.  Remember where this finger
					# landed so its own push can take over once that owner goes
					# quiet, instead of it being stuck as a passenger.
					_fingers[index] = {"role": "idle", "pos": pos, "down": pos}
			else:
				_fingers[index] = {"role": "look", "pos": pos}
			return true
		"groom":
			return _groom_touch_down(index, pos)
		"select":
			_fingers[index] = {"role": "swipe", "pos": pos}
			return true
	return false


func _groom_touch_down(index: int, pos: Vector2) -> bool:
	# Fingers already doing something in the groom view: a stroke or an orbit.
	var engaged := 0
	for other in _fingers:
		var role := String(_fingers[other]["role"])
		if role == "paint" or role == "orbit":
			engaged += 1
	if engaged >= 2:
		_fingers[index] = {"role": "idle", "pos": pos}
		return true
	if engaged == 1:
		# A second finger turns the stroke into a two-finger orbit and pinch.
		_paint_active = false
		for other in _fingers:
			if String(_fingers[other]["role"]) == "paint":
				_fingers[other]["role"] = "orbit"
		_fingers[index] = {"role": "orbit", "pos": pos}
		_begin_pinch_pair()
		return true
	# The first finger of a stroke: it paints or becomes a two-finger gesture.
	_fingers[index] = {"role": "paint", "pos": pos}
	_paint_active = true
	_paint_pos = pos
	_paint_started = true
	return true


func _touch_up(index: int) -> bool:
	if not _fingers.has(index):
		return false
	var finger: Dictionary = _fingers[index]
	_fingers.erase(index)
	match String(finger["role"]):
		"button":
			var id := String(finger["id"])
			_held_buttons.erase(id)
			var action := String(finger["action"])
			if not action.is_empty():
				_send_action(action, false)
		"stick":
			# Only the finger that owns the stick may release it.  A touch-up from
			# a holder that was already demoted (its release was lost and another
			# thumb took over) must not kill the stick that replaced it.
			if _stick_owned and index == _stick_index:
				_reset_stick()
				_adopt_idle_stick()
		"paint":
			_paint_active = false
		"orbit":
			_paint_active = false
			_pair_distance = 0.0
			_pair_start = 0.0
			_pinching = false
			for other in _fingers:
				if String(_fingers[other]["role"]) == "orbit":
					_fingers[other]["role"] = "idle"
	return true


func _release_all() -> void:
	for index in _fingers.keys():
		_touch_up(index)
	_fingers.clear()
	_held_buttons.clear()
	_reset_stick()
	_look_accum = Vector2.ZERO
	_orbit_accum = Vector2.ZERO
	_swipe_accum = 0.0
	_pinch_ratio = 1.0
	_pair_start = 0.0
	_pinching = false
	_paint_active = false
	_set_run(false)


func _on_mode_changed(_is_touch: bool) -> void:
	set_mode(mode)


func _notification(what: int) -> void:
	# Backgrounding the app can swallow the touch-up events, which would leave a
	# finger index and the stick wedged until the next scene change.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()
	elif what == NOTIFICATION_WM_SIZE_CHANGED:
		# Safari's toolbar sliding in and out resizes the canvas, and iOS cancels
		# the in-flight touches around it.  Dropping them here makes the next press
		# start clean instead of landing beside a holder that is already gone.
		_release_all()


# --- Stick and run -----------------------------------------------------------

## Arms the stick on `index`, taking it away from whatever finger held it.
func _claim_stick(index: int, pos: Vector2) -> void:
	# Exactly one finger may carry the stick role, so a holder left behind by a
	# lost touch-up is demoted here instead of staying a second owner.  Its
	# landing point is kept as an anchor, so if it is a live thumb it can claim
	# the stick back with a push of its own.
	for other in _fingers:
		if other == index or String(_fingers[other]["role"]) != "stick":
			continue
		_fingers[other]["role"] = "idle"
		if not _fingers[other].has("down"):
			_fingers[other]["down"] = _fingers[other]["pos"]
	_stick_index = index
	_stick_owned = true
	_stick_base = pos
	# A landing on the thumb's natural rest snaps to it, so the ring sits where
	# the thumb already is.  A landing anywhere else keeps its own point.
	var rest := stick_rest_anchor()
	if pos.distance_to(rest) <= STICK_SNAP:
		_stick_base = rest
	_stick_offset = Vector2.ZERO
	_move = Vector2.ZERO
	_stick_seen_ms = Time.get_ticks_msec()
	_fingers[index] = {"role": "stick", "pos": pos}


## Drops the stick without disturbing any other finger.
func _reset_stick() -> void:
	_stick_index = -1
	_stick_owned = false
	_stick_seen_ms = 0
	_move = Vector2.ZERO
	_stick_offset = Vector2.ZERO
	_set_run(false)


## True when a finger may take the stick from its current holder: nobody holds
## it, the holder is a contact that has not pushed, its entry is gone, or it has
## not reported for STICK_STALE_MS and is therefore a cancelled touch.
func _stick_is_available() -> bool:
	if not _stick_owned:
		return true
	if not _fingers.has(_stick_index):
		return true
	if String(_fingers[_stick_index]["role"]) != "stick":
		return true
	if _stick_offset.length() < STICK_REST:
		return true
	return Time.get_ticks_msec() - _stick_seen_ms > STICK_STALE_MS


## A finger filed "idle" because a live thumb held the stick.  Once it pushes
## past STICK_REST and that holder has gone quiet, the push takes over.  This is
## the other half of recovering a cancelled touch: the new press can arrive while
## the stale holder still looks live, and the push arrives after it timed out.
func _try_push_reclaim(index: int, pos: Vector2) -> void:
	var finger: Dictionary = _fingers[index]
	var anchor: Vector2 = finger.get("down", pos)
	if pos.distance_to(anchor) <= STICK_REST:
		return
	if not _stick_is_available():
		return
	_claim_stick(index, anchor)
	_update_stick(pos)


## Where the left thumb naturally rests, inside the bottom-left safe area.
func stick_rest_anchor() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	var insets := _safe_insets(size)
	return Vector2(insets.x + STICK_RADIUS + 40.0, size.y - insets.w - STICK_RADIUS - 24.0)


## Hands the stick to a finger already resting in the stick half, so lifting one
## thumb while the other is down does not leave the stick dead.
func _adopt_idle_stick() -> void:
	if mode != "ride":
		return
	if _stick_owned:
		if _fingers.has(_stick_index):
			return
		_reset_stick()
	var half := get_viewport().get_visible_rect().size.x * 0.5
	for other in _fingers:
		if String(_fingers[other]["role"]) != "idle":
			continue
		var pos: Vector2 = _fingers[other]["pos"]
		if pos.x < half:
			_claim_stick(other, pos)
			return


func _update_stick(pos: Vector2) -> void:
	_stick_seen_ms = Time.get_ticks_msec()
	_stick_offset = pos - _stick_base
	_move = (_stick_offset / STICK_RADIUS).limit_length(1.0)
	var strength := _stick_offset.length() / STICK_RADIUS
	if not _running and strength >= RUN_ENTER:
		_set_run(true)
	elif _running and strength < RUN_EXIT:
		_set_run(false)


func _set_run(on: bool) -> void:
	if _running == on:
		return
	_running = on
	_send_action("run", on)


# --- Pinch and orbit ---------------------------------------------------------

func _orbit_pair_distance() -> float:
	var points: Array[Vector2] = []
	for other in _fingers:
		if String(_fingers[other]["role"]) == "orbit":
			points.append(_fingers[other]["pos"])
	if points.size() < 2:
		return 0.0
	return points[0].distance_to(points[1])


## Records the gap between the two orbit fingers when the gesture forms.
func _begin_pinch_pair() -> void:
	_pair_distance = _orbit_pair_distance()
	_pair_start = _pair_distance
	_pinching = false


func _update_pinch() -> void:
	var distance := _orbit_pair_distance()
	if distance <= 0.0 or _pair_distance <= 0.0:
		_pair_distance = distance
		return
	if not _pinching:
		# Deliberate pinch or nothing: an orbit keeps the gap roughly steady.
		if _pair_start <= 0.0 or absf(distance / _pair_start - 1.0) <= PINCH_TRIGGER:
			_pair_distance = distance
			return
		_pinching = true
	# Spreading the fingers gives a ratio below 1, which brings the camera in.
	_pinch_ratio *= _pair_distance / distance
	_pair_distance = distance


# --- Cluster -----------------------------------------------------------------

## Layout of the action buttons in viewport coordinates.  It is derived from the
## viewport size and the display safe area on every call so a rotation or notch
## is picked up without any cache to invalidate.
##
## The three riding buttons sit under the right thumb; LEAD and RESET are out
## along the top edge instead.  Five circles plus a look area under one thumb is
## a mis-tap factory on a tablet, and the two thumbs that matter while riding are
## the left one on the stick and the right one on the camera.
func _cluster() -> Array:
	var size := get_viewport().get_visible_rect().size
	var insets := _safe_insets(size)
	var right := size.x - insets.z - 84.0
	var bottom := size.y - insets.w - 84.0
	var top := insets.y + 44.0
	var buttons := [
		{"id": "context", "center": Vector2(right, bottom), "radius": 62.0, "group": "thumb"},
		{"id": "jump", "center": Vector2(right - 118.0, bottom + 30.0), "radius": 42.0, "group": "thumb"},
		{"id": "lead", "center": Vector2(right - 4.0, top), "radius": 38.0, "group": "strip"},
		{"id": "reset", "center": Vector2(right - 92.0, top), "radius": 38.0, "group": "strip"},
	]
	# The gallop is a riding control, so it is not offered on foot at all.
	if _mounted:
		buttons.append({"id": "gallop", "center": Vector2(right - 118.0, bottom - 74.0), "radius": 46.0, "group": "thumb"})
	return buttons


func button_center(id: String) -> Vector2:
	for def in _cluster():
		if String(def["id"]) == id:
			return def["center"]
	return Vector2.ZERO


func _button_at(pos: Vector2) -> Dictionary:
	for def in _cluster():
		var center: Vector2 = def["center"]
		var radius: float = def["radius"]
		if pos.distance_to(center) <= radius + BUTTON_SLOP:
			return def
	return {}


func _action_for(id: String) -> String:
	match id:
		"context":
			return context_action()
		"jump":
			return "jump"
		"gallop":
			return "gallop"
		"lead":
			return "lead"
		"reset":
			return "restart_round"
	return ""


## Shows what the CONTEXT button will do.  Gameplay nodes in the "touch_context"
## group describe themselves with touch_context(); the highest priority wins.
func _refresh_context() -> void:
	var best := {"action": "", "label": "—", "priority": -1}
	for node in get_tree().get_nodes_in_group("touch_context"):
		if not node.has_method("touch_context"):
			continue
		var candidate: Dictionary = node.call("touch_context")
		if candidate.is_empty():
			continue
		if int(candidate.get("priority", 0)) > int(best["priority"]):
			best = candidate
	_context = best


# --- Input dispatch ----------------------------------------------------------

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


# --- UI overlap --------------------------------------------------------------

## True when a visible Control that swallows mouse input sits under pos.  Used so
## a touch that starts on a real button is left to the button.
func _is_ui_at(pos: Vector2) -> bool:
	return _ui_hit(get_tree().root, pos)


func _ui_hit(node: Node, pos: Vector2) -> bool:
	for child in node.get_children():
		if child == self:
			continue
		if child is Control:
			var control := child as Control
			if control.is_visible_in_tree() \
					and control.mouse_filter == Control.MOUSE_FILTER_STOP \
					and control.get_global_rect().has_point(pos):
				return true
		if _ui_hit(child, pos):
			return true
	return false


# --- Drawing -----------------------------------------------------------------

func _draw_overlay() -> void:
	if not is_active():
		return
	if mode == "ride":
		_draw_stick()
		_draw_cluster()
	if Device.debug_overlay():
		_draw_debug()


## Internal state, only with ?touchdebug=1.  A phone cannot show a console, and
## a stick that does nothing on the device is exactly the case where these
## numbers are the only evidence: which role each finger got, who owns the
## stick, what move is coming out of it, and - on the second line - what the
## player actually received and where the resolved velocity left it.
##
## The player line exists because the touch vector is not the last word.  A body
## that is blocked (or repositioned) still reads as idle: move_and_slide()
## writes the resolved velocity back, so `vel` near zero with `in` non-zero is a
## collision, while `in` at zero is a routing fault.  Reading `pos` over two
## pushes separates "not moving" from "moving with the camera on top of it".
func _draw_debug() -> void:
	var lines := PackedStringArray()
	var parts := PackedStringArray()
	# The pack carries the build string the loading screen shows, so this line
	# proves the page and the pack in play are the same build.
	var build := String(ProjectSettings.get_setting("application/config/version", ""))
	if not build.is_empty():
		parts.append(build)
	parts.append("mode %s" % mode)
	var size := get_viewport().get_visible_rect().size
	parts.append("vp %dx%d" % [int(size.x), int(size.y)])
	parts.append("fps %d" % Engine.get_frames_per_second())
	for index in _fingers:
		parts.append("%d:%s" % [index, String(_fingers[index]["role"])])
	# Printed as-is: a phone's index can be negative, and treating the sign as
	# "no owner" is the bug this readout was added to catch.
	parts.append(("stick %d" % _stick_index) if _stick_owned else "stick -")
	parts.append("move %.2f,%.2f" % [_move.x, _move.y])
	parts.append("gait %s" % stick_gait())
	lines.append("  ".join(parts))
	var body := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if body != null:
		var given := get_move_input()
		lines.append("p ctrl:%d mnt:%d seat:%d air:%d in:%.2f,%.2f vel:%.2f,%.2f pos:%.1f,%.1f" % [
			int(bool(body.get("controls_enabled"))),
			int(bool(body.get("mounted"))),
			int(bool(body.get("seated"))),
			0 if body.is_on_floor() else 1,
			given.x, given.y, body.velocity.x, body.velocity.z,
			body.global_position.x, body.global_position.z,
		])
	var font := ThemeDB.fallback_font
	const FONT_SIZE := 13
	var line_height := FONT_SIZE + 4.0
	# Below the HUD's wallet block and above the thumb's usual resting band, so
	# the readout does not sit under the stick it is describing.  A dark plate
	# keeps it legible where it crosses a HUD prompt.
	var top := 120.0
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	_overlay.draw_rect(
		Rect2(Vector2(8.0, top - FONT_SIZE - 2.0), Vector2(widest + 16.0, line_height * lines.size() + 6.0)),
		Color(0.0, 0.0, 0.0, 0.62)
	)
	var y := top
	for line in lines:
		_overlay.draw_string(
			font,
			Vector2(16.0, y),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			Color(1.0, 1.0, 1.0, 0.95)
		)
		y += line_height


## The ring is the gait readout: dim at a walk, accent at a trot, run-colour at
## a canter, with the one word beside it.  A rider can see what the horse is
## about to do without looking away from it.
func _draw_stick() -> void:
	if not _stick_owned:
		return
	var gait := stick_gait()
	var color := DIM_COLOR
	if gait == "canter":
		color = RUN_COLOR
	elif gait == "trot":
		color = ACCENT
	_overlay.draw_arc(_stick_base, STICK_RADIUS, 0.0, TAU, 64, color, 3.0)
	_overlay.draw_arc(_stick_base, STICK_RADIUS * TROT_NOTCH, 0.0, TAU, 64, Color(color.r, color.g, color.b, 0.22), 2.0)
	var knob := _stick_base + _stick_offset.limit_length(STICK_RADIUS)
	_overlay.draw_circle(knob, 34.0, Color(color.r, color.g, color.b, 0.55))
	var label := _gait_label(gait)
	if not label.is_empty():
		var font := ThemeDB.fallback_font
		var width := STICK_RADIUS * 2.0
		_overlay.draw_string(
			font,
			_stick_base + Vector2(-STICK_RADIUS, STICK_RADIUS + 28.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			width,
			15,
			color
		)


func _gait_label(gait: String) -> String:
	match gait:
		"walk":
			return "WALK"
		"trot":
			return "TROT"
		"canter":
			return "CANTER"
	return ""


func _draw_cluster() -> void:
	var font := ThemeDB.fallback_font
	for def in _cluster():
		var id := String(def["id"])
		var center: Vector2 = def["center"]
		var radius: float = def["radius"]
		var label := _label_for(id)
		var enabled := label != "—" and not label.is_empty()
		_overlay.draw_circle(center, radius, BUTTON_FILL)
		var held := _held_buttons.has(id)
		var ring := ACCENT if held else DIM_COLOR
		_overlay.draw_arc(center, radius, 0.0, TAU, 48, ring, 3.0 if held else 2.0)
		var text_color := TEXT_COLOR if enabled else DISABLED_TEXT
		var size := 18 if id == "context" else 14
		var text_width := radius * 2.0
		_overlay.draw_string(font, center + Vector2(-text_width * 0.5, size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, text_width, size, text_color)


func _label_for(id: String) -> String:
	match id:
		"context":
			return context_label()
		"jump":
			return "JUMP"
		"gallop":
			return "GALLOP"
		"lead":
			return "LEAD"
		"reset":
			return "RESET"
	return ""


## Insets (left, top, right, bottom) in viewport units, from the display safe
## area.  Zero on desktops and when the platform reports no safe area.
func _safe_insets(size: Vector2) -> Vector4:
	var screen := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var scale := size / screen
	var left := float(safe.position.x) * scale.x
	var top := float(safe.position.y) * scale.y
	var right := (screen.x - float(safe.end.x)) * scale.x
	var bottom := (screen.y - float(safe.end.y)) * scale.y
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))
