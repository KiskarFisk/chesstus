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
	for side in s.hands:  # Crazyhouse: pieces in hand count like pieces on the board
		for k in s.hands[side]:
			score += VALUE[k] * s.hands[side][k] * (1 if side == "w" else -1)
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


# --- Quoridor ---

## Easy walks a shortest path and now and then drops a random wall. Medium plays the move that most
## widens (closest rival's path - my path), stepping unless a wall strictly beats it. ponytail: 1 ply,
## add a reply search if Medium is too easy to wall in.
static func quoridor_move(s: QuoridorRules, level: int) -> Vector3i:
	var me := s.turn
	var steps := s.steps()
	steps.shuffle()
	var score := func(m: Vector3i) -> int:
		var after := s.play(m)
		if after.winner() == me:
			return MATE
		var rival := MATE
		for o in after.pawns.size():
			if o != me and o not in after.resigned:
				rival = mini(rival, after.distance(o))
		return rival - after.distance(me)
	# ponytail: a pawn boxed in by pawns and walls can have no step; assumes it still has a wall to place
	var best := steps[0] if not steps.is_empty() else s.moves()[0]
	for m in steps:
		if score.call(m) > score.call(best):
			best = m
	if s.walls_left[me] == 0 or score.call(best) == MATE:
		return best
	var walls := s.moves().slice(steps.size())
	if level <= 1:
		return walls.pick_random() if randf() < 0.15 and not walls.is_empty() else best
	var best_score: int = score.call(best)
	walls.shuffle()
	for m in walls:
		var sc: int = score.call(m)
		if sc > best_score:
			best = m
			best_score = sc
	return best


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


# --- Cribbage ---

## Easy picks at random. Medium discards to keep the best average hand over every possible starter, plus
## or minus what the discards are worth in the crib; in play it takes the most points now and avoids leaving
## the count on 5 or 21 (a ten makes 15 or 31). ponytail: no look-ahead at what the others hold.
static func cribbage_move(s: CribbageRules, seat: int, level: int) -> Vector3i:
	var moves := s.moves(seat)
	moves.shuffle()
	if level <= 1 or s.phase == CribbageRules.SHOW:
		return moves[0]
	var best := moves[0]
	var best_score := -INF
	for m in moves:
		var sc := _cribbage_discard_value(s, m) if s.phase == CribbageRules.DISCARD else _cribbage_play_value(s, m)
		if sc > best_score:
			best_score = sc
			best = m
	return best


static func _cribbage_discard_value(s: CribbageRules, m: Vector3i) -> float:
	var hand: Array = s.hands[m.x]
	var keep := hand.filter(func(c): return c != m.y and c != m.z)
	var sum := 0
	var n := 0
	for c in 52:
		if c not in hand:
			sum += CribbageRules.total(CribbageRules.score_hand(keep, c))
			n += 1
	var tossed := [m.y] if m.z == -1 else [m.y, m.z]
	var crib := 0.0  # rough: pairs, fifteens and fives help whoever owns the crib
	if tossed.size() == 2:
		crib += 2 if CribbageRules.rank(m.y) == CribbageRules.rank(m.z) else 0
		crib += 2 if CribbageRules.value(m.y) + CribbageRules.value(m.z) == 15 else 0
	for c in tossed:
		crib += 1 if CribbageRules.rank(c) == 5 else 0
	var mine := s.team(m.x) == s.team(s.dealer)
	return float(sum) / n + (crib if mine else -crib)


static func _cribbage_play_value(s: CribbageRules, m: Vector3i) -> float:
	var t := s.team(m.x)
	var after := s.play(m)
	if after.winner == t:
		return MATE
	var gained := after.scores[t] - s.scores[t]
	var left := s.count + CribbageRules.value(m.y)
	return gained * 10 - (4 if left in [5, 21] else 0) + CribbageRules.value(m.y) * 0.1


# --- Texas Hold'em ---

## Easy mostly calls, sometimes folds to a big bet or makes a min raise. Medium estimates its chance of winning
## by dealing out random opponents' cards and boards (it never looks at the real ones), then raises strong
## hands, calls when the pot pays enough, and folds the rest. ponytail: no position, reads or bluffs.
static func holdem_move(s: HoldemRules, seat: int, level: int) -> Vector3i:
	if s.phase != HoldemRules.BETTING:
		return Vector3i(seat, HoldemRules.NEXT, 0)
	var call := s.to_call(seat)
	var fold := Vector3i(seat, HoldemRules.FOLD, 0)
	var check := Vector3i(seat, HoldemRules.CALL, 0)
	var raise_min := Vector3i(seat, HoldemRules.RAISE, s.min_raise_to(seat))
	if level <= 1:
		var r := randf()
		if call > s.chips[seat] / 4 and r < 0.3:
			return fold
		return raise_min if r > 0.9 and s.ok(raise_min) else check
	var opponents := range(s.players).filter(func(q): return q != seat and s.live(q)).size()
	var equity := _holdem_equity(s, seat, opponents, 120)
	if equity > 0.7 or equity > 1.8 / (opponents + 1):
		var to := clampi(s.high + maxi(s.min_raise, s.pot() * 3 / 4), s.min_raise_to(seat), s.bet[seat] + s.chips[seat])
		var raise := Vector3i(seat, HoldemRules.RAISE, to)
		if s.ok(raise):
			return raise
	if call == 0 or equity >= float(call) / (s.pot() + call) + 0.05:
		return check
	return fold


static func _holdem_equity(s: HoldemRules, seat: int, opponents: int, sims: int) -> float:
	var known: Array = s.hands[seat] + s.board
	var unknown := range(52).filter(func(c): return c not in known)
	var total := 0.0
	for i in sims:
		unknown.shuffle()
		var k := 5 - s.board.size()
		var board: Array = s.board + unknown.slice(0, k)
		var mine := HoldemRules.score(s.hands[seat] + board)
		var result := 1.0
		for o in opponents:
			var theirs := HoldemRules.score(unknown.slice(k, k + 2) + board)
			k += 2
			if HoldemRules._beats(theirs, mine):
				result = 0.0
				break
			if not HoldemRules._beats(mine, theirs):
				result = 0.5
		total += result
	return total / sims
