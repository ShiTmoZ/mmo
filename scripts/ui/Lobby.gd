## scripts/ui/Lobby.gd
## Lobby controller: Solo practice, join online server, host local, or launch arena.
extends Control

const DEFAULT_SERVER_IP: String = "206.1.97.56"

@onready var _solo_btn: Button        = $VBoxContainer/SoloButton
@onready var _host_btn: Button        = $VBoxContainer/HostButton
@onready var _join_btn: Button        = $VBoxContainer/JoinButton
@onready var _start_btn: Button       = $VBoxContainer/StartButton
@onready var _address_field: LineEdit  = $VBoxContainer/AddressField
@onready var _status_label: Label     = $VBoxContainer/StatusLabel

func _ready() -> void:
	_solo_btn.pressed.connect(_on_solo_pressed)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_start_btn.pressed.connect(_on_start_pressed)
	_status_label.text = "Click [ENTER ARENA] to play solo right now, or [JOIN ONLINE SERVER] to play with friends."

	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_count_changed.connect(_on_player_count_changed)
	NetworkManager.arena_ready.connect(_on_arena_ready)

func _on_solo_pressed() -> void:
	_status_label.text = "Entering Solo Practice Arena..."
	_disable_all_buttons()
	NetworkManager.start_solo_arena()

func _on_host_pressed() -> void:
	_disable_all_buttons()
	_status_label.text = "Starting local server on port 7777..."
	NetworkManager.create_server()

func _on_join_pressed() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	_disable_all_buttons()
	_status_label.text = "Connecting to %s..." % address
	NetworkManager.join_server(address)

func _on_start_pressed() -> void:
	_start_btn.disabled = true
	if not multiplayer.has_multiplayer_peer():
		# Offline fallback: start solo arena directly!
		_status_label.text = "Entering Solo Arena..."
		NetworkManager.start_solo_arena()
	elif multiplayer.is_server():
		_status_label.text = "Starting arena for all players..."
		NetworkManager.request_start_arena()
	else:
		_status_label.text = "Requesting host to launch arena..."
		NetworkManager.request_client_start_arena.rpc_id(1)

func _disable_all_buttons() -> void:
	_solo_btn.disabled = true
	_host_btn.disabled = true
	_join_btn.disabled = true
	_address_field.editable = false

func _on_server_created() -> void:
	_start_btn.disabled = false
	_update_host_status(NetworkManager.get_player_count())

func _on_joined_server() -> void:
	_start_btn.disabled = false
	_status_label.text = "Connected to Server!\nClick [START MULTIPLAYER ARENA] when ready."

func _on_connection_failed() -> void:
	_solo_btn.disabled = false
	_host_btn.disabled = false
	_join_btn.disabled = false
	_address_field.editable = true
	_status_label.text = "Connection failed. Check address or try Solo Practice."

func _on_player_count_changed(count: int) -> void:
	_start_btn.disabled = false
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_update_host_status(count)
	else:
		_status_label.text = "Connected to Server!\nPlayers in lobby: %d / %d\nClick [START MULTIPLAYER ARENA] to begin!" % [
			count, GameData.MAX_PLAYERS
		]

func _update_host_status(count: int) -> void:
	_start_btn.disabled = false
	if count >= 2:
		_status_label.text = "Players connected: %d / %d\n[READY] Click START MULTIPLAYER ARENA to enter battle!" % [
			count, GameData.MAX_PLAYERS
		]
	else:
		_status_label.text = "Server running on port 7777.\nWaiting for players... (%d / %d)\n(You can also click START to play now)" % [
			count, GameData.MAX_PLAYERS
		]

func _on_arena_ready() -> void:
	queue_free()
