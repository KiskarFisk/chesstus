extends SceneTree
## Fischer Random and Crazyhouse rule checks. Run: godot --headless --path . -s test_variants.gd

const C := preload("res://chess_rules.gd")
var failed := false


func _init() -> void:
	# --- Fischer Random ---
	var seen := {}
	var ok := true
	for seed in 300:
		var f := C.fischer(seed)
		seen[f] = true
		var back := f.split("/")[7].split(" ")[0]
		var b1 := back.find("B")
		var b2 := back.rfind("B")
		var r1 := back.find("R")
		var r2 := back.rfind("R")
		ok = ok and b1 % 2 != b2 % 2 and r1 < back.find("K") and back.find("K") < r2 and back.count("N") == 2 \
			and back.count("Q") == 1 and C.from_fen(f).frc and C.fischer(seed) == f
	_check("fischer: bishops opposite colors, king between rooks, same seed same position", ok)
	_check("fischer: %d different positions from 300 seeds" % seen.size(), seen.size() > 200)
	_check("fischer: 16 pawn moves at the start", C.from_fen(C.fischer(7)).legal_moves().filter(func(m): return m.x < 56).size() == 16)
	# Classic setup with file letters: castling still lands on g1/f1 and c1/d1. Squares: y * 8 + x, a8 = 0.
	var s := C.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w HAha - 0 1")
	_check("fischer: king onto rook castles short", Vector2i(60, 63) in s.legal_moves() \
		and s.play(Vector2i(60, 63)).board.slice(56, 64) == ["wR", "", "", "", "", "wR", "wK", ""])
	_check("fischer: and long", s.play(Vector2i(60, 56)).board.slice(56, 64) == ["", "", "wK", "wR", "", "", "", "wR"])
	_check("fischer: no two-square king move", Vector2i(60, 62) not in s.legal_moves())
	# King b1, rook a1: castling long moves the king right to c1, rook jumps to d1.
	s = C.from_fen("4k3/8/8/8/8/8/8/RK5R w HA - 0 1")
	_check("fischer: king b1 castles long to c1", s.play(Vector2i(57, 56)).board.slice(56, 64) == ["", "", "wK", "wR", "", "", "", "wR"])
	# King g1, rook h1: castling short leaves the king put and the rook hops to f1.
	s = C.from_fen("4k3/8/8/8/8/8/8/R5KR w HA - 0 1")
	_check("fischer: king g1 castles short in place", s.play(Vector2i(62, 63)).board.slice(56, 64) == ["wR", "", "", "", "", "wR", "wK", ""])
	s = C.from_fen("4k3/8/8/8/8/8/8/RN4KR w HA - 0 1")
	_check("fischer: blocked by a piece on the rook's landing square", Vector2i(62, 56) not in s.legal_moves())
	s = C.from_fen("4kr2/8/8/8/8/8/8/1K5R w H - 0 1")
	_check("fischer: can't pass through an attacked square", Vector2i(57, 63) not in s.legal_moves())
	_check("fischer: rights go when the rook moves", C.from_fen("4k3/8/8/8/8/8/8/1K5R w H - 0 1") \
		.play(Vector2i(63, 55)).castling.is_empty())

	# --- Crazyhouse ---
	var h := C.from_fen(C.HOUSE)
	_check("house: start has empty hands, 20 moves", h.hands == {"w": {}, "b": {}} and h.legal_moves().size() == 20)
	h = C.from_fen("4k3/8/8/3p4/4P3/8/8/4K3[] w - - 0 1").play(Vector2i(36, 27))
	_check("house: capture goes to hand", h.hands.w == {"P": 1})
	var drops := h.play(Vector2i(4, 12)).legal_moves().filter(func(m): return m.x == -1 - C.DROPS.find("P"))
	_check("house: pawn drops on every empty square but the first and last rank", drops.size() == 46)
	var d := h.play(Vector2i(4, 12)).play(Vector2i(-1 - C.DROPS.find("P"), 20))
	_check("house: drop places the piece and empties the hand", d.board[20] == "wP" and d.hands.w.is_empty())
	var promo := C.from_fen("4k3/P7/8/8/8/8/8/4K2r[] w - - 0 1").play(Vector2i(8, 0))
	var back := promo.play(Vector2i(63, 7)).play(Vector2i(60, 52)).play(Vector2i(7, 0))
	_check("house: promoted queen goes to hand as a pawn", promo.board[0] == "wQ" and back.hands.b == {"P": 1})
	var ep := C.from_fen("4k3/8/8/3Pp3/8/8/8/4K3[] w - e6 0 1").play(Vector2i(27, 20))
	_check("house: en passant pawn goes to hand", ep.hands.w == {"P": 1} and ep.board[28] == "")
	var mate := C.from_fen("6k1/5ppp/8/8/8/8/8/6K1[R] w - - 0 1").play(Vector2i(-1 - C.DROPS.find("R"), 0))
	_check("house: drop mate", mate.in_check() and mate.legal_moves().is_empty())
	_check("house: dropping blocks check", Vector2i(-1 - C.DROPS.find("N"), 5) in \
		C.from_fen("4k2R/8/8/8/8/8/8/4K3[n] b - - 0 1").legal_moves())

	var mpos := C.from_fen("6k1/5ppp/8/8/8/8/8/6K1[R] w - - 0 1")
	var after := mpos.play(Bots.chess_move(mpos, 2))
	_check("bot: medium finds a drop mate", after.in_check() and after.legal_moves().is_empty())
	var busy := C.from_fen("r1bqk2r/pppp1ppp/2n2n2/4p3/1bB1P3/2N2N2/PPPP1PPP/R1BQK2R[Pp] w KQkq - 0 1")
	var t := Time.get_ticks_msec()
	Bots.chess_move(busy, 2)
	var ms := Time.get_ticks_msec() - t
	_check("bot: medium crazyhouse move with full hands in %d ms (< 3000)" % ms, ms < 3000)
	_check("bot: easy returns a legal move", Bots.chess_move(busy, 1) in busy.legal_moves())
	t = Time.get_ticks_msec()
	Bots.chess_move(C.from_fen(C.fischer(3)), 2)
	ms = Time.get_ticks_msec() - t
	_check("bot: medium fischer opening move in %d ms (< 3000)" % ms, ms < 3000)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
