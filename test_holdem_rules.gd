extends SceneTree
## Texas Hold'em checks: hand ranking, blinds and turn order, betting rounds, side pots, bots.
## Run: godot --headless --path . -s test_holdem_rules.gd

const H := preload("res://holdem_rules.gd")
var failed := false


## Card from rank (1 ace .. 13 king) and suit (0 clubs, 1 diamonds, 2 hearts, 3 spades).
func c(r: int, s := 0) -> int:
	return s * 13 + r - 1


func cat(cards: Array) -> int:
	return H.score(cards)[0]


func _init() -> void:
	_check("straight flush", cat([c(9, 2), c(10, 2), c(11, 2), c(12, 2), c(13, 2), c(2), c(3, 1)]) == 8)
	_check("wheel straight A-5", H.score([c(1), c(2, 1), c(3, 2), c(4, 3), c(5), c(9, 1), c(13, 2)]) == [4, 5])
	_check("four of a kind", cat([c(7), c(7, 1), c(7, 2), c(7, 3), c(2), c(3), c(4)]) == 7)
	_check("full house beats flush", cat([c(8), c(8, 1), c(8, 2), c(3), c(3, 1), c(2), c(6)]) == 6
		and cat([c(2), c(5), c(9), c(11), c(13), c(3, 1), c(4, 1)]) == 5)
	_check("two pair, kicker decides", H._beats(H.score([c(13), c(13, 1), c(4), c(4, 1), c(12), c(2, 2), c(3, 3)]),
		H.score([c(13, 2), c(13, 3), c(4, 2), c(4, 3), c(11), c(2), c(3)])))
	_check("aces beat kings", H._beats(H.score([c(1), c(1, 1), c(5), c(7, 2), c(9, 3)]), H.score([c(13), c(13, 1), c(5, 1), c(7), c(9)])))
	_check("high card", cat([c(2), c(5, 1), c(9, 2), c(11, 3), c(13), c(4, 2), c(7, 3)]) == 0)

	# Heads-up: the button posts the small blind and acts first before the flop, last after it.
	var s := H.create(2, 0)  # button = 0
	_check("heads-up blinds 10/20, button to act", s.button == 0 and s.bet == [10, 20] and s.turn == 0 and s.chips == [990, 980])
	s = s.play(Vector3i(0, H.CALL, 0))
	_check("big blind gets its option", s.turn == 1 and s.street == 0)
	s = s.play(Vector3i(1, H.CALL, 0))
	_check("check closes preflop, flop dealt, big blind first", s.street == 1 and s.board.size() == 3 and s.turn == 1 and s.pot() == 40)
	_check("min bet is the big blind", not s.ok(Vector3i(1, H.RAISE, 10)) and s.ok(Vector3i(1, H.RAISE, 20)))
	s = s.play(Vector3i(1, H.RAISE, 100))
	_check("raise must be at least the last raise", not s.ok(Vector3i(0, H.RAISE, 150)) and s.ok(Vector3i(0, H.RAISE, 200)))
	var f := s.play(Vector3i(0, H.FOLD, 0))
	_check("fold: the other takes the pot", f.phase == H.DONE and f.chips == [980, 1020])
	var nx := f.play(Vector3i(0, H.NEXT, 0))
	_check("next hand: button moves", nx.button == 1 and nx.bet == [20, 10] and nx.hand_no == 1)

	# 3 players: small blind left of the button, then big blind; first to act is the button (left of the big blind).
	var t := H.create(3, 0)
	_check("3 players: blinds and first to act", t.bet == [0, 10, 20] and t.turn == 0)

	# Side pot: A all in for 100, B and C go on. A's hand only plays for the main pot.
	var p := H.create(3, 0)  # A has 100 in all, B and C 1000 (blinds already in)
	p.bet.assign([0, 10, 20])
	p.put.assign([0, 10, 20])
	p.chips.assign([100, 990, 980])
	p.hands = [[c(1), c(1, 1)], [c(13), c(13, 1)], [c(2), c(7, 1)]]
	p.deck = [c(13, 2), c(9, 3), c(4), c(3, 2), c(6, 3)]
	p = p.play(Vector3i(0, H.RAISE, 100))  # A all in
	p = p.play(Vector3i(1, H.RAISE, 400))
	p = p.play(Vector3i(2, H.CALL, 0))
	_check("all in and calls: still betting between the two with chips", p.phase == H.BETTING and p.street == 1)
	while p.phase == H.BETTING:
		p = p.play(Vector3i(p.turn, H.CALL, 0))
	# Board K 9 4 3 6: B's trip kings beat A's aces. Main pot 300 and side pot 600 both go to B.
	_check("side pots paid: B wins both with trips", p.chips == [0, 1500, 600] and p.won[0][0] == 1)
	var q := H.create(3, 0)
	q.bet.assign([0, 10, 20])
	q.put.assign([0, 10, 20])
	q.chips.assign([100, 990, 980])
	q.hands = [[c(1), c(1, 1)], [c(13), c(12, 1)], [c(2), c(7, 1)]]
	q.deck = [c(5, 2), c(9, 3), c(4), c(3, 2), c(11, 3)]
	q = q.play(Vector3i(0, H.RAISE, 100)).play(Vector3i(1, H.RAISE, 400)).play(Vector3i(2, H.CALL, 0))
	while q.phase == H.BETTING:
		q = q.play(Vector3i(q.turn, H.CALL, 0))
	_check("short stack wins the main pot only", q.chips == [300, 1200, 600])

	var g := H.create(4, 5)  # bots finish a game
	var moves := 0
	while g.phase != H.OVER and moves < 20000:
		var seat := g.turn if g.phase == H.BETTING else 0
		g = g.play(Bots.holdem_move(g, seat, 1 + seat % 2))
		moves += 1
	_check("bots play a 4 player game to the end (%d moves, %d hands)" % [moves, g.hand_no + 1],
		g.phase == H.OVER and g.chips.reduce(func(a, b): return a + b, 0) == 4000)
	var b := H.create(4, 9)
	var tm := Time.get_ticks_msec()
	var m := Bots.holdem_move(b, b.turn, 2)
	var ms := Time.get_ticks_msec() - tm
	_check("medium move is legal, %d ms (< 1500)" % ms, b.ok(m) and ms < 1500)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
