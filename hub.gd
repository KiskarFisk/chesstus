extends Node2D

const TILE := 64
# '#' wall, '.' floor, 'K' king spawn, any key of GAMES = game square
const MAP := [
	"############",
	"#..........#",
	"#..##......#",
	"#..#....C..#",
	"#..........#",
	"#....K.....#",
	"#......##..#",
	"#.......#..#",
	"#..........#",
	"############",
]
const GAMES := {
	"C": {"scene": "res://chess.tscn", "color": Color(0.25, 0.55, 0.95)},
}

var king := Sprite2D.new()
var cell: Vector2i
var moving := false


func _ready() -> void:
	for y in MAP.size():
		var x: int = MAP[y].find("K")
		if x != -1:
			cell = Vector2i(x, y)
	king.texture = preload("res://pieces/wK.svg")
	king.position = _px(cell)
	add_child(king)
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	king.add_child(cam)


func _process(_delta: float) -> void:
	if moving:
		return
	var dir := Vector2i(
		int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
		int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up")))
	if dir == Vector2i.ZERO or _tile(cell + dir) == "#":
		return
	cell += dir
	moving = true
	var t := create_tween()
	t.tween_property(king, "position", _px(cell), 0.15)
	t.finished.connect(_arrived)


func _arrived() -> void:
	moving = false
	var game: Dictionary = GAMES.get(_tile(cell), {})
	if game:
		get_tree().change_scene_to_file(game.scene)


func _tile(c: Vector2i) -> String:
	if c.y < 0 or c.y >= MAP.size() or c.x < 0 or c.x >= MAP[c.y].length():
		return "#"
	return MAP[c.y][c.x]


func _px(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2.ONE * TILE / 2


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for y in MAP.size():
		for x in MAP[y].length():
			var ch: String = MAP[y][x]
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			var col := Color.BLACK if ch == "#" else (Color("#eed8b5") if (x + y) % 2 == 0 else Color("#b48963"))
			draw_rect(r, col)
			if ch in GAMES:
				draw_rect(r.grow(-6), GAMES[ch].color)
				draw_string(font, r.position + Vector2(0, TILE * 0.68), ch, HORIZONTAL_ALIGNMENT_CENTER, TILE, 32)
