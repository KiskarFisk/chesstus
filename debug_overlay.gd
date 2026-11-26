extends CanvasLayer
## Autoload "DebugOverlay": FPS counter, only when run from the Godot editor (same rule as the map editor).

var label := Label.new()


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 100  # above every scene's UI
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_left = -100
	label.offset_right = -12
	label.offset_top = 8
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)


func _process(_delta: float) -> void:
	label.text = "%d FPS" % Engine.get_frames_per_second()
