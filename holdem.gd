extends Node2D
## Texas Hold'em table. Net.seats = one peer id per seat (2-4). Your two cards are face up at the bottom, the
## others sit round the table; the board and pot are in the middle. Bet with the buttons under your cards.
## ponytail: every peer holds the whole deal (shuffled from Net.game_seed), so a modded client could peek.
## Deal hole cards from the host to each player if that ever matters.

const CARD := Vector2(96, 136)
const SMALL := 0.6
const SIDES := ["White", "Black", "Yellow", "Red"]
const FELT := Color("#1d4a32")
const GOLD := Color(1, 0.9, 0.3)
const NEXT_WAIT := 5.0  # all-bot games: seconds to look at a finished hand
const H := preload("res://holdem_rules.gd")

var game: HoldemRules = H.create(Net.seats.size(), Net.game_seed)
var font := Cards.font()
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


## The seat whose cards you see: the one you're acting for right now, else your first; -1 if you have none.
func _viewer() -> int:
	var me := multiplayer.get_unique_id()
	var mine := range(game.players).filter(func(q): return Net.seats[q] == me)
	if mine.is_empty():
		return -1
	return game.turn if game.turn in mine else mine[0]


func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	var v := _viewer()
	if result or Net.watching_bots():
		_button("Back to hub", func(): Net.end_game())
	elif v != -1:
		if game.phase == H.DONE:
			_button("Next hand", func(): Net.send(_move, Vector3i(v, H.NEXT, 0)))
		elif game.turn == v:
			_betting_buttons(v)
		if game.chips[v] > 0 or game.live(v):
			_button("Leave table", func(): Net.send(_resign))
	queue_redraw()
	_maybe_bot()


func _betting_buttons(v: int) -> void:
	var call := game.to_call(v)
	_button("Fold", func(): Net.send(_move, Vector3i(v, H.FOLD, 0)))
	_button("Call %d" % call if call else "Check", func(): Net.send(_move, Vector3i(v, H.CALL, 0)))
	var all_in := game.bet[v] + game.chips[v]
	if all_in > game.high:
		var amount := SpinBox.new()
		amount.min_value = game.min_raise_to(v)
		amount.max_value = all_in
		amount.value = amount.min_value
		amount.step = 1
		amount.focus_mode = Control.FOCUS_CLICK
		buttons.add_child(amount)
		_button("Bet" if game.high == 0 else "Raise to", func():
			Net.send(_move, Vector3i(v, H.RAISE, int(amount.value))))
		_button("All in (%d)" % all_in, func(): Net.send(_move, Vector3i(v, H.RAISE, all_in)))


## Host only: a bot to act bets; when a hand is over and nobody human is seated, deal on after a pause.
func _maybe_bot() -> void:
	if result or bot_busy or not multiplayer.is_server():
		return
	if game.phase == H.DONE:
		if Net.seats.all(func(id): return id < 0):
			bot_busy = true
			get_tree().create_timer(NEXT_WAIT).timeout.connect(_deal_on.bind(game))
		return
	var seat := game.turn
	if game.phase != H.BETTING or Net.seats[seat] >= 0:
		return
	bot_busy = true
	var state := game
	Net.think(self, Bots.holdem_move.bind(state, seat, -Net.seats[seat]), func(m):
		bot_busy = false
		if game == state:
			Net.send(_move, m))


func _deal_on(state: HoldemRules) -> void:
	bot_busy = false
	if game == state:
		Net.send(_move, Vector3i(0, H.NEXT, 0))


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)


# --- Drawing ---

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), FELT)
	var center := size / 2 + Vector2(0, -20)
	buttons.position = Vector2(size.x / 2 - 260, size.y - 56)
	draw_string(ThemeDB.fallback_font, Vector2(40, 50), _status(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(ThemeDB.fallback_font, Vector2(40, 80), "Blinds %d/%d  -  hand %d" % [game.small_blind(),
		2 * game.small_blind(), game.hand_no + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
	# Board and pot.
	var x := center.x - (5 * CARD.x + 4 * 12) / 2
	for i in 5:
		var r := Rect2(Vector2(x + i * (CARD.x + 12), center.y - CARD.y / 2), CARD)
		if i < game.board.size():
			Cards.draw(self, font, r, game.board[i])
		else:
			draw_rect(r, Color(1, 1, 1, 0.08))
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 150, center.y - CARD.y / 2 - 18), "Pot %d" % game.pot(),
		HORIZONTAL_ALIGNMENT_CENTER, 300, 26, GOLD)
	# Seats: you at the bottom, the others clockwise round the table.
	var v := _viewer()
	var base := maxi(v, 0)
	var spots: Array = {2: ["bottom", "top"], 3: ["bottom", "left", "right"], 4: ["bottom", "left", "top", "right"]}[game.players]
	for i in game.players:
		var q := (base + i) % game.players
		var where: Vector2 = {"bottom": Vector2(center.x, size.y - 190), "top": Vector2(center.x, 190),
			"left": Vector2(230, center.y), "right": Vector2(size.x - 230, center.y)}[spots[i]]
		_draw_seat(q, where, q == v, center)
	_draw_log(size)


func _status() -> String:
	if result:
		return result
	if game.phase == H.DONE:
		return "Hand over. Next hand when you're ready"
	return "%s to act" % _who(game.turn)


## A seat: cards (face up if yours, or shown at the showdown), name and chips, its bet toward the middle.
func _draw_seat(q: int, at: Vector2, mine: bool, center: Vector2) -> void:
	var size := CARD if mine else CARD * SMALL
	var hand: Array = game.hands[q]
	var shown := mine or (game.phase != H.BETTING and game.live(q) and range(game.players).filter(game.live).size() > 1)
	for i in hand.size():
		var r := Rect2(at + Vector2((i - 1) * (size.x + 8) + 4, -size.y / 2), size)
		Cards.draw(self, font, r, hand[i], shown, game.folded[q])
	var col := GOLD if game.turn == q else (Color(1, 1, 1, 0.45) if hand.is_empty() or game.folded[q] else Color.WHITE)
	var label := _who(q) + ("  [D]" if game.button == q else "")
	draw_string(ThemeDB.fallback_font, at + Vector2(-200, -size.y / 2 - 30), label, HORIZONTAL_ALIGNMENT_CENTER, 400, 18, col)
	var info := "%d chips" % game.chips[q] if game.chips[q] or game.live(q) else "out"
	if game.folded[q] and not hand.is_empty():
		info += "  -  folded"
	for w in game.won:
		if w[0] == q:
			info += "  -  wins %d" % w[1] + (" (%s)" % w[2] if w[2] else "")
	draw_string(ThemeDB.fallback_font, at + Vector2(-200, -size.y / 2 - 8), info, HORIZONTAL_ALIGNMENT_CENTER, 400, 16, col)
	if game.bet[q] > 0:
		var chip := at.lerp(center, 0.45)
		draw_circle(chip, 16, Color("#c0392b"))
		draw_arc(chip, 16, 0, TAU, 24, Color.WHITE, 2, true)
		draw_string(ThemeDB.fallback_font, chip + Vector2(22, 7), str(game.bet[q]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)


func _draw_log(size: Vector2) -> void:
	var y := size.y - 40 - 24 * game.events.size()
	for e in game.events:
		var line: String = (SIDES[e[0]] + " " if e[0] >= 0 else "") + e[1]
		draw_string(ThemeDB.fallback_font, Vector2(30, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))
		y += 24


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (result or Net.watching_bots()):
		Net.end_game()


# --- RPCs: sent with Net.send to everyone in the game. Senders are untrusted, so each checks seat and state. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector3i) -> void:
	if result or m.x < 0 or m.x >= game.players or not game.ok(m):
		return
	var sender := multiplayer.get_remote_sender_id()
	var seated := Net.seats.any(func(id): return Net.may_act(id, sender))
	if not (Net.may_act(Net.seats[m.x], sender) or (game.phase == H.DONE and seated)):
		return
	game = game.play(m)
	_check_over()
	_refresh()


@rpc("any_peer", "call_local", "reliable")
func _resign() -> void:
	var sender := multiplayer.get_remote_sender_id()
	var seat := -1
	for q in game.players:  # offline you may hold several seats: the one acting, else any still playing
		if Net.seats[q] == sender and (game.turn == q or (seat == -1 and game.chips[q] + game.put[q] > 0)):
			seat = q
	if result or seat == -1:
		return
	game = game.resign(seat)
	_check_over()
	_refresh()


func _check_over() -> void:
	if game.phase == H.OVER:
		result = ("%s wins all the chips!" % _who(game.winner)) if game.winner != -1 else "Game over"
