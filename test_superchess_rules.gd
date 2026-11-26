extends SceneTree
## Superchess rule checks. Run: godot --headless --path . -s test_superchess_rules.gd

const S := preload("res://superchess_rules.gd")
var failed := false


func _init() -> void:
	var s := S.start()
	var playable := 0
	for i in S.N * S.N:
		playable += int(S.playable(Vector2i(i % S.N, i / S.N)))
	_check("148 playable squares", playable == 148)
	_check("68 pieces at start", s.board.filter(func(p): return p != "").size() == 68)
	# 8 down pawns + 8 right pawns + 4 point pawn + 2+2 knights + 2 castles
	_check("white has 26 opening moves", s.legal_moves().size() == 26)

	var t := s.play(_m("e10", "f10"))
	_check("point pawn commits to its direction", t.board[S.sq_of("f10")] == "wPr")
	_check("turn passes clockwise to black", t.color() == "b")

	t = s.play(_m("c12", "a11"))
	_check("castling swaps king and rook", t.board[S.sq_of("a11")] == "wK" and t.board[S.sq_of("c12")] == "wR")
	_check("castling uses up that army's rights", not t.castling.any(func(r): return t.board[r].begins_with("w")))

	t = _pos({"e7": "wR"})
	_check("sliders stop at the hole", not _targets(t, "e7").any(func(sq): return sq % S.N >= 5))
	t = _pos({"e9": "wN"})
	var kn := _targets(t, "e9")
	_check("knights jump over the hole corner", S.sq_of("g10") in kn and S.sq_of("f7") not in kn)

	t = _pos({"e7": "wQ", "e6": "yP" + "u"})
	_check("can't capture your partner", S.sq_of("e6") not in _targets(t, "e7"))

	t = _pos({"k1": "yK", "k12": "bR", "k6": "wB", "m5": ""})
	_check("can't expose your partner's king", _targets(t, "k6").is_empty())

	# White mates the black king on k14; black's turn removes it and play moves on to yellow.
	var mate := {"k14": "bK", "m10": "", "f13": "wR", "g12": "wR"}
	t = _pos(mate).play(_m("g12", "g14"))
	_check("checkmated king is removed on its turn", t.king_of("b") == -1 and t.color() == "y" and t.result == "")
	mate["b5"] = ""  # no red king either: both dark kings gone
	t = _pos(mate).play(_m("g12", "g14"))
	_check("two kings down wins", t.result == "White and Yellow win!")

	t = _pos({"a5": "wPd"}).play(_m("a5", "a4"))
	_check("promotes at the end of its file", t.board[S.sq_of("a4")] == "wQ")
	t = _pos({"e5": "wPd", "f4": "rN"}).play(_m("e5", "f4"))
	_check("capture into a new frontier promotes", t.board[S.sq_of("f4")] == "wQ")
	t = _pos({"e5": "wPd"}).play(_m("e5", "e4"))
	_check("plain step doesn't promote", t.board[S.sq_of("e4")] == "wPd")

	t = _pos({"a5": "rPu", "b7": "wPd"}, "r").play(_m("a5", "a7"))
	_check("double step sets en passant", t.ep.get("target") == S.sq_of("a6"))
	t = t.play(_m("b7", "a6"))
	_check("en passant captures", t.board[S.sq_of("a7")] == "" and t.board[S.sq_of("a6")] == "wPd")

	t = S.start().resign()
	_check("resigning removes your king and passes the turn", t.king_of("w") == -1 and t.color() == "b")

	# --- 2 players: light (white + yellow) vs dark, any piece of either army per turn ---
	t = S.start("2p")
	_check("2p: light can move both armies (26 + 26)", t.legal_moves().size() == 52)
	t = t.play(_m("k5", "k7"))  # a yellow move on light's turn
	_check("2p: then dark moves", t.color() == "b" and t.side() == ["b", "r"])
	# A black knight forks both light kings: light saves one, the other is mated on the same turn.
	t = _pos({"b10": "", "m5": "", "f10": "wK", "j10": "yK", "h11": "bN"}, "w", "2p")
	t = t.play(t.legal_moves()[0])
	_check("2p: double check costs a king the same turn",
		(t.king_of("w") == -1) != (t.king_of("y") == -1) and t.color() == "b" and t.result == "")
	t = _pos({"m10": "", "b5": "", "k14": "bK", "f13": "wR", "j7": "wR"}, "w", "2p").play(_m("m5", "m6"))
	_check("2p: stalemate is a draw", t.result == "Draw: Dark is stalemated")

	# --- free for all ---
	t = S.start("ffa")
	_check("ffa: same opening moves", t.legal_moves().size() == 26)
	t = _pos({"e7": "wQ", "e6": "yPu"}, "w", "ffa")
	_check("ffa: anyone can be captured", S.sq_of("e6") in _targets(t, "e7"))
	t = _pos({"k14": "bK", "m10": "", "f13": "wR", "g12": "wR", "k10": "bP" + "d"}, "w", "ffa").play(_m("g12", "g14"))
	_check("ffa: a mated army leaves the board", t.king_of("b") == -1 and t.board[S.sq_of("k10")] == "" \
		and t.color() == "y" and t.result == "")
	t = _pos({"k14": "bK", "m10": "", "f13": "wR", "g12": "wR", "m5": "", "b5": ""}, "w", "ffa").play(_m("g12", "g14"))
	_check("ffa: last king standing wins", t.result == "White wins!")

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


## Empty board with a king for every army (overridable; "" removes), plus the given pieces.
func _pos(pieces: Dictionary, turn := "w", mode := "teams") -> SuperchessRules:
	var s := S.start(mode)
	s.board.fill("")
	s.castling = []
	var all := {"b10": "wK", "m10": "bK", "m5": "yK", "b5": "rK"}
	all.merge(pieces, true)
	for k in all:
		s.board[S.sq_of(k)] = all[k]
	s.turn = S.COLORS.find(turn)
	return s


func _m(a: String, b: String) -> Vector2i:
	return Vector2i(S.sq_of(a), S.sq_of(b))


func _targets(s: SuperchessRules, from: String) -> Array:
	return s.legal_moves().filter(func(m): return m.x == S.sq_of(from)).map(func(m): return m.y)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
