extends Node2D
## Hub map editor. hub.gd only adds this when running from the Godot editor.
## F1 toggles. LMB paints (outside the board grows it), RMB erases, arrows pan, wheel zooms.

const Hub := preload("res://hub.gd")
const SAVE_PATH := "res://hub_map.gd"
const PAN_SPEED := 600.0
const EMPTY := " "
const GAME := "game"  # brush id; the actual letter is picked from game_menu

var active := false
var brush := "#"
var cam := Camera2D.new()
var ui := CanvasLayer.new()
var info := Label.new()
var game_menu := PopupMenu.new()
var game_cell: Vector2i  # where the game picked from game_menu goes

@onready var hub: Hub = get_parent()


func _ready() -> void:
	add_child(cam)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 60)
	var col := VBoxContainer.new()
	panel.add_child(col)
	col.add_child(info)
	var row := HBoxContainer.new()
	var brushes := {"#": "Wall", ".": "Floor", "K": "Spawn", GAME: "Game"}
	for k in brushes:
		row.add_child(_button(brushes[k], _set_brush.bind(k)))
	row.add_child(_button("Save", _save))
	col.add_child(row)
	ui.add_child(panel)
	for k in Hub.GAMES:
		game_menu.add_item("%s: %s" % [k, Hub.GAMES[k].scene.get_file().get_basename().capitalize()])
	game_menu.id_pressed.connect(func(i): _paint(game_cell, Hub.GAMES.keys()[i]))
	ui.add_child(game_menu)
	ui.visible = false
	add_child(ui)
	_info()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for panning
	b.pressed.connect(cb)
	return b


func _set_brush(k: String) -> void:
	brush = k
	_info()


func _info(msg := "") -> void:
	info.text = "MAP EDITOR (F1 to exit)  Brush: %s  Size: %dx%d\nLMB paint (outside the board to grow it), RMB erase, arrows pan, wheel zoom\n%s" \
		% [brush.capitalize() if brush == GAME else brush, Hub.map[0].length(), Hub.map.size(), msg]


func _process(delta: float) -> void:
	if active:
		cam.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * PAN_SPEED * delta / cam.zoom.x


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		if Net.online():
			Net.status = "Map editor is offline only"
		else:
			_set_active(not active)
		return
	if not active:
		return
	var c := Vector2i((get_global_mouse_position() / Hub.TILE).floor())
	var pressed: bool = e is InputEventMouseButton and e.pressed
	if pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var z := cam.zoom.x * (1.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.1)
		cam.zoom = Vector2.ONE * clampf(z, 0.25, 2.0)
	elif pressed or e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_paint(c, EMPTY)
		elif e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if brush != GAME:
				_paint(c, brush)
			elif pressed:  # one game per click, not while dragging
				game_cell = c
				game_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _set_active(on: bool) -> void:
	active = on
	ui.visible = on
	hub.editing = on
	var me := multiplayer.get_unique_id()
	if on:
		cam.position = hub.kings[me].position
		cam.make_current()
	else:
		if Hub.tile(Net.cells[me]) == "#":  # painted or erased under our king
			Net.cells[me] = Net._free_spawn()
		hub.kings[me].get_child(0).make_current()
	hub.queue_redraw()


func _paint(c: Vector2i, ch: String) -> void:
	var m := Hub.map
	var w: int = m[0].length()
	var h := m.size()
	if ch == EMPTY and (c.x < 0 or c.y < 0 or c.x >= w or c.y >= h):
		return
	# Grow the board so c is inside it.
	var left := maxi(0, -c.x)
	var top := maxi(0, -c.y)
	var right := maxi(0, c.x - (w - 1))
	var bottom := maxi(0, c.y - (h - 1))
	if left or top or right or bottom:
		for i in h:
			m[i] = EMPTY.repeat(left) + m[i] + EMPTY.repeat(right)
		w += left + right
		for i in top:
			m.insert(0, EMPTY.repeat(w))
		for i in bottom:
			m.append(EMPTY.repeat(w))
		c += Vector2i(left, top)
		_shift(Vector2i(left, top))
	if m[c.y][c.x] == ch:
		return
	m[c.y] = m[c.y].substr(0, c.x) + ch + m[c.y].substr(c.x + 1)
	if ch == EMPTY:
		_trim()
	hub.queue_redraw()
	_info("Unsaved changes")


## Drop empty rows/columns from the edges.
func _trim() -> void:
	var m := Hub.map
	var lo := Vector2i(m[0].length(), m.size())
	var hi := Vector2i(-1, -1)
	for y in m.size():
		for x in m[y].length():
			if m[y][x] != EMPTY:
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x, y))
	if hi.x < 0:
		return  # everything erased; keep the size so there's somewhere to paint
	var rows := m.slice(lo.y, hi.y + 1).map(func(r): return r.substr(lo.x, hi.x - lo.x + 1))
	m.clear()
	m.append_array(rows)
	_shift(-lo)


## The board's top-left moved by off cells: move kings and the camera with it so nothing jumps.
func _shift(off: Vector2i) -> void:
	if off == Vector2i.ZERO:
		return
	for id in Net.cells:
		Net.cells[id] += off
		var k: Sprite2D = hub.kings.get(id)
		if k:
			k.position += Vector2(off * Hub.TILE)
			k.set_meta("cell", Net.cells[id])
	cam.position += Vector2(off * Hub.TILE)


func _save() -> void:
	if Hub.spawns().is_empty():
		_info("Not saved: the map needs at least one K spawn")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_info("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	var rows := "".join(Hub.map.map(func(r): return '\t"%s",\n' % r))
	f.store_string("# Hub layout. Rewritten by the in-game map editor (F1 in the hub, editor runs only).\n" \
		+ "# '#' wall, '.' floor, ' ' empty, 'K' spawn point, letters = game squares (see GAMES in hub.gd)\n" \
		+ "const MAP := [\n" + rows + "]\n")
	_info("Saved to " + SAVE_PATH)
