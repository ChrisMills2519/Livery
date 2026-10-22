extends Node

## Input-mode profile.  Decides whether the game speaks in keyboard prompts or
## touch prompts, and tells the touch layer whether to show itself.
##
## Resolution order (first match wins):
##   1. Runtime override: F3 in debug builds, or set_touch_mode() from code.
##   2. ?touch=1 / ?touch=0 in the web build's URL.
##   3. GROOM_TOUCH=1 / GROOM_TOUCH=0 environment variable.
##   4. DisplayServer.is_touchscreen_available() or the "mobile" OS feature.
##
## Keyboard prompt text must stay byte-identical to the strings it replaces,
## so the existing desktop checks keep matching.

signal mode_changed(is_touch: bool)

## -1 = no runtime override, 0 = keyboard, 1 = touch.
var _override := -1
var _env_override := -1
var _auto_touch := false
var _is_touch := false


func _ready() -> void:
	var requested := _web_query_override()
	if requested == "":
		requested = OS.get_environment("GROOM_TOUCH").strip_edges()
	if requested == "1":
		_env_override = 1
	elif requested == "0":
		_env_override = 0
	_auto_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_is_touch = _resolve()


## True when prompts and controls should be written for a finger rather than a
## keyboard.
func is_touch() -> bool:
	return _is_touch


## Forces the mode from code (tests, debug tools).  Pass -1 to clear the
## override and fall back to the environment and auto-detection.
func set_touch_mode(on: int) -> void:
	_override = on
	_refresh()


## Keyboard text when on a keyboard, touch text when on a touchscreen.
func pick(keyboard_text: String, touch_text: String) -> String:
	return touch_text if _is_touch else keyboard_text


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		set_touch_mode(0 if _is_touch else 1)
		get_viewport().set_input_as_handled()


## The exported web build has no F3 (that path is debug-only), so a browser can
## ask for a mode in the URL: index.html?touch=1 or ?touch=0.
func _web_query_override() -> String:
	if not OS.has_feature("web"):
		return ""
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return "" if search == null else _parse_touch_query(str(search))


## Split out from the JavaScript bridge so the parsing can be checked natively.
## Anything other than a clean 0 or 1 is ignored, as is a missing ``touch``.
func _parse_touch_query(search: String) -> String:
	var query := search.strip_edges()
	if query.begins_with("?"):
		query = query.substr(1)
	for pair in query.split("&", false):
		var parts := pair.split("=", true, 1)
		if parts.size() == 2 and parts[0].strip_edges() == "touch":
			var mode := parts[1].strip_edges()
			return mode if mode == "0" or mode == "1" else ""
	return ""


func _resolve() -> bool:
	if _override != -1:
		return _override == 1
	if _env_override != -1:
		return _env_override == 1
	return _auto_touch


func _refresh() -> void:
	var before := _is_touch
	_is_touch = _resolve()
	if _is_touch != before:
		mode_changed.emit(_is_touch)
