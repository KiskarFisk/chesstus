class_name QuoridorRules
extends RefCounted
## Quoridor on a 9x9 board, two players. No UI. Immutable: play() returns a new state.
## Cells are Vector2i(x, y), y = 0 the top row. Side 0 starts at the bottom middle and races to the top row,
## side 1 the reverse. Walls are two cells long and sit in the grooves; a wall is named by the top-left cell
## of the 2x2 block it splits, (0..7, 0..7). Moves are Vector3i(x, y, kind): kind STEP moves the pawn to
## cell (x, y), H / V place a horizontal / vertical wall there.

const N := 9
const WALLS := 10
const STEP := 0
const H := 1
const V := 2
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var pawns: Array[Vector2i] = [Vector2i(4, N - 1), Vector2i(4, 0)]
var walls_left: Array[int] = [WALLS, WALLS]
var h := {}  # Vector2i -> true, horizontal walls
var v := {}  # vertical walls
var turn := 0


func play(m: Vector3i) -> QuoridorRules:
	var s := QuoridorRules.new()
	s.pawns = pawns.duplicate()
	s.walls_left = walls_left.duplicate()
	s.h = h.duplicate()
	s.v = v.duplicate()
	if m.z == STEP:
		s.pawns[turn] = Vector2i(m.x, m.y)
	else:
		(s.h if m.z == H else s.v)[Vector2i(m.x, m.y)] = true
		s.walls_left[turn] -= 1
	s.turn = 1 - turn
	return s


## Side that has reached its goal row, or -1.
func winner() -> int:
	for side in 2:
		if pawns[side].y == goal(side):
			return side
	return -1


static func goal(side: int) -> int:
	return 0 if side == 0 else N - 1


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


## Pawn moves for the side to move: one step, or jump the other pawn (sideways if a wall or the edge is behind it).
func steps() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var me := pawns[turn]
	var other := pawns[1 - turn]
	for d in DIRS:
		if not open(me, d):
			continue
		var c := me + d
		if c != other:
			out.append(Vector3i(c.x, c.y, STEP))
		elif open(other, d):
			out.append(Vector3i(c.x + d.x, c.y + d.y, STEP))
		else:
			for side in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
				if open(other, side):
					out.append(Vector3i(c.x + side.x, c.y + side.y, STEP))
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
	return after.distance(0) >= 0 and after.distance(1) >= 0


## Fewest steps from side's pawn to its goal row, ignoring the other pawn. -1 if walled off.
func distance(side: int) -> int:
	var start := pawns[side]
	var target := goal(side)
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		if c.y == target:
			return seen[c]
		for d in DIRS:
			if open(c, d) and not seen.has(c + d):
				seen[c + d] = seen[c] + 1
				queue.append(c + d)
	return -1
