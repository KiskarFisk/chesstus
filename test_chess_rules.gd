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


func _init() -> void:
	var failed := false
	for c in CASES:
		var n := _perft(ChessRules.from_fen(c[0]), c[1])
		print("%s depth %d: %d (expected %d)" % [c[0], c[1], n, c[2]])
		failed = failed or n != c[2]
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _perft(s: ChessRules, depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	for m in s.legal_moves():
		n += _perft(s.play(m), depth - 1)
	return n
