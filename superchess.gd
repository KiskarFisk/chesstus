extends Node2D
## Superchess board. Net.seats = [white, black, yellow, red] peer ids; one player may hold several seats.
## Teams: white + yellow vs black + red. Leaving needs the game to be over.

const TILE := 38
const LIGHT := Color("#eed8b5")
const DARK := Color("#b48963")
const PANEL_X := 16.0
const FRAME := 16  # wooden border around the board; black beyond it
const MODE_NAMES := {"2p": "2 players", "teams": "Teams", "ffa": "Free for all"}

var game := SuperchessRules.start(Net.game_mode if Net.game_mode in ["2p", "teams", "ffa"] else "teams")
var selected := -1
var targets: Array = []
var last_move := Vector2i(-1, -1)
var dragging := false
var drag_pos := Vector2.ZERO
var textures := {}
var draw_offer := -1  # peer id that offered a draw, -1 if none
var draw_yes := {}  # peer id -> true, players who agreed so far
var log_lines: Array = []  # recent events shown in the side panel
var buttons := VBoxContainer.new()
var bot_busy := false  # host: a bot is thinking


func _ready() -> void:
	for c in "wb":
		for p in "KQRBNP":
			textures[c + p] = load("res://pieces/%s%s.svg" % [c, p])
	get_viewport().size_changed.connect(queue_redraw)
	var layer := CanvasLayer.new()
	buttons.position = Vector2(PANEL_X, 330)
	layer.add_child(buttons)
	add_child(layer)
	_refresh()


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * TILE * SuperchessRules.N) / 2


func _me() -> int:
	return multiplayer.get_unique_id()


func _players() -> Array:  # distinct peer ids holding a seat
	var out := []
	for id in Net.seats:
		if id not in out:
			out.append(id)
	return out


## Same tint as the hub kings: yellow and red are the white set tinted.
func _tex(piece: String) -> Array:
	var c := piece[0]
	var tint: Color = Net.PLAYER_COLORS[["w", "b", "y", "r"].find(c)].tint
	return [textures[("b" if c == "b" else "w") + piece[1]], tint]


func _refresh() -> void:
	for b in buttons.get_children():
		b.queue_free()
	var me := _me()
	if game.result or Net.watching_bots():
		_button("Back to hub", Net.end_game)
	elif me in Net.seats:
		if draw_offer != -1 and not draw_yes.has(me):
			_button("Accept draw", func(): Net.send(_answer_draw, true))
			_button("Decline draw", func(): Net.send(_answer_draw, false))
		elif draw_offer == -1 and not Net.seats.any(func(id): return id < 0):  # bots don't take draws
			_button("Offer draw", func(): Net.send(_offer_draw))
		if Net.seats[game.turn] == me and game.side().any(func(c): return game.king_of(c) != -1):
			var what := "Resign" if game.mode == "2p" else "Resign %s king" % SuperchessRules.NAMES[game.color()]
			_button(what, func(): Net.send(_resign))
	queue_redraw()
	_maybe_bot()


## Host only: if a bot is to move, think on a worker thread, then play its move like anyone else's.
func _maybe_bot() -> void:
	var seat: int = Net.seats[game.turn]
	if seat >= 0 or game.result or bot_busy or not multiplayer.is_server():
		return
	bot_busy = true
	var state := game
	Net.think(self, Bots.superchess_move.bind(state, -seat), func(m):
		bot_busy = false
		if game == state:
			Net.send(_move, m))


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)


func _draw() -> void:
	var o := _origin()
	var box := StyleBoxFlat.new()  # rounded wooden border around the board's square
	box.bg_color = Color("#4a3222")
	box.border_color = Color("#6e4c33")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	draw_style_box(box, Rect2(o, Vector2.ONE * TILE * SuperchessRules.N).grow(FRAME))
	var n := SuperchessRules.N
	var checked := []
	for c in SuperchessRules.COLORS:
		if game.in_check(c) and not game.result:
			checked.append(game.king_of(c))
	for i in n * n:
		var at := Vector2i(i % n, i / n)
		if not SuperchessRules.playable(at):
			continue
		var r := Rect2(o + Vector2(at) * TILE, Vector2.ONE * TILE)
		draw_rect(r, LIGHT if (at.x + at.y) % 2 == 0 else DARK)
		if i == last_move.x or i == last_move.y:
			draw_rect(r, Color(0.6, 0.8, 0.2, 0.45))
		if i == selected:
			draw_rect(r, Color(1, 1, 0, 0.4))
		if i in checked:
			draw_rect(r, Color(1, 0, 0, 0.5))
		var p: String = game.board[i]
		if p != "" and not (dragging and not game.result and i == selected):
			var t := _tex(p)
			draw_texture_rect(t[0], r, false, t[1])
		if i in targets:
			if p[0] in game.side():  # castling onto our own rook
				draw_arc(r.get_center(), TILE / 2.0 - 3, 0, TAU, 32, Color(0.1, 0.5, 1, 0.6), 4)
			elif p != "" or (game.board[selected][1] == "P" and _diagonal(selected, i)):
				draw_arc(r.get_center(), TILE / 2.0 - 3, 0, TAU, 32, Color(0, 0, 0, 0.3), 4)
			else:
				draw_circle(r.get_center(), 6, Color(0, 0, 0, 0.3))
	if dragging and not game.result:
		var t := _tex(game.board[selected])
		draw_texture_rect(t[0], Rect2(drag_pos - Vector2.ONE * TILE / 2, Vector2.ONE * TILE), false, t[1])
	_draw_panel()


func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var y := 40.0
	draw_string(font, Vector2(PANEL_X, y), "Superchess", HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string(font, Vector2(PANEL_X + 150, y), MODE_NAMES[game.mode], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	y += 34
	for i in SuperchessRules.COLORS.size():
		var c: String = SuperchessRules.COLORS[i]
		var t := _tex(c + "K")
		var row := Rect2(PANEL_X, y - 20, 26, 26)
		draw_rect(row.grow(1), LIGHT)  # so the black king shows on the black background
		draw_texture_rect(t[0], row, false, t[1])
		var line := "%s (%s)" % [SuperchessRules.NAMES[c], Net.name_of(Net.seats[i])]
		if game.king_of(c) == -1:
			line += " - king out"
		elif game.in_check(c):
			line += " - check!"
		var moving: bool = c in game.side() and not game.result
		var col := Color.WHITE if moving else Color(1, 1, 1, 0.55)
		draw_string(font, Vector2(PANEL_X + 32, y), ("> " if moving else "") + line,
			HORIZONTAL_ALIGNMENT_LEFT, 236, 17, col)
		y += 30
	y += 10
	var status := game.result if game.result else "%s to move" % (["Light", "Dark"][game.turn] if game.mode == "2p" else SuperchessRules.NAMES[game.color()])
	if draw_offer != -1 and not game.result:
		status += "\n%s offers a draw (%d/%d agree)" % [Net.name_of(draw_offer), draw_yes.size(), _players().size()]
	for line in (status + "\n" + "\n".join(log_lines.slice(-5))).split("\n"):
		draw_string(font, Vector2(PANEL_X, y), line, HORIZONTAL_ALIGNMENT_LEFT, 268, 16)
		y += 22


static func _diagonal(a: int, b: int) -> bool:
	return a % SuperchessRules.N != b % SuperchessRules.N and a / SuperchessRules.N != b / SuperchessRules.N


func _square_at(pos: Vector2) -> int:
	var c := Vector2i(((pos - _origin()) / TILE).floor())
	return c.y * SuperchessRules.N + c.x if SuperchessRules.playable(c) else -1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (game.result or Net.watching_bots()):
		Net.end_game()
	elif event is InputEventMouseMotion and dragging:
		drag_pos = make_input_local(event).position
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not game.result:
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
		elif sq != -1 and game.board[sq] != "" and game.board[sq][0] in game.side() and Net.seats[game.turn] == _me():
			selected = sq
			targets = game.legal_moves().filter(func(m): return m.x == sq).map(func(m): return m.y)
			dragging = true
		else:
			selected = -1
			targets = []
		queue_redraw()


func _after(new_state: SuperchessRules) -> void:
	game = new_state
	log_lines.append_array(game.events)
	draw_offer = -1
	draw_yes = {}
	selected = -1
	targets = []
	dragging = false
	_refresh()


# --- RPCs: sent with Net.send to everyone in the game. Senders are untrusted. ---

@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector2i) -> void:
	if game.result or not Net.may_act(Net.seats[game.turn], multiplayer.get_remote_sender_id()) or m not in game.legal_moves():
		return
	last_move = m
	_after(game.play(m))


@rpc("any_peer", "call_local", "reliable")
func _resign() -> void:
	if game.result or multiplayer.get_remote_sender_id() != Net.seats[game.turn] or not game.side().any(func(c): return game.king_of(c) != -1):
		return
	_after(game.resign())


@rpc("any_peer", "call_local", "reliable")
func _offer_draw() -> void:
	var id := multiplayer.get_remote_sender_id()
	if game.result or id not in Net.seats or draw_offer != -1:
		return
	draw_offer = id
	draw_yes = {id: true}
	_check_draw()


@rpc("any_peer", "call_local", "reliable")
func _answer_draw(yes: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if game.result or id not in Net.seats or draw_offer == -1:
		return
	if yes:
		draw_yes[id] = true
	else:
		log_lines.append("%s declines the draw" % Net.name_of(id))
		draw_offer = -1
		draw_yes = {}
	_check_draw()


func _check_draw() -> void:
	if draw_offer != -1 and _players().all(func(p): return draw_yes.has(p)):
		game.result = "Draw agreed"
	_refresh()
