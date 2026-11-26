extends Node
## Autoload "Net": ENet connection, synced scene changes, and hub king positions.
## Host is white, client is black.

const PORT := 7777
const SCENES := ["res://hub.tscn", "res://chess.tscn"]
const SETTINGS := "user://settings.cfg"
const MAX_NAME := 16

signal proposal_changed

var status := "Offline"
var cells := {}  # peer id -> Vector2i, every king in the hub
# Game being voted on, or {} if none. Host-owned:
# {"game": letter, "players": [ids], "seats": [id per seat], "votes": {id: true}}
var proposal := {}
var seats: Array = [1, 1]  # who plays each seat of the running game (offline: you play every seat)
var my_name := "Player"
var names := {}  # peer id -> display name, host-owned


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		my_name = _clean_name(cfg.get_value("player", "name", my_name))
	names = {1: my_name}
	cells = {1: _free_spawn()}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(func():
		cells.clear()
		names.clear()
		_request_spawn.rpc_id(1)
		_set_name.rpc_id(1, my_name))
	multiplayer.peer_disconnected.connect(func(_id): _reset("Opponent left"))
	multiplayer.server_disconnected.connect(func(): _reset("Host left"))
	multiplayer.connection_failed.connect(func(): _reset("Couldn't connect"))


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 1) != OK:
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


func color_of(id: int) -> String:
	return "w" if id == 1 else "b"


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
	if not multiplayer.is_server() or not proposal.is_empty() or not _hub().GAMES.has(game):
		return
	var players := [1] + Array(multiplayer.get_peers())
	var s := []
	for i in _hub().GAMES[game].seats.size():
		s.append(players[i % players.size()])
	_publish({"game": game, "players": players, "seats": s, "votes": {}})


@rpc("any_peer", "call_local", "reliable")
func set_seat(seat: int, id: int) -> void:
	if not multiplayer.is_server() or proposal.is_empty() or id not in proposal.players \
			or seat < 0 or seat >= proposal.seats.size():
		return
	var s: Array = proposal.seats
	var other := s.find(id)
	if other != -1:
		s[other] = s[seat]  # that player swaps into our old seat
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
		_start.rpc(proposal.seats, _hub().GAMES[proposal.game].scene)
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
func _start(s: Array, scene: String) -> void:
	seats = s
	proposal = {}
	proposal_changed.emit()
	goto(scene)


## Call as Net.goto.rpc(path) so both players switch together.
@rpc("any_peer", "call_local", "reliable")
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
	# Untrusted: one king step, no walls. Occupancy isn't checked so both sides stay in agreement on races.
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
	_sync.rpc(cells)


@rpc("authority", "reliable")
func _sync(c: Dictionary) -> void:
	cells = c


func _on_peer_connected(_id: int) -> void:
	status = "Connected"
	if multiplayer.is_server():
		_publish({})  # player list changed, drop any open proposal
		goto.rpc("res://hub.tscn")  # pull the host back if they wandered into a game alone


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
	proposal = {}
	seats = [1, 1]
	names = {1: my_name}
	proposal_changed.emit()
	status = msg
	get_tree().change_scene_to_file("res://hub.tscn")
