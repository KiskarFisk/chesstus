extends Node2D

const TILE := 64
const STEP_TIME := 0.15
const GAMES := {
	"C": {"scene": "res://chess.tscn", "color": Color(0.25, 0.55, 0.95)},
}

# Live copy of the layout; static so map editor changes survive scene reloads this session.
static var map: Array = preload("res://hub_map.gd").MAP.duplicate()

var kings := {}  # peer id -> Sprite2D, mirrors Net.cells
var moving := false
var editing := false  # set by the map editor
var status_label: Label


func _ready() -> void:
	_build_net_ui()
	if OS.has_feature("editor"):  # only when run from the Godot editor, never in exports
		add_child(load("res://map_editor.gd").new())


func _build_net_ui() -> void:
	var layer := CanvasLayer.new()
	var row := HBoxContainer.new()
	row.position = Vector2(12, 12)
	var ip := LineEdit.new()
	ip.text = "127.0.0.1"
	ip.custom_minimum_size.x = 160
	ip.text_submitted.connect(func(_t): ip.release_focus())
	var host_btn := Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(Net.host)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(func(): Net.join(ip.text.strip_edges()))
	for b in [host_btn, join_btn]:
		b.focus_mode = Control.FOCUS_NONE  # arrow keys drive the king, not button focus
	status_label = Label.new()
	for n in [ip, host_btn, join_btn, status_label]:
		row.add_child(n)
	layer.add_child(row)
	add_child(layer)


func _process(_delta: float) -> void:
	status_label.text = Net.status
	_sync_kings()
	var me := multiplayer.get_unique_id()
	if editing or moving or not Net.cells.has(me) or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	# One step per key press. Diagonal = hold one arrow, press the other.
	if not ["ui_left", "ui_right", "ui_up", "ui_down"].any(Input.is_action_just_pressed):
		return
	var dir := Vector2i(
		int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
		int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up")))
	var target: Vector2i = Net.cells[me] + dir
	if dir == Vector2i.ZERO or tile(target) == "#" or target in Net.cells.values():
		return
	Net.move(target)
	moving = true
	get_tree().create_timer(STEP_TIME).timeout.connect(_arrived)


func _arrived() -> void:
	moving = false
	var game: Dictionary = GAMES.get(tile(Net.cells.get(multiplayer.get_unique_id(), Vector2i.ZERO)), {})
	if game:
		Net.goto.rpc(game.scene)


## Create, slide, or remove king sprites so they match Net.cells.
func _sync_kings() -> void:
	for id in kings.keys():
		if not Net.cells.has(id):
			kings[id].queue_free()
			kings.erase(id)
	for id in Net.cells:
		var cell: Vector2i = Net.cells[id]
		if not kings.has(id):
			var k := Sprite2D.new()
			k.texture = load("res://pieces/%sK.svg" % Net.color_of(id))
			k.position = px(cell)
			k.set_meta("cell", cell)
			add_child(k)
			if id == multiplayer.get_unique_id():
				var cam := Camera2D.new()
				cam.position_smoothing_enabled = true
				k.add_child(cam)
				cam.make_current()  # the map editor's camera may have been added first
				cam.reset_smoothing()
			kings[id] = k
		elif kings[id].get_meta("cell") != cell:
			kings[id].set_meta("cell", cell)
			create_tween().tween_property(kings[id], "position", px(cell), STEP_TIME)


static func tile(c: Vector2i) -> String:
	if c.y < 0 or c.y >= map.size() or c.x < 0 or c.x >= map[c.y].length():
		return "#"
	var ch: String = map[c.y][c.x]
	return "#" if ch == " " else ch  # empty space blocks like a wall


static func spawns() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in map.size():
		for x in map[y].length():
			if map[y][x] == "K":
				out.append(Vector2i(x, y))
	return out


static func px(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2.ONE * TILE / 2


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for y in map.size():
		for x in map[y].length():
			var ch: String = map[y][x]
			if ch == " ":
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			var col := Color.BLACK if ch == "#" else (Color("#eed8b5") if (x + y) % 2 == 0 else Color("#b48963"))
			draw_rect(r, col)
			if editing and ch == "#":  # tell walls apart from empty space
				draw_rect(r.grow(-1), Color(0.35, 0.35, 0.35), false, 2)
			elif ch in GAMES:
				draw_rect(r.grow(-6), GAMES[ch].color)
				draw_string(font, r.position + Vector2(0, TILE * 0.68), ch, HORIZONTAL_ALIGNMENT_CENTER, TILE, 32)
			elif editing and ch == "K":
				draw_string(font, r.position + Vector2(0, TILE * 0.68), "K", HORIZONTAL_ALIGNMENT_CENTER, TILE, 32, Color(0, 0.6, 0, 0.8))
