extends SceneTree
## Four-player chess checks: board shape, setup, castling, promotion, points. Run: godot --headless --path . -s test_fourchess.gd

const S := preload("res://superchess_rules.gd")
var failed := false


func _init() -> void:
	var n := 0
	for i in S.N * S.N:
		n += int(S.playable(Vector2i(i % S.N, i / S.N), true))
	_check("160 squares (14x14 less four 3x3 corners)", n == 160)
	var s := S.start("ffa", true)
	var at := func(sq): return s.board[S.sq_of(sq)]
	_check("White: Q g1, K h1, rooks d1 k1", at.call("g1") == "wQ" and at.call("h1") == "wK" and at.call("d1") == "wR" and at.call("k1") == "wR")
	_check("Black: K a7, Q a8", at.call("a7") == "bK" and at.call("a8") == "bQ")
	_check("Yellow: K g14, Q h14", at.call("g14") == "yK" and at.call("h14") == "yQ")
	_check("Red: K n8, Q n7", at.call("n8") == "rK" and at.call("n7") == "rQ")
	_check("16 pieces each", S.COLORS.all(func(c): return s.board.filter(func(p): return p.begins_with(c)).size() == 16))
	_check("White opens with 20 moves", s.legal_moves().size() == 20)
	# Castling: clear White's back rank, king short to j1, rook to i1.
	var c := S.start("ffa", true)
	for sq in ["e1", "f1", "g1", "i1", "j1"]:
		c.board[S.sq_of(sq)] = ""
	var short := Vector2i(S.sq_of("h1"), S.sq_of("j1"))
	var long := Vector2i(S.sq_of("h1"), S.sq_of("f1"))
	_check("castles both ways", short in c.legal_moves() and long in c.legal_moves())
	var after := c.play(short)
	_check("short castle: king j1, rook i1", after.board[S.sq_of("j1")] == "wK" and after.board[S.sq_of("i1")] == "wR" and after.board[S.sq_of("k1")] == "")
	# Promotion on the 8th rank (the middle), worth 1 point when taken.
	var p := S.start("ffa", true)
	p.board[S.sq_of("e7")] = "wPu"
	p.board[S.sq_of("e2")] = ""
	var promo := p.play(Vector2i(S.sq_of("e7"), S.sq_of("e8")))
	_check("white pawn promotes on e8", promo.board[S.sq_of("e8")] == "wQ*")
	var cap := S.start("ffa", true)
	cap.board[S.sq_of("e3")] = "bN"
	var taken := cap.play(Vector2i(S.sq_of("d2"), S.sq_of("e3")))
	_check("capture scores the piece's points", taken.points.w == 3)
	_check("medium bot plays a legal move", Bots.superchess_move(s, 2) in s.legal_moves())
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
