extends Node2D
## Chess board. Net.seats = [white peer id, black peer id]; offline both are you.
## The game can only be left once it's over (mate, stalemate, resignation, agreed draw).

const TILE := 64
const FRAME := 16  # wooden border around the board; black beyond it
const SIDES := ["White", "Black"]
const VALUES := {"Q": 9, "R": 5, "B": 3, "N": 3, "P": 1}
const NONE := -99  # nothing selected (squares are >= 0, drop codes -1..-5)
const SLOT := 48  # width of a hand slot (Crazyhouse)
## Starting position; the scene sets it (babychess.tscn uses ChessRules.BABY). Board size comes from it.
@export var fen := ChessRules.START

var game: ChessRules
var start_count := {}  # piece type -> how many each side starts with, for the captured-pieces display
var selected := NONE  # board square, or a drop code (from of a drop move) while a Crazyhouse hand piece is picked
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
	game = ChessRules.from_fen(ChessRules.fischer(Net.game_seed) if Net.game_mode == "frc" else fen)
	for t in VALUES:
		start_count[t] = game.board.count("w" + t)
	for c in "wb":
		for p in "KQRBNP":
			textures[c + p] = load("res://pieces/%s%s.svg" % [c, p])
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * TILE * game.n) / 2


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
		s += "  -  %s offers a draw" % SIDES[draw_offer]  # one line: two would run off the top on 8x8
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
	Net.think(self, Bots.chess_move.bind(state, -seat), func(m):
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
	_draw_frame(Rect2(o, Vector2.ONE * TILE * game.n))
	buttons.position = o + Vector2(0, TILE * game.n + FRAME + 10)
	var check_sq := game.board.find(game.turn + "K") if game.in_check() and not result else -1
	for i in game.n * game.n:
		var r := Rect2(o + Vector2(i % game.n, i / game.n) * TILE, Vector2.ONE * TILE)
		draw_rect(r, Color("#eed8b5") if (i % game.n + game.n - 1 - i / game.n) % 2 == 1 else Color("#b48963"))  # a1 is always dark
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
	if game.hands.is_empty():
		_draw_captures(font, o)
	else:
		for side in ["w", "b"]:
			_draw_hand(side, font)
	var lines := _status().split("\n")
	for i in lines.size():
		draw_string(font, o + Vector2(0, -FRAME - 10 - 26 * (lines.size() - 1 - i)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


## Rounded wooden border hugging the board.
func _draw_frame(board: Rect2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#4a3222")
	box.border_color = Color("#6e4c33")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	draw_style_box(box, board.grow(FRAME))


## Right of the board: pieces each side has captured, plus "+N" for whoever is up material.
## Black's row sits by Black's side (top), White's by White's (bottom).
func _draw_captures(font: Font, o: Vector2) -> void:
	var totals := {"w": 0, "b": 0}
	for p in game.board:
		if p != "" and p[1] != "K":
			totals[p[0]] += VALUES[p[1]]
	for side in ["w", "b"]:
		var enemy := "b" if side == "w" else "w"
		var icons := []  # x offset, piece
		var x := 0
		for t in start_count:
			# ponytail: promotions can leave a type above its start count; clamp so it just shows nothing
			var missing := maxi(0, start_count[t] - game.board.count(enemy + t))
			for i in missing:
				icons.append([x, enemy + t])
				x += 16
			if missing:
				x += 18
		var lead: int = totals[side] - totals[enemy]
		if icons.is_empty() and lead <= 0:
			continue
		var pos := o + Vector2(TILE * game.n + FRAME + 14, TILE * game.n - 40 if side == "w" else 8)
		var width := x + (40 if lead > 0 else 0)
		# backing strip so black pieces don't vanish into the black background
		draw_rect(Rect2(pos - Vector2(6, 2), Vector2(width + 8, 36)), Color(0.62, 0.6, 0.57))
		for icon in icons:
			draw_texture_rect(textures[icon[1]], Rect2(pos + Vector2(icon[0], 0), Vector2(32, 32)), false)
		if lead > 0:
			draw_string(font, pos + Vector2(x + 4, 23), "+%d" % lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)


## Crazyhouse: a side's hand right of the board, where captures show in chess (Black's at the top, White's
## at the bottom). One slot per kind held, in DROPS order, with a count when there's more than one.
func _draw_hand(side: String, font: Font) -> void:
	draw_rect(_slot(side, 0).merge(_slot(side, ChessRules.DROPS.size() - 1)).grow(4), Color(0.62, 0.6, 0.57))
	var held := _held(side)
	for j in held.size():
		var kind: String = held[j]
		var count: int = game.hands[side][kind]
		var r := _slot(side, j)
		if selected == -1 - ChessRules.DROPS.find(kind) and game.turn == side:
			draw_rect(r, Color(1, 1, 0, 0.5))
		draw_texture_rect(textures[side + kind], Rect2(r.position, Vector2(36, 36)), false)
		if count > 1:
			draw_string(font, r.position + Vector2(34, 32), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)


func _slot(side: String, j: int) -> Rect2:
	var y := TILE * game.n - 40 if side == "w" else 4
	return Rect2(_origin() + Vector2(TILE * game.n + FRAME + 14 + j * SLOT, y), Vector2(SLOT - 4, 36))


func _held(side: String) -> Array:
	return ChessRules.DROPS.filter(func(k): return game.hands[side].has(k))


## The drop code under pos in the side to move's hand, or NONE.
func _hand_at(pos: Vector2) -> int:
	var held := _held(game.turn)
	for j in held.size():
		if _slot(game.turn, j).has_point(pos):
			return -1 - ChessRules.DROPS.find(held[j])
	return NONE


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
		var mine: bool = Net.seats[_turn()] == multiplayer.get_unique_id()
		var drop := _hand_at(drag_pos) if mine and not game.hands.is_empty() else NONE
		if sq in targets:
			Net.send(_move, Vector2i(selected, sq))
		elif drop != NONE:  # click a hand piece, then a square; no dragging from the hand
			selected = drop
			targets = game.legal_moves().filter(func(m): return m.x == drop).map(func(m): return m.y)
		elif sq != -1 and game.board[sq].begins_with(game.turn) and mine:
			selected = sq
			targets = game.legal_moves().filter(func(m): return m.x == sq).map(func(m): return m.y)
			dragging = true
		else:
			selected = NONE
			targets = []
		queue_redraw()


func _square_at(pos: Vector2) -> int:
	var c := Vector2i(((pos - _origin()) / TILE).floor())
	return c.y * game.n + c.x if game.on(c) else -1


## Target square holds an enemy piece, or is an en passant capture (pawn moving diagonally onto an empty square).
## (Fischer Random castling targets your own rook: not a capture.)
func _is_capture(sq: int) -> bool:
	return game.board[sq].begins_with(game.opponent()) \
		or (selected >= 0 and game.board[selected][1] == "P" and sq % game.n != selected % game.n)


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
	selected = NONE
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

