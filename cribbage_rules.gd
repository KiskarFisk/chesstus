class_name CribbageRules
extends RefCounted
## Cribbage for 2, 3 or 4 players (4: partners across the table, seats 0 + 2 against 1 + 3). No UI.
## play() returns a new state. First team to 121 wins, the moment it gets there.
## Cards are 0..51: rank = c % 13 + 1 (ace 1 .. king 13), suit = c / 13 (clubs, diamonds, hearts, spades).
## Each deal is shuffled from deal_seed + hand number, so every peer deals the same cards.
## Moves are Vector3i(seat, card, card2):
##   DISCARD: card (and card2 with 2 players, else -1) go to the dealer's crib.
##   PLAY: card is played onto the count; card2 is -1. Someone who can't play says "go" automatically.
##   SHOW: (seat, -1, -1) deals the next hand.

const GOAL := 121
enum {DISCARD, PLAY, SHOW, OVER}

var players := 2
var deal_seed := 0
var hand_no := 0
var dealer := 0
var scores: Array[int] = []  # per team: the front peg
var backs: Array[int] = []  # per team: the back peg, where the front one was before its last move
var hands: Array = []  # seat -> cards still in hand
var kept: Array = []  # seat -> the 4 cards kept after discarding, counted in the show
var crib: Array = []
var cut := -1  # the starter, decided at the deal but only turned up once everyone has discarded
var starter := -1
var phase := DISCARD
var turn := -1  # PLAY: the seat to play
var pile: Array = []  # cards played since the count last went back to 0
var count := 0
var shown: Array = []  # SHOW: [seat, cards, score_hand() result, is crib] in counting order
var events: Array = []  # [seat, points, text], newest last, for the UI's log
var winner := -1  # team


static func create(n: int, game_seed: int) -> CribbageRules:
	var s := CribbageRules.new()
	s.players = n
	s.deal_seed = game_seed
	for t in s.teams():
		s.scores.append(0)
		s.backs.append(0)
	s.dealer = posmod(game_seed, n)
	s._deal()
	return s


func teams() -> int:
	return 2 if players == 4 else players


func team(seat: int) -> int:
	return seat % 2 if players == 4 else seat


static func rank(c: int) -> int:
	return c % 13 + 1


static func suit(c: int) -> int:
	return c / 13


static func value(c: int) -> int:
	return mini(rank(c), 10)


static func card_name(c: int) -> String:
	return Cards.card_name(c)


## How many cards each seat puts in the crib.
func discards() -> int:
	return 2 if players == 2 else 1


func can_play(seat: int) -> bool:
	return hands[seat].any(func(c): return value(c) <= 31 - count)


func ok(m: Vector3i) -> bool:
	if m.x < 0 or m.x >= players:
		return false
	match phase:
		DISCARD:
			var hand: Array = hands[m.x]
			if hand.size() == 4 or m.y not in hand:
				return false
			return m.z == -1 if discards() == 1 else (m.z in hand and m.z != m.y)
		PLAY:
			return m.x == turn and m.y in hands[m.x] and value(m.y) <= 31 - count and m.z == -1
		SHOW:
			return m.y == -1 and m.z == -1
	return false


## Legal moves for seat (for bots): every discard choice, every playable card, or dealing on after the show.
func moves(seat: int) -> Array[Vector3i]:
	if phase == SHOW:
		return [Vector3i(seat, -1, -1)]
	var out: Array[Vector3i] = []
	var hand: Array = hands[seat]
	for i in hand.size():
		var options: Array[Vector3i] = [Vector3i(seat, hand[i], -1)]
		if phase == DISCARD and discards() == 2:
			options.assign(range(i + 1, hand.size()).map(func(j): return Vector3i(seat, hand[i], hand[j])))
		for m in options:
			if ok(m):
				out.append(m)
	return out


func play(m: Vector3i) -> CribbageRules:
	var s := _copy()
	match phase:
		DISCARD:
			for c in [m.y, m.z]:
				if c != -1:
					s.hands[m.x].erase(c)
					s.crib.append(c)
			if s.hands.all(func(h): return h.size() == 4):
				s.kept = s.hands.map(func(h): return h.duplicate())
				s.starter = cut
				s.phase = PLAY
				s.turn = (dealer + 1) % players
				if rank(cut) == 11:
					s._peg(dealer, 2, "his heels (jack turned up)")
		PLAY:
			s.hands[m.x].erase(m.y)
			s.pile.append(m.y)
			s.count += value(m.y)
			s.events.append([m.x, 0, "plays %s, count %d" % [card_name(m.y), s.count]])
			s._peg_play(m.x)
			if s.phase == OVER:
				pass
			elif s.count == 31:
				s._new_count(m.x)
			else:
				var next := s._next_to_play(m.x)
				if next == -1:
					s._peg(m.x, 1, "last card" if s.hands.all(func(h): return h.is_empty()) else "go")
					if s.phase != OVER:
						s._new_count(m.x)
				else:
					s.turn = next
		SHOW:
			s.hand_no += 1
			s.dealer = (dealer + 1) % players
			s._deal()
	s.events = s.events.slice(-8)
	return s


## Points for a hand of 4 plus the starter, by kind. A crib only scores a flush if all 5 match.
static func score_hand(cards: Array, start: int, is_crib := false) -> Dictionary:
	var all := cards + [start]
	var d := {"fifteens": 0, "pairs": 0, "runs": 0, "flush": 0, "nobs": 0}
	for mask in range(1, 32):
		var sum := 0
		for i in 5:
			if mask & (1 << i):
				sum += value(all[i])
		if sum == 15:
			d.fifteens += 2
	for i in 5:
		for j in range(i + 1, 5):
			if rank(all[i]) == rank(all[j]):
				d.pairs += 2
	for size in [5, 4, 3]:  # longest runs only, each way of making one counts (double runs)
		var n := 0
		for mask in 32:
			var pick := []
			for i in 5:
				if mask & (1 << i):
					pick.append(all[i])
			if pick.size() == size and _is_run(pick):
				n += 1
		if n:
			d.runs = n * size
			break
	if cards.all(func(c): return suit(c) == suit(cards[0])):
		d.flush = 5 if suit(start) == suit(cards[0]) else 4
		if is_crib and d.flush == 4:
			d.flush = 0
	if cards.any(func(c): return rank(c) == 11 and suit(c) == suit(start)):
		d.nobs = 1
	return d


static func total(d: Dictionary) -> int:
	return d.values().reduce(func(a, b): return a + b, 0)


static func _is_run(cards: Array) -> bool:
	var r := cards.map(func(c): return rank(c))
	r.sort()
	for i in range(1, r.size()):
		if r[i] != r[i - 1] + 1:
			return false
	return true


## Pegging points for the card just played: 15, 31, pairs and runs at the end of the pile.
func _peg_play(seat: int) -> void:
	if count == 15:
		_peg(seat, 2, "fifteen")
	if count == 31:
		_peg(seat, 2, "thirty-one")
	var same := 1
	while same < pile.size() and rank(pile[-1 - same]) == rank(pile[-1]):
		same += 1
	if same >= 2:
		_peg(seat, [0, 0, 2, 6, 12][same], ["", "", "pair", "three of a kind", "four of a kind"][same])
	for size in range(pile.size(), 2, -1):
		if _is_run(pile.slice(-size)):
			_peg(seat, size, "run of %d" % size)
			break


func _peg(seat: int, points: int, what: String) -> void:
	if phase == OVER:
		return
	var t := team(seat)
	backs[t] = scores[t]
	scores[t] = mini(GOAL, scores[t] + points)
	events.append([seat, points, what])
	if scores[t] >= GOAL:
		winner = t
		phase = OVER


## The next seat after seat (seat itself last) that can play on this count, or -1.
func _next_to_play(seat: int) -> int:
	for i in range(1, players + 1):
		var q := (seat + i) % players
		if can_play(q):
			return q
	return -1


## The count goes back to 0; the seat after the last player who still has cards leads. No cards left: the show.
func _new_count(last: int) -> void:
	count = 0
	pile = []
	for i in range(1, players + 1):
		var q := (last + i) % players
		if not hands[q].is_empty():
			turn = q
			return
	_show()


## Hands count in order from the dealer's left, the dealer's hand and crib last; stops as soon as someone wins.
func _show() -> void:
	phase = SHOW
	turn = -1
	shown = []
	for i in range(1, players + 1):
		var q := (dealer + i) % players
		shown.append([q, kept[q], score_hand(kept[q], starter), false])
	shown.append([dealer, crib, score_hand(crib, starter, true), true])
	for row in shown:
		var points := total(row[2])
		if points:
			_peg(row[0], points, "crib" if row[3] else "hand")


func _deal() -> void:
	var deck := Cards.shuffled("%d:%d" % [deal_seed, hand_no])
	var size := 6 if players == 2 else 5
	hands = []
	for p in players:
		var hand := deck.slice(p * size, (p + 1) * size)
		hand.sort_custom(func(a, b): return rank(a) < rank(b) or (rank(a) == rank(b) and a < b))
		hands.append(hand)
	crib = [deck[players * size]] if players == 3 else []
	cut = deck[51]
	starter = -1
	kept = []
	pile = []
	count = 0
	shown = []
	turn = -1
	phase = DISCARD


func _copy() -> CribbageRules:
	var s := CribbageRules.new()
	s.players = players
	s.deal_seed = deal_seed
	s.hand_no = hand_no
	s.dealer = dealer
	s.scores = scores.duplicate()
	s.backs = backs.duplicate()
	s.hands = hands.map(func(h): return h.duplicate())
	s.kept = kept
	s.crib = crib.duplicate()
	s.cut = cut
	s.starter = starter
	s.phase = phase
	s.turn = turn
	s.pile = pile.duplicate()
	s.count = count
	s.shown = shown
	s.events = events.duplicate()
	s.winner = winner
	return s
