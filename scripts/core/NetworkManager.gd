## Autoload singleton: scripts/core/NetworkManager.gd
## Manages ENet peer lifecycle, player spawning via MultiplayerSpawner,
## and lobby-to-arena transitions.
## Register as AutoLoad name "NetworkManager" in project settings.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal server_created()
signal joined_server()
signal connection_failed()
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal player_count_changed(count: int)
signal arena_ready()

# ---------------------------------------------------------------------------
# Exports / configuration
# ---------------------------------------------------------------------------
@export var player_scene: PackedScene
@export var arena_scene_path: String = "res://scenes/arena.tscn"

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _peer: ENetMultiplayerPeer       = ENetMultiplayerPeer.new()
var _player_data: Dictionary         = {}  # peer_id -> {team, display_name}
var _arena_node: Node                = null
var _spawner: MultiplayerSpawner     = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	if player_scene == null:
		player_scene = load("res://scenes/player.tscn") as PackedScene
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_args():
		call_deferred("start_dedicated_server")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func create_server() -> void:
	var err: int = _peer.create_server(GameData.NETWORK_PORT, GameData.MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to create server, error code %d" % err)
		return
	multiplayer.multiplayer_peer = _peer
	_register_player(1, "Host", GameData.Team.TEAM_1)
	server_created.emit()
	print("NetworkManager: Server started on port %d" % GameData.NETWORK_PORT)

func start_dedicated_server() -> void:
	var err: int = _peer.create_server(GameData.NETWORK_PORT, GameData.MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Dedicated server failed to start on port %d, error %d" % [GameData.NETWORK_PORT, err])
		return
	multiplayer.multiplayer_peer = _peer
	print("NetworkManager: Dedicated server running on UDP %d (Max: %d players)" % [GameData.NETWORK_PORT, GameData.MAX_PLAYERS])

func join_server(address: String) -> void:
	var err: int = _peer.create_client(address, GameData.NETWORK_PORT)
	if err != OK:
		push_error("NetworkManager: Failed to create client, error code %d" % err)
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = _peer
	print("NetworkManager: Connecting to %s:%d" % [address, GameData.NETWORK_PORT])

func disconnect_from_server() -> void:
	if _peer:
		_peer.close()
	_player_data.clear()
	_arena_node = null

func get_player_count() -> int:
	return _player_data.size()

func get_player_info(peer_id: int) -> Dictionary:
	return _player_data.get(peer_id, {})

func get_all_player_ids() -> Array:
	return _player_data.keys()

func start_solo_arena() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_player_data.clear()
	_player_data[1] = {
		"display_name": "Champion",
		"team": GameData.Team.TEAM_1,
	}
	_load_arena_solo()

func _load_arena_solo() -> void:
	if _arena_node != null:
		return
	var arena_resource: PackedScene = load(arena_scene_path) as PackedScene
	if arena_resource == null:
		push_error("NetworkManager: Cannot load arena scene at %s" % arena_scene_path)
		return
	_arena_node = arena_resource.instantiate()
	get_tree().root.add_child(_arena_node)
	get_tree().current_scene = _arena_node

	arena_ready.emit()

	# Spawn player 1
	var spawn_pos: Vector3 = GameData.SPAWN_TEAM_1
	_spawn_player_node(1, spawn_pos, GameData.Team.TEAM_1, "Champion")

	# Spawn training dummy 4m in front of player for immediate combat testing
	var dummy_pos: Vector3 = Vector3(-14.0, 1.0, 0.0)
	_spawn_training_dummy(dummy_pos, GameData.Team.TEAM_2)

func _spawn_training_dummy(spawn_pos: Vector3, dummy_team: int) -> void:
	if player_scene == null:
		player_scene = load("res://scenes/player.tscn") as PackedScene
	var dummy: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	dummy.name = "Training_Dummy"
	dummy.position = spawn_pos
	dummy.team = dummy_team
	dummy.display_name = "Training Dummy"
	dummy.set_meta("peer_id", 999)
	dummy.set_meta("team", dummy_team)
	dummy.set_meta("display_name", "Training Dummy")
	var players_container: Node = _arena_node.get_node_or_null("Players")
	if players_container == null:
		players_container = _arena_node
	players_container.add_child(dummy)
	# Notify local player to auto-lock the dummy
	var local_player: Node = players_container.get_node_or_null("Player_1")
	if local_player != null and local_player.has_method("_refresh_target_list"):
		local_player._refresh_target_list()
		if local_player.has_method("_auto_select_initial_target"):
			local_player._auto_select_initial_target()

func request_start_arena() -> void:
	if not multiplayer.is_server():
		return
	_load_arena.rpc()

@rpc("any_peer", "call_local", "reliable")
func request_client_start_arena() -> void:
	if not multiplayer.is_server():
		return
	print("NetworkManager: Start arena requested by remote peer %d" % multiplayer.get_remote_sender_id())
	request_start_arena()

func get_local_team() -> int:
	if not multiplayer.has_multiplayer_peer():
		return GameData.Team.TEAM_1
	var pid: int = multiplayer.get_unique_id()
	var info: Dictionary = _player_data.get(pid, {})
	return info.get("team", GameData.Team.NONE)

# ---------------------------------------------------------------------------
# Arena loading
# ---------------------------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func _load_arena() -> void:
	if _arena_node != null:
		return
	var arena_resource: PackedScene = load(arena_scene_path) as PackedScene
	if arena_resource == null:
		push_error("NetworkManager: Cannot load arena scene at %s" % arena_scene_path)
		return
	_arena_node = arena_resource.instantiate()
	get_tree().root.add_child(_arena_node)
	get_tree().current_scene = _arena_node

	_spawner = _arena_node.get_node_or_null("MultiplayerSpawner") as MultiplayerSpawner
	if _spawner == null:
		push_error("NetworkManager: Arena missing MultiplayerSpawner node")
		return

	arena_ready.emit()

	if multiplayer.is_server():
		_spawn_all_players()

# ---------------------------------------------------------------------------
# Player spawning (server-authoritative)
# ---------------------------------------------------------------------------
func _spawn_all_players() -> void:
	var ids: Array = _player_data.keys()
	var team_counters: Dictionary = {GameData.Team.TEAM_1: 0, GameData.Team.TEAM_2: 0}
	for pid: int in ids:
		var info: Dictionary = _player_data[pid]
		var team: int = info.get("team", GameData.Team.TEAM_1)
		var spawn_pos: Vector3 = _get_spawn_position(team, team_counters[team])
		team_counters[team] += 1
		_spawn_player_node(pid, spawn_pos, team, info.get("display_name", "Player_%d" % pid))

func _get_spawn_position(team: int, index: int) -> Vector3:
	var base: Vector3 = GameData.SPAWN_TEAM_1 if team == GameData.Team.TEAM_1 else GameData.SPAWN_TEAM_2
	return base + Vector3(0.0, 0.0, float(index) * 2.5)

func _spawn_player_node(peer_id: int, spawn_pos: Vector3, team: int, display_name: String) -> void:
	if player_scene == null:
		player_scene = load("res://scenes/player.tscn") as PackedScene
	var player: Node3D = player_scene.instantiate() as Node3D
	player.name = "Player_%d" % peer_id
	player.set_meta("peer_id",      peer_id)
	player.set_meta("team",         team)
	player.set_meta("display_name", display_name)
	player.position = spawn_pos
	if "team" in player:
		player.team = team
	if "display_name" in player:
		player.display_name = display_name
	var players_container: Node = _arena_node.get_node_or_null("Players")
	if players_container == null:
		players_container = _arena_node
	players_container.add_child(player, true)

	if multiplayer.has_multiplayer_peer():
		if player.has_method("set_multiplayer_authority"):
			player.set_multiplayer_authority(peer_id)
		_notify_player_spawned.rpc_id(peer_id, player.get_path(), peer_id, team)
	else:
		if player.has_method("init_as_local_player"):
			player.init_as_local_player(peer_id, team)

@rpc("authority", "call_local", "reliable")
func _notify_player_spawned(player_path: NodePath, peer_id: int, team: int) -> void:
	var player_node: Node = null
	for attempt in range(60):
		player_node = get_node_or_null(player_path)
		if player_node != null:
			break
		await get_tree().process_frame
	if player_node and player_node.has_method("init_as_local_player"):
		player_node.init_as_local_player(peer_id, team)

# ---------------------------------------------------------------------------
# Player registration & lobby sync
# ---------------------------------------------------------------------------
func _register_player(peer_id: int, display_name: String, team: int) -> void:
	_player_data[peer_id] = {
		"display_name": display_name,
		"team":         team,
	}
	player_joined.emit(peer_id)
	player_count_changed.emit(_player_data.size())
	print("NetworkManager: Player registered — id=%d team=%d name=%s" % [peer_id, team, display_name])

@rpc("any_peer", "reliable")
func register_player_rpc(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int   = multiplayer.get_remote_sender_id()
	var team: int = GameData.Team.TEAM_1
	var t1_count: int = 0
	var t2_count: int = 0
	for info: Dictionary in _player_data.values():
		if info.get("team") == GameData.Team.TEAM_1:
			t1_count += 1
		else:
			t2_count += 1
	if t2_count < t1_count:
		team = GameData.Team.TEAM_2
	_register_player(peer_id, display_name, team)
	_ack_registration.rpc_id(peer_id, peer_id, team)
	_sync_lobby_players.rpc(_player_data)
	if _arena_node != null:
		_load_arena.rpc_id(peer_id)
		var spawn_pos: Vector3 = _get_spawn_position(team, 0)
		_spawn_player_node(peer_id, spawn_pos, team, display_name)

@rpc("authority", "reliable")
func _ack_registration(peer_id: int, team: int) -> void:
	_player_data[peer_id] = {
		"display_name": "Challenger",
		"team":         team,
	}
	joined_server.emit()
	print("NetworkManager: Client acknowledged — id=%d team=%d" % [peer_id, team])

@rpc("authority", "reliable")
func _sync_lobby_players(synced_data: Dictionary) -> void:
	_player_data = synced_data
	player_count_changed.emit(_player_data.size())

# ---------------------------------------------------------------------------
# Connection callbacks
# ---------------------------------------------------------------------------
func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected id=%d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected id=%d" % id)
	_player_data.erase(id)
	player_left.emit(id)
	player_count_changed.emit(_player_data.size())
	if multiplayer.is_server():
		_sync_lobby_players.rpc(_player_data)
	if _arena_node != null:
		var node: Node = _arena_node.get_node_or_null("Players/Player_%d" % id)
		if node:
			node.queue_free()

func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	register_player_rpc.rpc("Challenger")

func _on_connection_failed() -> void:
	push_warning("NetworkManager: Connection failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	push_warning("NetworkManager: Server disconnected")
	_player_data.clear()
