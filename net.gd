extends Node
## Autoload "Net": ENet connection (host + up to 3 guests), game proposals, synced scene changes,
## hub king positions, player names and colors. The host owns shared state and publishes it.

const PORT := 7777
const MAX_PLAYERS := 4
const SCENES := ["res://hub.tscn", "res://chess.tscn", "res://babychess.tscn", "res://superchess.tscn",
	"res://shogi.tscn", "res://minishogi.tscn", "res://quoridor.tscn", "res://crazyhouse.tscn",
	"res://cribbage.tscn", "res://fourchess.tscn", "res://holdem.tscn"]
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

# Bots sit in seats with negative ids: -level. The host runs them (see may_act, think).
const BOTS := {-1: "Bot (Easy)", -2: "Bot (Medium)"}
const BOT_DELAY := 0.5  # seconds before a bot's move lands, so it's visible

signal proposal_changed

var status := "Offline"
var cells := {}  # peer id -> Vector2i, every king in the hub
var colors := {}  # peer id -> PLAYER_COLORS index
# Game being voted on, or {} if none. Host-owned:
# {"game": letter, "players": [ids], "seats": [id per seat], "votes": {id: true}}
var proposal := {}
var seats: Array = [1, 1]  # who plays each army of the running game (offline: you play every army)
var game_mode := ""  # id of the mode picked in the vote, e.g. Superchess "2p" / "teams" / "ffa"
var game_seed := 0  # random number picked by the host for each game, the same on every peer (Fischer Random start)
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
	if id < 0:
		return BOTS[id]
	return names.get(id, "Host" if id == 1 else "Guest")


## Offline with only bots playing: you're just watching, so you may leave before the game ends.
func watching_bots() -> bool:
	return not online() and seats.all(func(id): return id < 0)


## May sender act for this seat? Its own player, or the host on behalf of a bot.
func may_act(seat_id: int, sender: int) -> bool:
	return sender == seat_id or (seat_id < 0 and sender == 1)


## Run work() on a worker thread after BOT_DELAY, then done(result) on the main thread.
## done is skipped if owner (the game scene) was freed meanwhile: the game ended while the bot thought.
## (A lambda's Callable stays "valid" after its object is freed, so owner is checked instead.)
func think(owner: Node, work: Callable, done: Callable) -> void:
	await get_tree().create_timer(BOT_DELAY).timeout
	var box := []  # lambdas capture locals by value; an Array is shared
	var task := WorkerThreadPool.add_task(func(): box.append(work.call()))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if is_instance_valid(owner) and owner.is_inside_tree():
		done.call(box[0])


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
	var modes := modes_of(game)
	var mode := 0  # the mode meant for this many players, else the first
	for i in modes.size():
		if modes[i].get("players", 0) == clampi(players.size(), 2, 4):
			mode = i
			break
	_publish({"game": game, "mode": mode, "players": players, "seats": _default_seats(modes[mode], players), "votes": {}})


## A game's modes. Games without a "modes" list have one, built from their seats and teams.
func modes_of(game: String) -> Array:
	var g: Dictionary = _hub().GAMES[game]
	return g.get("modes", [{"id": "", "name": "", "seats": g.get("seats", []), "teams": g.get("teams", []),
		"armies": range(g.get("seats", []).size())}])


func proposal_mode() -> Dictionary:
	return modes_of(proposal.game)[proposal.mode]


@rpc("any_peer", "call_local", "reliable")
func set_mode(mode: int) -> void:
	if not multiplayer.is_server() or proposal.is_empty() or multiplayer.get_remote_sender_id() not in proposal.players \
			or mode < 0 or mode >= modes_of(proposal.game).size():
		return
	proposal.mode = mode
	proposal.seats = _default_seats(proposal_mode(), proposal.players)
	proposal.votes = {}  # everyone re-confirms
	_publish(proposal)


## Seat players one by one, taking each team's seats in turn (team A seat 1, team B seat 1, team A seat 2...),
## so a 3 player game gives one person to each seat. Seats left over go to a player already on that team
## (2 players in 4 player teams: each runs a whole team), or round-robin if the team has nobody.
func _default_seats(mode: Dictionary, players: Array) -> Array:
	var teams: Array = mode.teams
	var order := []
	for j in teams.map(func(t): return t.size()).max():
		for t in teams:
			if j < t.size():
				order.append(t[j])
	var s := []
	s.resize(mode.seats.size())
	for k in mini(players.size(), order.size()):
		s[order[k]] = players[k]
	for t in teams.size():
		var first = s[teams[t][0]]
		for seat in teams[t]:
			if s[seat] == null:
				s[seat] = first if first != null else players[t % players.size()]
	return s


@rpc("any_peer", "call_local", "reliable")
func set_seat(seat: int, id: int) -> void:
	if not multiplayer.is_server() or proposal.is_empty() or not (id in proposal.players or BOTS.has(id)) \
			or seat < 0 or seat >= proposal.seats.size() or (seat == 0 and id < 0 and online()):
		return  # online, the first seat must be a person: no all-bot games over the network
	var s: Array = proposal.seats
	var other := s.find(id)
	# One seat per team (chess): picking a player seated elsewhere swaps them. Team games with
	# several seats per team let one player hold more than one seat, so just assign. Bots can fill any number of seats.
	if id > 0 and other != -1 and proposal_mode().teams.all(func(t): return t.size() == 1):
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
		var mode := proposal_mode()
		var armies: Array = mode.armies.map(func(seat): return proposal.seats[seat])  # seat ids -> per army
		_start.rpc(armies, proposal.players, _hub().GAMES[proposal.game].scene, mode.id, randi())
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
func _start(s: Array, players: Array, scene: String, mode_id: String, seed: int) -> void:
	game_seed = seed
	seats = s
	game_mode = mode_id
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
