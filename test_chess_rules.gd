extends SceneTree
## Perft move-count check against known values.
## Run: godot --headless --path . -s test_chess_rules.gd

const CASES := [
	[ChessRules.START, 3, 8902],
	# "Kiwipete": castling, en passant, pins
	["r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97862],
	# en passant discovered checks along a rank
	["8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 3, 2812],
]


var failed := false


func _init() -> void:
	for c in CASES:
		var n := _perft(ChessRules.from_fen(c[0]), c[1])
		_check("%s depth %d: %d (expected %d)" % [c[0], c[1], n, c[2]], n == c[2])

	# Baby Chess (5x5). Squares: index = y * 5 + x, y = 0 is rank 5.
	var b := ChessRules.from_fen(ChessRules.BABY)
	_check("baby: 5x5 board", b.n == 5 and b.board.size() == 25)
	_check("baby: 7 opening moves (5 pawn steps, 2 knight)", b.legal_moves().size() == 7)
	_check("baby: no double step while blocked", _targets(b, 15) == [10])
	var w := ChessRules.from_fen("k4/5/5/5/R3K w Q - 0 1")
	_check("baby: white castles e1-c1, rook to d1", Vector2i(24, 22) in w.legal_moves() \
		and w.play(Vector2i(24, 22)).board.slice(20, 25) == ["", "", "wK", "wR", ""])
	var bl := ChessRules.from_fen("k3r/5/5/5/4K b k - 0 1")
	_check("baby: black castles a5-c5, rook to b5", Vector2i(0, 2) in bl.legal_moves() and bl.play(Vector2i(0, 2)).board.slice(0, 5) == ["", "bR", "bK", "", ""])
	var e := ChessRules.from_fen("4k/1p3/5/P4/K4 b - - 0 1").play(Vector2i(6, 16))
	_check("baby: double step when possible + en passant", e.ep == 11 and e.play(Vector2i(15, 11)).board[16] == "")
	_check("baby: promotion on the last rank", ChessRules.from_fen("4k/P4/5/5/K4 w - - 0 1").play(Vector2i(5, 0)).board[0] == "wQ")
	_check("baby: can't castle out of check", Vector2i(24, 22) not in ChessRules.from_fen("k3r/5/5/5/R3K w Qk - 0 1").legal_moves())

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _targets(s: ChessRules, from: int) -> Array:
	return s.legal_moves().filter(func(m): return m.x == from).map(func(m): return m.y)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok


func _perft(s: ChessRules, depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	for m in s.legal_moves():
		n += _perft(s.play(m), depth - 1)
	return n
