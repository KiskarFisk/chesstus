extends SceneTree
## Bot sanity checks. Run: godot --headless --path . -s test_bots.gd

const B := preload("res://bots.gd")
const C := preload("res://chess_rules.gd")
const S := preload("res://superchess_rules.gd")
var failed := false


func _init() -> void:
	var mate := B.chess_move(C.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"), 2)
	_check("medium chess finds mate in one (Ra8#)", mate == Vector2i(56, 0))
	var free := B.chess_move(C.from_fen("4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1"), 2)
	_check("medium chess takes a free queen", free == Vector2i(59, 27))
	var bait := B.chess_move(C.from_fen("4k3/8/4p3/3p4/8/8/8/3QK3 w - - 0 1"), 2)
	_check("medium chess won't trade its queen for a guarded pawn", bait != Vector2i(59, 27))
	var greedy := B.chess_move(C.from_fen("4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1"), 1)
	_check("easy chess returns a legal move", greedy in C.from_fen("4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1").legal_moves())

	var t := Time.get_ticks_msec()
	B.chess_move(C.from_fen(C.START), 2)
	var ms := Time.get_ticks_msec() - t
	_check("medium chess opening move in %d ms (< 3000)" % ms, ms < 3000)

	var s := _pos({"e7": "wR", "a7": "bQ"})
	_check("medium superchess takes a free queen", B.superchess_move(s, 2) == Vector2i(S.sq_of("e7"), S.sq_of("a7")))
	t = Time.get_ticks_msec()
	B.superchess_move(S.start(), 2)
	ms = Time.get_ticks_msec() - t
	_check("medium superchess opening move in %d ms (< 3000)" % ms, ms < 3000)
	_check("easy superchess returns a legal move", B.superchess_move(S.start(), 1) in S.start().legal_moves())

	const G := preload("res://shogi_rules.gd")
	var rook := G.from_sfen("4k/5/r4/5/R3K b - 1")
	_check("medium shogi takes a free rook", B.shogi_move(rook, 2) == Vector3i(20, 10, 0))
	_check("easy shogi returns a legal move", B.shogi_move(G.from_sfen(G.START), 1) in G.from_sfen(G.START).moves())
	for start in [G.START, G.MINI]:
		t = Time.get_ticks_msec()
		B.shogi_move(G.from_sfen(start), 2)
		ms = Time.get_ticks_msec() - t
		_check("medium shogi opening move on %dx%d in %d ms (< 3000)" % [G.from_sfen(start).n, G.from_sfen(start).n, ms], ms < 3000)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _pos(pieces: Dictionary) -> SuperchessRules:
	var s := S.start()
	s.board.fill("")
	s.castling = []
	var all := {"b10": "wK", "m10": "bK", "m5": "yK", "b5": "rK"}
	all.merge(pieces, true)
	for k in all:
		s.board[S.sq_of(k)] = all[k]
	return s


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
