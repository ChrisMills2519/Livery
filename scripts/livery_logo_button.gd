extends TextureButton

## Corner logo button shared by the gameplay HUD and the character select.

signal logo_pressed

const LOGO_TEXTURE: Texture2D = preload("res://assets/images/livery_logo_ui.png")
const BASE_SIZE := Vector2(168.0, 50.4)

var _tween: Tween
var _hovered := false


func _ready() -> void:
	texture_normal = LOGO_TEXTURE
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = BASE_SIZE
	size = BASE_SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Menu"
	texture_click_mask = _make_click_mask()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)
	resized.connect(_recentre_pivot)
	_recentre_pivot()


func _make_click_mask() -> BitMap:
	var image := LOGO_TEXTURE.get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(300, 90, Image.INTERPOLATE_BILINEAR)
	var mask := BitMap.new()
	mask.create_from_image_alpha(image, 0.35)
	return mask


func _recentre_pivot() -> void:
	pivot_offset = size * 0.5


func _animate(target_scale: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * target_scale, 0.12)
	_tween.tween_property(self, "modulate", Color(1.12, 1.12, 1.12) if _hovered else Color.WHITE, 0.12)


func _on_mouse_entered() -> void:
	_hovered = true
	_animate(1.03)


func _on_mouse_exited() -> void:
	_hovered = false
	_animate(1.0)


func _on_pressed() -> void:
	logo_pressed.emit()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * 0.96, 0.07)
	_tween.tween_property(self, "scale", Vector2.ONE * (1.03 if _hovered else 1.0), 0.16)
