class_name HoldemRules
extends RefCounted
## No-limit Texas Hold'em for 2-4 players, chips only. No UI. play() returns a new state.
## Everyone starts with START_CHIPS; blinds double every BLIND_EVERY hands so games end. The last player
## with chips wins. Cards come from Cards (0..51); each hand is shuffled from deal_seed + hand number.
## Moves are Vector3i(seat, action, amount):
##   FOLD, CALL (checks when there's nothing to call; all-in when short), RAISE to amount (the seat's total bet
##   this street; all of its chips is always allowed), NEXT (after a hand: deal the next one, any seat).

const START_CHIPS := 1000
const BLIND := 10  # small blind at the start; the big blind is twice it
const BLIND_EVERY := 10
const HANDS := ["High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house",
	"Four of a kind", "Straight flush"]
enum {FOLD, CALL, RAISE, NEXT}
enum {BETTING, DONE, OVER}

var players := 2
var deal_seed := 0
var hand_no := 0
var button := 0
var chips: Array[int] = []  # behind, not yet bet
var hands: Array = []  # seat -> its 2 cards, [] if it has none (out of chips)
var board: Array = []
var deck: Array = []  # what's left to deal the board from
var bet: Array[int] = []  # this street
var put: Array[int] = []  # this hand, for the pots
var folded: Array = []
var acted: Array = []  # has acted since the last full raise this street
var street := 0  # 0 preflop, 1 flop, 2 turn, 3 river
var high := 0  # biggest bet this street
var min_raise := 0
var turn := -1
var phase := BETTING
var won: Array = []  # DONE: [seat, chips won, hand name or ""] per payout
var events: Array = []  # [seat, text], newest last
var winner := -1


static func create(n: int, game_seed: int) -> HoldemRules:
	var s := HoldemRules.new()
	s.players = n
	s.deal_seed = game_seed
	for i in n:
		s.chips.append(START_CHIPS)
	s.button = posmod(game_seed, n)
	s._deal()
	return s


func small_blind() -> int:
	return BLIND << (hand_no / BLIND_EVERY)


func pot() -> int:
	return put.reduce(func(a, b): return a + b, 0)


func live(seat: int) -> bool:
	return not hands[seat].is_empty() and not folded[seat]


func to_call(seat: int) -> int:
	return mini(high - bet[seat], chips[seat])


## Smallest legal raise target for seat, or its all-in if that's less.
func min_raise_to(seat: int) -> int:
	return mini(high + min_raise, bet[seat] + chips[seat])


func ok(m: Vector3i) -> bool:
	if m.x < 0 or m.x >= players:
		return false
	if phase == DONE:
		return m.y == NEXT
	if phase != BETTING or m.x != turn:
		return false
	match m.y:
		FOLD, CALL:
			return true
		RAISE:
			var all_in := bet[m.x] + chips[m.x]
			return m.z > high and m.z <= all_in and (m.z - high >= min_raise or m.z == all_in)
	return false


func play(m: Vector3i) -> HoldemRules:
	var s := _copy()
	var p := m.x
	match m.y:
		NEXT:
			s.hand_no += 1
			s.button = s._next_with_chips(button)
			s._deal()
		FOLD:
			s.folded[p] = true
			s.events.append([p, "folds"])
			s._advance(p)
		CALL:
			var amount := to_call(p)
			s._bet(p, amount)
			s.events.append([p, ("calls %d" % amount if amount else "checks") + (" (all in)" if s.chips[p] == 0 else "")])
			s.acted[p] = true
			s._advance(p)
		RAISE:
			var size := m.z - high
			s._bet(p, m.z - bet[p])
			s.events.append([p, ("bets %d" if high == 0 else "raises to %d") % m.z + (" (all in)" if s.chips[p] == 0 else "")])
			s.high = m.z
			if size >= min_raise:  # a full raise reopens the betting for everyone
				s.min_raise = size
				s.acted.fill(false)
			s.acted[p] = true
			s._advance(p)
	s.events = s.events.slice(-8)
	return s


## seat leaves the game: folds, and its chips are gone.
func resign(seat: int) -> HoldemRules:
	var s := _copy()
	s.chips[seat] = 0
	s.events.append([seat, "leaves the table"])
	if s.phase == BETTING and live(seat):
		s.folded[seat] = true
		if seat == turn:
			s._advance(seat)
		elif range(players).filter(s.live).size() == 1:
			s._finish()
	if s.phase == DONE:
		s._check_over()
	return s


## Best 5 of the cards (5-7) as a comparable array: [category, tie-breaking ranks...]. Aces are 14.
static func score(cards: Array) -> Array:
	var best := []
	var n := cards.size()
	for a in n:
		for b in range(a + 1, n):
			var five := []
			for i in n:
				if i != a and i != b:
					five.append(cards[i])
			if n == 5:
				five = cards
			var sc := _score5(five)
			if best.is_empty() or _beats(sc, best):
				best = sc
			if n == 5:
				return best
	return best


static func _score5(five: Array) -> Array:
	var ranks := five.map(func(c): return 14 if Cards.rank(c) == 1 else Cards.rank(c))
	ranks.sort()
	ranks.reverse()
	var flush := five.all(func(c): return Cards.suit(c) == Cards.suit(five[0]))
	var top := -1  # straight's high card
	if ranks[0] - ranks[4] == 4 and _distinct(ranks):
		top = ranks[0]
	elif ranks == [14, 5, 4, 3, 2]:
		top = 5
	var counts := {}
	for r in ranks:
		counts[r] = counts.get(r, 0) + 1
	var groups := counts.keys()
	groups.sort_custom(func(x, y): return counts[x] > counts[y] or (counts[x] == counts[y] and x > y))
	var shape := groups.map(func(r): return counts[r])
	if top != -1 and flush:
		return [8, top]
	if shape[0] == 4:
		return [7] + groups
	if shape == [3, 2]:
		return [6] + groups
	if flush:
		return [5] + ranks
	if top != -1:
		return [4, top]
	if shape[0] == 3:
		return [3] + groups
	if shape == [2, 2, 1]:
		return [2] + groups
	if shape[0] == 2:
		return [1] + groups
	return [0] + ranks


static func _distinct(ranks: Array) -> bool:
	for i in range(1, ranks.size()):
		if ranks[i] == ranks[i - 1]:
			return false
	return true


static func _beats(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


func _bet(seat: int, amount: int) -> void:
	chips[seat] -= amount
	bet[seat] += amount
	put[seat] += amount


## After seat acted: next to act, or the street is over.
func _advance(seat: int) -> void:
	var alive := range(players).filter(live)
	if alive.size() == 1:
		_finish()
		return
	var can_act := alive.filter(func(q): return chips[q] > 0)
	for i in range(1, players + 1):
		var q := (seat + i) % players
		if q in can_act and (not acted[q] or bet[q] < high):
			if can_act.size() > 1 or bet[q] < high:  # alone with chips and nothing to call: nobody to bet against
				turn = q
				return
	_next_street(can_act.size())


func _next_street(can_act: int) -> void:
	while true:
		street += 1
		bet.fill(0)
		acted.fill(false)
		high = 0
		min_raise = 2 * small_blind()
		if street == 4:
			_finish()
			return
		var take := 3 if street == 1 else 1
		board += deck.slice(0, take)
		deck = deck.slice(take)
		events.append([-1, ["", "Flop", "Turn", "River"][street] + ": " + " ".join(PackedStringArray(board.map(func(c): return Cards.card_name(c))))])
		if can_act >= 2:
			for i in range(1, players + 1):
				var q := (button + i) % players
				if live(q) and chips[q] > 0:
					turn = q
					return


## Pay out: one player left takes it all; otherwise pots by level (side pots), best hand wins each, split ties.
func _finish() -> void:
	phase = DONE
	turn = -1
	won = []
	var alive := range(players).filter(live)
	var scores := {}
	for q in alive:
		scores[q] = score(hands[q] + board) if alive.size() > 1 else []
	var levels := []
	for q in players:
		if put[q] > 0 and put[q] not in levels:
			levels.append(put[q])
	levels.sort()
	var prev := 0
	for level in levels:
		var amount := 0
		for q in players:
			amount += clampi(put[q] - prev, 0, level - prev)
		var eligible := alive.filter(func(q): return put[q] >= level)
		if eligible.is_empty():  # chips nobody alive matched: back to whoever put them in
			eligible = range(players).filter(func(q): return put[q] >= level)
		var best: Array = eligible.filter(func(q): return scores.has(q) and not eligible.any(
			func(o): return scores.has(o) and _beats(scores[o], scores[q])))
		if best.is_empty():
			best = eligible
		for k in best.size():
			var q: int = best[k]
			var share := amount / best.size() + (amount % best.size() if k == 0 else 0)
			chips[q] += share
			_add_won(q, share, HANDS[scores[q][0]] if scores.has(q) and not scores[q].is_empty() else "")
		prev = level
	for w in won:
		events.append([w[0], "wins %d" % w[1] + (" with %s" % w[2].to_lower() if w[2] else "")])
	_check_over()


func _add_won(seat: int, amount: int, what: String) -> void:
	for w in won:
		if w[0] == seat:
			w[1] += amount
			return
	won.append([seat, amount, what])


func _check_over() -> void:
	var left := range(players).filter(func(q): return chips[q] > 0)
	if left.size() <= 1:
		phase = OVER
		winner = left[0] if left.size() == 1 else -1


func _next_with_chips(seat: int) -> int:
	for i in range(1, players + 1):
		var q := (seat + i) % players
		if chips[q] > 0:
			return q
	return seat


## New hand: shuffle, blinds, two cards each to everyone with chips. Heads-up the button posts the small blind.
func _deal() -> void:
	deck = Cards.shuffled("%d:%d" % [deal_seed, hand_no])
	hands = []
	bet = []
	put = []
	folded = []
	acted = []
	for q in players:
		hands.append(deck.slice(0, 2) if chips[q] > 0 else [])
		if chips[q] > 0:
			deck = deck.slice(2)
		bet.append(0)
		put.append(0)
		folded.append(false)
		acted.append(false)
	board = []
	street = 0
	won = []
	phase = BETTING
	var seated := range(players).filter(func(q): return chips[q] > 0).size()
	var sb := button if seated == 2 else _next_with_chips(button)
	var bb := _next_with_chips(sb)
	_bet(sb, mini(small_blind(), chips[sb]))
	_bet(bb, mini(2 * small_blind(), chips[bb]))
	events.append([-1, "Hand %d, blinds %d/%d" % [hand_no + 1, small_blind(), 2 * small_blind()]])
	high = 2 * small_blind()
	min_raise = high
	turn = bb
	_advance(bb)


func _copy() -> HoldemRules:
	var s := HoldemRules.new()
	s.players = players
	s.deal_seed = deal_seed
	s.hand_no = hand_no
	s.button = button
	s.chips = chips.duplicate()
	s.hands = hands.map(func(h): return h.duplicate())
	s.board = board.duplicate()
	s.deck = deck.duplicate()
	s.bet = bet.duplicate()
	s.put = put.duplicate()
	s.folded = folded.duplicate()
	s.acted = acted.duplicate()
	s.street = street
	s.high = high
	s.min_raise = min_raise
	s.turn = turn
	s.phase = phase
	s.won = won.duplicate(true)
	s.events = events.duplicate()
	s.winner = winner
	return s
