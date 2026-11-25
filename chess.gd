extends Node2D


func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(40, 80), "Chess goes here. Esc to return.", HORIZONTAL_ALIGNMENT_LEFT, -1, 32)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://hub.tscn")
