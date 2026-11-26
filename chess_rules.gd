class_name ChessRules
extends RefCounted
## Immutable-ish chess position on an n x n board (8 for chess, 5 for Baby Chess). play() returns a new position.
## Squares are 0..n*n-1, index = y * n + x, y = 0 is the top rank (black's back rank).
## Moves are Vector2i(from, to). Castling is the king moving two squares toward a castling rook.
## Fischer Random (castling rooks given as files in the FEN, e.g. "HAha"): castling is the king moving onto its
## own rook, and they land on the usual g/f or c/d files.
## Crazyhouse (FEN board ends in a [pocket]): captured pieces go to the captor's hand, promoted ones as pawns.
## Drops are Vector2i(-1 - DROPS.find(kind), to).

const START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const BABY := "kqbnr/ppppp/5/PPPPP/RNBQK w Qk - 0 1"  # Baby Chess, 5x5
const HOUSE := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR[] w KQkq - 0 1"  # Crazyhouse
const DROPS := ["Q", "R", "B", "N", "P"]
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KNIGHT := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]

var n := 8
var board: Array = []  # "" or color+piece, e.g. "wK", "bP"
var turn := "w"
var castling: Array = []  # squares of rooks that may still castle
var ep := -1  # en passant target square
var frc := false  # Fischer Random castling
var hands := {}  # Crazyhouse only: {"w": {kind: count}, "b": {...}}; empty in other games
var promoted: Array = []  # Crazyhouse: squares holding promoted pieces (they go to hand as pawns)


static func from_fen(fen: String) -> ChessRules:
	var s := ChessRules.new()
	var parts := fen.split(" ")
	var rows := parts[0].get_slice("[", 0)
	if parts[0].contains("["):
		s.hands = {"w": {}, "b": {}}
		for ch in parts[0].get_slice("[", 1).trim_suffix("]"):
			var side := "w" if ch == ch.to_upper() else "b"
			s.hands[side][ch.to_upper()] = s.hands[side].get(ch.to_upper(), 0) + 1
	s.n = rows.count("/") + 1
	for ch in rows:
		if ch == "/":
			continue
		if ch.is_valid_int():
			for i in int(ch):
				s.board.append("")
		else:
			s.board.append(("w" if ch == ch.to_upper() else "b") + ch.to_upper())
	s.turn = parts[1]
	# K/Q = rook in the right/left corner of that side's back rank; A-H = rook on that file (Fischer Random)
	for ch in parts[2].replace("-", ""):
		var y := s.n - 1 if ch == ch.to_upper() else 0
		var u := ch.to_upper()
		s.frc = s.frc or u not in ["K", "Q"]
		s.castling.append(y * s.n + (s.n - 1 if u == "K" else 0 if u == "Q" else u.unicode_at(0) - 65))
	if parts[3] != "-":
		s.ep = (parts[3].unicode_at(0) - 97) + (s.n - int(parts[3].substr(1))) * s.n
	return s


## A Fischer Random start (one of the 960), the same for the same seed: bishops on opposite colors,
## king somewhere between the rooks, black mirroring white.
static func fischer(seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var row := ["", "", "", "", "", "", "", ""]
	row[rng.randi_range(0, 3) * 2] = "B"
	row[rng.randi_range(0, 3) * 2 + 1] = "B"
	for p in ["Q", "N", "N"]:
		var free := range(8).filter(func(i): return row[i] == "")
		row[free[rng.randi_range(0, free.size() - 1)]] = p
	var rest := range(8).filter(func(i): return row[i] == "")
	row[rest[0]] = "R"
	row[rest[1]] = "K"
	row[rest[2]] = "R"
	var back := "".join(PackedStringArray(row))
	var rooks: String = "ABCDEFGH"[rest[2]] + "ABCDEFGH"[rest[0]]
	return "%s/pppppppp/8/8/8/8/PPPPPPPP/%s w %s%s - 0 1" % [back.to_lower(), back, rooks, rooks.to_lower()]


func opponent() -> String:
	return "b" if turn == "w" else "w"


func legal_moves() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for m in _pseudo_moves():
		var s := play(m)
		if not s.attacked(s.board.find(turn + "K"), s.turn):
			out.append(m)
	return out


func in_check() -> bool:
	return attacked(board.find(turn + "K"), opponent())


func play(m: Vector2i) -> ChessRules:
	var s := ChessRules.new()
	s.n = n
	s.board = board.duplicate()
	s.turn = opponent()
	s.frc = frc
	if not hands.is_empty():
		s.hands = {"w": hands.w.duplicate(), "b": hands.b.duplicate()}
		s.promoted = promoted.duplicate()
	if m.x < 0:  # drop
		var kind: String = DROPS[-1 - m.x]
		s.board[m.y] = turn + kind
		s.hands[turn][kind] -= 1
		if s.hands[turn][kind] == 0:
			s.hands[turn].erase(kind)
		s.castling = castling.duplicate()
		return s
	var p: String = board[m.x]
	var taken: String = opponent() + "P" if p[1] == "P" and m.y == ep else board[m.y]
	if not hands.is_empty() and taken.begins_with(opponent()):
		var kind := "P" if m.y in promoted else taken[1]
		s.hands[turn][kind] = s.hands[turn].get(kind, 0) + 1
	s.promoted.erase(m.y)
	if m.x in promoted:
		s.promoted.erase(m.x)
		s.promoted.append(m.y)
	s.board[m.y] = p
	s.board[m.x] = ""
	if p[1] == "P":
		if m.y == ep:
			s.board[m.y + (n if turn == "w" else -n)] = ""
		if absi(m.y - m.x) == 2 * n:
			s.ep = (m.x + m.y) / 2
		if m.y < n or m.y >= n * (n - 1):
			s.board[m.y] = turn + "Q"  # ponytail: auto-queen, add a promotion picker when underpromotion matters
			s.promoted.append(m.y)
	elif p[1] == "K" and frc and board[m.y] == turn + "R":  # Fischer Random castling: king onto its own rook
		var right := m.y > m.x
		var row := m.x / n * n
		s.board[m.y] = ""
		s.board[row + (6 if right else 2)] = p
		s.board[row + (5 if right else 3)] = turn + "R"
	elif p[1] == "K" and absi(m.y - m.x) == 2:  # castling: rook lands on the square the king crossed
		var rook := _castle_rook(m.x, signi(m.y - m.x))
		s.board[(m.x + m.y) / 2] = s.board[rook]
		s.board[rook] = ""
	# Rights go when the king moves, or a castling rook moves or is captured.
	var c := p[0]
	s.castling = castling.filter(func(r):
		return r != m.x and r != m.y and not (p[1] == "K" and board[r].begins_with(c)))
	return s


func attacked(sq: int, by: String) -> bool:
	var c := Vector2i(sq % n, sq / n)
	for d in KNIGHT:
		if _is(c + d, by + "N"):
			return true
	for d in ORTHO + DIAG:
		if _is(c + d, by + "K"):
			return true
	var pawn_row := 1 if by == "w" else -1
	if _is(c + Vector2i(-1, pawn_row), by + "P") or _is(c + Vector2i(1, pawn_row), by + "P"):
		return true
	for d in ORTHO:
		if _ray(c, d) in [by + "R", by + "Q"]:
			return true
	for d in DIAG:
		if _ray(c, d) in [by + "B", by + "Q"]:
			return true
	return false


func on(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < n and t.y >= 0 and t.y < n


func _pseudo_moves() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in n * n:
		var p: String = board[i]
		if not p.begins_with(turn):
			continue
		var c := Vector2i(i % n, i / n)
		match p[1]:
			"P": _pawn(i, c, out)
			"N": _steps(i, c, KNIGHT, out)
			"B": _slides(i, c, DIAG, out)
			"R": _slides(i, c, ORTHO, out)
			"Q": _slides(i, c, ORTHO + DIAG, out)
			"K":
				_steps(i, c, ORTHO + DIAG, out)
				_castles(i, out)
	if not hands.is_empty():
		for kind in hands[turn]:
			for sq in n * n:  # any empty square; pawns not on the first or last rank
				if board[sq] == "" and not (kind == "P" and (sq < n or sq >= n * (n - 1))):
					out.append(Vector2i(-1 - DROPS.find(kind), sq))
	return out


func _pawn(i: int, c: Vector2i, out: Array[Vector2i]) -> void:
	var fwd := -1 if turn == "w" else 1
	var one := c + Vector2i(0, fwd)
	if on(one) and board[_idx(one)] == "":
		out.append(Vector2i(i, _idx(one)))
		var two := one + Vector2i(0, fwd)
		if c.y == (n - 2 if turn == "w" else 1) and on(two) and board[_idx(two)] == "":
			out.append(Vector2i(i, _idx(two)))
	for dx in [-1, 1]:
		var t := c + Vector2i(dx, fwd)
		if on(t) and (board[_idx(t)].begins_with(opponent()) or _idx(t) == ep):
			out.append(Vector2i(i, _idx(t)))


func _steps(i: int, c: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = c + d
		if on(t) and not board[_idx(t)].begins_with(turn):
			out.append(Vector2i(i, _idx(t)))


func _slides(i: int, c: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = c + d
		while on(t) and not board[_idx(t)].begins_with(turn):
			out.append(Vector2i(i, _idx(t)))
			if board[_idx(t)] != "":
				break
			t += d


## King two squares toward each castling rook on its rank: everything between empty,
## not in check, and not passing through an attacked square.
func _castles(k: int, out: Array[Vector2i]) -> void:
	if in_check():
		return
	for r in castling:
		if board[r] != turn + "R" or r / n != k / n:
			continue
		var dir := signi(r - k)
		if frc:
			_castle_frc(k, r, dir, out)
			continue
		var clear := true
		for sq in range(k + dir, r, dir):
			clear = clear and board[sq] == ""
		if clear and absi(r - k) >= 3 and not attacked(k + dir, opponent()):
			out.append(Vector2i(k, k + 2 * dir))


## Fischer Random: king to the g (c) file, rook to f (d). Every square either piece covers must be empty
## (besides the two of them), and the king may not pass through an attacked square. Where it lands is
## checked by legal_moves like any move.
func _castle_frc(k: int, r: int, dir: int, out: Array[Vector2i]) -> void:
	var row := k / n * n
	var kd := row + (6 if dir > 0 else 2)
	var rd := row + (5 if dir > 0 else 3)
	for sq in range(mini(mini(k, r), mini(kd, rd)), maxi(maxi(k, r), maxi(kd, rd)) + 1):
		if board[sq] != "" and sq != k and sq != r:
			return
	for sq in range(mini(k, kd), maxi(k, kd) + 1):
		if sq != k and attacked(sq, opponent()):
			return
	out.append(Vector2i(k, r))


func _castle_rook(k: int, dir: int) -> int:
	for r in castling:
		if r / n == k / n and signi(r - k) == dir:
			return r
	return -1


func _ray(c: Vector2i, d: Vector2i) -> String:
	var t := c + d
	while on(t):
		if board[_idx(t)] != "":
			return board[_idx(t)]
		t += d
	return ""


func _is(t: Vector2i, piece: String) -> bool:
	return on(t) and board[_idx(t)] == piece


func _idx(t: Vector2i) -> int:
	return t.y * n + t.x
