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

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok
