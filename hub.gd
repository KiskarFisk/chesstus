extends Node2D

const TILE := 64
const STEP_TIME := 0.15
const GAMES := {
	"C": {"name": "Chess", "scene": "res://chess.tscn", "color": Color(0.25, 0.55, 0.95), "seats": ["White", "Black"]},
}

# Live copy of the layout; static so map editor changes survive scene reloads this session.
static var map: Array = preload("res://hub_map.gd").MAP.duplicate()

var kings := {}  # peer id -> Sprite2D, mirrors Net.cells
var moving := false
var editing := false  # set by the map editor
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


func _process(_delta: float) -> void:
	status_label.text = Net.status
	_sync_kings()
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
	for i in g.seats.size():
		var row := HBoxContainer.new()
		var seat := Label.new()
		seat.text = g.seats[i]
		seat.custom_minimum_size.x = 80
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		for id in p.players:
			pick.add_item(_you(id))
		pick.select(p.players.find(p.seats[i]))
		pick.item_selected.connect(func(idx): Net.set_seat.rpc_id(1, i, p.players[idx]))
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
