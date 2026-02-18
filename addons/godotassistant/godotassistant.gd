@tool
extends EditorPlugin

var _window: Window
var _panel: Control

func _enter_tree() -> void:
	print("🚀 GodotAssistant - Initializing...")

	# Load panel scene
	var scene = load("res://addons/godotassistant/plugin.tscn")
	_panel = scene.instantiate()

	# Wrap in a Window so it floats as a popup
	_window = Window.new()
	_window.title = "Godot Assistant"
	_window.size = Vector2i(1000, 700)
	_window.wrap_controls = true
	_window.exclusive = false
	_window.visible = false
	_window.close_requested.connect(_on_close_requested)
	_window.add_child(_panel)

	EditorInterface.get_base_control().add_child(_window)

	# Add a menu item under the top bar to open the window
	add_tool_menu_item("Godot Assistant", _open_window)

func _exit_tree() -> void:
	remove_tool_menu_item("Godot Assistant")
	if _window:
		_window.queue_free()
	print("🔌 GodotAssistant - Shut down.")

func _open_window() -> void:
	if _window:
		_panel._reset_ui_state()
		_window.popup_centered()

func _on_close_requested() -> void:
	_window.visible = false
