extends CanvasLayer

## Persistent screen fader used for the character-select -> game handoff.
##
## This is a small explicit state machine rather than a chain of awaits: the
## scene change frees the scene that started the transition, and the autoload
## must keep running across that swap.  It fades to the cover, swaps scenes,
## holds through the synchronous load, then fades the new scene in.

const COVER_COLOR := Color(0.012, 0.022, 0.016, 1.0)
const HOLD_SECONDS := 0.08

enum Phase { IDLE, OUT, HOLD, IN }

var _cover: ColorRect
var _phase := Phase.IDLE
var _alpha := 0.0
var _duration := 0.4
var _hold := 0.0
var _target := ""


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.name = "Cover"
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.color = COVER_COLOR
	_cover.modulate.a = 0.0
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	add_child(_cover)


func change_scene(path: String, duration := 0.4) -> void:
	if _phase != Phase.IDLE:
		return
	_target = path
	_duration = maxf(duration, 0.01)
	_hold = 0.0
	_phase = Phase.OUT
	_cover.visible = true
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_alpha(0.0)


func is_transitioning() -> bool:
	return _phase != Phase.IDLE


func _process(delta: float) -> void:
	match _phase:
		Phase.OUT:
			_set_alpha(_alpha + delta / _duration)
			if _alpha >= 1.0:
				var err := get_tree().change_scene_to_file(_target)
				if err != OK:
					push_error("SceneFade: cannot change to %s (error %d)" % [_target, err])
					_phase = Phase.IN
					_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
				else:
					# The load is synchronous, so this delay is only a beat to
					# let the new scene run its first frame under the cover.
					_phase = Phase.HOLD
					_hold = 0.0
		Phase.HOLD:
			_hold += delta
			if _hold >= HOLD_SECONDS:
				_phase = Phase.IN
				_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Phase.IN:
			_set_alpha(_alpha - delta / _duration)
			if _alpha <= 0.0:
				_target = ""
				_phase = Phase.IDLE
				_cover.visible = false


func _set_alpha(value: float) -> void:
	_alpha = clampf(value, 0.0, 1.0)
	_cover.modulate.a = _alpha
