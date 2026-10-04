class_name SettingsDialog
extends AcceptDialog

## Programmatically-built settings window. Lets the user pick the IDE theme,
## editor preferences, the active local AI model and the target board/port.

signal theme_applied(theme_id: String)

var _theme_option: OptionButton
var _font_spin: SpinBox
var _ui_scale_spin: SpinBox
var _wrap_check: CheckBox
var _numbers_check: CheckBox

# AI
var _ai_mode_option: OptionButton
var _local_model_option: OptionButton
var _local_endpoint_edit: LineEdit
var _online_provider_option: OptionButton
var _online_model_edit: LineEdit
var _gemini_model_edit: LineEdit
var _base_url_edit: LineEdit
var _gemini_key_edit: LineEdit
var _openai_key_edit: LineEdit

# Board / upload
var _board_edit: LineEdit
var _port_edit: LineEdit
var _backend_option: OptionButton
var _ota_host_edit: LineEdit
var _ota_port_spin: SpinBox
var _baud_spin: SpinBox
var _path_label: Label


func _ready() -> void:
	title = "CodisIDE Settings"
	ok_button_text = "Apply"
	min_size = Vector2i(560, 600)
	confirmed.connect(_apply)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(540, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	# --- Appearance ---------------------------------------------------------
	root.add_child(_section("Appearance"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)

	grid.add_child(_label("Theme"))
	_theme_option = OptionButton.new()
	var themes := ThemeManager.list_themes()
	for i in themes.size():
		_theme_option.add_item(ThemeManager.theme_label(themes[i]), i)
		_theme_option.set_item_metadata(i, themes[i])
	_theme_option.item_selected.connect(_on_theme_selected)
	grid.add_child(_theme_option)

	grid.add_child(_label("Font size"))
	_font_spin = SpinBox.new()
	_font_spin.min_value = 10
	_font_spin.max_value = 32
	_font_spin.value = int(Ide.get_setting("font_size", 15))
	grid.add_child(_font_spin)

	grid.add_child(_label("UI scale"))
	_ui_scale_spin = SpinBox.new()
	_ui_scale_spin.min_value = 0.7
	_ui_scale_spin.max_value = 2.0
	_ui_scale_spin.step = 0.05
	_ui_scale_spin.value = float(Ide.get_setting("ui_scale", 1.0))
	grid.add_child(_ui_scale_spin)

	grid.add_child(_label("Word wrap"))
	_wrap_check = CheckBox.new()
	_wrap_check.button_pressed = bool(Ide.get_setting("word_wrap", false))
	grid.add_child(_wrap_check)

	grid.add_child(_label("Line numbers"))
	_numbers_check = CheckBox.new()
	_numbers_check.button_pressed = bool(Ide.get_setting("show_line_numbers", true))
	grid.add_child(_numbers_check)

	# --- AI -----------------------------------------------------------------
	root.add_child(_section("AI"))

	grid.add_child(_label("Mode"))
	_ai_mode_option = OptionButton.new()
	_ai_mode_option.add_item("Offline (local model)", 0)
	_ai_mode_option.add_item("Online (API key)", 1)
	_ai_mode_option.select(1 if str(Ide.get_setting("ai_mode", "offline")) == "online" else 0)
	grid.add_child(_ai_mode_option)

	grid.add_child(_label("Local model (Ollama)"))
	var local_row := HBoxContainer.new()
	_local_model_option = OptionButton.new()
	_local_model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_local_models()
	local_row.add_child(_local_model_option)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.tooltip_text = "Re-scan models installed in Ollama"
	refresh_btn.pressed.connect(_populate_local_models)
	local_row.add_child(refresh_btn)
	grid.add_child(local_row)

	grid.add_child(_label("Local AI endpoint"))
	_local_endpoint_edit = LineEdit.new()
	_local_endpoint_edit.text = str(Ide.get_setting("local_ai_endpoint", "http://127.0.0.1:11434"))
	_local_endpoint_edit.placeholder_text = "http://127.0.0.1:11434 or reachable LAN host"
	grid.add_child(_local_endpoint_edit)
	grid.add_child(_label("Local AI note"))
	var local_ai_note := Label.new()
	local_ai_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	local_ai_note.text = _local_ai_platform_note()
	grid.add_child(local_ai_note)

	grid.add_child(_label("Online provider"))
	_online_provider_option = OptionButton.new()
	_online_provider_option.add_item("Google Gemini", 0)
	_online_provider_option.add_item("OpenAI-compatible", 1)
	_online_provider_option.select(1 if str(Ide.get_setting("online_provider", "gemini")) == "openai" else 0)
	grid.add_child(_online_provider_option)

	grid.add_child(_label("Online model"))
	_online_model_edit = LineEdit.new()
	_online_model_edit.text = str(Ide.get_setting("online_model", ""))
	_online_model_edit.placeholder_text = "gpt-4o-mini"
	grid.add_child(_online_model_edit)

	grid.add_child(_label("Gemini model"))
	_gemini_model_edit = LineEdit.new()
	_gemini_model_edit.text = str(Ide.get_setting("gemini_model", ""))
	_gemini_model_edit.placeholder_text = "gemini-2.0-flash"
	grid.add_child(_gemini_model_edit)

	grid.add_child(_label("API base URL"))
	_base_url_edit = LineEdit.new()
	_base_url_edit.text = str(Ide.get_setting("online_base_url", ""))
	_base_url_edit.placeholder_text = "https://api.openai.com/v1"
	grid.add_child(_base_url_edit)

	grid.add_child(_label("Gemini API key"))
	_gemini_key_edit = LineEdit.new()
	_gemini_key_edit.secret = true
	_gemini_key_edit.text = str(Ide.get_setting("api_key_gemini", ""))
	_gemini_key_edit.placeholder_text = "AIza…"
	grid.add_child(_gemini_key_edit)

	grid.add_child(_label("OpenAI-compatible key"))
	_openai_key_edit = LineEdit.new()
	_openai_key_edit.secret = true
	_openai_key_edit.text = str(Ide.get_setting("api_key_openai", ""))
	_openai_key_edit.placeholder_text = "sk-…"
	grid.add_child(_openai_key_edit)

	# --- Board / port -------------------------------------------------------
	root.add_child(_section("Board & port"))

	grid.add_child(_label("Board (FQBN)"))
	_board_edit = LineEdit.new()
	_board_edit.text = str(Ide.get_setting("selected_board", "esp32:esp32:esp32c3"))
	_board_edit.placeholder_text = "esp32:esp32:esp32c3"
	grid.add_child(_board_edit)

	grid.add_child(_label("Port"))
	_port_edit = LineEdit.new()
	_port_edit.text = str(Ide.get_setting("selected_port", ""))
	_port_edit.placeholder_text = "COM3 or /dev/ttyUSB0"
	grid.add_child(_port_edit)

	# --- Upload -------------------------------------------------------------
	root.add_child(_section("Upload"))

	grid.add_child(_label("Backend"))
	_backend_option = OptionButton.new()
	_populate_backends()
	grid.add_child(_backend_option)

	grid.add_child(_label("Network / OTA host"))
	_ota_host_edit = LineEdit.new()
	_ota_host_edit.text = str(Ide.get_setting("ota_host", ""))
	_ota_host_edit.placeholder_text = "192.168.1.50 or codis-bridge.local"
	grid.add_child(_ota_host_edit)

	grid.add_child(_label("Network / OTA port"))
	_ota_port_spin = SpinBox.new()
	_ota_port_spin.min_value = 1
	_ota_port_spin.max_value = 65535
	_ota_port_spin.value = int(Ide.get_setting("ota_port", 3232))
	grid.add_child(_ota_port_spin)

	grid.add_child(_label("Serial baud"))
	_baud_spin = SpinBox.new()
	_baud_spin.min_value = 9600
	_baud_spin.max_value = 2000000
	_baud_spin.step = 9600
	_baud_spin.value = int(Ide.get_setting("baud", 115200))
	grid.add_child(_baud_spin)

	# --- Data folder --------------------------------------------------------
	root.add_child(_section("Data folder"))
	_path_label = Label.new()
	_path_label.text = Ide.base_dir
	_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_path_label.add_theme_font_size_override("font_size", 12)
	root.add_child(_path_label)

	var open_btn := Button.new()
	open_btn.text = "Open data folder"
	open_btn.pressed.connect(_open_data_folder)
	root.add_child(open_btn)
	if not Platform.is_desktop():
		open_btn.disabled = true
		open_btn.tooltip_text = "Opening a file manager is not available on this platform."

	var platform_lbl := Label.new()
	platform_lbl.text = "Platform: " + Platform.describe()
	platform_lbl.add_theme_font_size_override("font_size", 12)
	root.add_child(platform_lbl)

	_select_current_theme()


func _section(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	return lbl


func _label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


## Platform-specific setup note for running a local inference server.
func _local_ai_platform_note() -> String:
	if Platform.is_mobile():
		return "Requires an Ollama-compatible server on this device or reachable over Wi-Fi; use the server's LAN address, not 127.0.0.1. Enable INTERNET permission in Android exports."
	if Platform.is_web():
		return "Browser builds cannot bundle Ollama. Use a reachable CORS-enabled Ollama-compatible server, or switch to Online mode."
	return "Install Ollama on this computer and keep it running. The endpoint can point to another reachable Ollama-compatible host."


## Lists the open-source models installed in the local Ollama runtime.
func _populate_local_models() -> void:
	if _local_model_option == null:
		return
	var current := str(Ide.get_setting("local_model", "qwen2.5:1.5b"))
	_local_model_option.clear()
	_local_model_option.add_item(current)
	_local_model_option.set_item_metadata(0, current)
	var mgr := AIManager.new()
	add_child(mgr)
	mgr.list_local_models(func(names: PackedStringArray) -> void:
		for n in names:
			if n == current or n.is_empty():
				continue
			_local_model_option.add_item(n)
			_local_model_option.set_item_metadata(_local_model_option.item_count - 1, n)
		mgr.queue_free())


## Lists the upload backends usable on this device (mirrors [UploadManager]).
func _populate_backends() -> void:
	_backend_option.clear()
	_backend_option.add_item("Automatic", 0)
	_backend_option.set_item_metadata(0, "")
	var mgr := UploadManager.new()
	add_child(mgr)
	var list := mgr.available()
	for i in list.size():
		_backend_option.add_item(list[i].display_name, i + 1)
		_backend_option.set_item_metadata(i + 1, list[i].id)
	mgr.queue_free()
	var current := str(Ide.get_setting("upload_backend", ""))
	for i in _backend_option.item_count:
		if str(_backend_option.get_item_metadata(i)) == current:
			_backend_option.select(i)
			break


func _open_data_folder() -> void:
	if not Platform.open_folder(Ide.base_dir):
		Ide.status_message.emit("[Settings] Data folder: " + Ide.base_dir)


func _select_current_theme() -> void:
	var current := Ide.current_theme_id()
	for i in _theme_option.item_count:
		if str(_theme_option.get_item_metadata(i)) == current:
			_theme_option.select(i)
			break


func _on_theme_selected(index: int) -> void:
	var id: String = str(_theme_option.get_item_metadata(index))
	Ide.apply_theme(id)
	Ide.set_setting("theme", id)
	theme_applied.emit(id)


func _apply() -> void:
	Ide.set_setting("theme", str(_theme_option.get_item_metadata(_theme_option.selected)))
	Ide.apply_theme(str(_theme_option.get_item_metadata(_theme_option.selected)))
	Ide.set_setting("font_size", int(_font_spin.value))
	Ide.set_setting("word_wrap", _wrap_check.button_pressed)
	Ide.set_setting("show_line_numbers", _numbers_check.button_pressed)
	Ide.set_setting("ui_scale", float(_ui_scale_spin.value))
	Ide.set_setting("ai_mode", "online" if _ai_mode_option.selected == 1 else "offline")
	Ide.set_setting("local_model", str(_local_model_option.get_item_metadata(maxi(_local_model_option.selected, 0))))
	Ide.set_setting("local_ai_endpoint", _local_endpoint_edit.text.strip_edges())
	Ide.set_setting("online_provider", "openai" if _online_provider_option.selected == 1 else "gemini")
	Ide.set_setting("online_model", _online_model_edit.text.strip_edges())
	Ide.set_setting("gemini_model", _gemini_model_edit.text.strip_edges())
	Ide.set_setting("online_base_url", _base_url_edit.text.strip_edges())
	Ide.set_setting("api_key_gemini", _gemini_key_edit.text.strip_edges())
	Ide.set_setting("api_key_openai", _openai_key_edit.text.strip_edges())
	Ide.set_setting("selected_board", _board_edit.text.strip_edges())
	Ide.set_setting("selected_port", _port_edit.text.strip_edges())
	Ide.set_setting("upload_backend", str(_backend_option.get_item_metadata(_backend_option.selected)))
	Ide.set_setting("ota_host", _ota_host_edit.text.strip_edges())
	Ide.set_setting("ota_port", int(_ota_port_spin.value))
	Ide.set_setting("baud", int(_baud_spin.value))
	Ide.save_settings()
	Ide.apply_ui_scale()
	_apply_editor_prefs()


func _apply_editor_prefs() -> void:
	var font_size := int(_font_spin.value)
	for node in _find_code_edits(get_tree().root):
		var edit := node as CodeEdit
		edit.add_theme_font_size_override("font_size", font_size)
		edit.gutters_draw_line_numbers = _numbers_check.button_pressed
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if _wrap_check.button_pressed else TextEdit.LINE_WRAPPING_NONE


func _find_code_edits(node: Node) -> Array:
	var out: Array = []
	if node is CodeEdit:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_code_edits(child))
	return out
