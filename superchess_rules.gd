class_name SuperchessRules
extends RefCounted
## Superchess (Rolf W. Jacobson): four armies on a 14x14 board with cut corners and a 4x4 hole.
## Rules: https://www.chessvariants.com/multiplayer.dir/superchess.html
## Squares are 0..195, index = y * 14 + x, x = file a..n, y = 0 is rank 14 (top).
## Pieces are color + type, pawns add their direction(s): "wPd" moves down, point pawn "wPrd" may pick r or d.
## Moves are Vector2i(from, to). Castling is the king moving onto its own rook's square (they swap).

const N := 14
const COLORS := ["w", "b", "y", "r"]  # turn order, clockwise
const NAMES := {"w": "White", "b": "Black", "y": "Yellow", "r": "Red"}
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KNIGHT := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
const DIRS := {"u": Vector2i(0, -1), "d": Vector2i(0, 1), "l": Vector2i(-1, 0), "r": Vector2i(1, 0)}
# Center cell of each army's home quadrant; home + dir * 5 lands in the frontier that pawn marches through.
const HOME := {"w": Vector2i(2, 2), "b": Vector2i(11, 2), "y": Vector2i(11, 11), "r": Vector2i(2, 11)}
const SETUP := {
	"w": {"K": ["c12"], "Q": ["d11"], "R": ["d14", "a11"], "B": ["d12", "c11"], "N": ["d13", "b11"],
		"Pr": ["e14", "e13", "e12", "e11"], "Pd": ["a10", "b10", "c10", "d10"], "Prd": ["e10"]},
	"b": {"K": ["l12"], "Q": ["k11"], "R": ["k14", "n11"], "B": ["k12", "l11"], "N": ["k13", "m11"],
		"Pl": ["j14", "j13", "j12", "j11"], "Pd": ["k10", "l10", "m10", "n10"], "Pld": ["j10"]},
	"y": {"K": ["l3"], "Q": ["k4"], "R": ["k1", "n4"], "B": ["k3", "l4"], "N": ["k2", "m4"],
		"Pl": ["j1", "j2", "j3", "j4"], "Pu": ["k5", "l5", "m5", "n5"], "Plu": ["j5"]},
	"r": {"K": ["c3"], "Q": ["d4"], "R": ["d1", "a4"], "B": ["d3", "c4"], "N": ["d2", "b4"],
		"Pr": ["e1", "e2", "e3", "e4"], "Pu": ["a5", "b5", "c5", "d5"], "Pru": ["e5"]},
}

var board: Array = []
var turn := 0  # index into COLORS
var castling: Array = []  # rook squares that may still castle (removed when the king or that rook moves)
var ep := {}  # {"target": sq, "pawn": sq} for the very next turn only
var pawn_starts := {}  # color -> squares; a pawn there hasn't moved yet (pawns never move backwards)
var result := ""  # non-empty when the game is over
var events: Array = []  # what happened automatically after the last move (mates, passes)


static func start() -> SuperchessRules:
	var s := SuperchessRules.new()
	s.board.resize(N * N)
	s.board.fill("")
	for c in SETUP:
		s.pawn_starts[c] = []
		for kind in SETUP[c]:
			for name in SETUP[c][kind]:
				var sq := sq_of(name)
				s.board[sq] = c + kind
				if kind == "R":
					s.castling.append(sq)
				elif kind[0] == "P":
					s.pawn_starts[c].append(sq)
	return s


static func sq_of(name: String) -> int:
	return (N - int(name.substr(1))) * N + (name.unicode_at(0) - 97)


static func team(color: String) -> int:
	return 0 if color == "w" or color == "y" else 1


static func partner(color: String) -> String:
	return {"w": "y", "y": "w", "b": "r", "r": "b"}[color]


static func playable(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return false
	if c.x >= 5 and c.x <= 8 and c.y >= 5 and c.y <= 8:
		return false  # center hole
	var cx := mini(c.x, N - 1 - c.x)
	var cy := mini(c.y, N - 1 - c.y)
	return not ((cy <= 1 and cx <= 2) or (cy == 2 and cx <= 1))  # 8 cut squares per corner


## "TL"/"TR"/"BL"/"BR" army quadrants, "T"/"B"/"L"/"R" frontiers (empty at the start).
static func region(c: Vector2i) -> String:
	var xs := "L" if c.x <= 4 else ("R" if c.x >= 9 else "")
	var ys := "T" if c.y <= 4 else ("B" if c.y >= 9 else "")
	return ys + xs


func color() -> String:
	return COLORS[turn]


func king_of(c: String) -> int:
	return board.find(c + "K")


func in_check(c: String) -> bool:
	var k := king_of(c)
	return k != -1 and attacked(k, 1 - team(c))


func legal_moves() -> Array[Vector2i]:
	var c := color()
	var p := partner(c)
	var partner_was_safe := not in_check(p)
	var out: Array[Vector2i] = []
	for m in _pseudo_moves(c):
		var s := _apply(m)
		# Can't leave yourself in check, or put your partner into check (a check they were already in may stand).
		if s.in_check(c) or (partner_was_safe and s.in_check(p)):
			continue
		out.append(m)
	return out


## Make a move, then run the automatic part of the next turns: checkmated kings are removed and
## players without a legal move pass (each counts as that player's turn). See events.
func play(m: Vector2i) -> SuperchessRules:
	var s := _apply(m)
	s._next_turn()
	return s


## The player to move resigns their king (counts as their move).
func resign() -> SuperchessRules:
	var s := _copy()
	s.board[s.king_of(s.color())] = ""
	s.events = ["%s resigns" % NAMES[s.color()]]
	s._check_win()
	s.ep = {}
	s._next_turn()
	return s


func attacked(sq: int, by_team: int) -> bool:
	var c := Vector2i(sq % N, sq / N)
	for d in KNIGHT:
		if _is(c + d, by_team, "N"):
			return true
	for d in ORTHO + DIAG:
		if _is(c + d, by_team, "K"):
			return true
	for d in DIAG:  # a pawn on c + d attacks c if one of its directions steps it diagonally onto c
		var q: Vector2i = c + d
		if _is(q, by_team, "P"):
			for dir in board[_idx(q)].substr(2):
				if -d in _capture_steps(DIRS[dir]):
					return true
	for d in ORTHO:
		var p := _ray(c, d)
		if p != "" and team(p[0]) == by_team and p[1] in "RQ":
			return true
	for d in DIAG:
		var p := _ray(c, d)
		if p != "" and team(p[0]) == by_team and p[1] in "BQ":
			return true
	return false


func _pseudo_moves(c: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in N * N:
		var p: String = board[i]
		if not p.begins_with(c):
			continue
		var at := Vector2i(i % N, i / N)
		match p[1]:
			"N": _steps(i, at, KNIGHT, out)
			"B": _slides(i, at, DIAG, out)
			"R": _slides(i, at, ORTHO, out)
			"Q": _slides(i, at, ORTHO + DIAG, out)
			"K":
				_steps(i, at, ORTHO + DIAG, out)
				if not in_check(c):
					for r in castling:
						if board[r] == c + "R" and region(Vector2i(r % N, r / N)) == region(at):
							out.append(Vector2i(i, r))
			"P":
				for dir in p.substr(2):
					_pawn(i, at, DIRS[dir], out)
	return out


func _pawn(i: int, at: Vector2i, d: Vector2i, out: Array[Vector2i]) -> void:
	var one := at + d
	if playable(one) and board[_idx(one)] == "":
		out.append(Vector2i(i, _idx(one)))
		var two := one + d
		if i in pawn_starts[color()] and playable(two) and board[_idx(two)] == "":
			out.append(Vector2i(i, _idx(two)))
	for step in _capture_steps(d):
		var t: Vector2i = at + step
		if not playable(t):
			continue
		var ti := _idx(t)
		if _enemy(ti) or (not ep.is_empty() and ti == ep.target and _enemy(ep.pawn)):
			out.append(Vector2i(i, ti))


func _steps(i: int, at: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = at + d
		if playable(t) and (board[_idx(t)] == "" or _enemy(_idx(t))):
			out.append(Vector2i(i, _idx(t)))


func _slides(i: int, at: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = at + d
		while playable(t):  # the hole and cut corners stop sliders
			var ti := _idx(t)
			if board[ti] != "" and not _enemy(ti):
				break
			out.append(Vector2i(i, ti))
			if board[ti] != "":
				break
			t += d


## Board change only, no turn handling.
func _apply(m: Vector2i) -> SuperchessRules:
	var s := _copy()
	var c := color()
	var p: String = board[m.x]
	var target: String = board[m.y]
	var from := Vector2i(m.x % N, m.x / N)
	var to := Vector2i(m.y % N, m.y / N)
	if p[1] == "K" and target == c + "R":  # castling: swap with own rook
		s.board[m.x] = target
		s.board[m.y] = p
	else:
		s.board[m.y] = p
		s.board[m.x] = ""
	if p[1] == "P":
		var delta := to - from
		var dir := p.substr(2)
		if dir.length() == 2:  # point pawn commits to the direction it used
			for dc in dir:
				var d: Vector2i = DIRS[dc]
				if delta == d or delta == d * 2 or delta in _capture_steps(d):
					dir = dc
					break
		var d: Vector2i = DIRS[dir]
		var captured := target != ""
		if not ep.is_empty() and m.y == ep.target and delta != d:
			s.board[ep.pawn] = ""
			captured = true
		if delta == d * 2:
			s.ep = {"target": _idx(from + d), "pawn": m.y}
		var piece := c + "P" + dir
		# Promotion: end of the file, or a capture that enters a frontier other than the one it marches through.
		var front := region(to)
		if not playable(to + d) or (captured and front.length() == 1 and front != region(HOME[c] + d * 5)):
			piece = c + "Q"  # ponytail: auto-queen, add a picker (any piece, incl. partner's colors) when wanted
		s.board[m.y] = piece
	if p[1] == "K":  # king moved (or castled): none of this army's rooks can castle any more
		s.castling = castling.filter(func(r): return board[r] != c + "R")
	s.castling = s.castling.filter(func(r): return r != m.x and r != m.y)
	return s


func _next_turn() -> void:
	for i in COLORS.size():
		if result:
			return
		turn = (turn + 1) % COLORS.size()
		var c := color()
		if not legal_moves().is_empty():
			return
		if in_check(c):
			board[king_of(c)] = ""
			events.append("%s is checkmated" % NAMES[c])
			_check_win()
		else:
			events.append("%s has no legal move and passes" % NAMES[c])
			var mate := _copy()
			mate.turn = COLORS.find(partner(c))
			if mate.legal_moves().is_empty() and not mate.in_check(partner(c)):
				result = "Draw: both %s armies are stalemated" % ("light" if team(c) == 0 else "dark")
		ep = {}
	if not result:
		result = "Draw: nobody can move"


func _check_win() -> void:
	for t in 2:
		var cs := COLORS.filter(func(c): return team(c) == t)
		if cs.all(func(c): return king_of(c) == -1):
			var winners := COLORS.filter(func(c): return team(c) != t)
			result = "%s and %s win!" % [NAMES[winners[0]], NAMES[winners[1]]]


func _copy() -> SuperchessRules:
	var s := SuperchessRules.new()
	s.board = board.duplicate()
	s.turn = turn
	s.castling = castling.duplicate()
	s.pawn_starts = pawn_starts
	s.result = result
	return s


static func _capture_steps(d: Vector2i) -> Array:
	return [d + Vector2i(d.y, d.x), d - Vector2i(d.y, d.x)]


func _enemy(i: int) -> bool:
	return board[i] != "" and team(board[i][0]) != team(color())


func _is(t: Vector2i, by_team: int, kind: String) -> bool:
	if not playable(t):
		return false
	var p: String = board[_idx(t)]
	return p != "" and p[1] == kind and team(p[0]) == by_team


func _ray(c: Vector2i, d: Vector2i) -> String:
	var t := c + d
	while playable(t):
		if board[_idx(t)] != "":
			return board[_idx(t)]
		t += d
	return ""


static func _idx(t: Vector2i) -> int:
	return t.y * N + t.x
