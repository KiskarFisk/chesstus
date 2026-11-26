extends Node2D
## Chess board. Net.seats = [white peer id, black peer id]; offline both are you.
## The game can only be left once it's over (mate, stalemate, resignation, agreed draw).

const TILE := 64
const SIDES := ["White", "Black"]
const VALUES := {"Q": 9, "R": 5, "B": 3, "N": 3, "P": 1}
const START_COUNT := {"Q": 1, "R": 2, "B": 2, "N": 2, "P": 8}

var game := ChessRules.from_fen(ChessRules.START)
var selected := -1
var targets: Array = []
var textures := {}
var result := ""      # non-empty once the game is over
var draw_offer := -1  # side (0 white, 1 black) with a draw offer on the table, -1 if none
var last_move := Vector2i(-1, -1)  # from, to of the latest move, highlighted
var dragging := false  # selected piece is held under the mouse
var drag_pos := Vector2.ZERO  # mouse position, local
var buttons := HBoxContainer.new()
var bot_busy := false  # host: a bot is thinking


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
	if result or Net.watching_bots():
		_button("Back to hub", func(): Net.end_game())
	elif _side_of(me) != -1:
		if draw_offer != -1 and Net.seats[1 - draw_offer] == me:
			_button("Accept draw", func(): Net.send(_accept_draw))
			_button("Decline draw", func(): Net.send(_decline_draw))
		elif draw_offer == -1 and not Net.seats.any(func(id): return id < 0):  # bots don't take draws
			_button("Offer draw", func(): Net.send(_offer_draw))
		_button("Resign", func(): Net.send(_resign))
	queue_redraw()
	_maybe_bot()


## Host only: if a bot is to move, think on a worker thread, then play its move like anyone else's.
func _maybe_bot() -> void:
	var seat: int = Net.seats[_turn()]
	if seat >= 0 or result or bot_busy or not multiplayer.is_server():
		return
	bot_busy = true
	var state := game
	Net.think(Bots.chess_move.bind(state, -seat), func(m):
		bot_busy = false
		if game == state:  # nothing else happened meanwhile (e.g. a resignation)
			Net.send(_move, m))


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
		if i == last_move.x or i == last_move.y:
			draw_rect(r, Color(0.6, 0.8, 0.2, 0.45))
		if i == selected:
			draw_rect(r, Color(1, 1, 0, 0.4))
		if i == check_sq:
			draw_rect(r, Color(1, 0, 0, 0.5))
		if game.board[i] != "" and not (dragging and not result and i == selected):
			var tex: Texture2D = textures[game.board[i]]
			draw_texture(tex, r.get_center() - tex.get_size() / 2)
		if i in targets:
			if _is_capture(i):
				draw_arc(r.get_center(), TILE / 2.0 - 4, 0, TAU, 40, Color(0, 0, 0, 0.3), 6)
			else:
				draw_circle(r.get_center(), 10, Color(0, 0, 0, 0.3))
	if dragging and not result:  # held piece follows the mouse, drawn on top
		var tex: Texture2D = textures[game.board[selected]]
		draw_texture(tex, drag_pos - tex.get_size() / 2)
	var font := ThemeDB.fallback_font
	_draw_captures(font, o)
	var lines := _status().split("\n")
	for i in lines.size():
		draw_string(font, o + Vector2(0, -16 - 26 * (lines.size() - 1 - i)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


## Right of the board: pieces each side has captured, plus "+N" for whoever is up material.
## Black's row sits by Black's side (top), White's by White's (bottom).
func _draw_captures(font: Font, o: Vector2) -> void:
	var material := {"w": 0, "b": 0}
	for p in game.board:
		if p != "" and p[1] != "K":
			material[p[0]] += VALUES[p[1]]
	for side in ["w", "b"]:
		var enemy := "b" if side == "w" else "w"
		var icons := []  # x offset, piece
		var x := 0
		for t in START_COUNT:
			# ponytail: promotions can leave a type above its start count; clamp so it just shows nothing
			var missing := maxi(0, START_COUNT[t] - game.board.count(enemy + t))
			for i in missing:
				icons.append([x, enemy + t])
				x += 16
			if missing:
				x += 18
		var lead: int = material[side] - material[enemy]
		if icons.is_empty() and lead <= 0:
			continue
		var pos := o + Vector2(TILE * 8 + 16, TILE * 8 - 40 if side == "w" else 8)
		var width := x + (40 if lead > 0 else 0)
		# backing strip so black pieces don't vanish into the black background
		draw_rect(Rect2(pos - Vector2(6, 2), Vector2(width + 8, 36)), Color(0.62, 0.6, 0.57))
		for icon in icons:
			draw_texture_rect(textures[icon[1]], Rect2(pos + Vector2(icon[0], 0), Vector2(32, 32)), false)
		if lead > 0:
			draw_string(font, pos + Vector2(x + 4, 23), "+%d" % lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (result or Net.watching_bots()):
		Net.end_game()
	elif event is InputEventMouseMotion and dragging:
		drag_pos = make_input_local(event).position
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not result:
		# Click-click and drag-and-drop both work: press picks up, release on a target moves.
		drag_pos = make_input_local(event).position
		var sq := _square_at(drag_pos)
		if not event.pressed:
			if dragging:
				dragging = false
				if sq in targets:
					Net.send(_move, Vector2i(selected, sq))
				queue_redraw()
			return
		if sq in targets:
			Net.send(_move, Vector2i(selected, sq))
		elif sq != -1 and game.board[sq].begins_with(game.turn) and Net.seats[_turn()] == multiplayer.get_unique_id():
			selected = sq
			targets = game.legal_moves().filter(func(m): return m.x == sq).map(func(m): return m.y)
			dragging = true
		else:
			selected = -1
			targets = []
		queue_redraw()


func _square_at(pos: Vector2) -> int:
	var c := Vector2i(((pos - _origin()) / TILE).floor())
	return c.y * 8 + c.x if ChessRules._on(c) else -1


## Target square holds an enemy piece, or is an en passant capture (pawn moving diagonally onto an empty square).
func _is_capture(sq: int) -> bool:
	return game.board[sq] != "" or (game.board[selected][1] == "P" and sq % 8 != selected % 8)


# --- RPCs: sent with _send to everyone in the game. Senders are untrusted, so each checks seat, turn and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector2i) -> void:
	if result or not Net.may_act(Net.seats[_turn()], multiplayer.get_remote_sender_id()) or m not in game.legal_moves():
		return
	game = game.play(m)
	last_move = m
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

