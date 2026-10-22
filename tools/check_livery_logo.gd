extends SceneTree

## Checks the Livery logo in both UI screens and on the stable roof.
##
##   godot --headless --path . --script res://tools/check_livery_logo.gd

const MAIN := "res://scenes/main.tscn"
const SELECT := "res://scenes/character_select.tscn"
const SIGN_ORIGIN := Vector3(-7.0, 3.263, -23.702)
const SIGN_HEIGHT := 0.367

var _failures: Array[String] = []
var _world: Node
var _stage := 0
var _wait := 0.0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_world)


func _process(delta: float) -> bool:
	_wait += delta
	match _stage:
		0:
			if _wait >= 0.5:
				_check_hud()
				_check_roof()
				_world.queue_free()
				_world = (load(SELECT) as PackedScene).instantiate()
				root.add_child(_world)
				_wait = 0.0
				_stage = 1
		1:
			if _wait >= 0.5:
				_check_select()
				_report()
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_button(screen: String) -> void:
	var button := _world.find_child("LiveryLogoButton", true, false) as TextureButton
	_expect(button != null, "%s: logo button missing" % screen)
	if button == null:
		return
	_expect(button.texture_normal != null, "%s: logo texture missing" % screen)
	_expect(button.texture_click_mask != null, "%s: click mask missing" % screen)
	_expect(is_equal_approx(button.anchor_left, 1.0) and is_equal_approx(button.anchor_right, 1.0), "%s: not anchored right" % screen)
	_expect(is_equal_approx(button.offset_right, -24.0), "%s: right margin is %.1f" % [screen, button.offset_right])
	_expect(absf(button.size.x - 168.0) < 1.0, "%s: width is %.1f" % [screen, button.size.x])
	_expect(button.mouse_filter == Control.MOUSE_FILTER_STOP, "%s: button does not consume clicks" % screen)

	var fired := [false]
	button.logo_pressed.connect(func() -> void: fired[0] = true)
	button.pressed.emit()
	_expect(fired[0], "%s: logo_pressed did not fire" % screen)


func _check_hud() -> void:
	_check_button("HUD")
	var hud := _world.find_child("HUD", true, false) as CanvasLayer
	_expect(hud != null, "HUD: CanvasLayer missing")
	if hud != null:
		_expect(hud.layer == 10, "HUD: unexpected layer %d" % hud.layer)


func _check_roof() -> void:
	var sign_node := _world.find_child("LiverySign", true, false) as Node3D
	_expect(sign_node != null, "Stable: LiverySign missing")
	if sign_node == null:
		return

	var xform := sign_node.global_transform
	_expect(xform.origin.distance_to(SIGN_ORIGIN) < 0.01, "Stable: sign origin is %s" % xform.origin)
	_expect(absf(xform.basis.get_scale().x - 1.25) < 0.01, "Stable: sign scale is %s" % xform.basis.get_scale())

	var face := xform.basis.z.normalized()
	_expect(face.y > 0.5 and face.z > 0.4, "Stable: sign does not face up and out over the yard (%s)" % face)

	var top := xform.origin + xform.basis.y.normalized() * SIGN_HEIGHT
	_expect(top.y < 3.98, "Stable: sign top (%.2f m) pokes through the ridge" % top.y)
	_expect(top.z > -25.0, "Stable: sign top (%.2f m) passes the ridge line" % top.z)

	var lowest := 1e9
	for child in sign_node.get_children():
		if child is VisualInstance3D:
			var box: AABB = (child as VisualInstance3D).get_aabb()
			lowest = minf(lowest, box.position.y)
	_expect(lowest > -0.2, "Stable: sign geometry extends too far below its origin (%.2f)" % lowest)


func _check_select() -> void:
	_check_button("Character select")
	var logo := _world.find_child("LiveryLogoButton", true, false) as TextureButton
	if logo == null:
		return
	var logo_rect := logo.get_global_rect()
	var index_label: Label = null
	for node in _world.find_children("*", "Label", true, false):
		var label := node as Label
		if is_equal_approx(label.offset_right, -64.0) and is_equal_approx(label.anchor_right, 1.0):
			index_label = label
			break
	_expect(index_label != null, "Character select: index label missing")
	if index_label != null:
		_expect(not logo_rect.intersects(index_label.get_global_rect()), "Character select: logo overlaps the index label")


func _report() -> void:
	if _failures.is_empty():
		print("[livery-check] PASS - HUD button, select button and roof sign are in place")
		quit(0)
		return
	for failure in _failures:
		printerr("[livery-check] FAIL - " + failure)
	quit(1)
