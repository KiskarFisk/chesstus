class_name Bots
extends RefCounted
## Bot move pickers. Pure functions of a rules state, safe to run on a worker thread.
## Level 1 = Easy (random, likes captures), 2 = Medium (chess: 3-ply search; superchess: 1-ply team eval).

const VALUE := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}
const MATE := 100000


# --- Chess ---

static func chess_move(s: ChessRules, level: int) -> Vector2i:
	var moves := s.legal_moves()
	moves.shuffle()  # variety between equal moves
	if level <= 1:
		return _easy(moves, func(m): return VALUE[s.board[m.y][1]] if s.board[m.y] != "" else -1)
	_order(s, moves)
	var best := moves[0]
	var alpha := -MATE * 2
	for m in moves:
		var score := -_negamax(s.play(m), 2, -MATE * 2, -alpha)
		if score > alpha:
			alpha = score
			best = m
	return best


## Score from the side to move's point of view.
static func _negamax(s: ChessRules, depth: int, alpha: int, beta: int) -> int:
	if depth == 0:
		return _chess_eval(s) * (1 if s.turn == "w" else -1)
	var moves := s.legal_moves()
	if moves.is_empty():
		return -(MATE + depth) if s.in_check() else 0  # being mated sooner is worse
	_order(s, moves)
	for m in moves:
		alpha = maxi(alpha, -_negamax(s.play(m), depth - 1, -beta, -alpha))
		if alpha >= beta:
			break
	return alpha


## Captures first, biggest victim first: makes alpha-beta cut much more.
static func _order(s: ChessRules, moves: Array[Vector2i]) -> void:
	moves.sort_custom(func(a, b):
		return (VALUE[s.board[a.y][1]] if s.board[a.y] != "" else -1) > (VALUE[s.board[b.y][1]] if s.board[b.y] != "" else -1))


## Material plus small nudges (advanced pawns, central minor pieces), from white's side.
static func _chess_eval(s: ChessRules) -> int:
	var score := 0
	for i in 64:
		var p: String = s.board[i]
		if p == "":
			continue
		var v: int = VALUE[p[1]]
		var x := i % 8
		var y := i / 8
		if p[1] == "P":
			v += (6 - y if p[0] == "w" else y - 1) * 8
		elif p[1] in "NB":
			v -= (absi(2 * x - 7) + absi(2 * y - 7)) * 3
		score += v if p[0] == "w" else -v
	return score


# --- Superchess ---

static func superchess_move(s: SuperchessRules, level: int) -> Vector2i:
	var moves := s.legal_moves()
	moves.shuffle()
	var me := s.color()
	var victim := func(m):
		var p: String = s.board[m.y]
		return VALUE[p[1]] if p != "" and not s.allied(p[0], me) else -1
	if level <= 1:
		return _easy(moves, victim)
	var best := moves[0]
	var best_score := -INF
	for m in moves:
		var score := _superchess_eval(s.play(m), me)
		if score > best_score:
			best_score = score
			best = m
	return best


## Our side's view after a move (side = team, or just our army in free for all): material,
## kings taken, and pieces left hanging to the enemy.
static func _superchess_eval(s: SuperchessRules, me: String) -> float:
	if s.result.contains("win"):
		return MATE if s.result.contains(SuperchessRules.NAMES[me]) else -MATE
	var score := 0.0
	for c in SuperchessRules.COLORS:
		var ours := s.allied(c, me)
		if s.king_of(c) == -1:
			score += -3000 if ours else 3000
		elif s.in_check(c):
			score += -150 if ours else 60
	for i in s.board.size():
		var p: String = s.board[i]
		if p == "" or p[1] == "K":
			continue
		var v: float = VALUE[p[1]]
		if not s.allied(p[0], me):
			score -= v
			continue
		score += v
		if s.attacked(i, p[0]):  # can be taken: count most of it as lost unless we guard it
			score -= v * (0.25 if s.defended(i, p[0]) else 0.9)
	return score


static func _easy(moves: Array[Vector2i], victim: Callable) -> Vector2i:
	var captures := moves.filter(func(m): return victim.call(m) >= 0)
	if not captures.is_empty() and randf() < 0.7:
		captures.sort_custom(func(a, b): return victim.call(a) > victim.call(b))
		return captures[0]
	return moves[0]
