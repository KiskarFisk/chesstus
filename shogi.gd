extends Node2D
## Shogi board. Net.seats = [Sente peer id, Gote peer id]; offline both are you. Sente sits at the bottom.
## Each side's captured pieces wait on its stand (Gote: top left, Sente: bottom right) and can be dropped.
## The game can only be left once it's over (mate, resignation, agreed draw).

const TILE := 64
const FRAME := 16  # wooden border around the board; black beyond it
const STAND_GAP := 24  # board frame to piece stand
const SIDES := ["Sente", "Gote"]
const NONE := -99  # nothing selected (squares are >= 0, drop codes -1..-7)
const WOOD := Color("#ecc77f")  # same kaya as the hub's Shogi theme
const LINE := Color(0.25, 0.16, 0.06)
const KANJI := {"K": "玉", "R": "飛", "B": "角", "G": "金", "S": "銀", "N": "桂", "L": "香", "P": "歩",
	"+R": "龍", "+B": "馬", "+S": "全", "+N": "圭", "+L": "杏", "+P": "と"}
## Starting position; the scene sets it (minishogi.tscn uses ShogiRules.MINI). Board size comes from it.
@export var sfen := ShogiRules.START

var game: ShogiRules
var stand_kinds: Array = []  # kinds that can ever be in hand, in stand order
var font := SystemFont.new()
var selected := NONE  # board square, or a drop code (from of a drop move) while a hand piece is picked
var targets: Array = []
var pending: Array[Vector3i] = []  # promote or not: the two versions of the move waiting for a choice
var result := ""
var draw_offer := -1  # side with a draw offer on the table, -1 if none
var last_move := Vector3i(-1, -1, 0)
var dragging := false
var drag_pos := Vector2.ZERO
var buttons := HBoxContainer.new()
var bot_busy := false


func _ready() -> void:
	game = ShogiRules.from_sfen(sfen)
	stand_kinds = ShogiRules.DROPS.filter(func(k): return game.board.has("b" + k))
	font.font_names = PackedStringArray(["Yu Mincho", "MS Mincho", "Noto Serif CJK JP", "Noto Sans CJK JP", "Yu Gothic", "MS Gothic"])
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * TILE * game.n) / 2


func _turn() -> int:
	return 0 if game.turn == "b" else 1


func _side_of(id: int) -> int:
	return _turn() if Net.seats[_turn()] == id else Net.seats.find(id)


func _who(side: int) -> String:
	var id: int = Net.seats[side]
	var you := ", you" if Net.online() and id == multiplayer.get_unique_id() else ""
	return "%s (%s%s)" % [SIDES[side], Net.name_of(id), you]


func _status() -> String:
	if result:
		return result
	if not pending.is_empty():
		return "Promote?"
	var s := _who(_turn()) + (" to move - check!" if game.in_check() else " to move")
	if draw_offer != -1:
		s += "  -  %s offers a draw" % SIDES[draw_offer]
	return s


func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	var me := multiplayer.get_unique_id()
	if result or Net.watching_bots():
		_button("Back to hub", func(): Net.end_game())
	elif not pending.is_empty():
		_button("Promote", func(): _choose(1))
		_button("Don't promote", func(): _choose(0))
	elif _side_of(me) != -1:
		if draw_offer != -1 and Net.seats[1 - draw_offer] == me:
			_button("Accept draw", func(): Net.send(_accept_draw))
			_button("Decline draw", func(): Net.send(_decline_draw))
		elif draw_offer == -1 and not Net.seats.any(func(id): return id < 0):  # bots don't take draws
			_button("Offer draw", func(): Net.send(_offer_draw))
		_button("Resign", func(): Net.send(_resign))
	queue_redraw()
	_maybe_bot()


func _choose(promote: int) -> void:
	var m: Vector3i = pending[promote]
	pending = []
	Net.send(_move, m)


func _maybe_bot() -> void:
	var seat: int = Net.seats[_turn()]
	if seat >= 0 or result or bot_busy or not multiplayer.is_server():
		return
	bot_busy = true
	var state := game
	Net.think(self, Bots.shogi_move.bind(state, -seat), func(m):
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
	var size := TILE * game.n
	_draw_wood(Rect2(o, Vector2.ONE * size).grow(FRAME), Color("#4a3222"))
	draw_rect(Rect2(o, Vector2.ONE * size), WOOD)
	buttons.position = o + Vector2(0, size + FRAME + 10)
	var check_sq := game.king(game.turn) if game.in_check() and not result else -1
	for i in game.n * game.n:
		var r := _cell(i)
		if i == last_move.y or i == last_move.x:
			draw_rect(r, Color(0.6, 0.8, 0.2, 0.45))
		if i == selected:
			draw_rect(r, Color(1, 1, 0, 0.4))
		if i == check_sq:
			draw_rect(r, Color(1, 0, 0, 0.5))
	for k in game.n + 1:  # grid lines
		draw_line(o + Vector2(k * TILE, 0), o + Vector2(k * TILE, size), LINE, 2)
		draw_line(o + Vector2(0, k * TILE), o + Vector2(size, k * TILE), LINE, 2)
	if game.n == 9:  # star points
		for p in [Vector2(3, 3), Vector2(6, 3), Vector2(3, 6), Vector2(6, 6)]:
			draw_circle(o + p * TILE, 5, LINE)
	for i in game.n * game.n:
		if game.board[i] != "" and not (dragging and i == selected):
			_draw_piece(_cell(i).get_center(), game.board[i])
		if i in targets:
			draw_circle(_cell(i).get_center(), 10, Color(0, 0, 0, 0.3))
	for side in ["b", "w"]:
		_draw_stand(side)
	if dragging:
		_draw_piece(drag_pos, game.board[selected])
	draw_string(ThemeDB.fallback_font, o + Vector2(0, -FRAME - 10), _status(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


func _draw_wood(r: Rect2, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#6e4c33")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	draw_style_box(box, r)


## Pentagon piece pointing at the enemy; Gote's are turned around. Promoted kanji are red.
func _draw_piece(center: Vector2, p: String) -> void:
	var kind := p.substr(1)
	var big := kind in ["K", "R", "B", "+R", "+B"]
	var w := TILE * (0.78 if big else 0.7)
	var h := TILE * (0.88 if big else 0.8)
	draw_set_transform(center, 0.0 if p[0] == "b" else PI)
	var pts := PackedVector2Array([Vector2(0, -h / 2), Vector2(w * 0.38, -h * 0.3), Vector2(w / 2, h / 2),
		Vector2(-w / 2, h / 2), Vector2(-w * 0.38, -h * 0.3)])
	draw_colored_polygon(pts, Color("#f2d9a2"))
	pts.append(pts[0])
	draw_polyline(pts, LINE, 2)
	var text: String = "王" if kind == "K" and p[0] == "w" else KANJI[kind]
	var fs := int(h * 0.5)
	draw_string(font, Vector2(-w / 2, fs * 0.45), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
		Color(0.75, 0.08, 0.08) if kind.begins_with("+") else Color.BLACK)
	draw_set_transform(Vector2.ZERO)


## A side's stand: a slot per kind it could hold, with a count when there's more than one.
func _draw_stand(side: String) -> void:
	var slots := stand_kinds.map(func(k): return _slot(side, k))
	var r: Rect2 = slots[0]
	for s in slots:
		r = r.merge(s)
	_draw_wood(r.grow(6), Color("#c9a063"))
	for k in stand_kinds:
		var count: int = game.hands[side].get(k, 0)
		if count == 0:
			continue
		var s := _slot(side, k)
		if selected == -1 - ShogiRules.DROPS.find(k) and game.turn == side:
			draw_rect(s, Color(1, 1, 0, 0.4))
		_draw_piece(Vector2(s.position.x + TILE / 2.0, s.get_center().y), side + k)
		if count > 1:
			draw_string(ThemeDB.fallback_font, s.position + Vector2(TILE, TILE * 0.62), "x%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)


## Stand slot of a kind: Sente's column grows up from the bottom right, Gote's down from the top left.
func _slot(side: String, kind: String) -> Rect2:
	var o := _origin()
	var j := stand_kinds.find(kind)
	var size := Vector2(TILE + 36, TILE)
	if side == "b":
		return Rect2(o + Vector2(TILE * game.n + FRAME + STAND_GAP, TILE * (game.n - 1 - j)), size)
	return Rect2(o + Vector2(-FRAME - STAND_GAP - size.x, TILE * j), size)


func _cell(i: int) -> Rect2:
	return Rect2(_origin() + Vector2(i % game.n, i / game.n) * TILE, Vector2.ONE * TILE)


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (result or Net.watching_bots()):
		Net.end_game()
	elif event is InputEventMouseMotion and dragging:
		drag_pos = make_input_local(event).position
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not result:
		drag_pos = make_input_local(event).position
		var sq := _square_at(drag_pos)
		if not event.pressed:
			if dragging:
				dragging = false
				if sq in targets:
					_try(sq)
				queue_redraw()
			return
		if not pending.is_empty():  # clicking away cancels the promotion question
			pending = []
			_deselect()
			_refresh()
			return
		var mine: bool = Net.seats[_turn()] == multiplayer.get_unique_id()
		var drop := _stand_at(drag_pos)
		if sq in targets:
			_try(sq)
		elif mine and drop != "":
			selected = -1 - ShogiRules.DROPS.find(drop)
			targets = _targets()
		elif mine and sq != -1 and game.board[sq].begins_with(game.turn):
			selected = sq
			targets = _targets()
			dragging = true
		else:
			_deselect()
		queue_redraw()


func _targets() -> Array:
	var out := []
	for m in game.moves():
		if m.x == selected and m.y not in out:
			out.append(m.y)
	return out


## Move the selected piece (or drop) to sq; asks first when promoting is optional.
func _try(sq: int) -> void:
	var options: Array[Vector3i] = []
	for m in game.moves():
		if m.x == selected and m.y == sq:
			options.append(m)
	if options.size() == 2:
		options.sort_custom(func(a, b): return a.z < b.z)
		pending = options
		targets = []
		_refresh()
	elif options.size() == 1:
		Net.send(_move, options[0])


func _deselect() -> void:
	selected = NONE
	targets = []
	dragging = false


func _square_at(pos: Vector2) -> int:
	var c := Vector2i(((pos - _origin()) / TILE).floor())
	return c.y * game.n + c.x if game.on(c) else -1


## The kind under pos on the side to move's stand, if they hold one.
func _stand_at(pos: Vector2) -> String:
	for k in stand_kinds:
		if game.hands[game.turn].get(k, 0) > 0 and _slot(game.turn, k).has_point(pos):
			return k
	return ""


# --- RPCs: sent with Net.send to everyone in the game. Senders are untrusted, so each checks seat, turn and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector3i) -> void:
	if result or not Net.may_act(Net.seats[_turn()], multiplayer.get_remote_sender_id()) or m not in game.moves():
		return
	game = game.play(m)
	last_move = m
	draw_offer = -1
	pending = []
	if game.moves().is_empty():  # ponytail: no repetition (sennichite) or impasse rules yet
		var how := "Checkmate!" if game.in_check() else "%s has no legal move." % SIDES[_turn()]
		result = "%s %s wins" % [how, _who(1 - _turn())]
	_deselect()
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
