## scripts/ui/Lobby.gd
## Lobby controller: host or join, display live player count, and launch arena.
extends Control

@onready var _host_btn: Button       = $VBoxContainer/HostButton
@onready var _join_btn: Button       = $VBoxContainer/JoinButton
@onready var _address_field: LineEdit = $VBoxContainer/AddressField
@onready var _status_label: Label    = $VBoxContainer/StatusLabel
@onready var _start_btn: Button      = $VBoxContainer/StartButton

func _ready() -> void:
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.disabled = true
	_status_label.text = "Enter server address or host a new game."

	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_count_changed.connect(_on_player_count_changed)
	NetworkManager.arena_ready.connect(_on_arena_ready)

func _on_host_pressed() -> void:
	_host_btn.disabled = true
	_join_btn.disabled = true
	_address_field.editable = false
	_status_label.text = "Starting server on port 7777..."
	NetworkManager.create_server()

func _on_join_pressed() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	_host_btn.disabled = true
	_join_btn.disabled = true
	_address_field.editable = false
	_status_label.text = "Connecting to %s..." % address
	NetworkManager.join_server(address)

func _on_start_pressed() -> void:
	_start_btn.disabled = true
	_status_label.text = "Starting arena for all players..."
	NetworkManager.request_start_arena()

func _on_server_created() -> void:
	_update_host_status(NetworkManager.get_player_count())

func _on_joined_server() -> void:
	_status_label.text = "Connected to host!\nWaiting for host to start arena..."
	_start_btn.disabled = true

func _on_connection_failed() -> void:
	_host_btn.disabled = false
	_join_btn.disabled = false
	_address_field.editable = true
	_status_label.text = "Connection failed. Check address and try again."

func _on_player_count_changed(count: int) -> void:
	if multiplayer.is_server():
		_update_host_status(count)
	else:
		_status_label.text = "Connected to host!\nPlayers in lobby: %d / %d\nWaiting for host to start..." % [
			count, GameData.MAX_PLAYERS
		]

func _update_host_status(count: int) -> void:
	_start_btn.disabled = false
	if count >= 2:
		_status_label.text = "Players connected: %d / %d\n[READY] Click START ARENA to enter battle!" % [
			count, GameData.MAX_PLAYERS
		]
	else:
		_status_label.text = "Server running on port 7777.\nWaiting for players... (%d / %d)\n(You can also click START ARENA for solo test)" % [
			count, GameData.MAX_PLAYERS
		]

func _on_arena_ready() -> void:
	queue_free()
