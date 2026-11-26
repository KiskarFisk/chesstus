class_name QuoridorRules
extends RefCounted
## Quoridor on a 9x9 board, 2 or 4 players. No UI. Immutable: play() returns a new state.
## Cells are Vector2i(x, y), y = 0 the top row. Each side starts in the middle of one edge and races to the
## opposite edge: with 2 players side 0 starts at the bottom and side 1 at the top; with 4 they go clockwise
## (bottom, left, top, right). Walls are two cells long and sit in the grooves; a wall is named by the top-left
## cell of the 2x2 block it splits, (0..7, 0..7). Moves are Vector3i(x, y, kind): kind STEP moves the pawn to
## cell (x, y), H / V place a horizontal / vertical wall there.

const N := 9
const STEP := 0
const H := 1
const V := 2
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const BOTTOM := 0
const LEFT := 1
const TOP := 2
const RIGHT := 3
const START := [Vector2i(4, N - 1), Vector2i(0, 4), Vector2i(4, 0), Vector2i(N - 1, 4)]  # by edge
const OFF := Vector2i(-9, -9)  # where a resigned side's pawn goes

var homes: Array = [BOTTOM, TOP]  # edge each side starts on
var pawns: Array[Vector2i] = [START[BOTTOM], START[TOP]]
var walls_left: Array[int] = [10, 10]
var h := {}  # Vector2i -> true, horizontal walls
var v := {}  # vertical walls
var turn := 0
var resigned: Array = []  # sides out of a 4 player game; their pawn is OFF the board


## A new game: 10 walls each for 2 players, 5 for 4.
static func create(players: int) -> QuoridorRules:
	var s := QuoridorRules.new()
	if players == 4:
		s.homes = [BOTTOM, LEFT, TOP, RIGHT]
		s.pawns.assign(s.homes.map(func(e): return START[e]))
		s.walls_left.assign([5, 5, 5, 5])
	return s


func play(m: Vector3i) -> QuoridorRules:
	var s := _copy()
	if m.z == STEP:
		s.pawns[turn] = Vector2i(m.x, m.y)
	else:
		(s.h if m.z == H else s.v)[Vector2i(m.x, m.y)] = true
		s.walls_left[turn] -= 1
	s.turn = _next(turn)
	return s


## side leaves the game: its pawn comes off the board and its turns are skipped.
func resign(side: int) -> QuoridorRules:
	var s := _copy()
	s.resigned.append(side)
	s.pawns[side] = OFF
	if turn == side:
		s.turn = s._next(turn)
	return s


## Side that has reached its goal edge, or the last one left; -1 if none.
func winner() -> int:
	var left := range(pawns.size()).filter(func(side): return side not in resigned)
	if left.size() == 1:
		return left[0]
	for side in left:
		if at_goal(side, pawns[side]):
			return side
	return -1


## Is cell c on the edge opposite side's start?
func at_goal(side: int, c: Vector2i) -> bool:
	match homes[side]:
		BOTTOM: return c.y == 0
		TOP: return c.y == N - 1
		LEFT: return c.x == N - 1
	return c.x == 0


func moves() -> Array[Vector3i]:
	var out := steps()
	if walls_left[turn] > 0:
		for y in N - 1:
			for x in N - 1:
				for kind in [H, V]:
					var m := Vector3i(x, y, kind)
					if wall_ok(m):
						out.append(m)
	return out


## Pawn moves for the side to move: one step, or jump a pawn next to it (sideways if a wall, the edge or
## another pawn is behind it).
func steps() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var me := pawns[turn]
	for d in DIRS:
		if not open(me, d):
			continue
		var c := me + d
		var lands: Array[Vector2i] = []
		if c not in pawns:
			lands = [c]
		elif open(c, d) and c + d not in pawns:
			lands = [c + d]
		else:
			for side in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
				if open(c, side) and c + side not in pawns:
					lands.append(c + side)
		for t in lands:
			if Vector3i(t.x, t.y, STEP) not in out:  # two diagonal jumps can land on the same cell
				out.append(Vector3i(t.x, t.y, STEP))
	return out


## Can a pawn step from c in direction d (on the board, no wall in between)?
func open(c: Vector2i, d: Vector2i) -> bool:
	var to := c + d
	if to.x < 0 or to.y < 0 or to.x >= N or to.y >= N:
		return false
	if d.x == 0:  # crossing a horizontal groove
		var row := mini(c.y, to.y)
		return not (h.has(Vector2i(c.x, row)) or h.has(Vector2i(c.x - 1, row)))
	var col := mini(c.x, to.x)
	return not (v.has(Vector2i(col, c.y)) or v.has(Vector2i(col, c.y - 1)))


## Wall placement check for the side to move: walls left, in range, no overlap or crossing, every pawn keeps a path.
func wall_ok(m: Vector3i) -> bool:
	var c := Vector2i(m.x, m.y)
	if m.z not in [H, V] or walls_left[turn] <= 0 or c.x < 0 or c.y < 0 or c.x >= N - 1 or c.y >= N - 1 \
			or h.has(c) or v.has(c):
		return false
	var along := Vector2i.RIGHT if m.z == H else Vector2i.DOWN
	var same := h if m.z == H else v
	if same.has(c + along) or same.has(c - along):
		return false
	var after := play(m)  # copy, not a temporary edit: the UI and a bot thread may read this state at once
	for side in pawns.size():
		if side not in resigned and after.distance(side) < 0:
			return false
	return true


## Fewest steps from side's pawn to its goal edge, ignoring other pawns. -1 if walled off.
func distance(side: int) -> int:
	var start := pawns[side]
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		if at_goal(side, c):
			return seen[c]
		for d in DIRS:
			if open(c, d) and not seen.has(c + d):
				seen[c + d] = seen[c] + 1
				queue.append(c + d)
	return -1


func _next(side: int) -> int:
	var t := (side + 1) % pawns.size()
	while t in resigned and t != side:
		t = (t + 1) % pawns.size()
	return t


func _copy() -> QuoridorRules:
	var s := QuoridorRules.new()
	s.homes = homes
	s.pawns = pawns.duplicate()
	s.walls_left = walls_left.duplicate()
	s.h = h.duplicate()
	s.v = v.duplicate()
	s.turn = turn
	s.resigned = resigned.duplicate()
	return s
