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
	var n := s.n
	for i in n * n:
		var p: String = s.board[i]
		if p == "":
			continue
		var v: int = VALUE[p[1]]
		var x := i % n
		var y := i / n
		if p[1] == "P":
			v += (n - 2 - y if p[0] == "w" else y - 1) * 8
		elif p[1] in "NB":
			v -= (absi(2 * x - n + 1) + absi(2 * y - n + 1)) * 3
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


# --- Shogi ---

const SHOGI_VALUE := {"P": 100, "L": 300, "N": 350, "S": 500, "G": 550, "B": 800, "R": 1000, "K": 0,
	"+P": 550, "+L": 550, "+N": 550, "+S": 550, "+B": 1050, "+R": 1250}


## Medium searches 3 plies on Minishogi, 2 on the full board (drops make shogi's branching much wider).
static func shogi_move(s: ShogiRules, level: int) -> Vector3i:
	var moves := s.moves()
	moves.shuffle()
	var victim := func(m): return SHOGI_VALUE[s.board[m.y].substr(1)] if s.board[m.y] != "" else -1
	if level <= 1:
		var captures := moves.filter(func(m): return victim.call(m) >= 0)
		if not captures.is_empty() and randf() < 0.7:
			captures.sort_custom(func(a, b): return victim.call(a) > victim.call(b))
			return captures[0]
		return moves[0]
	_shogi_order(s, moves)
	var depth := 2 if s.n <= 5 else 1
	var best := moves[0]
	var alpha := -MATE * 2
	for m in moves:
		var score := -_shogi_negamax(s.play(m), depth, -MATE * 2, -alpha)
		if score > alpha:
			alpha = score
			best = m
	return best


static func _shogi_negamax(s: ShogiRules, depth: int, alpha: int, beta: int) -> int:
	if depth == 0:
		return _shogi_eval(s) * (1 if s.turn == "b" else -1)
	var moves := s.moves()
	if moves.is_empty():
		return -(MATE + depth)  # no legal move loses in shogi, check or not
	_shogi_order(s, moves)
	for m in moves:
		alpha = maxi(alpha, -_shogi_negamax(s.play(m), depth - 1, -beta, -alpha))
		if alpha >= beta:
			break
	return alpha


## Captures first (biggest victim first), then promotions.
static func _shogi_order(s: ShogiRules, moves: Array[Vector3i]) -> void:
	var key := func(m): return (SHOGI_VALUE[s.board[m.y].substr(1)] if s.board[m.y] != "" else 0) + m.z * 50
	moves.sort_custom(func(a, b): return key.call(a) > key.call(b))


## Material on the board plus pieces in hand (worth a bit more: they can drop anywhere), from Sente's side.
static func _shogi_eval(s: ShogiRules) -> int:
	var score := 0
	for p in s.board:
		if p != "":
			score += SHOGI_VALUE[p.substr(1)] * (1 if p[0] == "b" else -1)
	for side in s.hands:
		for k in s.hands[side]:
			score += SHOGI_VALUE[k] * 11 / 10 * s.hands[side][k] * (1 if side == "b" else -1)
	return score


static func _easy(moves: Array[Vector2i], victim: Callable) -> Vector2i:
	var captures := moves.filter(func(m): return victim.call(m) >= 0)
	if not captures.is_empty() and randf() < 0.7:
		captures.sort_custom(func(a, b): return victim.call(a) > victim.call(b))
		return captures[0]
	return moves[0]
