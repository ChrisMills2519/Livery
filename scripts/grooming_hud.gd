extends CanvasLayer

## Grooming session UI.  Built in code, like the gameplay HUD, so the bay scene
## stays small.  The HUD only emits intent; the session owns all state.

signal tool_selected(index: int)
signal finish_requested
signal return_requested
signal mask_toggled(enabled: bool)

const TEXT_COLOR := Color(0.96, 0.97, 0.92, 1.0)
const DIM_COLOR := Color(0.78, 0.82, 0.74, 1.0)
const ACCENT := Color(0.72, 1.0, 0.62, 1.0)
const WARM := Color(0.98, 0.82, 0.48, 1.0)

const TOOLS := [
	{"id": "curry", "name": "Curry comb", "key": "1", "desc": "Body and legs — loosen dirt in small circles."},
	{"id": "dandy", "name": "Dandy brush", "key": "2", "desc": "Body and legs — lift the loosened dirt."},
	{"id": "soft", "name": "Soft brush", "key": "3", "desc": "Clean coat, legs and head — polish for shine."},
	{"id": "face", "name": "Face brush", "key": "4", "desc": "Head only — clean, then polish gently."},
	{"id": "hoof", "name": "Hoof pick", "key": "5", "desc": "Muddy hooves — pick all four."},
]

var _root: Control
var _title_label: Label
var _subtitle_label: Label
var _clean_bar: ProgressBar
var _shine_bar: ProgressBar
var _clean_value: Label
var _shine_value: Label
var _hoof_label: Label
var _tool_buttons: Array = []
var _tool_desc: Label
var _done_button: Button
var _mask_button: Button
var _legend: VBoxContainer
var _toast_label: Label
var _toast_tween: Tween
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _area_panel: PanelContainer
var _area_box: VBoxContainer
var _area_names: Array = []
var _area_values: Array = []
var _areas_label: Label
var _selected := 0
var _mask_active := false
var _finished := false


func _ready() -> void:
	layer = 20
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "GroomingHudRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top()
	_build_tools()
	_build_buttons()
	_build_areas()
	_build_hints()
	_build_legend()
	_build_toast()
	_build_result()


func _build_top() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 14
	top.add_theme_constant_override("separation", 1)
	_root.add_child(top)
	_title_label = _label(top, "GROOMING", 26, ACCENT)
	_subtitle_label = _label(top, "A calm routine — dirty to gleaming", 14, DIM_COLOR)

	# A CenterContainer keeps the two bars compact; dropping them straight into
	# the top VBox let them stretch across the screen and swallow the labels.
	var bars_wrap := CenterContainer.new()
	bars_wrap.custom_minimum_size = Vector2(430, 0)
	top.add_child(bars_wrap)
	var bars := HBoxContainer.new()
	bars.custom_minimum_size = Vector2(430, 0)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 22)
	bars_wrap.add_child(bars)

	var clean_box := VBoxContainer.new()
	clean_box.custom_minimum_size = Vector2(190, 0)
	clean_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clean_box.add_theme_constant_override("separation", 1)
	bars.add_child(clean_box)
	var clean_row := HBoxContainer.new()
	clean_row.add_theme_constant_override("separation", 8)
	clean_box.add_child(clean_row)
	_label(clean_row, "CLEAN", 12, DIM_COLOR)
	_clean_value = _label(clean_row, "0%", 13, TEXT_COLOR)
	_clean_bar = _progress_bar(clean_box, Color(0.48, 0.82, 0.44, 1.0))

	var shine_box := VBoxContainer.new()
	shine_box.custom_minimum_size = Vector2(190, 0)
	shine_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shine_box.add_theme_constant_override("separation", 1)
	bars.add_child(shine_box)
	var shine_row := HBoxContainer.new()
	shine_row.add_theme_constant_override("separation", 8)
	shine_box.add_child(shine_row)
	_label(shine_row, "SHINE", 12, DIM_COLOR)
	_shine_value = _label(shine_row, "0%", 13, TEXT_COLOR)
	_shine_bar = _progress_bar(shine_box, Color(0.94, 0.80, 0.42, 1.0))

	_hoof_label = _label(top, "Hooves  0 / 4", 14, DIM_COLOR)


func _build_tools() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 132)
	panel.custom_minimum_size = Vector2(258, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.09, 0.06, 0.86), Color(0.42, 0.62, 0.38, 0.65)))
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	_label(box, "TOOLS", 13, DIM_COLOR)
	for i in range(TOOLS.size()):
		var info: Dictionary = TOOLS[i]
		var button := Button.new()
		button.text = "%s   %s" % [info["key"], info["name"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 56 if Device.is_touch() else 34)
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", ACCENT)
		button.add_theme_color_override("font_pressed_color", ACCENT)
		button.add_theme_stylebox_override("normal", _button_style(false))
		button.add_theme_stylebox_override("hover", _button_style(false, true))
		button.add_theme_stylebox_override("pressed", _button_style(true))
		button.add_theme_stylebox_override("focus", _button_style(true))
		button.pressed.connect(func() -> void: tool_selected.emit(i))
		box.add_child(button)
		_tool_buttons.append(button)
	_tool_desc = _label(box, "", 13, DIM_COLOR)
	_tool_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_desc.custom_minimum_size = Vector2(230, 0)
	_set_button_selected(0, true)


func _build_buttons() -> void:
	_done_button = Button.new()
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

	_mask_button = Button.new()
	_mask_button.text = Device.pick("MASK VIEW   Tab", "MASK VIEW")
	_mask_button.focus_mode = Control.FOCUS_NONE
	_mask_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mask_button.offset_left = -178
	_mask_button.offset_right = -24
	_mask_button.offset_top = 80 if Device.is_touch() else 58
	_mask_button.offset_bottom = 136 if Device.is_touch() else 92
	_mask_button.add_theme_font_size_override("font_size", 14)
	_mask_button.add_theme_color_override("font_color", DIM_COLOR)
	_mask_button.add_theme_color_override("font_hover_color", ACCENT)
	_mask_button.add_theme_stylebox_override("normal", _button_style(false))
	_mask_button.add_theme_stylebox_override("hover", _button_style(false, true))
	_mask_button.add_theme_stylebox_override("pressed", _button_style(true))
	_mask_button.pressed.connect(_on_mask_pressed)
	_root.add_child(_mask_button)


## The per-area checklist.  It lives in the free space under the buttons, so
## the player can see which parts of the horse are done while the glow shows
## where the current brush works.
func _build_areas() -> void:
	_area_panel = PanelContainer.new()
	_area_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_area_panel.offset_left = -214
	_area_panel.offset_right = -24
	_area_panel.offset_top = 100
	_area_panel.offset_bottom = 300
	_area_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.09, 0.06, 0.80), Color(0.42, 0.62, 0.38, 0.55)))
	_root.add_child(_area_panel)
	_area_box = VBoxContainer.new()
	_area_box.add_theme_constant_override("separation", 1)
	_area_panel.add_child(_area_box)
	_areas_label = _label(_area_box, "Areas  0 / 9", 13, DIM_COLOR)


## Rebuild the rows when the number of areas changes, then refresh them.
func _ensure_area_rows(count: int) -> void:
	if _area_names.size() == count:
		return
	for child in _area_box.get_children():
		if child == _areas_label:
			continue
		child.queue_free()
	_area_names.clear()
	_area_values.clear()
	for i in range(count):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_area_box.add_child(row)
		var name_label := _label(row, "", 13, DIM_COLOR)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := _label(row, "", 13, DIM_COLOR)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_area_names.append(name_label)
		_area_values.append(value_label)


## Refresh the checklist from the session's per-area state.
func set_regions(states: Array) -> void:
	if states.is_empty():
		return
	_ensure_area_rows(states.size())
	var done := 0
	for i in range(states.size()):
		var entry = states[i]
		if not (entry is Dictionary):
			continue
		var name_label: Label = _area_names[i]
		var value_label: Label = _area_values[i]
		name_label.text = String(entry.get("name", ""))
		if bool(entry.get("complete", false)):
			done += 1
			name_label.add_theme_color_override("font_color", ACCENT)
			value_label.text = "OK"
			value_label.add_theme_color_override("font_color", ACCENT)
		else:
			name_label.add_theme_color_override("font_color", DIM_COLOR)
			value_label.text = "%d%%" % int(round(float(entry.get("clean", 0.0)) * 100.0))
			value_label.add_theme_color_override("font_color", DIM_COLOR)
	if _areas_label != null:
		_areas_label.text = "Areas  %d / %d" % [done, states.size()]


func _build_hints() -> void:
	var hints := _label(_root, Device.pick("Left drag  brush   ·   Right drag  orbit   ·   Wheel  zoom   ·   1–5  tools (glow = area)   ·   Tab  mask   ·   Esc  done", "Drag brush   ·   Two-finger orbit   ·   Pinch zoom   ·   Tap tool   ·   Done"), 14, DIM_COLOR)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_left = 24
	hints.offset_top = -44
	hints.offset_bottom = -18


func _build_legend() -> void:
	_legend = VBoxContainer.new()
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend.offset_left = -230
	_legend.offset_right = -24
	_legend.offset_top = -144
	_legend.offset_bottom = -20
	_legend.add_theme_constant_override("separation", 1)
	_legend.visible = false
	_root.add_child(_legend)
	_label(_legend, "MASK VIEW", 13, TEXT_COLOR)
	_label(_legend, "brown  ·  dirty", 13, Color(0.62, 0.48, 0.30, 1.0))
	_label(_legend, "amber  ·  curried", 13, Color(1.0, 0.70, 0.28, 1.0))
	_label(_legend, "green  ·  clean", 13, Color(0.42, 0.92, 0.50, 1.0))
	_label(_legend, "gold  ·  polished", 13, Color(1.0, 0.92, 0.56, 1.0))


func _build_toast() -> void:
	_toast_label = _label(_root, "", 20, WARM)
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.offset_top = 112
	_toast_label.modulate.a = 0.0


func _build_result() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.custom_minimum_size = Vector2(440, 0)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.10, 0.07, 0.94), Color(0.48, 0.72, 0.42, 0.75)))
	_result_panel.visible = false
	_root.add_child(_result_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_result_panel.add_child(box)
	_result_title = _label(box, "GROOMING COMPLETE", 28, ACCENT)
	_result_body = _label(box, "", 18, TEXT_COLOR)
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var return_button := Button.new()
	return_button.text = "RETURN TO THE YARD"
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.custom_minimum_size = Vector2(0, 38)
	return_button.add_theme_font_size_override("font_size", 16)
	return_button.add_theme_color_override("font_color", Color(0.07, 0.10, 0.07, 1.0))
	return_button.add_theme_stylebox_override("normal", _solid_style(ACCENT))
	return_button.add_theme_stylebox_override("hover", _solid_style(Color(0.82, 1.0, 0.72, 1.0)))
	return_button.add_theme_stylebox_override("pressed", _solid_style(Color(0.58, 0.82, 0.50, 1.0)))
	return_button.pressed.connect(func() -> void: return_requested.emit())
	box.add_child(return_button)


func _on_mask_pressed() -> void:
	_mask_active = not _mask_active
	mask_toggled.emit(_mask_active)


func reset_for_session() -> void:
	_finished = false
	_done_button.disabled = false
	_done_button.modulate.a = 1.0
	_result_panel.visible = false
	_title_label.text = "GROOMING"
	_title_label.add_theme_color_override("font_color", ACCENT)
	_subtitle_label.text = "A calm routine — dirty to gleaming"
	_toast_label.modulate.a = 0.0
	if _areas_label != null:
		_areas_label.text = "Areas  0 / 9"


func set_tool(index: int) -> void:
	if index < 0 or index >= TOOLS.size():
		return
	_selected = index
	for i in range(_tool_buttons.size()):
		_set_button_selected(i, i == index)
	_tool_desc.text = TOOLS[index]["desc"]


func _set_button_selected(index: int, selected: bool) -> void:
	if index < 0 or index >= _tool_buttons.size():
		return
	var button: Button = _tool_buttons[index]
	button.add_theme_stylebox_override("normal", _button_style(selected))
	button.add_theme_color_override("font_color", ACCENT if selected else TEXT_COLOR)


func set_progress(clean: float, polish: float, hooves: int) -> void:
	_clean_bar.value = clampf(clean, 0.0, 1.0) * 100.0
	_shine_bar.value = clampf(polish, 0.0, 1.0) * 100.0
	_clean_value.text = "%d%%" % int(round(clean * 100.0))
	_shine_value.text = "%d%%" % int(round(polish * 100.0))
	_hoof_label.text = "Hooves  %d / 4" % clampi(hooves, 0, 4)


func set_complete(complete: bool) -> void:
	if _finished:
		return
	_title_label.text = "GROOMING · COMPLETE" if complete else "GROOMING"
	_title_label.add_theme_color_override("font_color", WARM if complete else ACCENT)
	_subtitle_label.text = Device.pick("Ready when you are — press Esc to finish", "Ready when you are — tap Done to finish") if complete else "A calm routine — dirty to gleaming"


func set_mask_active(enabled: bool) -> void:
	_mask_active = enabled
	_legend.visible = enabled
	_mask_button.text = "MASK VIEW   ON" if enabled else Device.pick("MASK VIEW   Tab", "MASK VIEW")


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
	_tool_desc.text = "A calm groom is part of good horse care."
	_toast_label.modulate.a = 0.0
	var complete: bool = result.get("complete", false)
	_result_title.text = "GROOMING COMPLETE" if complete else "GROOMING PAUSED"
	_result_title.add_theme_color_override("font_color", WARM if complete else ACCENT)
	var clean: float = result.get("clean", 0.0)
	var polish: float = result.get("polish", 0.0)
	var hooves: int = result.get("hooves", 0)
	var trust_gain: float = result.get("trust_gain", 0.0)
	var happiness_gain: float = result.get("happiness_gain", 0.0)
	_result_body.text = "Coat clean  %d%%\nShine  %d%%\nHooves  %d / 4\n\nTrust +%.2f     Happiness +%.2f" % [
		int(round(clean * 100.0)), int(round(polish * 100.0)), clampi(hooves, 0, 4), trust_gain, happiness_gain
	]
	if not complete:
		var next := "There is more dirt to lift. Come back when you are ready."
		if clampi(hooves, 0, 4) < 4:
			next = "The hooves still need picking."
		elif clean < 0.90:
			next = "There is more dirt to lift. Come back when you are ready."
		elif polish < 0.55:
			next = "A little more polishing will bring out the shine."
		_result_body.text += "\n\n" + next
	_result_panel.visible = true


func is_pointer_over_ui() -> bool:
	if _root == null:
		return false
	var hovered := _root.get_viewport().gui_get_hovered_control()
	return hovered != null


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
	bar.custom_minimum_size = Vector2(190, 7)
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
	return style
