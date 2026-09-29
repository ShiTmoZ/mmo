## scripts/ui/Lobby.gd
## Simple lobby screen: host or join, then wait for NetworkManager to signal arena ready.
class_name Lobby
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
	NetworkManager.arena_ready.connect(_on_arena_ready)

func _on_host_pressed() -> void:
	_status_label.text = "Starting server..."
	NetworkManager.create_server()

func _on_join_pressed() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	_status_label.text = "Connecting to %s..." % address
	NetworkManager.join_server(address)

func _on_start_pressed() -> void:
	NetworkManager.request_start_arena()

func _on_server_created() -> void:
	_status_label.text = "Server running. Waiting for players...\nPlayers: %d" % NetworkManager.get_player_count()
	_start_btn.disabled = false

func _on_joined_server() -> void:
	_status_label.text = "Connected! Waiting for host to start."
	_start_btn.disabled = true

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed. Check the address and try again."

func _on_arena_ready() -> void:
	# Hide lobby UI — arena scene is now active
	hide()
