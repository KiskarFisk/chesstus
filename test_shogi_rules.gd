extends SceneTree
## Shogi and Minishogi rule checks: perft move counts plus the special rules.
## Run: godot --headless --path . -s test_shogi_rules.gd

const P_DROP := -7  # -1 - ShogiRules.DROPS.find("P")

var failed := false


func _init() -> void:
	for c in [[ShogiRules.START, 3, 25470], [ShogiRules.MINI, 3, 2512]]:
		var n := _perft(ShogiRules.from_sfen(c[0]), c[1])
		_check("%s depth %d: %d (expected %d)" % [c[0], c[1], n, c[2]], n == c[2])

	# 5x5 squares: index = y * 5 + x, y = 0 is the top rank (Gote's side).
	var m := ShogiRules.from_sfen(ShogiRules.MINI)
	_check("mini: gote pawn moves down", m.play(Vector3i(20, 15, 0)).moves().has(Vector3i(9, 14, 0)))
	var pawn := ShogiRules.from_sfen("4k/P4/5/5/K4 b - 1").moves()
	_check("pawn must promote on the last rank", Vector3i(5, 0, 1) in pawn and Vector3i(5, 0, 0) not in pawn)
	var silver := ShogiRules.from_sfen("4k/2S2/5/5/K4 b - 1").moves()
	_check("silver may promote or not", Vector3i(7, 2, 0) in silver and Vector3i(7, 2, 1) in silver)
	var cap := ShogiRules.from_sfen("k4/5/+b4/5/R3K b - 1").play(Vector3i(20, 10, 0))
	_check("captured piece goes to hand unpromoted", cap.hands.b == {"B": 1})
	var drop := ShogiRules.from_sfen("k4/5/5/5/4K b B 1").play(Vector3i(-2, 12, 0))
	_check("dropped from hand", drop.board[12] == "bB" and drop.hands.b.is_empty())
	var nifu := ShogiRules.from_sfen("k4/5/5/P4/4K b P 1").moves()
	_check("no second pawn on a file (nifu)", Vector3i(P_DROP, 10, 0) not in nifu and Vector3i(P_DROP, 11, 0) in nifu)
	_check("no pawn drop on the last rank", Vector3i(P_DROP, 1, 0) not in nifu)
	_check("no checkmate by pawn drop (uchifuzume)",
		Vector3i(P_DROP, 5, 0) not in ShogiRules.from_sfen("kn3/5/1G3/5/4K b P 1").moves())
	_check("pawn drop check that isn't mate is fine",
		Vector3i(P_DROP, 5, 0) in ShogiRules.from_sfen("k4/5/1G3/5/4K b P 1").moves())
	var kn := ShogiRules.from_sfen("4k/5/1N3/5/K4 b - 1")
	_check("knight jumps forward only", kn.attacked(0, "b") and kn.attacked(2, "b") and not kn.attacked(20, "b"))

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok


func _perft(s: ShogiRules, depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	for m in s.moves():
		n += _perft(s.play(m), depth - 1)
	return n
