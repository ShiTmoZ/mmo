extends Control

@onready var ip_input: LineEdit = $Panel/VBoxContainer/IpInput
@onready var port_input: LineEdit = $Panel/VBoxContainer/PortInput
@onready var user_input: LineEdit = $Panel/VBoxContainer/UserInput
@onready var pass_input: LineEdit = $Panel/VBoxContainer/PassInput
@onready var connect_btn: Button = $Panel/VBoxContainer/ConnectButton
@onready var host_btn: Button = $Panel/VBoxContainer/HostButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var lobby_panel: Panel = $Panel

func _ready() -> void:
	connect_btn.pressed.connect(_on_connect_pressed)
	host_btn.pressed.connect(_on_host_pressed)

	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_failed)

func _on_connect_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	var port = int(port_input.text.strip_edges())
	var user = user_input.text.strip_edges()
	var passw = pass_input.text.strip_edges()

	if user.is_empty() or passw.is_empty():
		status_label.text = "Username and password required."
		return

	status_label.text = "Connecting..."
	NetworkManager.connect_to_server(ip, port, user, passw)

func _on_host_pressed() -> void:
	var port = int(port_input.text.strip_edges())
	var err = NetworkManager.start_dedicated_server(port)
	if err == OK:
		status_label.text = "Hosting server on port %d" % port
	else:
		status_label.text = "Failed to host: %s" % err

func _on_connected() -> void:
	status_label.text = "Connected! Entering realm..."
	lobby_panel.visible = false

func _on_failed() -> void:
	status_label.text = "Connection / Auth failed."
