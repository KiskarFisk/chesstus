class_name SuperchessRules
extends RefCounted
## Superchess (Rolf W. Jacobson): four armies on a 14x14 board with cut corners and a 4x4 hole.
## Rules: https://www.chessvariants.com/multiplayer.dir/superchess.html
## Squares are 0..195, index = y * 14 + x, x = file a..n, y = 0 is rank 14 (top).
## Pieces are color + type, pawns add their direction(s): "wPd" moves down, point pawn "wPrd" may pick r or d.
## Moves are Vector2i(from, to). Castling is the king moving onto its own rook's square (they swap).
##
## Modes:
##  "teams" - official 3 and 4 player game: White + Yellow vs Black + Red, one army per turn, clockwise.
##  "2p"    - official 2 player game: light vs dark alternate, moving any piece of either of their armies.
##  "ffa"   - free for all (not in the official rules): every army alone; a mated army leaves the board.

const N := 14
const COLORS := ["w", "b", "y", "r"]  # turn order, clockwise; in "2p", turn 0 = light (w+y), 1 = dark (b+r)
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
# Four-player chess (four = true): the modern 14x14 board with 3x3 corners cut and no hole. Each army's back
# rank is the middle 8 squares of its edge, queen on its own left of the king (seen from its side), pawns
# march straight across and promote on reaching the middle (their 8th rank). Free for all scores points.
const SETUP_FOUR := {
	"w": {"R": ["d1", "k1"], "N": ["e1", "j1"], "B": ["f1", "i1"], "Q": ["g1"], "K": ["h1"],
		"Pu": ["d2", "e2", "f2", "g2", "h2", "i2", "j2", "k2"]},
	"b": {"R": ["a11", "a4"], "N": ["a10", "a5"], "B": ["a9", "a6"], "Q": ["a8"], "K": ["a7"],
		"Pr": ["b4", "b5", "b6", "b7", "b8", "b9", "b10", "b11"]},
	"y": {"R": ["d14", "k14"], "N": ["e14", "j14"], "B": ["f14", "i14"], "K": ["g14"], "Q": ["h14"],
		"Pd": ["d13", "e13", "f13", "g13", "h13", "i13", "j13", "k13"]},
	"r": {"R": ["n11", "n4"], "N": ["n10", "n5"], "B": ["n9", "n6"], "K": ["n8"], "Q": ["n7"],
		"Pl": ["m4", "m5", "m6", "m7", "m8", "m9", "m10", "m11"]},
}
const POINTS := {"P": 1, "N": 3, "B": 5, "R": 5, "Q": 9, "K": 20}  # free for all; a promoted queen ("Q*") is 1

var four := false
var points := {"w": 0, "b": 0, "y": 0, "r": 0}
var last_mover := ""  # army that made the latest move: credited with any checkmate it caused
var mode := "teams"
var board: Array = []
var turn := 0  # index into COLORS (in "2p" only 0 or 1)
var castling: Array = []  # rook squares that may still castle (removed when the king or that rook moves)
var ep := {}  # {"target": sq, "pawn": sq} for the very next turn only
var pawn_starts := {}  # color -> squares; a pawn there hasn't moved yet (pawns never move backwards)
var result := ""  # non-empty when the game is over
var events: Array = []  # what happened automatically during the last move (mates, passes)


static func start(game_mode := "teams", is_four := false) -> SuperchessRules:
	var s := SuperchessRules.new()
	s.mode = game_mode
	s.four = is_four
	s.board.resize(N * N)
	s.board.fill("")
	var setup: Dictionary = SETUP_FOUR if is_four else SETUP
	for c in setup:
		s.pawn_starts[c] = []
		for kind in setup[c]:
			for name in setup[c][kind]:
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


static func playable(c: Vector2i, is_four := false) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return false
	if is_four:  # 3x3 cut from each corner
		return not ((c.x < 3 or c.x > 10) and (c.y < 3 or c.y > 10))
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


## Same side: same team, or in free for all the same army.
func allied(a: String, b: String) -> bool:
	return a == b if mode == "ffa" else team(a) == team(b)


func color() -> String:
	return COLORS[turn]


## Armies the player to move controls this turn.
func side() -> Array:
	return [color(), partner(color())] if mode == "2p" else [color()]


func king_of(c: String) -> int:
	return board.find(c + "K")


func in_check(c: String) -> bool:
	var k := king_of(c)
	return k != -1 and attacked(k, c)


func legal_moves() -> Array[Vector2i]:
	if mode == "2p":
		return _legal_2p()
	var c := color()
	var p := partner(c)
	var guard_partner := mode == "teams" and not in_check(p)
	var out: Array[Vector2i] = []
	for m in _pseudo_moves(c):
		var s := _apply(m)
		# Can't leave yourself in check, or put your partner into check (a check they were already in may stand).
		if s.in_check(c) or (guard_partner and s.in_check(p)):
			continue
		out.append(m)
	return out


## 2 players: any piece of either army. No move may put a safe king into check. If no move saves
## every checked king, the moves that save the most are allowed and the rest get mated (see play).
func _legal_2p() -> Array[Vector2i]:
	var kings := side()
	var checked := kings.filter(func(c): return in_check(c))
	var best := 99
	var out: Array[Vector2i] = []
	for c in kings:
		for m in _pseudo_moves(c):
			var s := _apply(m)
			var still := kings.filter(func(k): return s.in_check(k))
			if still.any(func(k): return k not in checked):
				continue
			if still.size() < best:
				best = still.size()
				out = []
			if still.size() == best:
				out.append(m)
	return out


## Make a move, then run the automatic part of the next turns: checkmated kings are removed and
## players without a legal move pass (each counts as that player's turn). See events.
func play(m: Vector2i) -> SuperchessRules:
	var s := _apply(m)
	if mode == "2p":  # a king this move couldn't save is checkmated on the same turn
		for c in side():
			if s.in_check(c):
				s._mate(c)
	s.last_mover = color()
	s._check_win()  # four-player chess: a king can be taken outright when its owner couldn't answer the check yet
	s._next_turn()
	return s


## The player to move resigns: their king (2p: the whole game; ffa: their army leaves).
func resign() -> SuperchessRules:
	var s := _copy()
	if mode == "2p":
		s.events = ["%s resigns" % ("Light" if turn == 0 else "Dark")]
		for c in s.side():
			if s.king_of(c) != -1:
				s.board[s.king_of(c)] = ""
	else:
		s.events = ["%s resigns" % NAMES[s.color()]]
		s._remove_king(s.color())
	s._check_win()
	s.ep = {}
	s._next_turn()
	return s


## Is sq attacked by a piece not on c's side?
func attacked(sq: int, c: String) -> bool:
	return _hit(sq, c, false)


## Is sq covered by another piece on c's side?
func defended(sq: int, c: String) -> bool:
	return _hit(sq, c, true)


func _hit(sq: int, c: String, allies: bool) -> bool:
	var at := Vector2i(sq % N, sq / N)
	for d in KNIGHT:
		if _is(at + d, "N", c, allies):
			return true
	for d in ORTHO + DIAG:
		if _is(at + d, "K", c, allies):
			return true
	for d in DIAG:  # a pawn on at + d hits at if one of its directions steps it diagonally onto at
		var q: Vector2i = at + d
		if _is(q, "P", c, allies):
			for dir in board[_idx(q)].substr(2):
				if -d in _capture_steps(DIRS[dir]):
					return true
	for d in ORTHO:
		var p := _ray(at, d)
		if p != "" and allied(p[0], c) == allies and p[1] in "RQ":
			return true
	for d in DIAG:
		var p := _ray(at, d)
		if p != "" and allied(p[0], c) == allies and p[1] in "BQ":
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
			"N": _steps(i, at, KNIGHT, c, out)
			"B": _slides(i, at, DIAG, c, out)
			"R": _slides(i, at, ORTHO, c, out)
			"Q": _slides(i, at, ORTHO + DIAG, c, out)
			"K":
				_steps(i, at, ORTHO + DIAG, c, out)
				if four and not in_check(c):
					_castles_four(i, c, out)
				elif not in_check(c):
					for r in castling:
						if board[r] == c + "R" and region(Vector2i(r % N, r / N)) == region(at):
							out.append(Vector2i(i, r))
			"P":
				for dir in p.substr(2):
					_pawn(i, at, DIRS[dir], c, out)
	return out


func _pawn(i: int, at: Vector2i, d: Vector2i, c: String, out: Array[Vector2i]) -> void:
	var one := at + d
	if _ok(one) and board[_idx(one)] == "":
		out.append(Vector2i(i, _idx(one)))
		var two := one + d
		if i in pawn_starts[c] and _ok(two) and board[_idx(two)] == "":
			out.append(Vector2i(i, _idx(two)))
	for step in _capture_steps(d):
		var t: Vector2i = at + step
		if not _ok(t):
			continue
		var ti := _idx(t)
		if _enemy(ti, c) or (not ep.is_empty() and ti == ep.target and _enemy(ep.pawn, c)):
			out.append(Vector2i(i, ti))


func _steps(i: int, at: Vector2i, dirs: Array, c: String, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = at + d
		if _ok(t) and (board[_idx(t)] == "" or _enemy(_idx(t), c)):
			out.append(Vector2i(i, _idx(t)))


func _slides(i: int, at: Vector2i, dirs: Array, c: String, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = at + d
		while _ok(t):  # the hole and cut corners stop sliders
			var ti := _idx(t)
			if board[ti] != "" and not _enemy(ti, c):
				break
			out.append(Vector2i(i, ti))
			if board[ti] != "":
				break
			t += d


## Board change only, no turn handling.
func _apply(m: Vector2i) -> SuperchessRules:
	var s := _copy()
	var p: String = board[m.x]
	var c := p[0]
	var target: String = board[m.y]
	var from := Vector2i(m.x % N, m.x / N)
	var to := Vector2i(m.y % N, m.y / N)
	if four and target != "":  # free for all points; taking a king knocks that army out
		s.points[c] += 1 if target == target[0] + "Q*" else POINTS[target[1]]
		if target[1] == "K":
			for i in s.board.size():
				if s.board[i].begins_with(target[0]):
					s.board[i] = ""
			s.events.append("%s's king is taken" % NAMES[target[0]])
	if four and p[1] == "K" and (absi(m.y - m.x) == 2 or absi(m.y - m.x) == 2 * N):  # castling: the rook crosses
		var step := (m.y - m.x) / 2
		var r := m.x + step
		while board[r] != c + "R":
			r += step
		s.board[m.x + step] = board[r]
		s.board[r] = ""
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
			if four:
				s.points[c] += 1
		if delta == d * 2:
			s.ep = {"target": _idx(from + d), "pawn": m.y}
		var piece := c + "P" + dir
		# Promotion: end of the file, or a capture that enters a frontier other than the one it marches through.
		var front := region(to)
		if four:  # promote on the 8th rank: 6 squares on from the pawns' starting line, the board's middle
			if {"u": to.y == 6, "d": to.y == 7, "r": to.x == 7, "l": to.x == 6}[dir]:
				piece = c + "Q*"  # ponytail: auto-queen
		elif not _ok(to + d) or (captured and front.length() == 1 and front != region(HOME[c] + d * 5)):
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
		turn = (turn + 1) % (2 if mode == "2p" else COLORS.size())
		var cs := side()
		if not board.any(func(p): return p != "" and p[0] in cs):
			continue  # army gone (all captured, or out in free for all): skip quietly
		if not legal_moves().is_empty():
			return
		var checked := cs.filter(func(c): return in_check(c))
		if not checked.is_empty():
			for c in checked:
				_mate(c)  # removing a mated king uses up the turn
		elif mode == "2p":
			result = "Draw: %s is stalemated" % ("Light" if turn == 0 else "Dark")
		else:
			var c := color()
			events.append("%s has no legal move and passes" % NAMES[c])
			if mode == "teams":
				var p := _copy()
				p.turn = COLORS.find(partner(c))
				if p.legal_moves().is_empty() and not p.in_check(partner(c)):
					result = "Draw: both %s armies are stalemated" % ("light" if team(c) == 0 else "dark")
		ep = {}
	if not result:
		result = "Draw: nobody can move"


func _mate(c: String) -> void:
	events.append("%s is checkmated" % NAMES[c])
	if four and last_mover != "" and last_mover != c:
		points[last_mover] += 20
	_remove_king(c)
	_check_win()


## King leaves the board. In free for all the whole army goes with it.
func _remove_king(c: String) -> void:
	board[king_of(c)] = ""
	if mode == "ffa":
		for i in board.size():
			if board[i].begins_with(c):
				board[i] = ""
		events.append("%s is out" % NAMES[c])


func _check_win() -> void:
	if mode == "ffa" and four:
		_four_result()
		return
	if mode == "ffa":
		var alive := COLORS.filter(func(c): return king_of(c) != -1)
		if alive.size() == 1:
			result = "%s wins!" % NAMES[alive[0]]
		return
	for t in 2:
		var cs := COLORS.filter(func(c): return team(c) == t)
		if cs.all(func(c): return king_of(c) == -1):
			var winners := COLORS.filter(func(c): return team(c) != t)
			result = "%s and %s win!" % [NAMES[winners[0]], NAMES[winners[1]]]


func _copy() -> SuperchessRules:
	var s := SuperchessRules.new()
	s.mode = mode
	s.four = four
	s.points = points.duplicate()
	s.last_mover = last_mover
	s.board = board.duplicate()
	s.turn = turn
	s.castling = castling.duplicate()
	s.pawn_starts = pawn_starts
	s.result = result
	return s


static func _capture_steps(d: Vector2i) -> Array:
	return [d + Vector2i(d.y, d.x), d - Vector2i(d.y, d.x)]


func _enemy(i: int, c: String) -> bool:
	return board[i] != "" and not allied(board[i][0], c)


func _is(t: Vector2i, kind: String, c: String, allies: bool) -> bool:
	if not _ok(t):
		return false
	var p: String = board[_idx(t)]
	return p != "" and p[1] == kind and allied(p[0], c) == allies


func _ray(at: Vector2i, d: Vector2i) -> String:
	var t := at + d
	while _ok(t):
		if board[_idx(t)] != "":
			return board[_idx(t)]
		t += d
	return ""


static func _idx(t: Vector2i) -> int:
	return t.y * N + t.x


func _ok(c: Vector2i) -> bool:
	return playable(c, four)


## Four-player chess castling, as in chess: king two squares toward an unmoved rook on its own edge, the rook
## landing on the square it crossed. Everything between empty, the crossed square not attacked.
func _castles_four(k: int, c: String, out: Array[Vector2i]) -> void:
	for r in castling:
		if board[r] != c + "R" or (r / N != k / N and r % N != k % N):
			continue
		var step := (1 if r > k else -1) * (1 if r / N == k / N else N)
		var clear := true
		for sq in range(k + step, r, step):
			clear = clear and board[sq] == ""
		if clear and not attacked(k + step, c):
			out.append(Vector2i(k, k + 2 * step))


## Free for all is over once one king is left: most points wins.
func _four_result() -> void:
	var alive := COLORS.filter(func(c): return king_of(c) != -1)
	if alive.size() > 1:
		return
	var best: int = points.values().max()
	var top := COLORS.filter(func(c): return points[c] == best)
	result = ("%s wins with %d points!" % [NAMES[top[0]], best]) if top.size() == 1 \
		else "Draw: %s tie on %d points" % [" and ".join(PackedStringArray(top.map(func(c): return NAMES[c]))), best]
