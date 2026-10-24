extends CanvasLayer

signal logo_pressed

## Minimal gameplay HUD for the schooling-round loop.
##
## Everything is built in code so the scene file stays small.  The HUD only
## reads state from the course, the horse and the GameState autoload; it never
## changes the simulation.

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.78, 0.82, 0.74, 1.0)
const ACCENT := Color(0.72, 1.0, 0.62, 1.0)
const LiveryLogoButton := preload("res://scripts/livery_logo_button.gd")

var _course: Node
var _horse: Node3D
var _player: Node3D

var _money_label: Label
var _skill_label: Label
var _best_label: Label
var _rosette_label: Label
var _objective_label: Label
var _timer_label: Label
var _progress_label: Label
var _toast_label: Label
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _controls_hint: Label
var _toast_tween: Tween


func _ready() -> void:
	add_to_group("gameplay_hud")
	Device.mode_changed.connect(func(_on: bool) -> void: _apply_input_hints())
	layer = 10
	_build_ui()
	call_deferred("_bind")


func _bind() -> void:
	_course = get_tree().get_first_node_in_group("riding_course")
	_horse = get_tree().get_first_node_in_group("horse") as Node3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _course != null:
		_course.round_started.connect(_on_round_started)
		_course.jump_cleared.connect(_on_jump_cleared)
		_course.round_finished.connect(_on_round_finished)
		_course.round_reset.connect(_on_round_reset)
		_course.notice.connect(_show_toast)
	GameState.money_changed.connect(func(_m): _refresh_stats())
	GameState.best_time_changed.connect(func(_t): _refresh_stats())
	GameState.rosettes_changed.connect(func(_n): _refresh_stats())
	_refresh_stats()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-left: wallet and horse progress.
	var stats := VBoxContainer.new()
	stats.position = Vector2(24, 18)
	stats.add_theme_constant_override("separation", 2)
	root.add_child(stats)
	_money_label = _label(stats, "£0", 27, ACCENT)
	_skill_label = _label(stats, "Jumping 1.0 / 10", 17, DIM_COLOR)
	_best_label = _label(stats, "Best round —", 17, DIM_COLOR)
	_rosette_label = _label(stats, "", 17, Color(1.0, 0.86, 0.52))
	_rosette_label.visible = false

	# Top-centre: objective, timer and fence progress.
	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.offset_top = 16
	centre.add_theme_constant_override("separation", 2)
	root.add_child(centre)
	_objective_label = _label(centre, "", 25, TEXT_COLOR)
	_timer_label = _label(centre, "", 34, ACCENT)
	_progress_label = _label(centre, "", 18, DIM_COLOR)

	# Toast sits just under the objective.
	var toast_slot := VBoxContainer.new()
	toast_slot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_slot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_slot.offset_top = 118
	toast_slot.add_theme_constant_override("separation", 0)
	root.add_child(toast_slot)
	_toast_label = _label(toast_slot, "", 22, Color(1.0, 0.93, 0.56, 1.0))
	_toast_label.modulate.a = 0.0

	# Result card, hidden until a round ends.
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.custom_minimum_size = Vector2(420, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.07, 0.90)
	style.border_color = Color(0.48, 0.72, 0.42, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_result_panel.add_theme_stylebox_override("panel", style)
	_result_panel.name = "ResultCard"
	_result_panel.visible = false
	root.add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 8)
	_result_panel.add_child(result_box)
	_result_title = _label(result_box, "ROUND COMPLETE", 30, ACCENT)
	_result_title.name = "ResultTitle"
	_result_body = _label(result_box, "", 20, TEXT_COLOR)
	var hint := _label(result_box, "Clear a fence to go again", 15, DIM_COLOR)
	hint.name = "Hint"

	var logo := LiveryLogoButton.new()
	logo.name = "LiveryLogoButton"
	root.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	logo.offset_left = -24.0 - LiveryLogoButton.BASE_SIZE.x
	logo.offset_right = -24.0
	logo.offset_top = 18.0
	logo.offset_bottom = 18.0 + LiveryLogoButton.BASE_SIZE.y
	logo.logo_pressed.connect(_on_logo_pressed)

	var controls := _label(root, "", 15, DIM_COLOR)
	_controls_hint = controls
	_apply_input_hints()
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls.offset_left = 24
	controls.offset_bottom = -18


## Keyboard and touch control summaries.  Keyboard text is unchanged.
func _apply_input_hints() -> void:
	if _controls_hint == null:
		return
	_controls_hint.text = Device.pick(
		"WASD move   ·   Shift trot / canter   ·   Space jump   ·   E mount / interact   ·   R reset rails   ·   F lead   ·   Q pet",
		"Left stick move   ·   Push far to trot / canter   ·   Right drag look   ·   CONTEXT act   ·   JUMP   ·   LEAD   ·   RESET"
	)


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.02, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	if _course == null:
		return
	_refresh_stats()
	_update_objective()
	_update_course_text()


func _refresh_stats() -> void:
	_money_label.text = "£%d" % GameState.money
	if _horse != null:
		var skill: float = _horse.get("jumping_skill") if _horse.get("jumping_skill") != null else 1.0
		_skill_label.text = "Jumping  %.1f / 10" % skill
	if GameState.best_round_time > 0.0:
		_best_label.text = "Best round  %.1fs" % GameState.best_round_time
	else:
		_best_label.text = "Best round  —"
	if _rosette_label != null:
		var count := GameState.rosettes.size()
		_rosette_label.visible = count > 0
		_rosette_label.text = "Rosettes  %d" % count


func _update_objective() -> void:
	if _course.has_method("get_objective_text"):
		_objective_label.text = String(_course.call("get_objective_text"))
		return
	var mounted: bool = _player != null and _player.get("mounted") == true
	match _course.state:
		"running":
			_objective_label.text = "Clear all %d fences" % _course.get_jump_count()
		"finished":
			_objective_label.text = "Round complete"
		_:
			if mounted:
				_objective_label.text = "Jump a fence to start a round"
			elif _horse != null and _horse.get("boarded") == true:
				_objective_label.text = "Your horse is stabled - press E at the stable door"
			else:
				_objective_label.text = Device.pick("Walk to your horse and press E to mount or F to lead", "Walk to your horse, then tap CONTEXT to mount or LEAD to take the rope")


func _update_course_text() -> void:
	match _course.state:
		"running":
			_timer_label.text = "%.1fs" % _course.elapsed
			var f: int = _course.get("faults") if _course.get("faults") != null else 0
			if f > 0:
				_progress_label.text = "Fences  %d / %d   ·   Faults: %d" % [_course.cleared_count, _course.get_jump_count(), f]
			else:
				_progress_label.text = "Fences  %d / %d   ·   0 Faults (Clear)" % [_course.cleared_count, _course.get_jump_count()]
			_timer_label.visible = true
			_progress_label.visible = true
		"finished":
			_timer_label.visible = false
			_progress_label.visible = false
		_:
			_timer_label.visible = false
			_progress_label.visible = false


func _on_logo_pressed() -> void:
	logo_pressed.emit()


func _on_round_started() -> void:
	_result_panel.visible = false


func _on_jump_cleared(_index: int, cleared: int, total: int) -> void:
	_progress_label.text = "Fences cleared  %d / %d" % [cleared, total]


func _on_round_finished(result: Dictionary) -> void:
	# The result card carries the message; clear the toast so the two do not
	# overlap over the card.
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.modulate.a = 0.0
	_toast_label.text = ""
	var cleared: int = result.get("clears", 0)
	var total: int = result.get("total", 8)
	var seconds: float = result.get("seconds", 0.0)
	var reward: int = result.get("reward", 0)
	var timed_out: bool = result.get("timed_out", false)
	var faults: int = result.get("faults", 0)
	var is_clear_round: bool = result.get("clear_round", false)

	if result.get("show_class", false):
		_show_class_result(result)
		return

	if timed_out:
		_result_title.text = "TIME UP"
	elif is_clear_round:
		_result_title.text = "★ CLEAR ROUND! ★"
	elif cleared >= total:
		_result_title.text = "ROUND COMPLETE"
	else:
		_result_title.text = "ROUND FINISHED"

	_result_body.text = "%d / %d fences   ·   %d faults\nTime  %.1fs\nReward  +£%d\nJumping training  +%d" % [
		cleared, total, faults, seconds, reward, 4 if is_clear_round else (3 if cleared >= total else cleared)
	]
	if is_clear_round:
		_result_body.text += "\nFlawless clear round bonus awarded!"
	if result.get("new_best", false):
		_result_body.text += "\nNew personal best time!"
	_result_panel.visible = true


## Show-class card: placing, field, prize and the rosette are added only when
## the result carries them, so schooling rounds are unchanged.
func _show_class_result(result: Dictionary) -> void:
	var placing: int = result.get("placing", 0)
	var field: int = result.get("field", 0)
	var prize: int = result.get("prize", 0)
	var eliminated: bool = result.get("eliminated", false)
	var rosette := String(result.get("rosette", ""))
	_result_title.text = String(result.get("title", "CLASS RESULT"))
	var lines: Array[String] = []
	lines.append(String(result.get("class_label", "CLASS")))
	lines.append("%d / %d fences   ·   %d faults" % [
		int(result.get("clears", 0)), int(result.get("total", 0)), int(result.get("faults", 0))])
	lines.append("Time  %.2fs" % float(result.get("seconds", 0.0)))
	if placing > 0:
		lines.append("%s of %d   ·   Prize  +£%d" % [_ordinal(placing), field, prize])
	elif eliminated:
		lines.append("No placing or prize")
	else:
		lines.append("Not placed this time")
	if not rosette.is_empty():
		lines.append("Rosette: %s  ·  collect it at the judges' box" % rosette.capitalize())
	if result.get("new_best", false):
		lines.append("New personal best!")
	if not bool(result.get("timed_out", false)) and placing == 0 and not eliminated:
		lines.append("Clear every fence with 0 faults to be placed")
	_result_body.text = "\n".join(lines)
	var hint := _result_panel.find_child("Hint", true, false) as Label
	if hint != null:
		hint.text = "Enter again at the secretary's desk"
	_result_panel.visible = true


func _ordinal(value: int) -> String:
	match value:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
		_:
			return "%dth" % value


func _on_round_reset() -> void:
	_result_panel.visible = false


func _show_toast(text: String) -> void:
	if _toast_label == null:
		return
	# The result card already carries the round summary.
	if _result_panel != null and _result_panel.visible:
		return
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)
