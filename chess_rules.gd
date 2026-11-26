class_name ChessRules
extends RefCounted
## Immutable-ish chess position. play() returns a new position.
## Squares are 0..63, index = y * 8 + x, y = 0 is rank 8 (black's back rank).
## Moves are Vector2i(from, to).

const START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KNIGHT := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
# A move touching any of these squares removes those castling rights.
const RIGHTS := {60: "KQ", 63: "K", 56: "Q", 4: "kq", 7: "k", 0: "q"}

var board: Array = []  # "" or color+piece, e.g. "wK", "bP"
var turn := "w"
var castling := ""
var ep := -1  # en passant target square


static func from_fen(fen: String) -> ChessRules:
	var s := ChessRules.new()
	var parts := fen.split(" ")
	for ch in parts[0]:
		if ch == "/":
			continue
		if ch.is_valid_int():
			for i in int(ch):
				s.board.append("")
		else:
			s.board.append(("w" if ch == ch.to_upper() else "b") + ch.to_upper())
	s.turn = parts[1]
	s.castling = parts[2].replace("-", "")
	if parts[3] != "-":
		s.ep = (parts[3].unicode_at(0) - 97) + (8 - int(parts[3][1])) * 8
	return s


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
	s.board = board.duplicate()
	s.castling = castling
	s.turn = opponent()
	var p: String = board[m.x]
	s.board[m.y] = p
	s.board[m.x] = ""
	if p[1] == "P":
		if m.y == ep:
			s.board[m.y + (8 if turn == "w" else -8)] = ""
		if absi(m.y - m.x) == 16:
			s.ep = (m.x + m.y) / 2
		if m.y < 8 or m.y >= 56:
			s.board[m.y] = turn + "Q"  # ponytail: auto-queen, add a promotion picker when underpromotion matters
	elif p[1] == "K" and absi(m.y - m.x) == 2:
		var rook_from := m.y + 1 if m.y > m.x else m.y - 2
		s.board[(m.x + m.y) / 2] = s.board[rook_from]
		s.board[rook_from] = ""
	for sq in [m.x, m.y]:
		for r in RIGHTS.get(sq, ""):
			s.castling = s.castling.replace(r, "")
	return s


func attacked(sq: int, by: String) -> bool:
	var c := Vector2i(sq % 8, sq / 8)
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


func _pseudo_moves() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in 64:
		var p: String = board[i]
		if not p.begins_with(turn):
			continue
		var c := Vector2i(i % 8, i / 8)
		match p[1]:
			"P": _pawn(i, c, out)
			"N": _steps(i, c, KNIGHT, out)
			"B": _slides(i, c, DIAG, out)
			"R": _slides(i, c, ORTHO, out)
			"Q": _slides(i, c, ORTHO + DIAG, out)
			"K":
				_steps(i, c, ORTHO + DIAG, out)
				_castles(i, out)
	return out


func _pawn(i: int, c: Vector2i, out: Array[Vector2i]) -> void:
	var fwd := -1 if turn == "w" else 1
	var one := c + Vector2i(0, fwd)
	if _on(one) and board[_idx(one)] == "":
		out.append(Vector2i(i, _idx(one)))
		var two := one + Vector2i(0, fwd)
		if c.y == (6 if turn == "w" else 1) and board[_idx(two)] == "":
			out.append(Vector2i(i, _idx(two)))
	for dx in [-1, 1]:
		var t := c + Vector2i(dx, fwd)
		if _on(t) and (board[_idx(t)].begins_with(opponent()) or _idx(t) == ep):
			out.append(Vector2i(i, _idx(t)))


func _steps(i: int, c: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = c + d
		if _on(t) and not board[_idx(t)].begins_with(turn):
			out.append(Vector2i(i, _idx(t)))


func _slides(i: int, c: Vector2i, dirs: Array, out: Array[Vector2i]) -> void:
	for d in dirs:
		var t: Vector2i = c + d
		while _on(t) and not board[_idx(t)].begins_with(turn):
			out.append(Vector2i(i, _idx(t)))
			if board[_idx(t)] != "":
				break
			t += d


func _castles(k: int, out: Array[Vector2i]) -> void:
	var w := turn == "w"
	if k != (60 if w else 4) or in_check():
		return
	var them := opponent()
	if castling.contains("K" if w else "k") and board[k + 1] == "" and board[k + 2] == "" \
			and not attacked(k + 1, them):
		out.append(Vector2i(k, k + 2))
	if castling.contains("Q" if w else "q") and board[k - 1] == "" and board[k - 2] == "" \
			and board[k - 3] == "" and not attacked(k - 1, them):
		out.append(Vector2i(k, k - 2))


func _ray(c: Vector2i, d: Vector2i) -> String:
	var t := c + d
	while _on(t):
		if board[_idx(t)] != "":
			return board[_idx(t)]
		t += d
	return ""


func _is(t: Vector2i, piece: String) -> bool:
	return _on(t) and board[_idx(t)] == piece


static func _on(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < 8 and t.y >= 0 and t.y < 8


static func _idx(t: Vector2i) -> int:
	return t.y * 8 + t.x
