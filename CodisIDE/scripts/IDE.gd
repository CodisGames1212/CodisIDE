extends Node

## Central manager for CodisIDE. Autoloaded as `Ide`.
##
## Owns the on-disk directory layout (under Documents/CodisGames/CodisIDE),
## persisted settings, global theming, and the small set of helpers every panel
## in the IDE shares (active editor lookup, file listing, project I/O).

signal theme_changed(theme_id: String)
signal settings_changed()
signal file_saved(path: String)
signal code_committed(path: String)
signal status_message(text: String)

const BASE_SUBDIR: String = "CodisGames/CodisIDE"

## Sub-folders created under the base directory. "AI/Models" keeps downloaded
## GGUF/ONNX models separate from other AI assets.
const SUBDIRS: PackedStringArray = [
	"Codes",
	"Boards",
	"Libraries",
	"AI",
	"AI/Models",
	"Saves",
]

const SETTINGS_USER_PATH: String = "user://codis_settings.json"

# --- Resolved absolute paths ---------------------------------------------
var base_dir: String = ""
var codes_dir: String = ""
var boards_dir: String = ""
var libraries_dir: String = ""
var ai_dir: String = ""
var models_dir: String = ""
var saves_dir: String = ""

## True when the sandboxed `user://` tree is used instead of Documents (mobile
## and web). The editor and every file dialog branch on this.
var uses_user_space: bool = false

## Persisted settings. Keys are read/written through [method get_setting] and
## [method set_setting].
var settings: Dictionary = {
	"theme": "arduino_dark",
	"font_size": 15,
	"word_wrap": false,
	"show_line_numbers": true,
	"active_model": "",
	"selected_board": "esp32:esp32:esp32c3",
	"selected_port": "",
	"baud": 115200,
	"ota_host": "",
	"ota_port": 3232,
	"upload_backend": "",
	"ai_mode": "offline",
	"local_model": "qwen2.5:1.5b",
	"local_ai_endpoint": "http://127.0.0.1:11434",
	"online_provider": "gemini",
	"online_model": "",
	"gemini_model": "gemini-2.0-flash",
	"online_base_url": "",
	"api_key_gemini": "",
	"api_key_openai": "",
	"ai_autocommit": true,
	"ui_scale": 1.0,
	"auto_save": true,
}

## The currently applied [Theme] resource (may be null before _ready).
var current_theme: Theme = null


func _ready() -> void:
	_resolve_paths()
	_ensure_directories()
	load_settings()
	apply_theme(str(settings.get("theme", "arduino_dark")), false)
	apply_ui_scale()
	print("[CodisIDE] Data directory: ", base_dir)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

func _resolve_paths() -> void:
	var docs_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	# Mobile/web sandboxes either hide Documents or make it unwritable, so keep
	# everything inside user:// on those platforms.
	uses_user_space = docs_dir.is_empty() or Platform.uses_user_space()
	if uses_user_space:
		base_dir = ProjectSettings.globalize_path("user://").path_join(BASE_SUBDIR)
	else:
		base_dir = docs_dir.path_join(BASE_SUBDIR)

	codes_dir = base_dir.path_join("Codes")
	boards_dir = base_dir.path_join("Boards")
	libraries_dir = base_dir.path_join("Libraries")
	ai_dir = base_dir.path_join("AI")
	models_dir = ai_dir.path_join("Models")
	saves_dir = base_dir.path_join("Saves")


func _ensure_directories() -> void:
	for sub in SUBDIRS:
		ensure_dir(base_dir.path_join(sub))


## Creates [param path] (recursively) when it does not yet exist.
func ensure_dir(path: String) -> void:
	if path.is_empty():
		return
	if not DirAccess.dir_exists_absolute(path):
		var err: int = DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			printerr("[CodisIDE] Could not create directory: ", path, " (", err, ")")


# ---------------------------------------------------------------------------
# Settings persistence
# ---------------------------------------------------------------------------

func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_USER_PATH):
		_read_settings_file(SETTINGS_USER_PATH)
		return
	# Secondary location inside the save folder (portable/back-up copy).
	var mirror: String = saves_dir.path_join("settings.json")
	if FileAccess.file_exists(mirror):
		_read_settings_file(mirror)


func _read_settings_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for key in parsed:
			settings[key] = parsed[key]


func save_settings() -> void:
	var text: String = JSON.stringify(settings, "  ")
	var f := FileAccess.open(SETTINGS_USER_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	# Mirror to the Saves folder next to the user's projects.
	var mirror := FileAccess.open(saves_dir.path_join("settings.json"), FileAccess.WRITE)
	if mirror:
		mirror.store_string(text)
		mirror.close()


func get_setting(key: String, default: Variant = null) -> Variant:
	return settings.get(key, default)


func set_setting(key: String, value: Variant) -> void:
	if settings.get(key) == value:
		return
	settings[key] = value
	settings_changed.emit()


# ---------------------------------------------------------------------------
# Theming
# ---------------------------------------------------------------------------

## Applies a theme globally to the running UI and re-skins every open editor.
func apply_theme(theme_id: String, persist: bool = true) -> void:
	if not ThemeManager.has_theme(theme_id):
		theme_id = "arduino_dark"

	current_theme = ThemeManager.build_theme(theme_id)
	settings["theme"] = theme_id

	var root: Window = get_tree().root if is_inside_tree() else null
	if root:
		root.theme = current_theme
		_refresh_editor_highlighters(theme_id)

	theme_changed.emit(theme_id)
	if persist:
		save_settings()


func _refresh_editor_highlighters(theme_id: String) -> void:
	for edit in _find_nodes_of_type(get_tree().root, "CodeEdit"):
		apply_highlighter(edit, theme_id)


## Scales the whole UI by the saved `ui_scale` factor (handy on phones/tablets).
func apply_ui_scale() -> void:
	var factor: float = float(settings.get("ui_scale", 1.0))
	if not is_inside_tree():
		return
	var root: Window = get_tree().root
	if root != null:
		root.content_scale_factor = clampf(factor, 0.5, 3.0)


## Re-skins a single [CodeEdit] (or any [TextEdit] subclass) with the theme's
## syntax colours, matching the language to the file extension.
func apply_highlighter(edit: Node, theme_id: String = "") -> void:
	if not (edit is CodeEdit):
		return
	if theme_id.is_empty():
		theme_id = str(settings.get("theme", "arduino_dark"))

	var lang: String = "cpp"
	var path: String = str(edit.get_meta("file_path", ""))
	if path.to_lower().ends_with(".gd"):
		lang = "gdscript"

	(edit as CodeEdit).syntax_highlighter = ThemeManager.build_highlighter(theme_id, lang)


func current_theme_id() -> String:
	return str(settings.get("theme", "arduino_dark"))


# ---------------------------------------------------------------------------
# Editor lookup helpers
# ---------------------------------------------------------------------------

## Returns the [CodeEdit] the user is currently editing, or null. Works even
## when the Code tab is not the visible tab (the AI assistant commits to it).
func get_active_code_edit() -> CodeEdit:
	var root: Window = get_tree().root if is_inside_tree() else null
	if root == null:
		return null

	# 1. A focused CodeEdit wins.
	var focused: Control = root.gui_get_focus_owner()
	if focused is CodeEdit:
		return focused

	# 2. Ask the tab container for its current editor.
	var container: Node = _find_node_with_method(root, "get_current_editor")
	if container:
		var edit: Variant = container.call("get_current_editor")
		if edit is CodeEdit:
			return edit

	# 3. Any CodeEdit, even inside a hidden tab.
	var candidates: Array = _find_nodes_of_type(root, "CodeEdit")
	if not candidates.is_empty():
		return candidates[0]
	return null


func get_active_code() -> String:
	var edit := get_active_code_edit()
	return edit.text if edit else ""


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

## Lists files in [param dir] (non-recursive) whose extension is in
## [param extensions]. Pass an empty array to list everything.
func list_files(dir: String, extensions: PackedStringArray = PackedStringArray()) -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	var d := DirAccess.open(dir)
	if d == null:
		return result
	d.list_dir_begin()
	var file_name := d.get_next()
	while file_name != "":
		if not d.current_is_dir():
			if extensions.is_empty() or extensions.has(file_name.get_extension().to_lower()):
				result.append(file_name)
		file_name = d.get_next()
	d.list_dir_end()
	result.sort()
	return result


func read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func write_text_file(path: String, content: String) -> bool:
	ensure_dir(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[CodisIDE] Could not write file: ", path)
		return false
	f.store_string(content)
	f.close()
	file_saved.emit(path)
	return true


# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

func _find_nodes_of_type(node: Node, type_name: String) -> Array:
	var out: Array = []
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_nodes_of_type(child, type_name))
	return out


func _find_node_with_method(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child in node.get_children():
		var found: Node = _find_node_with_method(child, method)
		if found:
			return found
	return null
