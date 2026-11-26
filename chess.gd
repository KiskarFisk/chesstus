extends Node2D

const TILE := 64

var game := ChessRules.from_fen(ChessRules.START)
var selected := -1
var targets: Array = []
var textures := {}


func _ready() -> void:
	for c in "wb":
		for p in "KQRBNP":
			textures[c + p] = load("res://pieces/%s%s.svg" % [c, p])
	get_viewport().size_changed.connect(queue_redraw)


func _origin() -> Vector2:
	return (get_viewport_rect().size - Vector2.ONE * TILE * 8) / 2


func _status() -> String:
	var side := "White" if game.turn == "w" else "Black"
	if game.legal_moves().is_empty():
		return ("Checkmate! %s wins" % ("Black" if game.turn == "w" else "White")) if game.in_check() else "Stalemate"
	var you := ("You are %s. " % ("White" if Net.my_color() == "w" else "Black")) if Net.online() else ""
	return you + side + (" to move - check!" if game.in_check() else " to move")


func _draw() -> void:
	var o := _origin()
	var check_sq := game.board.find(game.turn + "K") if game.in_check() else -1
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
	draw_string(font, o + Vector2(0, -16), _status(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(font, o + Vector2(0, TILE * 8 + 32), "Esc: back to hub", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Net.goto.rpc("res://hub.tscn")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(((get_local_mouse_position() - _origin()) / TILE).floor())
		if not ChessRules._on(c):
			return
		var sq := c.y * 8 + c.x
		if sq in targets:
			_move.rpc(Vector2i(selected, sq))
		elif game.board[sq].begins_with(game.turn) and (not Net.online() or game.turn == Net.my_color()):
			selected = sq
			targets = game.legal_moves().filter(func(m): return m.x == sq).map(func(m): return m.y)
		else:
			selected = -1
			targets = []
		queue_redraw()


## Every move goes through here, local or remote. The sender is untrusted: check turn and legality.
@rpc("any_peer", "call_local", "reliable")
func _move(m: Vector2i) -> void:
	if Net.online() and Net.color_of(multiplayer.get_remote_sender_id()) != game.turn:
		return
	if m not in game.legal_moves():
		return
	game = game.play(m)
	selected = -1
	targets = []
	queue_redraw()
