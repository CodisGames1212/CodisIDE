extends HBoxContainer

## AI assistant panel. Reads the active sketch, runs the offline
## [LocalCodeAnalyzer], and lets the user commit an automatically corrected
## version straight back into the editor with one button.

signal request_settings()
signal request_tab(index: int)

@onready var chat_log: VBoxContainer = $HSplitContainer/Chat/Response/VBoxContainer
@onready var scroll: ScrollContainer = $HSplitContainer/Chat/Response
@onready var ask: TextEdit = $HSplitContainer/Chat/AiAsk
@onready var access_panel: Panel = $HSplitContainer/AccessPanel
@onready var ai_recent: Control = $HSplitContainer/AccessPanel/AiRecent
@onready var model_list: Control = $HSplitContainer/AccessPanel/ModelList

var _manager: AIManager
var _sidebar: VBoxContainer
var _chat_column: VBoxContainer
var _recent_list: VBoxContainer
var _recent_scroll: ScrollContainer

# Header widgets.
var _model_label: Label
var _mode_button: OptionButton
var _stop_button: Button
var _autocommit_check: CheckBox

# Transcript persisted to <data>/Saves/AIChats/.
var _transcript: Array[Dictionary] = []
var _conversation_id: String = ""
var _thinking_bubble: Control = null


func _ready() -> void:
	_manager = AIManager.new()
	_manager.name = "AIManager"
	add_child(_manager)
	_manager.generation_started.connect(_on_generation_started)
	_manager.generation_finished.connect(_on_generation_finished)
	_manager.generation_failed.connect(_on_generation_failed)

	_sidebar = get_node_or_null("VBoxContainer")
	_chat_column = get_node_or_null("HSplitContainer/Chat")
	_connect_sidebar()
	_connect_ask()
	_build_recent_list()
	_build_header()
	_show_models(false)
	_new_conversation()
	_ensure_local_model()


## Makes sure the offline runtime has a usable model: if the configured Ollama
## model is not installed, the first installed one is adopted automatically so
## local generation works without opening Settings first.
func _ensure_local_model() -> void:
	if _manager == null or _manager.mode() != "offline":
		return
	_manager.list_local_models(func(names: PackedStringArray) -> void:
		if names.is_empty():
			return
		var configured := str(Ide.get_setting("local_model", ""))
		if not names.has(configured):
			Ide.set_setting("local_model", names[0])
			Ide.save_settings()
		_refresh_model_label())


func _connect_sidebar() -> void:
	if _sidebar == null:
		return
	_bind_button("AINewChat", _on_new_chat, "New chat")
	_bind_button("AISearch", _on_search, "Search / help")
	_bind_button("AIRecent", _on_recent, "Recent conversations")
	_bind_button("AIModels", _on_ai_models, "Manage models")
	_bind_button("Settings", func() -> void: request_settings.emit(), "IDE settings")


func _bind_button(node_name: String, callback: Callable, tip: String) -> void:
	var button := _sidebar.get_node_or_null(node_name) as Button
	if button == null:
		return
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	button.tooltip_text = tip


## Header strip: active model, autocommit toggle, offline/online switch, Stop.
func _build_header() -> void:
	if _chat_column == null:
		return
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_chat_column.add_child(bar)
	_chat_column.move_child(bar, 0)

	_model_label = Label.new()
	_model_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_label.add_theme_font_size_override("font_size", 12)
	bar.add_child(_model_label)

	_autocommit_check = CheckBox.new()
	_autocommit_check.text = "Autocommit"
	_autocommit_check.button_pressed = bool(Ide.get_setting("ai_autocommit", true))
	_autocommit_check.tooltip_text = "Apply generated code to the editor automatically"
	_autocommit_check.toggled.connect(func(on: bool) -> void: Ide.set_setting("ai_autocommit", on))
	bar.add_child(_autocommit_check)

	_mode_button = OptionButton.new()
	_mode_button.add_item("Offline", 0)
	_mode_button.add_item("Online", 1)
	_mode_button.select(1 if _manager.mode() == "online" else 0)
	_mode_button.tooltip_text = "Offline = local Ollama · Online = API key"
	_mode_button.item_selected.connect(_on_mode_selected)
	bar.add_child(_mode_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.disabled = true
	_stop_button.pressed.connect(func() -> void: _manager.stop())
	bar.add_child(_stop_button)


func _on_mode_selected(index: int) -> void:
	Ide.set_setting("ai_mode", "online" if index == 1 else "offline")
	Ide.save_settings()
	_refresh_model_label()


func _refresh_model_label() -> void:
	if _model_label == null:
		return
	var mode := "Offline" if _manager.mode() == "offline" else "Online"
	_model_label.text = "%s · running: %s" % [mode, _manager.active_label()]


func _connect_ask() -> void:
	if ask:
		ask.placeholder_text = "Message the model… (Enter to send, Shift+Enter for newline)"
		if not ask.gui_input.is_connected(_on_ask_input):
			ask.gui_input.connect(_on_ask_input)


func _on_ask_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_submit(ask.text)


# ---------------------------------------------------------------------------
# Sidebar actions
# ---------------------------------------------------------------------------

func _on_new_chat() -> void:
	_new_conversation()


func _new_conversation() -> void:
	_conversation_id = Time.get_datetime_string_from_system().replace(":", "-")
	_transcript.clear()
	if chat_log != null:
		for child in chat_log.get_children():
			child.queue_free()
	_greet()
	_refresh_model_label()


func _on_search() -> void:
	_add_message("Codis", "Ask me anything — I can explain code, write a sketch from a description, debug an error, or just chat. The **current sketch is always sent as context**.\n\nPut any code you want committed inside a ``` fenced block and it will be applied automatically.")


func _on_recent() -> void:
	var was_visible := _recent_scroll != null and _recent_scroll.visible
	if _recent_scroll != null:
		if was_visible:
			_recent_scroll.visible = false
		else:
			_populate_recent()
			_recent_scroll.visible = true
	_show_models(false)


func _on_ai_models() -> void:
	var was_visible := model_list != null and model_list.visible
	if _recent_scroll != null:
		_recent_scroll.visible = false
	_show_models(not was_visible)


func _show_models(show_list: bool) -> void:
	if model_list:
		model_list.visible = show_list
	if ai_recent:
		ai_recent.visible = false
	if access_panel:
		# Only take space in the layout while something is actually shown.
		access_panel.visible = show_list or (_recent_scroll != null and _recent_scroll.visible)


# ---------------------------------------------------------------------------
# Chat plumbing
# ---------------------------------------------------------------------------

func _greet() -> void:
	_add_message("Codis", "Hi! I'm **%s**, running %s. Ask me anything — I can write or fix your sketch and, with **Autocommit** on, apply the code straight to the editor." % [
		_manager.active_label(),
		"on this device" if _manager.mode() == "offline" else "through your API key",
	])


func _submit(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_add_message("You", clean)
	_transcript.append({"role": "user", "text": clean})
	if ask != null:
		ask.text = ""
	_save_conversation()

	# The offline analyzer stays available as an explicit tool.
	if clean.to_lower().strip_edges() == "/analyze":
		_run_analysis()
		return

	_thinking_bubble = _add_message("Codis", "_thinking…_")
	_manager.generate(clean, _system_prompt())


func _system_prompt() -> String:
	var code := Ide.get_active_code()
	var prompt := "You are Codis, a concise coding assistant embedded in an Arduino/GDScript IDE. " \
		+ "Answer any question the user asks, not only coding ones. " \
		+ "When you output a complete sketch or a full file replacement, wrap it in a single ``` fenced code block so it can be committed. Keep prose short."
	if not code.strip_edges().is_empty():
		prompt += "\n\nThe user's current sketch (%s):\n```\n%s\n```" % [_active_sketch_name(), code]
	return prompt


func _on_generation_started(label: String) -> void:
	if _stop_button != null:
		_stop_button.disabled = false
	if _model_label != null:
		_model_label.text = "Running %s…" % label


func _on_generation_finished(text: String) -> void:
	if _stop_button != null:
		_stop_button.disabled = true
	_clear_thinking()
	_refresh_model_label()

	var code := _extract_code(text)
	var actions: Array = []
	if not code.is_empty():
		actions.append({"label": "Commit code to editor", "callback": func() -> void: _commit_code(code)})
		actions.append({"label": "Preview changes", "callback": func() -> void: _preview_diff(Ide.get_active_code(), code)})

	_add_message("Codis", text, actions)
	_transcript.append({"role": "assistant", "text": text})
	_save_conversation()

	if not code.is_empty() and bool(Ide.get_setting("ai_autocommit", true)):
		_commit_code(code, true)


func _on_generation_failed(message: String) -> void:
	if _stop_button != null:
		_stop_button.disabled = true
	_clear_thinking()
	_refresh_model_label()
	_add_message("Codis", "⚠️ " + message)


func _clear_thinking() -> void:
	if _thinking_bubble != null and is_instance_valid(_thinking_bubble):
		_thinking_bubble.queue_free()
	_thinking_bubble = null


## Pulls the first ``` fenced block out of a model reply, if any.
func _extract_code(text: String) -> String:
	var start := text.find("```")
	if start < 0:
		return ""
	var after := text.find("\n", start)
	if after < 0:
		return ""
	var end := text.find("```", after)
	if end < 0:
		return ""
	return text.substr(after + 1, end - after - 1).strip_edges(false, true)


# ---------------------------------------------------------------------------
# Analysis (the core "AI reads and analyzes the code" feature)
# ---------------------------------------------------------------------------

func _run_analysis() -> void:
	var code := Ide.get_active_code()
	if code.strip_edges().is_empty():
		_add_message("Codis", "There's no code in the active editor yet. Open a sketch in the Code tab and try again.")
		return

	var report: Dictionary = LocalCodeAnalyzer.analyze(code, _manager.active_label())
	var issues: Array = report["issues"]
	var score: int = report["score"]

	var body := str(report["summary"]) + "  \nQuality score: **%d/100**." % score
	if issues.is_empty():
		body += "\n\nNo issues detected — nice work!"
	else:
		body += "\n\n"
		for issue in issues:
			body += "• `line %d` — %s\n" % [int(issue["line"]), str(issue["message"])]
			body += "   ↳ %s\n" % str(issue["suggestion"])

	var actions: Array = []
	if bool(report["has_changes"]):
		var fixed: String = str(report["fixed_code"])
		actions.append({
			"label": "Commit fixes to editor",
			"callback": func() -> void: _commit_code(fixed),
		})
		actions.append({
			"label": "Preview changes",
			"callback": func() -> void: _preview_diff(code, fixed),
		})

	_add_message("Codis", body, actions)
	_transcript.append({"role": "assistant", "text": body})


func _commit_code(new_code: String, automatic: bool = false) -> void:
	_clear_thinking()
	var editor := Ide.get_active_code_edit()
	if editor == null:
		_add_message("Codis", "No editor is open. Open or create a sketch first.")
		return
	# Apply as a single undoable edit and save if the file has a path.
	var edit_container := _find_code_editor_container()
	if edit_container and edit_container.has_method("apply_code"):
		edit_container.apply_code(new_code, editor)
	else:
		editor.text = new_code
	editor.grab_focus()
	if automatic:
		_add_message("Codis", "✅ Autocommitted the generated code to the editor. Use Ctrl+Z to undo.")
	else:
		_add_message("Codis", "✅ Committed the changes to the editor. Use Ctrl+Z to undo, or Save to write them to disk.")
	Ide.code_committed.emit(editor.get_meta("file_path", ""))
	Ide.status_message.emit("AI changes committed to editor")
	# Reveal the editor so the user sees the applied changes.
	request_tab.emit(0)


func _preview_diff(before: String, after: String) -> void:
	var before_lines := before.split("\n")
	var after_lines := after.split("\n")
	var body := "**Diff preview** (showing added/changed lines):\n\n"
	var max_lines: int = maxi(before_lines.size(), after_lines.size())
	var shown := 0
	for i in range(max_lines):
		var b: String = before_lines[i] if i < before_lines.size() else ""
		var a: String = after_lines[i] if i < after_lines.size() else ""
		if b != a:
			body += "+ line %d: `%s`\n" % [i + 1, a]
			shown += 1
		if shown >= 40:
			body += "…\n"
			break
	if shown == 0:
		body = "No line-level differences."
	_add_message("Codis", body)


# ---------------------------------------------------------------------------
# Chat rendering
# ---------------------------------------------------------------------------

func _add_message(sender: String, text: String, actions: Array = []) -> Control:
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bubble.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var head := Label.new()
	head.text = sender
	head.add_theme_font_size_override("font_size", 13)
	head.modulate = Color(0.6, 0.75, 0.95) if sender != "You" else Color(0.6, 0.9, 0.6)
	vbox.add_child(head)

	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.selection_enabled = true
	rich.text = text
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rich)

	for action in actions:
		var btn := Button.new()
		btn.text = str(action["label"])
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var cb: Callable = action["callback"]
		btn.pressed.connect(cb)
		vbox.add_child(btn)

	chat_log.add_child(bubble)
	if scroll != null:
		_scroll_to_bottom.call_deferred()
	return bubble


func _scroll_to_bottom() -> void:
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------------------
# Persistence & recent conversations
# ---------------------------------------------------------------------------

func _chats_dir() -> String:
	return Ide.saves_dir.path_join("AIChats")


func _save_conversation() -> void:
	if _transcript.is_empty():
		return
	Ide.ensure_dir(_chats_dir())
	var payload := {
		"id": _conversation_id,
		"created": _conversation_id,
		"mode": _manager.mode(),
		"model": _manager.active_label(),
		"messages": _transcript,
	}
	var text := JSON.stringify(payload, "  ")
	Ide.write_text_file(_chats_dir().path_join(_conversation_id + ".json"), text)
	# Keep a convenience mirror of the latest chat.
	Ide.write_text_file(Ide.saves_dir.path_join("last_chat.json"), text)


## Creates the scrollable container that lists past conversations.
func _build_recent_list() -> void:
	if access_panel == null:
		return
	var sc := ScrollContainer.new()
	sc.name = "RecentList"
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.visible = false
	access_panel.add_child(sc)
	_recent_scroll = sc
	_recent_list = VBoxContainer.new()
	_recent_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_recent_list)


func _populate_recent() -> void:
	if _recent_list == null:
		return
	for child in _recent_list.get_children():
		child.queue_free()
	var dir := DirAccess.open(_chats_dir())
	if dir == null:
		var empty := Label.new()
		empty.text = "No saved conversations yet."
		_recent_list.add_child(empty)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	names.reverse()
	for file_name in names:
		var button := Button.new()
		button.text = file_name.get_basename().replace("T", "  ")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := _chats_dir().path_join(file_name)
		button.pressed.connect(func() -> void: _load_conversation(path))
		_recent_list.add_child(button)


func _load_conversation(path: String) -> void:
	var parsed: Variant = JSON.parse_string(Ide.read_text_file(path))
	if not (parsed is Dictionary):
		_add_message("Codis", "Could not read that conversation.")
		return
	_conversation_id = str(parsed.get("id", _conversation_id))
	_transcript.clear()
	if chat_log != null:
		for child in chat_log.get_children():
			child.queue_free()
	var messages: Array = parsed.get("messages", [])
	for message in messages:
		if message is Dictionary:
			_add_message(str(message.get("role", "?")), str(message.get("text", "")))
			_transcript.append(message)
	_add_message("Codis", "Loaded conversation from %s." % path.get_file())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _active_sketch_name() -> String:
	var editor := Ide.get_active_code_edit()
	if editor == null:
		return "untitled"
	var path := str(editor.get_meta("file_path", ""))
	return path.get_file() if not path.is_empty() else "untitled"


func _find_code_editor_container() -> Node:
	# CodeEditor is a sibling of this panel under the outer TabContainer.
	return get_node_or_null("../CodeEditor")
