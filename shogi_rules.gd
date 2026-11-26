class_name ShogiRules
extends RefCounted
## Shogi position on an n x n board (9 for shogi, 5 for Minishogi). play() returns a new position.
## Squares are 0..n*n-1, index = y * n + x, y = 0 is the top rank (Gote's side). Sente ("b") moves first, from the bottom.
## Pieces are side + kind, e.g. "bS", "w+R" (promoted). Captured pieces go to the captor's hand, unpromoted.
## Moves are Vector3i(from, to, promote): promote is 1 to promote. Drops have from = -1 - DROPS.find(kind).

const START := "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"
const MINI := "rbsgk/4p/5/P4/KGSBR b - 1"  # Minishogi, 5x5
const DROPS := ["R", "B", "G", "S", "N", "L", "P"]
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KING := ORTHO + DIAG
const GOLD := [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
# One-square steps and sliding directions, seen from Sente (forward = up). Gote's are mirrored vertically.
const STEPS := {
	"K": KING, "G": GOLD, "+S": GOLD, "+N": GOLD, "+L": GOLD, "+P": GOLD,
	"S": [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)],
	"N": [Vector2i(-1, -2), Vector2i(1, -2)], "P": [Vector2i(0, -1)],
	"L": [], "R": [], "B": [], "+R": DIAG, "+B": ORTHO,
}
const SLIDES := {"L": [Vector2i(0, -1)], "R": ORTHO, "B": DIAG, "+R": ORTHO, "+B": DIAG}
const PROMOTES := ["R", "B", "S", "N", "L", "P"]

var n := 9
var board: Array = []  # "" or side + kind
var turn := "b"
var hands := {"b": {}, "w": {}}  # side -> {kind: count}


static func from_sfen(sfen: String) -> ShogiRules:
	var s := ShogiRules.new()
	var parts := sfen.split(" ")
	s.n = parts[0].count("/") + 1
	var plus := false
	for ch in parts[0]:
		if ch == "/":
			continue
		if ch == "+":
			plus = true
		elif ch.is_valid_int():
			for i in int(ch):
				s.board.append("")
		else:
			s.board.append(("b" if ch == ch.to_upper() else "w") + ("+" if plus else "") + ch.to_upper())
			plus = false
	s.turn = parts[1]
	var count := 0
	for ch in parts[2].replace("-", ""):
		if ch.is_valid_int():
			count = count * 10 + int(ch)
		else:
			var side := "b" if ch == ch.to_upper() else "w"
			s.hands[side][ch.to_upper()] = maxi(count, 1)
			count = 0
	return s


func opponent() -> String:
	return "w" if turn == "b" else "b"


func king(side: String) -> int:
	return board.find(side + "K")


func in_check() -> bool:
	return attacked(king(turn), opponent())


## Every legal move for the side to move. No uchifuzume: a pawn drop may not give checkmate.
func moves() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for m in _pseudo_moves():
		var s := play(m)
		if s.attacked(s.king(turn), s.turn):
			continue
		if m.x == -1 - DROPS.find("P") and s.in_check() and not s._has_move():
			continue
		out.append(m)
	return out


func play(m: Vector3i) -> ShogiRules:
	var s := ShogiRules.new()
	s.n = n
	s.board = board.duplicate()
	s.hands = {"b": hands.b.duplicate(), "w": hands.w.duplicate()}
	s.turn = opponent()
	if m.x < 0:
		var kind: String = DROPS[-1 - m.x]
		s.board[m.y] = turn + kind
		s.hands[turn][kind] -= 1
		if s.hands[turn][kind] == 0:
			s.hands[turn].erase(kind)
		return s
	var p: String = board[m.x]
	var taken: String = board[m.y]
	if taken != "":
		var kind := taken.substr(1).trim_prefix("+")
		s.hands[turn][kind] = s.hands[turn].get(kind, 0) + 1
	s.board[m.y] = turn + "+" + p.substr(1) if m.z == 1 else p
	s.board[m.x] = ""
	return s


## Is sq attacked by side by? Walks out from sq in the 8 directions and checks the first piece met,
## then the two squares a knight could jump from.
func attacked(sq: int, by: String) -> bool:
	if sq < 0:
		return false
	var c := Vector2i(sq % n, sq / n)
	var f := 1 if by == "b" else -1
	for d in KING:
		var t: Vector2i = c + d
		var dist := 1
		while on(t):
			var p: String = board[_idx(t)]
			if p != "":
				if p[0] == by:
					var k := p.substr(1)
					var back := Vector2i(-d.x, -d.y * f)  # attacker -> sq, in the attacker's frame
					if (dist == 1 and back in STEPS[k]) or back in SLIDES.get(k, []):
						return true
				break
			t += d
			dist += 1
	for d in STEPS["N"]:
		var t: Vector2i = c - Vector2i(d.x, d.y * f)
		if on(t) and board[_idx(t)] == by + "N":
			return true
	return false


func on(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < n and t.y >= 0 and t.y < n


## Ranks in front of sq, from side's point of view.
func ahead(sq: int, side: String) -> int:
	return sq / n if side == "b" else n - 1 - sq / n


## Promotion zone: the far third of the board (3 ranks in shogi, 1 in Minishogi).
func in_zone(sq: int, side: String) -> bool:
	return ahead(sq, side) < n / 3


## A piece that could never move again from sq: pawn or lance on the last rank, knight on the last two.
func stuck(kind: String, sq: int, side: String) -> bool:
	var a := ahead(sq, side)
	return (kind in ["P", "L"] and a == 0) or (kind == "N" and a < 2)


func _has_move() -> bool:
	for m in _pseudo_moves():
		var s := play(m)
		if not s.attacked(s.king(turn), s.turn):
			return true
	return false


func _pseudo_moves() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var f := 1 if turn == "b" else -1
	var pawn_files := {}
	for i in n * n:
		var p: String = board[i]
		if not p.begins_with(turn):
			continue
		var kind := p.substr(1)
		if kind == "P":
			pawn_files[i % n] = true
		var c := Vector2i(i % n, i / n)
		for d in STEPS[kind]:
			var t: Vector2i = c + Vector2i(d.x, d.y * f)
			if on(t) and not board[_idx(t)].begins_with(turn):
				_add(i, _idx(t), kind, out)
		for d in SLIDES.get(kind, []):
			var step := Vector2i(d.x, d.y * f)
			var t: Vector2i = c + step
			while on(t) and not board[_idx(t)].begins_with(turn):
				_add(i, _idx(t), kind, out)
				if board[_idx(t)] != "":
					break
				t += step
	for kind in hands[turn]:
		for sq in n * n:
			if board[sq] == "" and not stuck(kind, sq, turn) and not (kind == "P" and pawn_files.has(sq % n)):
				out.append(Vector3i(-1 - DROPS.find(kind), sq, 0))  # pawn: no two unpromoted pawns on a file (nifu)
	return out


## A board move, plus its promoting twin when the piece starts or ends in the zone.
## Promotion is forced when the piece would otherwise be stuck.
func _add(from: int, to: int, kind: String, out: Array[Vector3i]) -> void:
	if not stuck(kind, to, turn):
		out.append(Vector3i(from, to, 0))
	if kind in PROMOTES and (in_zone(from, turn) or in_zone(to, turn)):
		out.append(Vector3i(from, to, 1))


func _idx(t: Vector2i) -> int:
	return t.y * n + t.x
