extends Node2D
## Quoridor board. Net.seats = one peer id per side (2 or 4); offline all are you. White starts at the bottom,
## the others clockwise from it (2 players: Black at the top).
## On your turn, dots mark where your pawn can go; hover a groove to preview a wall, click to place it.
## The game can only be left once it's over (someone reached the far side, or everyone else resigned).

const CELL := 60
const GAP := 14  # groove width, where walls go
const P := CELL + GAP  # cell pitch
const FRAME := 16
const SIDES := ["White", "Black", "Yellow", "Red"]
const PAWN := [Color("#f4f0e6"), Color("#202020"), Color(1.0, 0.82, 0.15), Color(1.0, 0.3, 0.25)]
const NO_WALL := Vector3i(-1, -1, -1)

var game := QuoridorRules.create(Net.seats.size())
var targets: Array[Vector3i] = []  # your pawn's moves, shown while it's your turn
var hover := NO_WALL  # legal wall under the mouse
var last_move := NO_WALL
var result := ""
var buttons := HBoxContainer.new()
var bot_busy := false


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * _size()) / 2


func _size() -> float:
	return QuoridorRules.N * P - GAP


func _mine() -> bool:
	return not result and Net.seats[game.turn] == multiplayer.get_unique_id()


func _side_of(id: int) -> int:
	return game.turn if Net.seats[game.turn] == id else Net.seats.find(id)


func _who(side: int) -> String:
	var id: int = Net.seats[side]
	var you := ", you" if Net.online() and id == multiplayer.get_unique_id() else ""
	return "%s (%s%s)" % [SIDES[side], Net.name_of(id), you]


func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	if result or Net.watching_bots():
		_button("Back to hub", func(): Net.end_game())
	elif _side_of(multiplayer.get_unique_id()) not in [-1] + game.resigned:
		_button("Resign", func(): Net.send(_resign))
	targets.clear()
	if _mine():
		targets = game.steps()
	hover = NO_WALL
	queue_redraw()
	_maybe_bot()


func _maybe_bot() -> void:
	var seat: int = Net.seats[game.turn]
	if seat >= 0 or result or bot_busy or not multiplayer.is_server():
		return
	bot_busy = true
	var state := game
	Net.think(self, Bots.quoridor_move.bind(state, -seat), func(m):
		bot_busy = false
		if game == state:
			Net.send(_move, m))


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)


# --- Drawing ---

func _draw() -> void:
	var o := _origin()
	var board := Rect2(o, Vector2.ONE * _size())
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#4a3222")
	box.border_color = Color("#6e4c33")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	draw_style_box(box, board.grow(FRAME))
	buttons.position = o + Vector2(0, _size() + FRAME + 10)
	for y in QuoridorRules.N:
		for x in QuoridorRules.N:
			var c := Vector2i(x, y)
			var col := Color("#c99a62")
			if last_move.z == QuoridorRules.STEP and c == Vector2i(last_move.x, last_move.y):
				col = col.lerp(Color(0.6, 0.8, 0.2), 0.45)
			draw_rect(_cell(c), col)
	for t in targets:
		draw_circle(_cell(Vector2i(t.x, t.y)).get_center(), 10, Color(0, 0, 0, 0.3))
	for side in game.pawns.size():
		_draw_supply(side)
		if side in game.resigned:
			continue
		draw_circle(_cell(game.pawns[side]).get_center(), CELL * 0.34, PAWN[side])
		draw_arc(_cell(game.pawns[side]).get_center(), CELL * 0.34, 0, TAU, 32, Color.BLACK, 2, true)
	for kind in [QuoridorRules.H, QuoridorRules.V]:
		for w in (game.h if kind == QuoridorRules.H else game.v):
			var m := Vector3i(w.x, w.y, kind)
			draw_rect(_wall(m), Color("#f2d9a2"))
			if m == last_move:
				draw_rect(_wall(m), Color(0.6, 0.8, 0.2), false, 3)
	if hover != NO_WALL:
		draw_rect(_wall(hover), Color(1, 1, 1, 0.45))
	var status := result if result else "%s to move  -  %d walls left" % [_who(game.turn), game.walls_left[game.turn]]
	draw_string(ThemeDB.fallback_font, o + Vector2(0, -FRAME - 10), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


## A side's unplaced walls standing in a row, in the board corner clockwise of its start: the bottom side's
## right of the board at the bottom, the left side's left at the bottom, top's top left, right's top right.
func _draw_supply(side: int) -> void:
	var o := _origin()
	var tall := 2 * CELL + GAP
	var home: int = game.homes[side]
	var right := home in [QuoridorRules.BOTTOM, QuoridorRules.RIGHT]
	var low := home in [QuoridorRules.BOTTOM, QuoridorRules.LEFT]
	for i in game.walls_left[side]:
		var x: float = _size() + FRAME + 24 + i * (GAP + 8) if right else -FRAME - 24 - GAP - i * (GAP + 8)
		var y: float = _size() - tall if low else 0.0
		var pos := o + Vector2(x, y)
		draw_rect(Rect2(pos, Vector2(GAP, tall)), Color("#f2d9a2"))
		draw_rect(Rect2(pos, Vector2(GAP, tall)), PAWN[side], false, 2)


func _cell(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c) * P, Vector2.ONE * CELL)


func _wall(m: Vector3i) -> Rect2:
	var at := _origin() + Vector2(m.x, m.y) * P
	if m.z == QuoridorRules.H:
		return Rect2(at + Vector2(0, CELL), Vector2(2 * CELL + GAP, GAP))
	return Rect2(at + Vector2(CELL, 0), Vector2(GAP, 2 * CELL + GAP))


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (result or Net.watching_bots()):
		Net.end_game()
	elif event is InputEventMouseMotion:
		var w := _wall_at(make_input_local(event).position)
		if w != hover:
			hover = w
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _mine():
		var pos: Vector2 = make_input_local(event).position
		var c := _cell_at(pos)
		var step := Vector3i(c.x, c.y, QuoridorRules.STEP)
		if step in targets:
			Net.send(_move, step)
		elif hover != NO_WALL:
			Net.send(_move, hover)


func _cell_at(pos: Vector2) -> Vector2i:
	var p := pos - _origin()
	var c := Vector2i((p / P).floor())
	var inside := p - Vector2(c) * P
	return c if inside.x < CELL and inside.y < CELL else Vector2i(-1, -1)


## The legal wall a click at pos would place, or NO_WALL. In a horizontal groove the wall centers on the
## nearest groove crossing; where grooves cross, horizontal wins unless only vertical fits.
func _wall_at(pos: Vector2) -> Vector3i:
	if not _mine() or game.walls_left[game.turn] == 0:
		return NO_WALL
	var p := pos - _origin()
	var c := Vector2i((p / P).floor())
	var inside := p - Vector2(c) * P
	var near := Vector2i(((p + Vector2.ONE * GAP / 2) / P).round()) - Vector2i.ONE  # nearest crossing, as a wall name
	var options: Array[Vector3i] = []
	if inside.y >= CELL:
		options.append(Vector3i(clampi(near.x, 0, QuoridorRules.N - 2), c.y, QuoridorRules.H))
	if inside.x >= CELL:
		options.append(Vector3i(c.x, clampi(near.y, 0, QuoridorRules.N - 2), QuoridorRules.V))
	for m in options:
		if p.x >= 0 and p.y >= 0 and game.wall_ok(m):
			return m
	return NO_WALL


# --- RPCs: sent with Net.send to everyone in the game. Senders are untrusted, so each checks seat, turn and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector3i) -> void:
	if result or not Net.may_act(Net.seats[game.turn], multiplayer.get_remote_sender_id()) \
			or not (m in game.steps() if m.z == QuoridorRules.STEP else game.wall_ok(m)):
		return
	var side := game.turn
	game = game.play(m)
	last_move = m
	if game.winner() == side:
		result = "%s reaches the far side and wins" % _who(side)
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _resign() -> void:
	var side := _side_of(multiplayer.get_remote_sender_id())
	if result or side == -1 or side in game.resigned:
		return
	game = game.resign(side)  # 4 players: the others play on
	if game.winner() != -1:
		result = "%s resigns. %s wins" % [_who(side), _who(game.winner())]
	_refresh()
