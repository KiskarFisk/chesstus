extends Node2D
## Cribbage table. Net.seats = one peer id per seat (2, 3 or 4; with 4, seats 0 + 2 are partners against 1 + 3).
## Your hand is face up at the bottom, the others' backs sit around the table and the pegboard runs along the top.
## Click cards to pick your discards, then Send to crib; in play, click a card to lay it on the count.
## ponytail: every peer holds the whole deal (it's shuffled from Net.game_seed), so a modded client could peek.
## Deal it from the host to each player if that ever matters.

const CARD := Vector2(96, 136)
const SMALL := 0.6  # others' hands, the starter and crib, the show
const SIDES := ["White", "Black", "Yellow", "Red"]
const PEG := [Color("#f4f0e6"), Color("#202020"), Color(1.0, 0.82, 0.15), Color(1.0, 0.3, 0.25)]
const FELT := Color("#1d4a32")
const SHOW_WAIT := 6.0  # all-bot games: seconds to read the show before the next deal
const C := preload("res://cribbage_rules.gd")

var game: CribbageRules = C.create(Net.seats.size(), Net.game_seed)
var font := Cards.font()
var picked: Array = []  # cards you've clicked to discard
var result := ""
var buttons := HBoxContainer.new()
var bot_busy := false


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _who(seat: int) -> String:
	var id: int = Net.seats[seat]
	var you := ", you" if Net.online() and id == multiplayer.get_unique_id() else ""
	return "%s (%s%s)" % [SIDES[seat], Net.name_of(id), you]


func _team_name(t: int) -> String:
	return "%s + %s" % [SIDES[t], SIDES[t + 2]] if game.players == 4 else SIDES[t]


## The seat whose hand you see: the one you're acting for right now (offline you may hold several), -1 if none.
func _viewer() -> int:
	var me := multiplayer.get_unique_id()
	var mine := range(game.players).filter(func(q): return Net.seats[q] == me)
	if mine.is_empty():
		return -1
	if game.phase == C.DISCARD:
		for q in mine:
			if game.hands[q].size() > 4:
				return q
	if game.phase == C.PLAY and game.turn in mine:
		return game.turn
	return mine[0]


func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	var v := _viewer()
	if result or Net.watching_bots():
		_button("Back to hub", func(): Net.end_game())
	elif v != -1:
		if game.phase == C.DISCARD and game.hands[v].size() > 4:
			var send := _button("Send to crib", func():
				Net.send(_move, Vector3i(v, picked[0], picked[1] if picked.size() > 1 else -1)))
			send.disabled = picked.size() != game.discards()
		elif game.phase == C.SHOW:
			_button("Next deal", func(): Net.send(_move, Vector3i(v, -1, -1)))
		_button("Resign", func(): Net.send(_resign))
	queue_redraw()
	_maybe_bot()


## Host only: let a bot act if one is due. Discards happen all at once, so a bot's choice is re-checked
## against the current state rather than requiring nothing else to have happened.
func _maybe_bot() -> void:
	if result or bot_busy or not multiplayer.is_server():
		return
	var seat := -1
	match game.phase:
		C.DISCARD:
			for q in game.players:
				if Net.seats[q] < 0 and game.hands[q].size() > 4:
					seat = q
					break
		C.PLAY:
			if Net.seats[game.turn] < 0:
				seat = game.turn
		C.SHOW:
			if Net.seats.all(func(id): return id < 0):  # nobody to press Next deal
				bot_busy = true
				get_tree().create_timer(SHOW_WAIT).timeout.connect(_deal_on.bind(game))
			return
	if seat == -1:
		return
	bot_busy = true
	Net.think(self, Bots.cribbage_move.bind(game, seat, -Net.seats[seat]), func(m):
		bot_busy = false
		if game.ok(m) and Net.seats[m.x] < 0:
			Net.send(_move, m)
		else:
			_maybe_bot())


func _deal_on(state: CribbageRules) -> void:
	bot_busy = false
	if game == state:
		Net.send(_move, Vector3i(0, -1, -1))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)
	return b


# --- Drawing ---

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), FELT)
	var bottom := _draw_board(size)
	buttons.position = Vector2(size.x / 2 - 120, size.y - 56)
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 740, bottom + 36), _status(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if not game.shown.is_empty():
		_draw_show(size)
	else:
		_draw_table(size)
	_draw_log(size)


func _status() -> String:
	if result:
		return result
	var v := _viewer()
	match game.phase:
		C.DISCARD:
			if v != -1 and game.hands[v].size() > 4:
				var n := game.discards()
				return "Pick %d card%s for %s crib" % [n, "s" if n > 1 else "", SIDES[game.dealer] + "'s"]
			return "Waiting for the others to discard"
		C.PLAY:
			return "%s to play" % _who(game.turn)
	return "The show. Next deal when you're ready"


## Pegboard along the top: a row of holes per team, front and back peg, score at the end. Returns its bottom y.
func _draw_board(size: Vector2) -> float:
	var x0 := size.x / 2 - 750
	var rows := game.teams()
	var r := Rect2(x0, 16, 1500, 24 + rows * 30)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#7a5230")
	box.border_color = Color("#4a3222")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	draw_style_box(box, r)
	var hole := func(i: int) -> float: return x0 + 150 + i * 10.4 + (i / 5) * 2.6
	for t in rows:
		var y := r.position.y + 27 + t * 30
		draw_string(ThemeDB.fallback_font, Vector2(x0 + 12, y + 6), _team_name(t), HORIZONTAL_ALIGNMENT_LEFT, 130, 16)
		for i in C.GOAL + 1:
			draw_circle(Vector2(hole.call(i), y), 2.5 if i % 5 else 3.2, Color("#3a2414"))
		for peg in [game.backs[t], game.scores[t]]:
			draw_circle(Vector2(hole.call(peg), y), 6, PEG[t])
			draw_arc(Vector2(hole.call(peg), y), 6, 0, TAU, 16, Color.BLACK, 1.5, true)
		draw_string(ThemeDB.fallback_font, Vector2(hole.call(C.GOAL) + 14, y + 7), str(game.scores[t]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	return r.end.y


func _draw_table(size: Vector2) -> void:
	var center := Vector2(size.x / 2, size.y / 2 + 10)
	var v := _viewer()
	var base := maxi(v, 0)  # spectators see the table from seat 0
	# Count: the cards played since it was last 0, overlapping.
	var n := game.pile.size()
	var x := center.x - (CARD.x + 40 * maxi(n - 1, 0)) / 2
	for i in n:
		_draw_card(Rect2(Vector2(x + 40 * i, center.y - CARD.y / 2), CARD), game.pile[i])
	if game.phase == C.PLAY:
		draw_string(ThemeDB.fallback_font, Vector2(center.x - 100, center.y - CARD.y / 2 - 14), "Count %d" % game.count,
			HORIZONTAL_ALIGNMENT_CENTER, 200, 26)
	# Starter and crib, left of the count.
	var small := CARD * SMALL
	var at := Vector2(center.x - 440, center.y - small.y / 2)
	_draw_card(Rect2(at, small), game.starter, game.starter != -1)
	_label(at + Vector2(-40, small.y + 22), "Starter", Color.WHITE, small.x + 80)
	at.x += small.x + 30
	for i in game.crib.size():
		_draw_card(Rect2(at + Vector2(i * 6, -i * 3), small), -1, false)
	_label(at + Vector2(-40, small.y + 22), "%s's crib" % SIDES[game.dealer], Color.WHITE, small.x + 80)
	# Everyone else's hand, face down, round the table clockwise from you.
	var spots: Array = {2: [null, "top"], 3: [null, "left", "right"], 4: [null, "left", "top", "right"]}[game.players]
	for i in range(1, game.players):
		var q := (base + i) % game.players
		var where: Vector2 = {"top": Vector2(size.x / 2, 250), "left": Vector2(200, center.y), "right": Vector2(size.x - 200, center.y)}[spots[i]]
		_draw_backs(q, where)
	if v == -1:
		_draw_backs(0, Vector2(size.x / 2, size.y - 160))
		return
	# Your hand.
	var rects := _hand_rects(v)
	for i in rects.size():
		var c: int = game.hands[v][i]
		var dim := game.phase == C.PLAY and (game.turn != v or not game.ok(Vector3i(v, c, -1)))
		_draw_card(rects[i], c, true, dim)
	var name_y := (rects[0].position.y if not rects.is_empty() else size.y - 200) - 34
	var col := Color(1, 0.9, 0.3) if game.turn == v else Color.WHITE
	_label(Vector2(size.x / 2 - 300, name_y), _who(v) + (" - dealer" if game.dealer == v else ""), col, 600)


## A seat's cards as small backs, its name above (yellow on its turn).
func _draw_backs(q: int, center: Vector2) -> void:
	var small := CARD * SMALL
	var n: int = game.hands[q].size()
	var x := center.x - (small.x + 22 * maxi(n - 1, 0)) / 2
	for i in n:
		_draw_card(Rect2(Vector2(x + 22 * i, center.y - small.y / 2), small), -1, false)
	var col := Color(1, 0.9, 0.3) if game.turn == q else Color.WHITE
	_label(Vector2(center.x - 160, center.y - small.y / 2 - 14), _who(q) + (" - dealer" if game.dealer == q else ""), col, 320)


## The show: each hand with the starter and what it scored, in counting order.
func _draw_show(size: Vector2) -> void:
	var small := CARD * SMALL
	var y := 190.0
	for row in game.shown:
		var x := size.x / 2 - 520
		_label(Vector2(x, y + small.y / 2 + 8), "%s %s" % [SIDES[row[0]], "crib" if row[3] else "hand"], Color.WHITE, 150, HORIZONTAL_ALIGNMENT_LEFT)
		x += 160
		for c in row[1]:
			_draw_card(Rect2(Vector2(x, y), small), c)
			x += small.x + 8
		x += 16
		_draw_card(Rect2(Vector2(x, y), small), game.starter)
		x += small.x + 30
		var d: Dictionary = row[2]
		var parts := d.keys().filter(func(k): return d[k] > 0).map(func(k): return "%s %d" % [k, d[k]])
		var text := "%d   %s" % [C.total(d), ", ".join(PackedStringArray(parts))] if parts else "0"
		_label(Vector2(x, y + small.y / 2 + 8), text, Color.WHITE, 500, HORIZONTAL_ALIGNMENT_LEFT)
		y += small.y + 18


## Recent plays and points, bottom left.
func _draw_log(size: Vector2) -> void:
	var y := size.y - 40 - 24 * game.events.size()
	for e in game.events:
		var line: String = "%s %s" % [SIDES[e[0]], e[2]] + (" +%d" % e[1] if e[1] else "")
		draw_string(ThemeDB.fallback_font, Vector2(30, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(1, 0.9, 0.3) if e[1] else Color(1, 1, 1, 0.75))
		y += 24


func _label(pos: Vector2, text: String, col := Color.WHITE, width := 200.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, align, width, 18, col)


func _draw_card(r: Rect2, c: int, up := true, dim := false) -> void:
	Cards.draw(self, font, r, c, up, dim)


## Your cards along the bottom; ones picked for the crib sit raised.
func _hand_rects(v: int) -> Array[Rect2]:
	var size := get_viewport_rect().size
	var hand: Array = game.hands[v]
	var width := hand.size() * (CARD.x + 12) - 12
	var out: Array[Rect2] = []
	for i in hand.size():
		var lift := 26 if hand[i] in picked else 0
		out.append(Rect2(Vector2(size.x / 2 - width / 2 + i * (CARD.x + 12), size.y - CARD.y - 80 - lift), CARD))
	return out


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (result or Net.watching_bots()):
		Net.end_game()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not result:
		var v := _viewer()
		if v == -1:
			return
		var pos: Vector2 = make_input_local(event).position
		var rects := _hand_rects(v)
		for i in rects.size():
			if not rects[i].has_point(pos):
				continue
			var c: int = game.hands[v][i]
			if game.phase == C.DISCARD and game.hands[v].size() > 4:
				if c in picked:
					picked.erase(c)
				else:
					picked.append(c)
					if picked.size() > game.discards():
						picked.pop_front()
				_refresh()
			elif game.phase == C.PLAY and game.ok(Vector3i(v, c, -1)):
				Net.send(_move, Vector3i(v, c, -1))
			return


# --- RPCs: sent with Net.send to everyone in the game. Senders are untrusted, so each checks seat and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector3i) -> void:
	if result or m.x < 0 or m.x >= game.players or not game.ok(m):
		return
	var sender := multiplayer.get_remote_sender_id()
	var seated := Net.seats.any(func(id): return Net.may_act(id, sender))
	if not (Net.may_act(Net.seats[m.x], sender) or (game.phase == C.SHOW and seated)):
		return
	game = game.play(m)
	var v := _viewer()
	picked = picked.filter(func(c): return game.phase == C.DISCARD and v != -1 and c in game.hands[v])
	if game.phase == C.OVER:
		result = "%s win%s with 121!" % [_team_name(game.winner), "" if game.players == 4 else "s"]
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _resign() -> void:
	var seat := Net.seats.find(multiplayer.get_remote_sender_id())
	if result or seat == -1:
		return
	result = "%s resigns." % _who(seat)
	if game.teams() == 2:
		result += " %s win%s" % [_team_name(1 - game.team(seat)), "" if game.players == 4 else "s"]
	_refresh()
