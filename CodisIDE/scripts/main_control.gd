extends Control

## Top-level controller for the CodisIDE window: toolbar, menu, tab routing,
## compile/upload actions and the settings dialog.

@onready var menu_bar: MenuBar = $Control/MenuBar
@onready var tabs: TabContainer = $Control/TabContainer
@onready var code_editor: Node = $Control/TabContainer/CodeEditor
@onready var output: TextEdit = $Control/TabContainer/OutputTerminal
@onready var ai_assistant: Node = $Control/TabContainer/AiAssistant
@onready var undo: Button = $Control/RightContainer/Undo
@onready var redo: Button = $Control/RightContainer/Redo
@onready var upload: Button = $Control/RightContainer/Upload
@onready var compile: Button = $Control/RightContainer/Compile

const TAB_CODE: int = 0
const TAB_OUTPUT: int = 1
const TAB_SERIAL: int = 2
const TAB_PLOTTER: int = 3
const TAB_BOARDS: int = 4
const TAB_LIBRARIES: int = 5
const TAB_AI: int = 6

const EXAMPLES: Dictionary = {
	"Blink": "// Blink - toggles the built-in LED\nvoid setup() {\n\tpinMode(LED_BUILTIN, OUTPUT);\n}\n\nvoid loop() {\n\tdigitalWrite(LED_BUILTIN, HIGH);\n\tdelay(1000);\n\tdigitalWrite(LED_BUILTIN, LOW);\n\tdelay(1000);\n}\n",
	"Fade (PWM)": "// Fade an LED using PWM\nint led = 9;\nint brightness = 0;\nint fadeAmount = 5;\n\nvoid setup() {\n\tpinMode(led, OUTPUT);\n}\n\nvoid loop() {\n\tanalogWrite(led, brightness);\n\tbrightness = brightness + fadeAmount;\n\tif (brightness <= 0 || brightness >= 255) {\n\t\tfadeAmount = -fadeAmount;\n\t}\n\tdelay(30);\n}\n",
	"Serial Read": "// Echo serial input back with a timestamp\nvoid setup() {\n\tSerial.begin(9600);\n}\n\nvoid loop() {\n\tif (Serial.available() > 0) {\n\t\tString in = Serial.readStringUntil('\\n');\n\t\tSerial.print(millis());\n\t\tSerial.print(\": \");\n\t\tSerial.println(in);\n\t}\n}\n",
	"Button + LED": "// Turn an LED on while a button is pressed\nconst int buttonPin = 2;\nconst int ledPin = 13;\n\nvoid setup() {\n\tpinMode(ledPin, OUTPUT);\n\tpinMode(buttonPin, INPUT_PULLUP);\n}\n\nvoid loop() {\n\tint state = digitalRead(buttonPin);\n\tdigitalWrite(ledPin, state == LOW ? HIGH : LOW);\n}\n",
}

var _file_menu: PopupMenu
var _edit_menu: PopupMenu
var _sketch_menu: PopupMenu
var _tools_menu: PopupMenu
var _help_menu: PopupMenu
var _theme_submenu: PopupMenu
var _examples_submenu: PopupMenu
var _settings_dialog: SettingsDialog
var _arduino_cli: int = -1 # -1 unknown, 0 missing, 1 present
var _upload_manager: UploadManager
var _upload_menu: PopupMenu
var _port_selector: OptionButton
var _examples_scanned: bool = false


func _ready() -> void:
	_build_menu()
	_setup_tabs()
	_connect_toolbar_actions()
	_connect_ide()
	_setup_uploaders()
	_setup_board_selector()
	output.editable = false
	tabs.current_tab = TAB_CODE
	_append_output("[CodisIDE] Ready on " + Platform.describe() + ". Data folder: " + Ide.base_dir)


func _setup_tabs() -> void:
	# Icons-only navigation bar: blank titles, names only shown as tooltips.
	var names: Array[String] = ["Code", "Output", "Serial Monitor", "Serial Plotter", "Boards", "Libraries", "AI Assistant"]
	for i in names.size():
		tabs.set_tab_title(i, "")
		tabs.set_tab_tooltip(i, names[i])


func _connect_toolbar_actions() -> void:
	compile.pressed.connect(_on_compile)
	upload.pressed.connect(_on_upload)
	undo.pressed.connect(_on_undo)
	redo.pressed.connect(_on_redo)
	undo.tooltip_text = "Undo (Ctrl+Z)"
	redo.tooltip_text = "Redo (Ctrl+Y)"
	undo.visible = true
	redo.visible = true


func _connect_ide() -> void:
	if not Ide.status_message.is_connected(_append_output):
		Ide.status_message.connect(_append_output)
	if not Ide.theme_changed.is_connected(_on_theme_changed):
		Ide.theme_changed.connect(_on_theme_changed)

	if ai_assistant:
		if ai_assistant.has_signal("request_settings"):
			ai_assistant.request_settings.connect(_open_settings)
		if ai_assistant.has_signal("request_tab"):
			ai_assistant.request_tab.connect(func(i: int) -> void: tabs.current_tab = i)


# ---------------------------------------------------------------------------
# Upload backends
# ---------------------------------------------------------------------------

func _setup_uploaders() -> void:
	_upload_manager = UploadManager.new()
	_upload_manager.name = "UploadManager"
	add_child(_upload_manager)
	for loader in _upload_manager.uploaders:
		loader.log_line.connect(_append_output)
	_upload_manager.upload_finished.connect(_on_upload_finished)

	_upload_menu = PopupMenu.new()
	add_child(_upload_menu)
	_upload_menu.id_pressed.connect(_on_upload_backend_chosen)

	var names: Array[String] = []
	for loader in _upload_manager.available():
		names.append(loader.display_name)
	if names.is_empty():
		_append_output("[Upload] No backend available on this platform — see Settings ▸ Upload.")
	else:
		_append_output("[Upload] Backends: " + ", ".join(PackedStringArray(names)))


# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

func _build_menu() -> void:
	if menu_bar == null:
		return
	_file_menu = _add_menu("File")
	_file_menu.add_item("New Sketch", 1)
	_file_menu.add_item("Open…", 2)
	_file_menu.add_item("Save", 3)
	_file_menu.add_item("Save As…", 4)
	_file_menu.add_separator()

	_examples_submenu = PopupMenu.new()
	_examples_submenu.name = "Examples"
	_examples_submenu.id_pressed.connect(_on_example_id)
	_file_menu.add_child(_examples_submenu)
	_file_menu.add_submenu_item("Examples", _examples_submenu.name, 5)
	_add_builtin_examples()
	# With thousands of libraries the scan is deferred to the first time the
	# menu is actually opened, so startup stays instant.
	_examples_submenu.about_to_popup.connect(_scan_library_examples_once)

	_file_menu.add_separator()
	_file_menu.add_item("Settings…", 7)
	_file_menu.add_separator()
	_file_menu.add_item("Open Data Folder", 8)
	_file_menu.add_item("Quit", 9)

	_edit_menu = _add_menu("Edit")
	_edit_menu.add_item("Undo", 20)
	_edit_menu.add_item("Redo", 21)
	_edit_menu.add_separator()
	_edit_menu.add_item("Cut", 22)
	_edit_menu.add_item("Copy", 23)
	_edit_menu.add_item("Paste", 24)
	_edit_menu.add_item("Select All", 25)

	_sketch_menu = _add_menu("Sketch")
	_sketch_menu.add_item("Compile", 30)
	_sketch_menu.add_item("Upload", 31)
	_sketch_menu.add_item("Upload with…", 32)
	_sketch_menu.add_separator()
	_sketch_menu.add_item("Manage Libraries", 33)
	_sketch_menu.add_item("Manage Boards", 34)

	_tools_menu = _add_menu("Tools")
	_theme_submenu = PopupMenu.new()
	_theme_submenu.name = "Themes"
	for theme_id in ThemeManager.list_themes():
		_theme_submenu.add_item(ThemeManager.theme_label(theme_id))
		_theme_submenu.set_item_metadata(_theme_submenu.item_count - 1, theme_id)
	_theme_submenu.id_pressed.connect(_on_theme_id)
	_tools_menu.add_child(_theme_submenu)
	_tools_menu.add_submenu_item("Themes", _theme_submenu.name)
	_tools_menu.add_separator()
	_tools_menu.add_item("AI Settings…", 40)
	_tools_menu.add_item("Upload Settings…", 41)
	_tools_menu.add_item("Rescan Ports", 42)

	_help_menu = _add_menu("Help")
	_help_menu.add_item("About CodisIDE", 50)
	_help_menu.add_item("Local AI models", 51)

	for m in [_file_menu, _edit_menu, _sketch_menu, _tools_menu, _help_menu]:
		m.id_pressed.connect(_on_menu_id)


func _add_menu(title: String) -> PopupMenu:
	var popup := PopupMenu.new()
	popup.name = title
	menu_bar.add_child(popup)
	return popup


func _check_menu_state() -> void:
	if _theme_submenu == null:
		return
	var current_theme := Ide.current_theme_id()
	for i in _theme_submenu.item_count:
		var meta: String = str(_theme_submenu.get_item_metadata(i))
		_theme_submenu.set_item_checked(i, meta == current_theme)


func _on_menu_id(id: int) -> void:
	match id:
		1: code_editor.new_sketch(); tabs.current_tab = TAB_CODE
		2: code_editor.open_dialog()
		3: code_editor.save_current()
		4: code_editor.save_current_as()
		7: _open_settings()
		8: _open_data_folder()
		9: get_tree().quit()
		20: _on_undo()
		21: _on_redo()
		22: _clipboard("cut")
		23: _clipboard("copy")
		24: _clipboard("paste")
		25: _clipboard("select_all")
		30: _on_compile()
		31: _on_upload()
		32: _open_upload_menu()
		33: tabs.current_tab = TAB_LIBRARIES
		34: tabs.current_tab = TAB_BOARDS
		40: _open_settings()
		41: _open_settings()
		42: _setup_board_selector()
		50: _show_about()
		51: _append_output("[AI] Local models run through Ollama. Pull one with e.g. `ollama pull gemma2:2b`, `qwen2.5:1.5b` or `smollm2:1.8b`.")


func _clipboard(action: String) -> void:
	var editor := Ide.get_active_code_edit()
	if editor == null:
		return
	match action:
		"cut": editor.cut()
		"copy": editor.copy()
		"paste": editor.paste()
		"select_all": editor.select_all()


func _show_about() -> void:
	_append_output("[CodisIDE] Offline-first Arduino IDE · platform: %s · data: %s" % [Platform.describe(), Ide.base_dir])


func _on_example_id(id: int) -> void:
	var index: int = id - 100
	var names := EXAMPLES.keys()
	if index < 0 or index >= names.size():
		return
	var example_name: String = str(names[index])
	code_editor.create_new_tab(example_name, str(EXAMPLES[example_name]))
	tabs.current_tab = TAB_CODE


func _on_theme_id(id: int) -> void:
	var meta: String = str(_theme_submenu.get_item_metadata(id))
	Ide.apply_theme(meta)
	_append_output("[CodisIDE] Theme: " + ThemeManager.theme_label(meta))


func _on_theme_changed(_theme_id: String) -> void:
	_check_menu_state()


# ---------------------------------------------------------------------------
# Examples (built-in + every installed library)
# ---------------------------------------------------------------------------

func _add_builtin_examples() -> void:
	if _examples_submenu.has_node("Built-in"):
		return
	var builtin := PopupMenu.new()
	builtin.name = "Built-in"
	var idx := 0
	for ex_name in EXAMPLES:
		builtin.add_item(str(ex_name), 100 + idx)
		idx += 1
	builtin.id_pressed.connect(_on_example_id)
	_examples_submenu.add_child(builtin)
	_examples_submenu.add_submenu_item("Built-in", builtin.name)


## Scans every installed library for example sketches. Runs once, the first
## time the Examples menu is opened, and is time-boxed so a huge library folder
## cannot freeze the UI.
func _scan_library_examples_once() -> void:
	if _examples_scanned:
		return
	_examples_scanned = true
	if not DirAccess.dir_exists_absolute(Ide.libraries_dir):
		return
	var dir := DirAccess.open(Ide.libraries_dir)
	if dir == null:
		return
	var libs: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			libs.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	libs.sort()

	var started := Time.get_ticks_msec()
	var added := 0
	for lib in libs:
		if added >= 80 or Time.get_ticks_msec() - started > 3000:
			break
		var examples_dir := _find_examples_dir(Ide.libraries_dir.path_join(lib))
		if examples_dir.is_empty():
			continue
		var sub := PopupMenu.new()
		sub.name = lib.validate_node_name()
		sub.set_meta("examples_dir", examples_dir)
		sub.about_to_popup.connect(_load_library_examples.bind(sub))
		_examples_submenu.add_child(sub)
		_examples_submenu.add_submenu_item(lib, sub.name)
		added += 1
	if added == 0:
		_examples_submenu.add_separator()
		_examples_submenu.add_item("No library examples found", 999)


## Finds a library's examples folder, either directly or one level down
## (many libraries are packaged as `<Library>/<version>/examples`).
func _find_examples_dir(lib_path: String) -> String:
	var direct := lib_path.path_join("examples")
	if DirAccess.dir_exists_absolute(direct):
		return direct
	var dir := DirAccess.open(lib_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	var found := ""
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var nested := lib_path.path_join(entry).path_join("examples")
			if DirAccess.dir_exists_absolute(nested):
				found = nested
				break
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _load_library_examples(sub: PopupMenu) -> void:
	if sub.item_count > 0:
		return
	var examples_dir := str(sub.get_meta("examples_dir", ""))
	_scan_examples_into(sub, examples_dir, 0)
	if sub.item_count == 0:
		sub.add_item("(empty)", 999)


func _scan_examples_into(menu: PopupMenu, dir_path: String, depth: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or depth > 2:
		return
	var folders: Array[String] = []
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				folders.append(entry)
		elif entry.get_extension().to_lower() == "ino":
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	folders.sort()
	for f in files:
		if menu.item_count > 200:
			break
		var item_id := menu.item_count
		menu.add_item(f.get_basename())
		menu.set_item_metadata(item_id, dir_path.path_join(f))
	for folder in folders:
		if menu.item_count > 200:
			break
		var child_path := dir_path.path_join(folder)
		var child := PopupMenu.new()
		child.name = folder.validate_node_name()
		child.about_to_popup.connect(_load_library_examples.bind(child))
		child.set_meta("examples_dir", child_path)
		menu.add_child(child)
		menu.add_submenu_item(folder, child.name)
	if not menu.has_meta("wired"):
		menu.set_meta("wired", true)
		menu.id_pressed.connect(_on_example_file_id.bind(menu))


func _on_example_file_id(item_id: int, menu: PopupMenu) -> void:
	var path := str(menu.get_item_metadata(item_id))
	if path.is_empty():
		return
	_open_example_file(path)


func _open_example_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	code_editor.create_new_tab(path.get_file(), Ide.read_text_file(path))
	tabs.current_tab = TAB_CODE
	_append_output("[Examples] Opened " + path)


# ---------------------------------------------------------------------------
# Board / port detection
# ---------------------------------------------------------------------------

func _setup_board_selector() -> void:
	var toolbar: Node = get_node_or_null("Control")
	if toolbar == null:
		return
	if _port_selector != null:
		toolbar.remove_child(_port_selector)
		_port_selector.queue_free()
		_port_selector = null
	var ports := _detect_ports()
	if ports.is_empty():
		_append_output("[Boards] No board detected — connect one to choose a target board.")
		return
	_port_selector = OptionButton.new()
	_port_selector.tooltip_text = "Detected boards / serial ports"
	_port_selector.position = Vector2(695.0, 6.0)
	_port_selector.custom_minimum_size = Vector2(120.0, 38.0)
	var selected := 0
	var saved := str(Ide.get_setting("selected_port", ""))
	for i in ports.size():
		_port_selector.add_item(ports[i])
		if ports[i] == saved:
			selected = i
	_port_selector.select(selected)
	_port_selector.item_selected.connect(func(i: int) -> void:
		Ide.set_setting("selected_port", ports[i])
		Ide.save_settings()
		_append_output("[Boards] Target port: " + ports[i]))
	toolbar.add_child(_port_selector)
	if saved.is_empty():
		Ide.set_setting("selected_port", ports[selected])
		Ide.save_settings()
	_append_output("[Boards] Detected: " + ", ".join(ports))


func _detect_ports() -> PackedStringArray:
	var ports := PackedStringArray()
	if OS.get_name() == "Windows":
		if not Platform.supports_subprocess():
			return ports
		var out: Array = []
		var code := OS.execute("powershell", ["-NoProfile", "-Command", "[System.IO.Ports.SerialPort]::getportnames()"], out, true)
		if code == 0:
			for line in out:
				var p := str(line).strip_edges()
				if not p.is_empty():
					ports.append(p)
	elif Platform.is_desktop():
		var dir := DirAccess.open("/dev")
		if dir != null:
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if entry.begins_with("ttyUSB") or entry.begins_with("ttyACM") or entry.begins_with("cu."):
					ports.append("/dev/" + entry)
				entry = dir.get_next()
			dir.list_dir_end()
	return ports


# ---------------------------------------------------------------------------
# Compile / upload
# ---------------------------------------------------------------------------

func _on_compile() -> void:
	var editor := Ide.get_active_code_edit()
	if editor == null:
		_append_output("[Compile] No open sketch to compile.")
		tabs.current_tab = TAB_OUTPUT
		return

	# Only save when the tab already maps to a file; unsaved sketches compile
	# straight from memory (no blocking save dialog).
	if code_editor.get_current_path() != "":
		code_editor.save_current()

	# Save a copy of the build attempt into the Saves folder.
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var log_path := Ide.saves_dir.path_join("build_" + stamp + ".log")

	var report: Dictionary = LocalCodeAnalyzer.analyze(editor.text, "compile")
	var lines: Array[String] = []
	lines.append("Compiling " + _sketch_name(editor) + " ...")
	lines.append(str(report["summary"]))
	for issue in report["issues"]:
		lines.append("  line %d: %s -> %s" % [int(issue["line"]), str(issue["message"]), str(issue["suggestion"])])
	if int(report["score"]) >= 60:
		lines.append("Done compiling. (local analysis, %d/100)" % int(report["score"]))
	else:
		lines.append("Compilation reported problems. Score %d/100." % int(report["score"]))

	if _has_arduino_cli():
		lines.append("")
		lines.append(_run_arduino_cli(["compile", "--fqbn", _fqbn()]))

	for l in lines:
		_append_output(l)
	Ide.write_text_file(log_path, "\n".join(lines))
	tabs.current_tab = TAB_OUTPUT


func _on_upload() -> void:
	var editor := Ide.get_active_code_edit()
	if editor == null:
		_append_output("[Upload] No open sketch to upload.")
		tabs.current_tab = TAB_OUTPUT
		return

	# Persist only when the tab already maps to a file (no blocking dialog).
	if code_editor.get_current_path() != "":
		code_editor.save_current()

	var options := _upload_manager.available()
	if options.is_empty():
		_append_output("[Upload] No upload backend is available on this device.")
		_append_output("          Set a Network/OTA host in Settings, install arduino-cli")
		_append_output("          (desktop), or add the CodisSerial native driver for USB.")
		tabs.current_tab = TAB_OUTPUT
		return

	# Honour a preferred backend from Settings when it is usable.
	var preferred := _preferred_uploader()
	if preferred != null:
		_start_upload(preferred)
		return

	if options.size() == 1:
		_start_upload(options[0])
		return
	_open_upload_menu()


func _preferred_uploader() -> UploaderPlugin:
	var id := str(Ide.get_setting("upload_backend", ""))
	if id.is_empty():
		return null
	var up := _upload_manager.find(id)
	return up if up != null and up.is_available() else null


func _open_upload_menu() -> void:
	var options := _upload_manager.available()
	if options.is_empty():
		_on_upload()
		return
	_upload_menu.clear()
	var i := 0
	for up in options:
		_upload_menu.add_item("%s — %s" % [up.display_name, up.description], i)
		_upload_menu.set_item_metadata(i, up.id)
		i += 1
	var pos := menu_bar.global_position + Vector2(0, menu_bar.size.y)
	_upload_menu.position = Vector2i(pos)
	_upload_menu.popup()


func _on_upload_backend_chosen(id: int) -> void:
	var backend_id := str(_upload_menu.get_item_metadata(id))
	var up := _upload_manager.find(backend_id)
	if up != null:
		_start_upload(up)


func _start_upload(uploader: UploaderPlugin) -> void:
	var editor := Ide.get_active_code_edit()
	if editor == null:
		return
	var sketch := _current_sketch(editor)
	_append_output("[Upload] Using %s …" % uploader.display_name)
	tabs.current_tab = TAB_OUTPUT
	if _upload_manager.upload(sketch, uploader):
		# Remember the chosen backend for next time.
		Ide.set_setting("upload_backend", uploader.id)


func _current_sketch(editor: CodeEdit) -> Dictionary:
	return {
		"name": _sketch_name(editor),
		"source": editor.text,
		"path": str(editor.get_meta("file_path", "")),
		"fqbn": _fqbn(),
		"port": str(Ide.get_setting("selected_port", "")),
	}


func _on_upload_finished(success: bool, message: String) -> void:
	_append_output(("[Upload] OK — " if success else "[Upload] Failed — ") + message)


func _fqbn() -> String:
	var board := str(Ide.get_setting("selected_board", ""))
	return board if not board.is_empty() else "esp32:esp32:esp32c3"


func _has_arduino_cli() -> bool:
	if _arduino_cli == -1:
		_arduino_cli = 1 if _command_on_path("arduino-cli") else 0
	return _arduino_cli == 1


## Scans PATH for an executable without spawning a process (avoids engine
## errors when the tool is absent).
func _command_on_path(cmd: String) -> bool:
	var path_env: String = OS.get_environment("PATH")
	var separator: String = ";" if OS.get_name() == "Windows" else ":"
	var extensions: Array = ["", ".exe", ".bat", ".cmd"] if OS.get_name() == "Windows" else [""]
	for dir in path_env.split(separator):
		if dir.is_empty():
			continue
		for ext in extensions:
			if FileAccess.file_exists(dir.path_join(cmd + str(ext))):
				return true
	return false


func _run_arduino_cli(args: Array) -> String:
	var out: Array = []
	var editor := Ide.get_active_code_edit()
	var sketch_path := str(editor.get_meta("file_path", "")) if editor else ""
	var full_args := args.duplicate()
	if not sketch_path.is_empty():
		full_args.append(sketch_path)
	var code: int = OS.execute("arduino-cli", full_args, out, true)
	var text := ""
	for line in out:
		text += str(line) + "\n"
	text += "(exit code %d)" % code
	return text


func _sketch_name(editor: CodeEdit) -> String:
	var path := str(editor.get_meta("file_path", ""))
	return path.get_file() if not path.is_empty() else "untitled"


# ---------------------------------------------------------------------------
# Undo / redo / output
# ---------------------------------------------------------------------------

func _on_undo() -> void:
	var editor := Ide.get_active_code_edit()
	if editor:
		editor.undo()


func _on_redo() -> void:
	var editor := Ide.get_active_code_edit()
	if editor:
		editor.redo()


func _append_output(text: String) -> void:
	if output == null:
		return
	output.text += text + "\n"
	output.scroll_vertical = int(output.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------------------
# Settings & folders
# ---------------------------------------------------------------------------

func _open_settings() -> void:
	if _settings_dialog == null:
		_settings_dialog = SettingsDialog.new()
		add_child(_settings_dialog)
		_settings_dialog.theme_applied.connect(func(_id: String) -> void: _check_menu_state())
	_settings_dialog.popup_centered(Vector2i(480, 520))


func _open_data_folder() -> void:
	Ide.ensure_dir(Ide.base_dir)
	if not Platform.open_folder(Ide.base_dir):
		_append_output("[CodisIDE] Data folder: " + Ide.base_dir)
