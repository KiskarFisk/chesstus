extends SceneTree
## Cribbage checks: hand counting, pegging, go, the show, dealing, bots.
## Run: godot --headless --path . -s test_cribbage_rules.gd

const R := preload("res://cribbage_rules.gd")
var failed := false


## Card from rank (1..13) and suit (0 clubs, 1 diamonds, 2 hearts, 3 spades).
func c(r: int, s := 0) -> int:
	return s * 13 + r - 1


func _init() -> void:
	var t := func(cards, start, crib := false): return R.total(R.score_hand(cards, start, crib))
	_check("29 hand: three 5s and the jack of the starter's suit", t.call([c(5, 0), c(5, 1), c(5, 2), c(11, 3)], c(5, 3)) == 29)
	_check("double run 4-5-6-6 with a 9: 16", t.call([c(4), c(5, 1), c(6, 2), c(6, 3)], c(9, 1)) == 16)
	_check("nothing: 0", t.call([c(1), c(3, 1), c(7, 2), c(9, 3)], c(13, 1)) == 0)
	_check("hand flush 4, with starter 5", t.call([c(1), c(3), c(7), c(9)], c(13, 2)) == 4 and t.call([c(1), c(3), c(7), c(9)], c(12)) == 5)
	_check("crib flush needs all five", t.call([c(1), c(3), c(7), c(9)], c(13, 2), true) == 0)
	_check("nobs", R.score_hand([c(11, 2), c(2), c(4, 1), c(8, 3)], c(1, 2)).nobs == 1)

	# Pegging. 2 players, dealer 0, so seat 1 leads.
	var s := R.create(2, 7)
	s.dealer = 0
	s.phase = R.PLAY
	s.turn = 1
	s.hands = [[c(8), c(8, 1), c(9), c(1)], [c(7), c(8, 2), c(10), c(2)]]
	s.kept = s.hands.map(func(h): return h.duplicate())
	s.crib = [c(3), c(4), c(5), c(6)]
	s.starter = c(13)
	s = s.play(Vector3i(1, c(7), -1))
	s = s.play(Vector3i(0, c(8), -1))
	_check("fifteen pegs 2", s.scores == [2, 0] and s.count == 15)
	s = s.play(Vector3i(1, c(8, 2), -1))
	_check("pair pegs 2", s.scores == [2, 2] and s.count == 23)
	s = s.play(Vector3i(0, c(8, 1), -1))
	_check("three of a kind + 31 peg 8, count resets, other side leads", s.scores == [10, 2] and s.count == 0 and s.turn == 1)
	var over := R.create(2, 7)
	over.phase = R.PLAY
	over.turn = 1
	over.count = 25
	over.hands = [[c(1)], [c(10), c(2)]]
	_check("can't go over 31", not over.ok(Vector3i(1, c(10), -1)) and over.ok(Vector3i(1, c(2), -1)))

	var p := R.create(2, 7)  # go: seat 1 can't play on 28, seat 0 plays on and pegs the go
	p.dealer = 0
	p.phase = R.PLAY
	p.turn = 0
	p.count = 25
	p.pile = [c(13), c(12), c(5)]
	p.hands = [[c(3), c(2)], [c(10)]]
	p.kept = [[c(3), c(2), c(13), c(5)], [c(10), c(12), c(1), c(1, 1)]]
	p.crib = [c(4), c(4, 1), c(6), c(6, 1)]
	p.starter = c(9)
	p = p.play(Vector3i(0, c(3), -1))
	_check("other side can't play: same player goes again", p.turn == 0 and p.count == 28)
	p = p.play(Vector3i(0, c(2), -1))
	_check("go pegs 1 and resets the count", p.scores[0] == 1 and p.count == 0 and p.turn == 1)
	p = p.play(Vector3i(1, c(10), -1))
	_check("last card pegs 1, then the show", p.phase == R.SHOW and p.shown.size() == 3 and p.shown[2][3])
	var next := p.play(Vector3i(0, -1, -1))
	_check("next deal: dealer moves, 6 cards each", next.dealer == 1 and next.phase == R.DISCARD
		and next.hands.all(func(h): return h.size() == 6) and next.hand_no == 1)

	for n in [2, 3, 4]:
		var d := R.create(n, 42)
		var all := []
		for h in d.hands:
			all += h
		all += d.crib + [d.cut]
		var distinct := {}
		for x in all:
			distinct[x] = true
		_check("%d players: deal sizes and no repeated cards" % n, d.hands.all(func(h): return h.size() == (6 if n == 2 else 5))
			and distinct.size() == all.size() and d.crib.size() == (1 if n == 3 else 0))
	_check("same seed, same deal", R.create(3, 99).hands == R.create(3, 99).hands and R.create(3, 99).hands != R.create(3, 98).hands)

	var w := R.create(4, 5)
	w.scores = [119, 0]
	w.phase = R.PLAY
	w.turn = 2
	w.hands = [[c(1)], [c(2)], [c(10)], [c(3)]]
	w.count = 5
	w.pile = [c(5)]
	_check("partners share a score; 121 wins at once", w.play(Vector3i(2, c(10), -1)).winner == 0
		and w.play(Vector3i(2, c(10), -1)).phase == R.OVER)

	var b := R.create(2, 3)
	var tm := Time.get_ticks_msec()
	var dm := Bots.cribbage_move(b, 0, 2)
	var ms := Time.get_ticks_msec() - tm
	_check("medium discard is legal, in %d ms (< 1500)" % ms, b.ok(dm) and ms < 1500)
	_check("easy discard is legal", b.ok(Bots.cribbage_move(b, 1, 1)))
	var game := R.create(3, 11)  # bots play whole deals without getting stuck
	var steps := 0
	while game.phase != R.OVER and steps < 3000:
		var seat := game.turn
		if game.phase == R.DISCARD:
			seat = range(3).filter(func(q): return game.hands[q].size() > 4)[0]
		elif game.phase == R.SHOW:
			seat = 0
		game = game.play(Bots.cribbage_move(game, seat, 1 + steps % 2))
		steps += 1
	_check("bots play a 3 player game to 121 (%d moves)" % steps, game.phase == R.OVER and game.scores.max() == 121)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
