extends Node2D
## Chess board. Net.seats = [white peer id, black peer id]; offline both are you.
## The game can only be left once it's over (mate, stalemate, resignation, agreed draw).

const TILE := 64
const SIDES := ["White", "Black"]

var game := ChessRules.from_fen(ChessRules.START)
var selected := -1
var targets: Array = []
var textures := {}
var result := ""      # non-empty once the game is over
var draw_offer := -1  # side (0 white, 1 black) with a draw offer on the table, -1 if none
var buttons := HBoxContainer.new()


func _ready() -> void:
	for c in "wb":
		for p in "KQRBNP":
			textures[c + p] = load("res://pieces/%s%s.svg" % [c, p])
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * TILE * 8) / 2


func _turn() -> int:
	return 0 if game.turn == "w" else 1


## Which side a peer plays. Someone holding both seats (offline) acts for the side to move.
func _side_of(id: int) -> int:
	return _turn() if Net.seats[_turn()] == id else Net.seats.find(id)


func _who(side: int) -> String:
	var id: int = Net.seats[side]
	var you := ", you" if Net.online() and id == multiplayer.get_unique_id() else ""
	return "%s (%s%s)" % [SIDES[side], Net.name_of(id), you]


func _status() -> String:
	if result:
		return result
	var s := _who(_turn()) + (" to move - check!" if game.in_check() else " to move")
	if draw_offer != -1:
		s += "\n%s offers a draw" % SIDES[draw_offer]
	return s


## Rebuild the buttons under the board for the current state, then redraw.
func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	var me := multiplayer.get_unique_id()
	if result:
		_button("Back to hub", func(): Net.goto.rpc("res://hub.tscn"))
	elif _side_of(me) != -1:
		if draw_offer != -1 and Net.seats[1 - draw_offer] == me:
			_button("Accept draw", func(): _accept_draw.rpc())
			_button("Decline draw", func(): _decline_draw.rpc())
		elif draw_offer == -1:
			_button("Offer draw", func(): _offer_draw.rpc())
		_button("Resign", func(): _resign.rpc())
	queue_redraw()


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)


func _draw() -> void:
	var o := _origin()
	buttons.position = o + Vector2(0, TILE * 8 + 12)
	var check_sq := game.board.find(game.turn + "K") if game.in_check() and not result else -1
	for i in 64:
		var r := Rect2(o + Vector2(i % 8, i / 8) * TILE, Vector2.ONE * TILE)
		draw_rect(r, Color("#eed8b5") if (i % 8 + i / 8) % 2 == 0 else Color("#b48963"))
		if i == selected:
			draw_rect(r, Color(1, 1, 0, 0.4))
		if i == check_sq:
			draw_rect(r, Color(1, 0, 0, 0.5))
		if game.board[i] != "":
			var tex: Texture2D = textures[game.board[i]]
			draw_texture(tex, r.get_center() - tex.get_size() / 2)
		if i in targets:
			draw_circle(r.get_center(), 10, Color(0, 0, 0, 0.3))
	var font := ThemeDB.fallback_font
	var lines := _status().split("\n")
	for i in lines.size():
		draw_string(font, o + Vector2(0, -16 - 26 * (lines.size() - 1 - i)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and result:
		Net.goto.rpc("res://hub.tscn")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not result:
		var c := Vector2i(((get_local_mouse_position() - _origin()) / TILE).floor())
		if not ChessRules._on(c):
			return
		var sq := c.y * 8 + c.x
		if sq in targets:
			_move.rpc(Vector2i(selected, sq))
		elif game.board[sq].begins_with(game.turn) and Net.seats[_turn()] == multiplayer.get_unique_id():
			selected = sq
			targets = game.legal_moves().filter(func(m): return m.x == sq).map(func(m): return m.y)
		else:
			selected = -1
			targets = []
		queue_redraw()


# --- RPCs: run on both sides. Senders are untrusted, so each checks seat, turn and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector2i) -> void:
	if result or multiplayer.get_remote_sender_id() != Net.seats[_turn()] or m not in game.legal_moves():
		return
	game = game.play(m)
	draw_offer = -1  # a move answers any pending offer
	if game.legal_moves().is_empty():
		result = ("Checkmate! %s wins" % _who(1 - _turn())) if game.in_check() else "Stalemate - draw"
	selected = -1
	targets = []
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _resign() -> void:
	var side := _side_of(multiplayer.get_remote_sender_id())
	if result or side == -1:
		return
	result = "%s resigns. %s wins" % [_who(side), _who(1 - side)]
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _offer_draw() -> void:
	var side := _side_of(multiplayer.get_remote_sender_id())
	if result or side == -1 or draw_offer != -1:
		return
	draw_offer = side
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _accept_draw() -> void:
	if result or draw_offer == -1 or Net.seats[1 - draw_offer] != multiplayer.get_remote_sender_id():
		return
	result = "Draw agreed"
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _decline_draw() -> void:
	if result or draw_offer == -1 or Net.seats[1 - draw_offer] != multiplayer.get_remote_sender_id():
		return
	draw_offer = -1
	_refresh()
