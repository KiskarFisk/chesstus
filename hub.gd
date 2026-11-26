extends Node2D

const TILE := 64
const STEP_TIME := 0.15
const LABEL_RANGE := 4  # a game's name shows while any king is this many squares away or closer
const LABEL_FADE := 0.35  # seconds to fade a name fully in or out
# Key: the game's unique character in hub_map.gd. letter: what's drawn on its square, usually the
# family it belongs to (Superchess is a chess game, so C). seats: one per side; teams: seats playing together.
const GAMES := {
	"C": {"name": "Chess", "letter": "C", "scene": "res://chess.tscn", "color": Color(0.25, 0.55, 0.95),
		"seats": ["White", "Black"], "teams": [[0], [1]]},
	"B": {"name": "Baby Chess", "letter": "C", "scene": "res://babychess.tscn", "color": Color(0.35, 0.75, 0.5),
		"seats": ["White", "Black"], "teams": [[0], [1]]},
	# modes: picked in the vote popup. armies: which seat plays each of the game's armies; players: the
	# player count it's the default for. The game reads the mode id from Net.game_mode.
	"S": {"name": "Superchess", "letter": "C", "scene": "res://superchess.tscn", "color": Color(0.7, 0.3, 0.75),
		"modes": [
			{"id": "2p", "name": "2 players", "players": 2, "seats": ["Light (White + Yellow)", "Dark (Black + Red)"],
				"teams": [[0], [1]], "armies": [0, 1, 0, 1]},
			{"id": "teams", "name": "3 players", "players": 3, "seats": ["Light (White + Yellow)", "Black", "Red"],
				"teams": [[0], [1, 2]], "armies": [0, 1, 0, 2]},
			{"id": "teams", "name": "4 players (teams)", "players": 4, "seats": ["White", "Black", "Yellow", "Red"],
				"teams": [[0, 2], [1, 3]], "armies": [0, 1, 2, 3]},
			{"id": "ffa", "name": "Free for all", "seats": ["White", "Black", "Yellow", "Red"],
				"teams": [[0], [1], [2], [3]], "armies": [0, 1, 2, 3]},
		]},
}

# Checkerboard colors per area, painted with the map editor's Theme brush. Key = letter in THEME_MAP.
const THEMES := {
	".": {"name": "Classic", "light": Color("#eed8b5"), "dark": Color("#b48963")},
	"s": {"name": "Shogi", "light": Color("#ecc77f"), "dark": Color("#d9ab5c")},  # kaya wood
}

# Live copies of the layout; static so map editor changes survive scene reloads this session.
static var map: Array = preload("res://hub_map.gd").MAP.duplicate()
static var theme_map: Array = preload("res://hub_map.gd").THEME_MAP.duplicate()

var kings := {}  # peer id -> Sprite2D, mirrors Net.cells
var moving := false
var editing := false  # set by the map editor
var label_alpha := {}  # game square (Vector2i) -> name opacity 0..1
var status_label: Label
var vote_layer := CanvasLayer.new()


func _ready() -> void:
	_build_net_ui()
	add_child(vote_layer)
	Net.proposal_changed.connect(_show_proposal)
	_show_proposal()
	if OS.has_feature("editor"):  # only when run from the Godot editor, never in exports
		add_child(load("res://map_editor.gd").new())


func _build_net_ui() -> void:
	var layer := CanvasLayer.new()
	var row := HBoxContainer.new()
	row.position = Vector2(12, 12)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.text = Net.my_name
	name_edit.max_length = Net.MAX_NAME
	name_edit.custom_minimum_size.x = 140
	name_edit.text_changed.connect(Net.set_my_name)
	name_edit.text_submitted.connect(func(_t): name_edit.release_focus())
	row.add_child(name_edit)
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


func _process(delta: float) -> void:
	status_label.text = Net.status
	_sync_kings()
	_fade_labels(delta)
	var me := multiplayer.get_unique_id()
	if editing or moving or not Net.proposal.is_empty() or not Net.cells.has(me) \
			or get_viewport().gui_get_focus_owner() is LineEdit:
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
	var letter := tile(Net.cells.get(multiplayer.get_unique_id(), Vector2i.ZERO))
	if GAMES.has(letter):
		Net.propose.rpc_id(1, letter)


func _you(id: int) -> String:
	return Net.name_of(id) + (" (you)" if Net.online() and id == multiplayer.get_unique_id() else "")


## The "Play <game>?" popup every player sees while a proposal is open. Rebuilt on every change.
func _show_proposal() -> void:
	for c in vote_layer.get_children():
		c.queue_free()
	var p := Net.proposal
	if p.is_empty():
		return
	var me := multiplayer.get_unique_id()
	var g: Dictionary = GAMES[p.game]
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Play %s?" % g.name
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)
	var modes := Net.modes_of(p.game)
	var mode: Dictionary = modes[p.mode]
	if modes.size() > 1:
		var mode_pick := OptionButton.new()
		mode_pick.focus_mode = Control.FOCUS_NONE
		for md in modes:
			mode_pick.add_item(md.name)
		mode_pick.select(p.mode)
		mode_pick.item_selected.connect(func(idx): Net.set_mode.rpc_id(1, idx))
		col.add_child(mode_pick)
	for i in mode.seats.size():
		var row := HBoxContainer.new()
		var seat := Label.new()
		seat.text = mode.seats[i]
		seat.custom_minimum_size.x = 80
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		var bots_ok: bool = i > 0 or not Net.online()  # online, the first seat must be a person
		var options: Array = p.players + (Net.BOTS.keys() if bots_ok else [])
		for id in options:
			pick.add_item(_you(id))
		pick.select(options.find(p.seats[i]))
		pick.item_selected.connect(func(idx): Net.set_seat.rpc_id(1, i, options[idx]))
		row.add_child(seat)
		row.add_child(pick)
		col.add_child(row)
	var votes := Label.new()
	votes.text = "\n".join(p.players.map(func(id): return "%s: %s" % [_you(id), "ready" if p.votes.has(id) else "deciding..."]))
	col.add_child(votes)
	var buttons := HBoxContainer.new()
	var play := Button.new()
	play.text = "Play"
	play.disabled = p.votes.has(me)
	play.pressed.connect(func(): Net.vote.rpc_id(1, true))
	var decline := Button.new()
	decline.text = "Decline"
	decline.pressed.connect(func(): Net.vote.rpc_id(1, false))
	for b in [play, decline]:
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	col.add_child(buttons)
	panel.add_child(col)
	center.add_child(panel)
	vote_layer.add_child(center)


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
			k.position = px(cell)
			k.set_meta("cell", cell)
			add_child(k)
			if id == multiplayer.get_unique_id():
				var cam := Camera2D.new()
				cam.position_smoothing_enabled = true
				k.add_child(cam)
				cam.make_current()  # the map editor's camera may have been added first
				cam.reset_smoothing()
			var tag := Label.new()  # added after the camera: the map editor expects the camera as child 0
			tag.name = "Name"
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.size = Vector2(160, 24)
			tag.position = Vector2(-80, -TILE * 0.5 - 22)
			tag.add_theme_constant_override("outline_size", 6)
			tag.add_theme_color_override("font_outline_color", Color.BLACK)
			k.add_child(tag)
			kings[id] = k
		elif kings[id].get_meta("cell") != cell:
			kings[id].set_meta("cell", cell)
			create_tween().tween_property(kings[id], "position", px(cell), STEP_TIME)
		kings[id].get_node("Name").text = Net.name_of(id)
		var color := Net.color_of(id)  # refreshed each frame: colors can arrive after the king
		kings[id].texture = load("res://pieces/%sK.svg" % color.piece)
		kings[id].self_modulate = color.tint  # self_: don't tint the name label


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


## Fade each game's name toward visible while any king is within LABEL_RANGE (king-move distance).
func _fade_labels(delta: float) -> void:
	var changed := false
	for y in map.size():
		for x in map[y].length():
			if map[y][x] not in GAMES:
				continue
			var c := Vector2i(x, y)
			var near := Net.cells.values().any(func(k): return maxi(absi(k.x - x), absi(k.y - y)) <= LABEL_RANGE)
			var a: float = label_alpha.get(c, 0.0)
			var to := move_toward(a, 1.0 if near else 0.0, delta / LABEL_FADE)
			if to != a:
				label_alpha[c] = to
				changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for y in map.size():
		for x in map[y].length():
			var ch: String = map[y][x]
			if ch == " ":
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			var theme: Dictionary = THEMES.get(theme_map[y][x], THEMES["."])
			var col: Color = Color.BLACK if ch == "#" else (theme.light if (x + y) % 2 == 0 else theme.dark)
			draw_rect(r, col)
			if editing and ch == "#":  # tell walls apart from empty space
				draw_rect(r.grow(-1), Color(0.35, 0.35, 0.35), false, 2)
			elif ch in GAMES:
				draw_rect(r.grow(-6), GAMES[ch].color)
				draw_string(font, r.position + Vector2(0, TILE * 0.68), GAMES[ch].letter, HORIZONTAL_ALIGNMENT_CENTER, TILE, 32)
			elif editing and ch == "K":
				draw_string(font, r.position + Vector2(0, TILE * 0.68), "K", HORIZONTAL_ALIGNMENT_CENTER, TILE, 32, Color(0, 0.6, 0, 0.8))
	# Game names under their squares, drawn after the tiles so neighbouring squares don't cover them.
	# Names that would overlap (games next to each other) stack downwards.
	var taken: Array[Rect2] = []
	var cells := label_alpha.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or a.y == b.y and a.x < b.x)
	for c in cells:
		var a: float = label_alpha[c]
		if a <= 0.0 or tile(c) not in GAMES:  # skip faded out, or a square the map editor removed
			continue
		var text: String = GAMES[tile(c)].name
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		var box := Rect2(Vector2(c.x + 0.5, c.y + 1) * TILE - Vector2(size.x / 2 + 4, 0), size + Vector2(8, 2))
		while taken.any(func(t): return t.intersects(box)):
			box.position.y += box.size.y
		taken.append(box)
		var pos := box.position + Vector2(4, 20)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0, 0, 0, a))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, a))
