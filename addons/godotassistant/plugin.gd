@tool
extends Control

# ========================================
# EXPORTS — Assign in Inspector
# ========================================

@export_group("API")
@export var api_key_input: LineEdit
@export var api_key_save_button: Button

@export_group("GdScript Tab")
@export var gdscript_output: TextEdit
@export var gdscript_output_copy: Button
@export var gdscript_output_clear: Button
@export var gdscript_output_save: Button
@export var gdscript_output_saveas: Button
@export var gdscript_input: TextEdit
@export var gdscript_input_open: Button
@export var gdscript_input_copy: Button
@export var gdscript_input_clear: Button
@export var gdscript_input_run: Button

@export_group("SceneGenerator Tab")
@export var scene_output: TextEdit
@export var scene_output_copy: Button
@export var scene_output_clear: Button
@export var scene_output_save: Button
@export var scene_output_saveas: Button
@export var scene_input: TextEdit
@export var scene_input_open: Button
@export var scene_input_copy: Button
@export var scene_input_clear: Button
@export var scene_input_run: Button

@export_group("Chat Tab")
@export var chat_output: TextEdit
@export var chat_input: TextEdit
@export var chat_input_open: Button
@export var chat_input_copy: Button
@export var chat_input_clear: Button
@export var chat_input_run: Button

# ========================================
# CONSTANTS
# ========================================

const GROQ_MODEL   = "llama-3.3-70b-versatile"
const GROQ_URL     = "https://api.groq.com/openai/v1/chat/completions"
const SETTINGS_KEY = "godot_assistant/groq_api_key"

const SYSTEM_GDSCRIPT = """You are a Godot 4 GDScript expert.
Your response must be a complete, valid, runnable .gd file and nothing else.
No explanations. No markdown. No backticks. No code blocks. No extra text before or after.
Start directly with extends or class_name. End with the last line of code.
Do NOT add @tool at the top unless the user explicitly asks for a tool script or editor plugin.
If given an existing script, modify or extend it as instructed and return the full updated script."""

const SYSTEM_TSCN = """You are a Godot 4 scene file expert.
Your response must be a complete, valid .tscn file and nothing else.
No explanations. No markdown. No backticks. No code blocks. No extra text before or after.

=== REAL EXAMPLE — study this format carefully and follow it exactly ===

[gd_scene format=3 uid="uid://3lafummasqcd"]

[node name="Control" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBoxContainer" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Label" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Hello World"
horizontal_alignment = 1

[node name="HBoxContainer" type="HBoxContainer" parent="VBoxContainer"]
layout_mode = 2

[node name="Button" type="Button" parent="VBoxContainer/HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3
text = "Click Me"

[node name="LineEdit" type="LineEdit" parent="VBoxContainer/HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3
placeholder_text = "Type here..."

[node name="TextEdit" type="TextEdit" parent="VBoxContainer"]
custom_minimum_size = Vector2(0, 300)
layout_mode = 2
size_flags_vertical = 3

=== END EXAMPLE ===

STRICT RULES (never break these):
- uid must use format uid://xxxxxxxxxxxx - alphanumeric only, NO dashes, NO UUID format
- Only include load_steps if there are ext_resource or sub_resource entries. Count them exactly.
- Root node has NO parent= field.
- Direct children of root use parent="."
- Deeper nodes use the full path e.g. parent="VBoxContainer/HBoxContainer"
- NEVER use parent="$NodeName" - the $ prefix is invalid in .tscn files
- layout_mode = 2 for children inside containers (VBox, HBox, Tab etc.)
- layout_mode = 1 for a container that fills its parent with anchors
- layout_mode = 3 for the root Control node
- Do NOT add script references. No ExtResource for .gd files. No script = on any node.
- Only use built-in Godot 4 node types: Node, Node2D, Node3D, Control, Label, Button, LineEdit, TextEdit, VBoxContainer, HBoxContainer, TabContainer, Panel, Sprite2D, etc.
- Only use [sub_resource] for inline meshes, shapes, or materials - nothing else.
- NEVER use name = "..." as a property inside a node block. The node's name belongs in the [node name="..."] header only.
- If the user wants a specific node name, put it directly in the header: [node name="Kid" type="Label" parent="."] NOT as a property below it."""

const SYSTEM_CHAT = """You are a helpful Godot 4 game development assistant.
Help developers with GDScript, scene structure, game logic, and Godot editor features.
Be concise and practical. Use GDScript 4 syntax for any code."""

# ========================================
# STATE
# ========================================

var _api_key: String = ""
var _gdscript_open_path: String = ""
var _scene_open_path: String = ""
var _current_mode: String = ""
var _chat_history: Array = []
var _http_request: HTTPRequest

# ========================================
# LIFECYCLE
# ========================================

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	if ProjectSettings.has_setting(SETTINGS_KEY):
		_api_key = ProjectSettings.get_setting(SETTINGS_KEY)
		if api_key_input:
			api_key_input.text = _api_key

	_connect_signals()

func _reset_ui_state() -> void:
	_chat_history.clear()
	_gdscript_open_path = ""
	_scene_open_path    = ""

	if gdscript_output: gdscript_output.text = ""
	if gdscript_input:  gdscript_input.text  = ""
	if scene_output:    scene_output.text    = ""
	if scene_input:     scene_input.text     = ""
	if chat_output:     chat_output.text     = ""
	if chat_input:      chat_input.text      = ""

	if gdscript_input_run: gdscript_input_run.disabled = false
	if scene_input_run:    scene_input_run.disabled    = false
	if chat_input_run:     chat_input_run.disabled     = false

	print("[GodotAssistant] UI reset to fresh state")

# ========================================
# SIGNAL CONNECTIONS
# ========================================

func _connect_signals() -> void:
	if api_key_save_button:    api_key_save_button.pressed.connect(_on_save_api_key)

	if gdscript_input_run:     gdscript_input_run.pressed.connect(_on_gdscript_run)
	if gdscript_input_open:    gdscript_input_open.pressed.connect(_on_gdscript_open)
	if gdscript_input_copy:    gdscript_input_copy.pressed.connect(func(): _copy_text(gdscript_input))
	if gdscript_input_clear:   gdscript_input_clear.pressed.connect(func(): _clear_text(gdscript_input))
	if gdscript_output_copy:   gdscript_output_copy.pressed.connect(func(): _copy_text(gdscript_output))
	if gdscript_output_clear:  gdscript_output_clear.pressed.connect(func(): _clear_text(gdscript_output))
	if gdscript_output_save:   gdscript_output_save.pressed.connect(_on_gdscript_save)
	if gdscript_output_saveas: gdscript_output_saveas.pressed.connect(_on_gdscript_saveas)

	if scene_input_run:        scene_input_run.pressed.connect(_on_scene_run)
	if scene_input_open:       scene_input_open.pressed.connect(_on_scene_open)
	if scene_input_copy:       scene_input_copy.pressed.connect(func(): _copy_text(scene_input))
	if scene_input_clear:      scene_input_clear.pressed.connect(func(): _clear_text(scene_input))
	if scene_output_copy:      scene_output_copy.pressed.connect(func(): _copy_text(scene_output))
	if scene_output_clear:     scene_output_clear.pressed.connect(func(): _clear_text(scene_output))
	if scene_output_save:      scene_output_save.pressed.connect(_on_scene_save)
	if scene_output_saveas:    scene_output_saveas.pressed.connect(_on_scene_saveas)

	if chat_input_run:         chat_input_run.pressed.connect(_on_chat_run)
	if chat_input_open:        chat_input_open.pressed.connect(_on_chat_open)
	if chat_input_copy:        chat_input_copy.pressed.connect(func(): _copy_text(chat_input))
	if chat_input_clear:       chat_input_clear.pressed.connect(func(): _clear_text(chat_input))

# ========================================
# API KEY
# ========================================

func _on_save_api_key() -> void:
	if not api_key_input: return
	_api_key = api_key_input.text.strip_edges()
	ProjectSettings.set_setting(SETTINGS_KEY, _api_key)
	ProjectSettings.save()
	print("[GodotAssistant] Groq API key saved. Length: %d" % _api_key.length())

# ========================================
# GDSCRIPT TAB
# ========================================

func _on_gdscript_open() -> void:
	_open_file_dialog(["*.gd ; GDScript Files", "*.tscn ; Scene Files"], func(path: String):
		_gdscript_open_path = path
		gdscript_input.text = FileAccess.get_file_as_string(path)
	)

func _on_gdscript_run() -> void:
	if not _validate_credentials(): return
	var prompt = gdscript_input.text.strip_edges()
	if prompt.is_empty():
		_show_error("Prompt is empty.")
		return
	gdscript_output.text = "Generating..."
	gdscript_input_run.disabled = true
	_send_request(SYSTEM_GDSCRIPT, prompt, "gdscript")

func _on_gdscript_save() -> void:
	if gdscript_output.text.is_empty():
		_show_error("Nothing to save.")
		return
	if _gdscript_open_path.is_empty():
		_on_gdscript_saveas()
		return
	_write_file(_gdscript_open_path, gdscript_output.text)

func _on_gdscript_saveas() -> void:
	if gdscript_output.text.is_empty():
		_show_error("Nothing to save.")
		return
	_save_file_dialog("*.gd ; GDScript Files", func(path: String):
		if not path.ends_with(".gd"):
			path += ".gd"
		_gdscript_open_path = path
		_write_file(path, gdscript_output.text)
	)

# ========================================
# SCENE TAB
# ========================================

func _on_scene_open() -> void:
	_open_file_dialog(["*.tscn ; Scene Files"], func(path: String):
		_scene_open_path = path
		scene_input.text = FileAccess.get_file_as_string(path)
	)

func _on_scene_run() -> void:
	if not _validate_credentials(): return
	var prompt = scene_input.text.strip_edges()
	if prompt.is_empty():
		_show_error("Prompt is empty.")
		return
	scene_output.text = "Generating..."
	scene_input_run.disabled = true
	_send_request(SYSTEM_TSCN, prompt, "scene")

func _on_scene_save() -> void:
	if scene_output.text.is_empty():
		_show_error("Nothing to save.")
		return
	if _scene_open_path.is_empty():
		_on_scene_saveas()
		return
	_write_file(_scene_open_path, scene_output.text)

func _on_scene_saveas() -> void:
	if scene_output.text.is_empty():
		_show_error("Nothing to save.")
		return
	_save_file_dialog("*.tscn ; Scene Files", func(path: String):
		if not path.ends_with(".tscn"):
			path += ".tscn"
		_scene_open_path = path
		_write_file(path, scene_output.text)
	)

# ========================================
# CHAT TAB
# ========================================

func _on_chat_open() -> void:
	_open_file_dialog(["*.gd ; GDScript Files", "*.tscn ; Scene Files"], func(path: String):
		var file_content = FileAccess.get_file_as_string(path)
		chat_input.text = "[File: %s]\n%s\n\n%s" % [path.get_file(), file_content, chat_input.text]
	)

func _on_chat_run() -> void:
	if not _validate_credentials(): return
	var prompt = chat_input.text.strip_edges()
	if prompt.is_empty():
		_show_error("Prompt is empty.")
		return
	_chat_history.append({"role": "user", "content": prompt})
	chat_output.text += "\n\nYou:\n%s\n\nThinking..." % prompt
	chat_input_run.disabled = true
	_send_request(SYSTEM_CHAT, prompt, "chat")

# ========================================
# GROQ API REQUEST
# ========================================

func _send_request(system_prompt: String, user_prompt: String, mode: String) -> void:
	_current_mode = mode

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	]

	var messages: Array = [{"role": "system", "content": system_prompt}]

	if mode == "chat" and _chat_history.size() > 1:
		for i in range(_chat_history.size() - 1):
			messages.append(_chat_history[i])

	messages.append({"role": "user", "content": user_prompt})

	var body = {
		"model": GROQ_MODEL,
		"messages": messages,
		"max_tokens": 4096,
		"temperature": 0.2
	}

	print("[GodotAssistant] Sending to Groq | mode: %s" % mode)
	var error = _http_request.request(GROQ_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_on_request_failed("HTTP request error: %s" % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if gdscript_input_run: gdscript_input_run.disabled = false
	if scene_input_run:    scene_input_run.disabled    = false
	if chat_input_run:     chat_input_run.disabled     = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_on_request_failed("HTTP transport error: %s" % result)
		return

	var raw = body.get_string_from_utf8()

	if response_code != 200:
		push_error("[GodotAssistant] Groq error: " + raw)
		match response_code:
			401: _on_request_failed("Invalid API key - get yours free at console.groq.com")
			429: _on_request_failed("Rate limit - wait a moment and try again")
			_:   _on_request_failed("API error %d: %s" % [response_code, raw])
		return

	var json = JSON.new()
	if json.parse(raw) != OK:
		_on_request_failed("Failed to parse API response.")
		return

	var choices = json.data.get("choices", [])
	if choices.is_empty():
		_on_request_failed("No choices in Groq response.")
		return

	var content: String = choices[0].get("message", {}).get("content", "").strip_edges()
	if content.is_empty():
		_on_request_failed("Empty response from Groq.")
		return

	match _current_mode:
		"gdscript":
			content = _strip_code_fences(content)
			if not (content.begins_with("extends") or content.begins_with("class_name") or content.begins_with("@tool")):
				content = _extract_code_block(content)
				if content.is_empty():
					_on_request_failed("AI returned invalid GDScript. Try rephrasing your prompt.")
					return
			gdscript_output.text = content
		"scene":
			content = _strip_code_fences(content)
			content = _sanitize_tscn(content)
			if not content.begins_with("[gd_scene"):
				_on_request_failed("AI returned invalid .tscn. Try rephrasing your prompt.")
				return
			scene_output.text = content
		"chat":
			_chat_history.append({"role": "assistant", "content": content})
			var out = chat_output.text.trim_suffix("Thinking...")
			chat_output.text = out + "\nAssistant:\n%s" % content
			chat_input.text = ""

func _extract_code_block(text: String) -> String:
	var lines = text.split("\n")
	var in_code_block = false
	var code_lines = []
	for line in lines:
		if line.strip_edges().begins_with("```"):
			in_code_block = !in_code_block
			continue
		if in_code_block:
			code_lines.append(line)
	if code_lines.size() > 0:
		return "\n".join(code_lines).strip_edges()
	return ""

func _on_request_failed(message: String) -> void:
	push_error("[GodotAssistant] %s" % message)
	if gdscript_input_run: gdscript_input_run.disabled = false
	if scene_input_run:    scene_input_run.disabled    = false
	if chat_input_run:     chat_input_run.disabled     = false
	match _current_mode:
		"gdscript": gdscript_output.text = "Error: %s" % message
		"scene":    scene_output.text    = "Error: %s" % message
		"chat":     chat_output.text    += "\nError: %s" % message

# ========================================
# SANITIZERS
# ========================================

func _strip_code_fences(text: String) -> String:
	var lines = text.split("\n")
	var result: PackedStringArray = []
	var in_code_block = false
	for line in lines:
		var stripped = line.strip_edges()
		if stripped.begins_with("```"):
			in_code_block = !in_code_block
			continue
		if not in_code_block and stripped.begins_with("`") and stripped.ends_with("`"):
			continue
		result.append(line)
	return "\n".join(result).strip_edges()

func _sanitize_tscn(tscn: String) -> String:
	var lines = tscn.split("\n")
	var cleaned: PackedStringArray = []
	for line in lines:
		var s = line.strip_edges()
		var skip = false
		if s.begins_with("[ext_resource") and ".gd" in s:
			skip = true
		if s.begins_with("script =") and ("ExtResource" in s or ".gd" in s):
			skip = true
		# Remove invalid name = "..." property lines (name belongs in node header only)
		if s.begins_with("name = "):
			skip = true
		if not skip:
			var fixed = line
			if fixed.contains("uid=\"") and not fixed.contains("uid=\"uid://"):
				var uid_start = fixed.find("uid=\"") + 5
				var uid_end   = fixed.find("\"", uid_start)
				if uid_end > uid_start:
					var old_uid = fixed.substr(uid_start, uid_end - uid_start)
					var new_uid = "uid://" + old_uid.replace("-", "").left(12)
					fixed = fixed.substr(0, uid_start - 5) + "uid=\"" + new_uid + "\"" + fixed.substr(uid_end + 1)
			if fixed.contains("parent=\"$"):
				fixed = fixed.replace("parent=\"$", "parent=\"")
			if fixed.contains("load_steps=0"):
				fixed = fixed.replace(" load_steps=0", "")
			cleaned.append(fixed)
	return "\n".join(cleaned).strip_edges()

# ========================================
# FILE HELPERS
# ========================================

func _open_file_dialog(filters: Array, callback: Callable) -> void:
	var dialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	for f in filters:
		dialog.add_filter(f)
	dialog.file_selected.connect(callback)
	dialog.canceled.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _save_file_dialog(filter: String, callback: Callable) -> void:
	var dialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter(filter)
	dialog.file_selected.connect(callback)
	dialog.canceled.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _write_file(path: String, content: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		EditorInterface.get_resource_filesystem().scan()
		print("[GodotAssistant] Saved: %s" % path)
	else:
		_show_error("Failed to write file: %s" % path)

func _copy_text(target: TextEdit) -> void:
	if target and not target.text.is_empty():
		DisplayServer.clipboard_set(target.text)

func _clear_text(target: TextEdit) -> void:
	if target:
		target.text = ""

# ========================================
# VALIDATION
# ========================================

func _validate_credentials() -> bool:
	if _api_key.is_empty():
		_show_error("Please enter your Groq API Key and click Save.")
		return false
	return true

func _show_error(message: String) -> void:
	push_error("[GodotAssistant] %s" % message)
	var dialog = AcceptDialog.new()
	dialog.title = "GodotAssistant"
	dialog.dialog_text = message
	dialog.confirmed.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
