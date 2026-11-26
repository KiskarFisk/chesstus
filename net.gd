extends Node
## Autoload "Net": ENet connection (host + up to 3 guests), game proposals, synced scene changes,
## hub king positions, player names and colors. The host owns shared state and publishes it.

const PORT := 7777
const MAX_PLAYERS := 4
const SCENES := ["res://hub.tscn", "res://chess.tscn", "res://superchess.tscn"]
const HUB := "res://hub.tscn"
const SETTINGS := "user://settings.cfg"
const MAX_NAME := 16
# Player color slots, handed out in join order. Yellow and red are the white set tinted
# (tinting multiplies, so the white fill takes the color and black outlines stay black).
const PLAYER_COLORS := [
	{"name": "White", "piece": "w", "tint": Color.WHITE},
	{"name": "Black", "piece": "b", "tint": Color.WHITE},
	{"name": "Yellow", "piece": "w", "tint": Color(1.0, 0.82, 0.15)},
	{"name": "Red", "piece": "w", "tint": Color(1.0, 0.3, 0.25)},
]

signal proposal_changed

var status := "Offline"
var cells := {}  # peer id -> Vector2i, every king in the hub
var colors := {}  # peer id -> PLAYER_COLORS index
# Game being voted on, or {} if none. Host-owned:
# {"game": letter, "players": [ids], "seats": [id per seat], "votes": {id: true}}
var proposal := {}
var seats: Array = [1, 1]  # who plays each seat of the running game (offline: you play every seat)
var in_game: Array = []  # peers in the running game (players + spectators); empty while in the hub
var my_name := "Player"
var names := {}  # peer id -> display name, host-owned


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		my_name = _clean_name(cfg.get_value("player", "name", my_name))
	names = {1: my_name}
	colors = {1: 0}
	cells = {1: _free_spawn()}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func():
		cells.clear()
		colors.clear()
		names.clear()
		_request_spawn.rpc_id(1)
		_set_name.rpc_id(1, my_name))
	multiplayer.server_disconnected.connect(func(): _reset("Host left"))
	multiplayer.connection_failed.connect(func(): _reset("Couldn't connect"))


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		status = "Couldn't host on port %d" % PORT
		return
	multiplayer.multiplayer_peer = peer
	status = "Hosting on port %d, waiting..." % PORT


func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		status = "Bad address"
		return
	multiplayer.multiplayer_peer = peer
	status = "Connecting to %s..." % ip


func online() -> bool:
	return not multiplayer.get_peers().is_empty()


func color_of(id: int) -> Dictionary:
	return PLAYER_COLORS[colors.get(id, 0)]


func name_of(id: int) -> String:
	return names.get(id, "Host" if id == 1 else "Guest")


## Change our name: remembered in user://settings.cfg and sent to the host.
func set_my_name(n: String) -> void:
	my_name = _clean_name(n)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("player", "name", my_name)
	cfg.save(SETTINGS)
	_set_name.rpc_id(1, my_name)


@rpc("any_peer", "call_local", "reliable")
func _set_name(n: String) -> void:
	if multiplayer.is_server():
		names[multiplayer.get_remote_sender_id()] = _clean_name(n)
		_sync_names.rpc(names)


@rpc("authority", "call_local", "reliable")
func _sync_names(d: Dictionary) -> void:
	names = d


static func _clean_name(n: String) -> String:
	n = n.strip_edges().left(MAX_NAME)
	return n if n else "Player"


# --- Game proposals: every call goes to the host (rpc_id(1, ...)), which validates and publishes. ---

@rpc("any_peer", "call_local", "reliable")
func propose(game: String) -> void:
	if not multiplayer.is_server() or not proposal.is_empty() or not in_game.is_empty() \
			or not _hub().GAMES.has(game):
		return
	var players := [1] + Array(multiplayer.get_peers())
	_publish({"game": game, "players": players, "seats": _default_seats(game, players), "votes": {}})


## Spread players over the game's teams, then over each team's seats. Short on players,
## someone holds several seats (2 players in Superchess: one runs both light armies).
func _default_seats(game: String, players: Array) -> Array:
	var teams: Array = _hub().GAMES[game].teams
	var s := []
	s.resize(_hub().GAMES[game].seats.size())
	for t in teams.size():
		var mine := players.filter(func(p): return players.find(p) % teams.size() == t)
		if mine.is_empty():
			mine = [players[t % players.size()]]
		for j in teams[t].size():
			s[teams[t][j]] = mine[j % mine.size()]
	return s


@rpc("any_peer", "call_local", "reliable")
func set_seat(seat: int, id: int) -> void:
	if not multiplayer.is_server() or proposal.is_empty() or id not in proposal.players \
			or seat < 0 or seat >= proposal.seats.size():
		return
	var s: Array = proposal.seats
	var other := s.find(id)
	# One seat per team (chess): picking someone seated elsewhere swaps them. Team games with
	# several seats per team let one player hold more than one seat, so just assign.
	if other != -1 and _hub().GAMES[proposal.game].teams.all(func(t): return t.size() == 1):
		s[other] = s[seat]
	s[seat] = id
	proposal.votes = {}  # seating changed, everyone re-confirms
	_publish(proposal)


@rpc("any_peer", "call_local", "reliable")
func vote(yes: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or proposal.is_empty() or id not in proposal.players:
		return
	if not yes:
		_publish({}, "%s declined" % name_of(id))
		return
	proposal.votes[id] = true
	if proposal.players.all(func(p): return proposal.votes.has(p)):
		_start.rpc(proposal.seats, proposal.players, _hub().GAMES[proposal.game].scene)
	else:
		_publish(proposal)


func _publish(p: Dictionary, msg := "") -> void:
	_set_proposal.rpc(p, msg)


@rpc("authority", "call_local", "reliable")
func _set_proposal(p: Dictionary, msg: String) -> void:
	proposal = p
	if msg:
		status = msg
	proposal_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start(s: Array, players: Array, scene: String) -> void:
	seats = s
	in_game = players
	proposal = {}
	proposal_changed.emit()
	if multiplayer.get_unique_id() in players:  # someone who joined mid-vote stays in the hub
		goto(scene)


## Call a game RPC on everyone in the running game (players and spectators), including ourselves.
## Games use this instead of .rpc(): peers waiting in the hub don't have the game scene.
func send(method: Callable, arg = null) -> void:
	for id in in_game:
		if arg == null:
			method.rpc_id(id)
		else:
			method.rpc_id(id, arg)


## Game over: everyone who was in it goes back to the hub. Games gate when this can be called.
func end_game() -> void:
	_end_game.rpc()


@rpc("any_peer", "call_local", "reliable")
func _end_game() -> void:
	var was_in := multiplayer.get_unique_id() in in_game
	in_game = []
	if was_in:
		goto(HUB)


func goto(scene: String) -> void:
	if scene in SCENES:
		get_tree().change_scene_to_file(scene)


## Move our own king; the hub has already checked walls and occupancy.
func move(cell: Vector2i) -> void:
	cells[multiplayer.get_unique_id()] = cell
	_moved.rpc(cell)


@rpc("any_peer", "reliable")
func _moved(cell: Vector2i) -> void:
	var id := multiplayer.get_remote_sender_id()
	var from = cells.get(id)
	# Untrusted: one king step, no walls. Occupancy isn't checked so everyone stays in agreement on races.
	if from == null or _hub().tile(cell) == "#" or absi(cell.x - from.x) > 1 or absi(cell.y - from.y) > 1:
		return
	cells[id] = cell


@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not cells.has(id):
		cells[id] = _free_spawn()
		colors[id] = range(PLAYER_COLORS.size()).filter(func(i): return i not in colors.values())[0]
	_sync.rpc(cells, colors)


@rpc("authority", "reliable")
func _sync(c: Dictionary, col: Dictionary) -> void:
	cells = c
	colors = col


func _on_peer_connected(_id: int) -> void:
	status = "Connected"
	if multiplayer.is_server() and not proposal.is_empty():
		_publish({})  # player list changed, the open vote is stale


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return  # host's syncs below cover clients; host leaving is server_disconnected
	var seated := id in in_game and id in seats
	var msg := "%s left" % name_of(id)
	in_game.erase(id)
	for d in [cells, colors, names]:
		d.erase(id)
	_sync.rpc(cells, colors)
	_sync_names.rpc(names)
	_publish({}, msg)  # also drops any open vote
	if seated:
		_end_game.rpc()  # a player in the running game left, it can't continue


func _free_spawn() -> Vector2i:
	var all: Array[Vector2i] = _hub().spawns()
	var free := all.filter(func(s): return s not in cells.values())
	return free.pick_random() if not free.is_empty() else all.pick_random()  # ponytail: overlap when all spawns taken


func _hub() -> GDScript:
	return load("res://hub.gd")  # loaded lazily: hub.gd references Net, avoid a preload cycle


func _reset(msg: String) -> void:
	var mine = cells.get(multiplayer.get_unique_id(), cells.get(1))
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	cells = {1: mine if mine != null else _free_spawn()}
	colors = {1: 0}
	proposal = {}
	seats = [1, 1]
	in_game = []
	names = {1: my_name}
	proposal_changed.emit()
	status = msg
	goto(HUB)
