extends Node
## Autoload "Net": ENet connection, synced scene changes, and hub king positions.
## Host is white, client is black.

const PORT := 7777
const SCENES := ["res://hub.tscn", "res://chess.tscn"]

var status := "Offline"
var cells := {}  # peer id -> Vector2i, every king in the hub


func _ready() -> void:
	cells = {1: _free_spawn()}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(func():
		cells.clear()
		_request_spawn.rpc_id(1))
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


func my_color() -> String:
	return color_of(multiplayer.get_unique_id())


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
	status = msg
	get_tree().change_scene_to_file("res://hub.tscn")
