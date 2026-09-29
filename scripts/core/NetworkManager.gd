extends Node

signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal player_authenticated(peer_id: int, username: String)
signal player_left(peer_id: int)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var is_server: bool = false
var registered_users: Dictionary = {}  # username -> sha256_password (in-memory auth table)
var active_sessions: Dictionary = {}   # peer_id -> username

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Check if launched in headless server mode
	var args = OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless" or "--server" in args:
		start_dedicated_server(DEFAULT_PORT)

func start_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	var err = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		print("[NetworkManager] Failed to start dedicated server on port %d: %s" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("[NetworkManager] Headless Dedicated Server running on UDP port %d" % port)
	return OK

func connect_to_server(ip: String, port: int, username: String, password_plain: String) -> Error:
	var err = peer.create_client(ip, port)
	if err != OK:
		print("[NetworkManager] Failed to create client connection: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	
	# Cache credentials to send upon handshake
	_pending_username = username
	_pending_password_hash = password_plain.sha256_text()
	print("[NetworkManager] Connecting to %s:%d as %s..." % [ip, port, username])
	return OK

var _pending_username: String = ""
var _pending_password_hash: String = ""

func _on_connected_to_server() -> void:
	print("[NetworkManager] Handshake established. Sending credentials...")
	rpc_id(1, "request_login", _pending_username, _pending_password_hash)

func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed.")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected.")
	server_disconnected.emit()

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % id)
	if is_server:
		active_sessions.erase(id)
		player_left.emit(id)

# Authentication RPCs
@rpc("any_peer", "call_remote")
func request_login(user: String, pass_hash: String) -> void:
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Simple auth: register if first time, verify if user exists
	if not registered_users.has(user):
		registered_users[user] = pass_hash
		print("[NetworkManager] New user registered: %s" % user)
	elif registered_users[user] != pass_hash:
		rpc_id(sender_id, "login_response", false, "Invalid password.")
		return

	active_sessions[sender_id] = user
	rpc_id(sender_id, "login_response", true, "Welcome to Ashen Sanctum.")
	player_authenticated.emit(sender_id, user)
	print("[NetworkManager] User %s authenticated (Peer ID: %d)" % [user, sender_id])

@rpc("authority", "call_remote")
func login_response(success: bool, message: String) -> void:
	if success:
		print("[NetworkManager] Login successful: %s" % message)
		connection_succeeded.emit()
	else:
		print("[NetworkManager] Login rejected: %s" % message)
		connection_failed.emit()
		multiplayer.multiplayer_peer = null
