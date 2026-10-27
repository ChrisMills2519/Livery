extends CanvasLayer

## Muck-out session UI.  Built in code, like the gameplay HUD and the grooming
## HUD, so the stable scene stays small.  The HUD only emits intent; the session
## owns every value.

signal finish_requested
signal return_requested

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.78, 0.82, 0.74, 1.0)
const ACCENT := Color(0.72, 1.0, 0.62, 1.0)
const WARM := Color(0.98, 0.82, 0.48, 1.0)

var _root: Control
var _title_label: Label
var _subtitle_label: Label
var _bed_bar: ProgressBar
var _bed_value: Label
var _barrow_label: Label
var _hint_label: Label
var _done_button: Button
var _toast_label: Label
var _toast_tween: Tween
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _finished := false


func _ready() -> void:
	layer = 20
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "MuckHudRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top()
	_build_panel()
	_build_done()
	_build_toast()
	_build_result()


func _build_top() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 14
	top.add_theme_constant_override("separation", 1)
	_root.add_child(top)
	_title_label = _label(top, "MUCKING OUT", 26, ACCENT)
	_subtitle_label = _label(top, "A clean bed for a comfortable horse", 14, DIM_COLOR)

	# Wrapped in a CenterContainer so the bar keeps its width instead of
	# stretching across the screen and swallowing the labels.
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(240, 0)
	top.add_child(wrap)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 1)
	wrap.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_label(row, "BED CLEAN", 12, DIM_COLOR)
	_bed_value = _label(row, "0%", 13, TEXT_COLOR)
	_bed_bar = _progress_bar(box, Color(0.62, 0.86, 0.46, 1.0))


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 132)
	panel.custom_minimum_size = Vector2(268, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.06, 0.09, 0.06, 0.86), Color(0.42, 0.62, 0.38, 0.65)))
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_label(box, "THE BED", 13, DIM_COLOR)
	_barrow_label = _label(box, "Barrow  0 / 0", 16, TEXT_COLOR)
	_barrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint_label = _label(box, "", 13, DIM_COLOR)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint_label.custom_minimum_size = Vector2(240, 0)
	_apply_hint()


func _apply_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.text = Device.pick(
		"Scoop every heap into the barrow. A clean bed keeps the horse content.",
		"Tap every heap to scoop it into the barrow. A clean bed keeps the horse content."
	)


func _build_done() -> void:
	_done_button = Button.new()
	_done_button.name = "DoneButton"
	_done_button.text = Device.pick("DONE   Esc", "DONE")
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_done_button.offset_left = -178
	_done_button.offset_right = -24
	_done_button.offset_top = 16
	_done_button.offset_bottom = 72 if Device.is_touch() else 52
	_done_button.add_theme_font_size_override("font_size", 15)
	_done_button.add_theme_color_override("font_color", TEXT_COLOR)
	_done_button.add_theme_color_override("font_hover_color", ACCENT)
	_done_button.add_theme_stylebox_override("normal", _button_style(false))
	_done_button.add_theme_stylebox_override("hover", _button_style(false, true))
	_done_button.add_theme_stylebox_override("pressed", _button_style(true))
	_done_button.pressed.connect(func() -> void: finish_requested.emit())
	_root.add_child(_done_button)


func _build_toast() -> void:
	var slot := VBoxContainer.new()
	slot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	slot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slot.offset_bottom = -96
	slot.add_theme_constant_override("separation", 0)
	_root.add_child(slot)
	_toast_label = _label(slot, "", 22, Color(1.0, 0.93, 0.56, 1.0))
	_toast_label.modulate.a = 0.0


func _build_result() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.name = "MuckResultCard"
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.custom_minimum_size = Vector2(440, 0)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.07, 0.10, 0.07, 0.94), Color(0.48, 0.72, 0.42, 0.75)))
	_result_panel.visible = false
	_root.add_child(_result_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_result_panel.add_child(box)
	_result_title = _label(box, "STALL MUCKED OUT", 28, ACCENT)
	_result_body = _label(box, "", 18, TEXT_COLOR)
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "BACK TO THE YARD"
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.custom_minimum_size = Vector2(0, 38)
	return_button.add_theme_font_size_override("font_size", 16)
	return_button.add_theme_color_override("font_color", Color(0.07, 0.10, 0.07, 1.0))
	return_button.add_theme_stylebox_override("normal", _solid_style(ACCENT))
	return_button.add_theme_stylebox_override("hover", _solid_style(Color(0.82, 1.0, 0.72, 1.0)))
	return_button.add_theme_stylebox_override("pressed", _solid_style(Color(0.58, 0.82, 0.50, 1.0)))
	return_button.pressed.connect(func() -> void: return_requested.emit())
	box.add_child(return_button)


func reset_for_session() -> void:
	_finished = false
	if _done_button != null:
		_done_button.disabled = false
		_done_button.modulate.a = 1.0
	if _result_panel != null:
		_result_panel.visible = false
	_title_label.text = "MUCKING OUT"
	_title_label.add_theme_color_override("font_color", ACCENT)
	_subtitle_label.text = "A clean bed for a comfortable horse"
	_toast_label.modulate.a = 0.0
	_apply_hint()
	set_progress(0.0, 0, 0)


## `bed_clean` is what is left to muck, so the bar reads full when the bed is
## fresh and empty when there is still work to do.
func set_progress(bed_muck: float, scooped: int, total: int) -> void:
	var clean := clampf(1.0 - bed_muck, 0.0, 1.0)
	_bed_bar.value = clean * 100.0
	_bed_value.text = "%d%%" % int(round(clean * 100.0))
	_barrow_label.text = "Barrow  %d / %d" % [maxi(scooped, 0), maxi(total, 0)]


func show_toast(text: String, seconds := 1.6) -> void:
	if _toast_label == null or _result_panel.visible:
		return
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.45)


func show_result(result: Dictionary) -> void:
	_finished = true
	_done_button.disabled = true
	_done_button.modulate.a = 0.45
	_toast_label.modulate.a = 0.0
	var complete: bool = result.get("complete", false)
	_result_title.text = "STALL MUCKED OUT" if complete else "MUCKING PAUSED"
	_result_title.add_theme_color_override("font_color", WARM if complete else ACCENT)
	var cleaned: float = result.get("cleaned", 0.0)
	var scoops: int = result.get("scoops", 0)
	var total: int = result.get("total_scoops", 0)
	var trust_gain: float = result.get("trust_gain", 0.0)
	var happiness_gain: float = result.get("happiness_gain", 0.0)
	_result_body.text = "Bed cleared  %d%%\nHeaps scooped  %d / %d\n\nTrust +%.2f     Happiness +%.2f" % [
		int(round(clampf(cleaned, 0.0, 1.0) * 100.0)), maxi(scoops, 0), maxi(total, 0),
		trust_gain, happiness_gain,
	]
	if not complete:
		_result_body.text += "\n\nHeaps are still waiting in the bed. Come back when you are ready."
	_result_panel.visible = true


## Used by the session to leave a click that landed on the UI alone.
func is_pointer_over_ui() -> bool:
	if _root == null:
		return false
	return _root.get_viewport().gui_get_hovered_control() != null


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.02, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _progress_bar(parent: Node, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.04, 0.02, 0.75)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _panel_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	return style


func _button_style(selected: bool, hover := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.16, 0.10, 0.92) if hover else Color(0.04, 0.06, 0.04, 0.55)
	style.border_color = ACCENT if selected else Color(0.32, 0.44, 0.30, 0.45)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _solid_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style
