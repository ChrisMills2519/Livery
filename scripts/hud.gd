extends CanvasLayer

## Minimal gameplay HUD for the schooling-round loop.
##
## Everything is built in code so the scene file stays small.  The HUD only
## reads state from the course, the horse and the GameState autoload; it never
## changes the simulation.

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.78, 0.82, 0.74, 1.0)
const ACCENT := Color(0.72, 1.0, 0.62, 1.0)

var _course: Node
var _horse: Node3D
var _player: Node3D

var _money_label: Label
var _skill_label: Label
var _best_label: Label
var _objective_label: Label
var _timer_label: Label
var _progress_label: Label
var _toast_label: Label
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _toast_tween: Tween


func _ready() -> void:
	add_to_group("gameplay_hud")
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
	_result_panel.visible = false
	root.add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 8)
	_result_panel.add_child(result_box)
	_result_title = _label(result_box, "ROUND COMPLETE", 30, ACCENT)
	_result_body = _label(result_box, "", 20, TEXT_COLOR)
	var hint := _label(result_box, "Ride back through the arena gate to go again", 15, DIM_COLOR)
	hint.name = "Hint"

	var controls := _label(root, "WASD move   ·   Shift trot / canter   ·   Space jump   ·   E mount / dismount", 15, DIM_COLOR)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls.offset_left = 24
	controls.offset_bottom = -18


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


func _update_objective() -> void:
	var mounted: bool = _player != null and _player.get("mounted") == true
	match _course.state:
		"running":
			_objective_label.text = "Clear all %d fences" % _course.get_jump_count()
		"finished":
			_objective_label.text = "Round complete"
		_:
			if mounted:
				var meters := 0.0
				if _horse != null:
					meters = Vector2(
						_horse.global_position.x - _course.gate_position.x,
						_horse.global_position.z - _course.gate_position.z
					).length()
				_objective_label.text = "Ride west through the arena gate  (%.0f m)" % meters
			else:
				_objective_label.text = "Walk to your horse and press E to mount"


func _update_course_text() -> void:
	match _course.state:
		"running":
			_timer_label.text = "%.1fs" % _course.elapsed
			_progress_label.text = "Fences cleared  %d / %d" % [_course.cleared_count, _course.get_jump_count()]
			_timer_label.visible = true
			_progress_label.visible = true
		"finished":
			_timer_label.visible = false
			_progress_label.visible = false
		_:
			_timer_label.visible = false
			_progress_label.visible = false


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
	var total: int = result.get("total", 3)
	var seconds: float = result.get("seconds", 0.0)
	var reward: int = result.get("reward", 0)
	var timed_out: bool = result.get("timed_out", false)
	_result_title.text = "TIME UP" if timed_out else "ROUND COMPLETE"
	if cleared >= total and not timed_out:
		_result_title.text = "CLEAR ROUND!" if result.get("new_best", false) == false else "NEW BEST TIME!"
	_result_body.text = "%d / %d fences\nTime  %.1fs\nReward  +£%d\nJumping training  +%d" % [
		cleared, total, seconds, reward, 3 if cleared >= total else cleared
	]
	if result.get("new_best", false):
		_result_body.text += "\nNew personal best!"
	_result_panel.visible = true


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
