extends SceneTree
## Quoridor rule checks: steps, jumps, wall overlap and path blocking, bots.
## Run: godot --headless --path . -s test_quoridor_rules.gd

const Q := preload("res://quoridor_rules.gd")
var failed := false


func _init() -> void:
	var s := Q.new()
	_check("start: 3 steps + 128 walls", s.moves().size() == 3 + 128)
	_check("start: both 8 from goal", s.distance(0) == 8 and s.distance(1) == 8)

	s.pawns = [Vector2i(4, 4), Vector2i(4, 3)]
	_check("straight jump over the other pawn", Vector3i(4, 2, Q.STEP) in s.steps())
	s.h = {Vector2i(4, 2): true}  # wall behind the other pawn
	var st := s.steps()
	_check("wall behind: diagonal jumps instead",
		Vector3i(4, 2, Q.STEP) not in st and Vector3i(3, 3, Q.STEP) in st and Vector3i(5, 3, Q.STEP) in st)
	s.h = {Vector2i(3, 3): true}  # wall between the pawns (covers columns 3-4)
	_check("wall between: no jump, no step up", st.size() > 0 and s.steps().all(func(m): return m.y >= 4))

	s = Q.new()
	s.h = {Vector2i(3, 3): true}
	_check("no overlapping wall", not s.wall_ok(Vector3i(4, 3, Q.H)) and not s.wall_ok(Vector3i(2, 3, Q.H)))
	_check("no crossing wall", not s.wall_ok(Vector3i(3, 3, Q.V)))
	_check("adjacent wall ok", s.wall_ok(Vector3i(5, 3, Q.H)) and s.wall_ok(Vector3i(4, 3, Q.V)))

	s = Q.new()  # top row walled off except a pocket at column 8, then try to close the pocket
	s.pawns[1] = Vector2i(0, 8)
	s.h = {Vector2i(0, 0): true, Vector2i(2, 0): true, Vector2i(4, 0): true, Vector2i(6, 0): true}
	s.v = {Vector2i(7, 0): true}
	_check("can't wall a pawn off its goal", s.distance(0) == 12 and not s.wall_ok(Vector3i(7, 1, Q.H))
		and s.wall_ok(Vector3i(0, 5, Q.H)))
	var empty := Q.new()
	empty.walls_left = [0, 10]
	_check("no walls left, no walls", empty.moves().size() == 3)

	s = Q.new()
	s.pawns = [Vector2i(4, 1), Vector2i(0, 8)]
	_check("medium bot takes the winning step", Bots.quoridor_move(s, 2) == Vector3i(4, 0, Q.STEP))
	_check("winner after reaching the top", s.play(Vector3i(4, 0, Q.STEP)).winner() == 0)
	s = Q.new()
	s.pawns = [Vector2i(4, 2), Vector2i(0, 7)]  # a corner wall costs Black 2 steps, more than a step gains
	_check("medium bot walls when it gains more than a step", Bots.quoridor_move(s, 2).z != Q.STEP)
	var t := Time.get_ticks_msec()
	Bots.quoridor_move(Q.new(), 2)
	var ms := Time.get_ticks_msec() - t
	_check("medium bot move in %d ms (< 1000)" % ms, ms < 1000)
	_check("easy bot returns a legal move", Bots.quoridor_move(Q.new(), 1) in Q.new().moves())

	# --- 4 players ---
	var f := Q.create(4)
	_check("4p: pawns on all four edges, 5 walls each, all 8 from goal", f.pawns.size() == 4
		and f.walls_left == [5, 5, 5, 5] and range(4).all(func(i): return f.distance(i) == 8))
	var order := []
	var g := f
	for i in 5:
		order.append(g.turn)
		g = g.play(g.steps()[0])
	_check("4p: turns go round 0 1 2 3 0", order == [0, 1, 2, 3, 0])
	_check("4p: left side wins on the right edge", not f.at_goal(1, Vector2i(0, 4)) and f.at_goal(1, Vector2i(8, 2)))
	f.pawns = [Vector2i(4, 6), Vector2i(4, 5), Vector2i(4, 4), Vector2i(8, 4)]  # a pawn behind the one in front
	var fs := f.steps()
	_check("4p: can't jump two pawns, goes diagonal", Vector3i(4, 4, Q.STEP) not in fs
		and Vector3i(3, 5, Q.STEP) in fs and Vector3i(5, 5, Q.STEP) in fs)
	f = Q.create(4)  # same pocket as the 2 player test, with the side pawns on the board too
	f.pawns[2] = Vector2i(0, 8)
	f.h = {Vector2i(0, 0): true, Vector2i(2, 0): true, Vector2i(4, 0): true, Vector2i(6, 0): true}
	f.v = {Vector2i(7, 0): true}
	_check("4p: can't wall a pawn off its goal", f.distance(0) == 12 and not f.wall_ok(Vector3i(7, 1, Q.H))
		and f.wall_ok(Vector3i(0, 5, Q.H)))
	var r := Q.create(4).resign(0)
	_check("4p: resigning passes the turn and frees the square", r.turn == 1 and r.pawns[0] == Q.OFF
		and r.play(r.steps()[0]).play(Vector3i(0, 0, Q.H)).play(r.steps()[0]).turn == 1)
	_check("4p: last one left wins", r.resign(1).resign(3).winner() == 2 and r.winner() == -1)
	_check("4p: easy and medium bots return legal moves", Bots.quoridor_move(Q.create(4), 1) in Q.create(4).moves()
		and Bots.quoridor_move(Q.create(4), 2) in Q.create(4).moves())
	t = Time.get_ticks_msec()
	Bots.quoridor_move(Q.create(4), 2)
	ms = Time.get_ticks_msec() - t
	_check("4p: medium bot move in %d ms (< 1000)" % ms, ms < 1000)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
