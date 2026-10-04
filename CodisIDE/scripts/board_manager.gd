extends VBoxContainer

const BOARDS = preload("uid://bbkter7t8wr4d")

# Arduino & Community Board Registry URLs
var PACKAGE_URLS: Array[String] = [
	"https://downloads.arduino.cc/packages/package_index.json",
	"https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json",
	"https://arduino.esp8266.com/stable/package_esp8266com_index.json",
	"https://www.pjrc.com/teensy/package_teensy_index.json",
	"https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json",
	"https://raw.githubusercontent.com/openwch/board_manager_files/main/package_ch32v_index.json"
]

# Dynamic Node References (Supports Scene Unique Names % and Relative Paths)
var search: LineEdit
var boards_container: VBoxContainer
var board_manufacturer_dropdown: CustomDropdown
var available_board_dropdown: CustomDropdown
var board_type_dropdown: CustomDropdown

var connected_ports: Array[String] = [
	"ESP32 Dev Module (COM3)",
	"Teensy 4.1 (COM4)",
	"Arduino Nano (COM7)"
]

# Tracking structures
var unique_cores: Dictionary = {}
var requests_pending: int = 0

var all_boards: Array[Dictionary] = []
var unique_manufacturers: Dictionary = {}
var unique_types: Dictionary = {}

var current_filter_manufacturer: String = "All"
var current_filter_type: String = "All"
var current_search_query: String = ""

# File paths
var base_boards_dir: String = ""
var registries_dir: String = ""

# Active downloads: { HTTPRequest: {"node": item_node, "core_data": core_data} }
var active_downloads: Dictionary = {}

func _ready() -> void:
	_resolve_node_references()
	_init_directories()
	_setup_search()
	_setup_dropdowns()
	_fetch_all_boards()

func _process(_delta: float) -> void:
	_update_download_progresses()

# --- 1. Robust Node Resolution ---

func _resolve_node_references() -> void:
	search = _find_node("Search", ["HBoxContainer/Search", "Search"]) as LineEdit
	boards_container = _find_node("BoardsContainer", ["ScrollContainer/BoardsContainer", "BoardsContainer"]) as VBoxContainer
	board_manufacturer_dropdown = _find_node("BoardManufacturerDropdown", ["HBoxContainer/BoardManufacturerDropdown", "HBoxContainer/HBoxContainer2/BoardManufacturerDropdown"]) as CustomDropdown
	available_board_dropdown = _find_node("AvailableBoardDropdown", ["HBoxContainer/AvailableBoardDropdown", "HBoxContainer/HBoxContainer2/AvailableBoardDropdown"]) as CustomDropdown
	board_type_dropdown = _find_node("BoardTypeDropdown", ["HBoxContainer/BoardTypeDropdown", "HBoxContainer/HBoxContainer2/BoardTypeDropdown"]) as CustomDropdown

func _find_node(unique_name: String, fallbacks: Array[String]) -> Node:
	if has_node("%" + unique_name):
		return get_node("%" + unique_name)
	for path in fallbacks:
		if has_node(path):
			return get_node(path)
	printerr("BoardManager Warning: Could not find node for '", unique_name, "'. Check scene hierarchy or enable 'Access as Unique Name'.")
	return null

# --- 2. File System & Pathing ---

func _init_directories() -> void:
	# Cross-platform paths come from the IDE: Documents on desktop, user://
	# inside a mobile sandbox.
	var ide_root: Node = get_node_or_null("/root/Ide")
	if ide_root != null:
		base_boards_dir = str(ide_root.get("boards_dir"))
	else:
		var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if not docs_dir.is_empty():
			base_boards_dir = docs_dir.path_join("CodisGames/CodisIDE/Boards")
		else:
			base_boards_dir = ProjectSettings.globalize_path("user://").path_join("CodisGames/CodisIDE/Boards")

	registries_dir = base_boards_dir.path_join(".Registries")
	_ensure_path_exists(registries_dir)

func _ensure_path_exists(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		var err = DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			printerr("Failed to create directory: ", path, " | Error code: ", err)

# Safe directory helper to strip trailing periods that crash Windows FS (e.g. 'S.r.l.')
func _safe_dir_name(raw_name: String) -> String:
	var safe_name = raw_name.validate_filename().strip_edges()
	while safe_name.ends_with("."):
		safe_name = safe_name.trim_suffix(".")
	return safe_name if not safe_name.is_empty() else "Unknown"

func _get_target_board_dir(author: String, arch: String) -> String:
	var clean_author = _safe_dir_name(author)
	var clean_arch = _safe_dir_name(arch)
	var target_dir = base_boards_dir.path_join(clean_author).path_join(clean_arch)
	_ensure_path_exists(target_dir)
	return target_dir

# --- 3. Setup UI Controls ---

func _setup_search() -> void:
	if search:
		search.placeholder_text = "Search boards by name, maintainer, or arch..."
		if not search.text_changed.is_connected(_on_search_text_changed):
			search.text_changed.connect(_on_search_text_changed)

func _setup_dropdowns() -> void:
	if available_board_dropdown:
		available_board_dropdown.button_text = "Select Target Board"
		available_board_dropdown.items = connected_ports

	if board_manufacturer_dropdown:
		board_manufacturer_dropdown.button_text = "Manufacturer: All"
		board_manufacturer_dropdown.items = ["All"]
		if not board_manufacturer_dropdown.item_selected.is_connected(_on_manufacturer_selected):
			board_manufacturer_dropdown.item_selected.connect(_on_manufacturer_selected)

	if board_type_dropdown:
		board_type_dropdown.button_text = "Type: All"
		board_type_dropdown.items = ["All"]
		if not board_type_dropdown.item_selected.is_connected(_on_type_selected):
			board_type_dropdown.item_selected.connect(_on_type_selected)

# --- 4. Downloading & Parsing Registries ---

func _fetch_all_boards() -> void:
	unique_cores.clear()
	unique_manufacturers.clear()
	unique_types.clear()
	requests_pending = PACKAGE_URLS.size()

	_show_loading_message("Downloading board registries (" + str(requests_pending) + " remaining)...")

	for url in PACKAGE_URLS:
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_registry_downloaded.bind(http_request, url))

		if http_request.request(url) != OK:
			_load_cached_registry(url.get_file())
			_decrement_pending_requests()

func _decrement_pending_requests() -> void:
	requests_pending -= 1
	if requests_pending > 0:
		_show_loading_message("Downloading... (" + str(requests_pending) + " remaining)")
	else:
		_finalize_board_list()

func _show_loading_message(message: String) -> void:
	if not boards_container: return
	for child in boards_container.get_children():
		child.queue_free()
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boards_container.add_child(label)

func _on_registry_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, url: String) -> void:
	http_request.queue_free()
	var filename = url.get_file()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_save_registry_file(filename, body)
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			_parse_package_index(json.data)
	else:
		_load_cached_registry(filename)

	_decrement_pending_requests()

func _save_registry_file(filename: String, body: PackedByteArray) -> void:
	var file_path = registries_dir.path_join(filename)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()

func _load_cached_registry(filename: String) -> void:
	var file_path = registries_dir.path_join(filename)
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(content) == OK:
				_parse_package_index(json.data)

func _parse_package_index(data: Dictionary) -> void:
	if data.has("packages"):
		for pkg in data["packages"]:
			var pkg_name = pkg.get("name", "unknown")
			var pkg_author = pkg.get("maintainer", "Unknown")
			var pkg_url = pkg.get("websiteURL", "")

			if pkg.has("platforms"):
				for platform in pkg["platforms"]:
					var arch = platform.get("architecture", "unknown")
					var core_id = pkg_name + ":" + arch
					var archive_url = platform.get("url", "")

					if not unique_cores.has(core_id):
						var category = platform.get("category", "General")
						unique_manufacturers[pkg_author] = true
						unique_types[arch.to_upper()] = true

						var board_folder = _get_target_board_dir(pkg_author, arch)
						var is_installed = FileAccess.file_exists(board_folder.path_join("installed.json"))

						unique_cores[core_id] = {
							"id": core_id,
							"name": platform.get("name", core_id),
							"author": pkg_author,
							"architecture": arch.to_upper(),
							"description": "Architecture: " + arch.to_upper() + " | Category: " + category,
							"url": pkg_url,
							"archive_url": archive_url,
							"installed": is_installed
						}

# --- 5. Filtering & Display ---

func _finalize_board_list() -> void:
	all_boards.clear()
	for key in unique_cores:
		all_boards.append(unique_cores[key])

	all_boards.sort_custom(func(a, b): return a["name"] < b["name"])

	if board_manufacturer_dropdown:
		var mfg_list: Array[String] = ["All"]
		var mfg_keys: Array = unique_manufacturers.keys()
		mfg_keys.sort()
		mfg_list.append_array(mfg_keys)
		board_manufacturer_dropdown.items = mfg_list

	if board_type_dropdown:
		var type_list: Array[String] = ["All"]
		var type_keys: Array = unique_types.keys()
		type_keys.sort()
		type_list.append_array(type_keys)
		board_type_dropdown.items = type_list

	_apply_filters()

func _apply_filters() -> void:
	if not boards_container: return

	for child in boards_container.get_children():
		child.queue_free()

	var matched_count = 0
	for core_data in all_boards:
		if current_filter_manufacturer != "All" and core_data["author"] != current_filter_manufacturer:
			continue
		if current_filter_type != "All" and core_data["architecture"] != current_filter_type:
			continue
		if not current_search_query.is_empty():
			var search_space = (core_data["name"] + " " + core_data["author"] + " " + core_data["architecture"]).to_lower()
			if not search_space.contains(current_search_query):
				continue

		matched_count += 1
		var item = BOARDS.instantiate()
		boards_container.add_child(item)
		item.setup(core_data)
		item.install_requested.connect(_on_core_install_requested)
		item.remove_requested.connect(_on_core_remove_requested)

	if matched_count == 0:
		var label = Label.new()
		label.text = "No matching boards found."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boards_container.add_child(label)

# --- 6. Installation & Downloads ---

func _on_core_install_requested(core_data: Dictionary, item_node: Node) -> void:
	var download_url = core_data.get("archive_url", "")

	if download_url.is_empty():
		_install_via_cli(core_data, item_node)
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)

	active_downloads[http_request] = {
		"node": item_node,
		"core_data": core_data
	}

	http_request.request_completed.connect(_on_board_archive_downloaded.bind(http_request))

	if http_request.request(download_url) != OK:
		active_downloads.erase(http_request)
		http_request.queue_free()
		if is_instance_valid(item_node):
			item_node.set_installed_state(false)

func _update_download_progresses() -> void:
	for http_request in active_downloads.keys():
		var body_size = http_request.get_body_size()
		var downloaded = http_request.get_downloaded_bytes()

		if body_size > 0:
			var percent = int((float(downloaded) / float(body_size)) * 100)
			var item_node = active_downloads[http_request]["node"]
			if is_instance_valid(item_node):
				item_node.update_progress(percent)

func _on_board_archive_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	var info = active_downloads.get(http_request, {})
	active_downloads.erase(http_request)
	http_request.queue_free()

	if info.is_empty(): return
	var item_node = info["node"]
	var core_data = info["core_data"]

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var board_dir = _get_target_board_dir(core_data["author"], core_data["architecture"])
		var file_path = board_dir.path_join("package.zip")
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()

			var marker = FileAccess.open(board_dir.path_join("installed.json"), FileAccess.WRITE)
			if marker:
				marker.store_string(JSON.stringify(core_data))
				marker.close()

		if is_instance_valid(item_node):
			item_node.set_installed_state(true)
	else:
		if is_instance_valid(item_node):
			item_node.set_installed_state(false)

func _install_via_cli(core_data: Dictionary, item_node: Node) -> void:
	var output: Array = []
	var exit_code: int = -1
	if Platform.supports_subprocess():
		exit_code = OS.execute("arduino-cli", ["core", "install", core_data["id"]], output, true)
	if exit_code == 0:
		var board_dir = _get_target_board_dir(core_data["author"], core_data["architecture"])
		var marker = FileAccess.open(board_dir.path_join("installed.json"), FileAccess.WRITE)
		if marker:
			marker.store_string(JSON.stringify(core_data))
			marker.close()
		if is_instance_valid(item_node):
			item_node.set_installed_state(true)
	else:
		if is_instance_valid(item_node):
			item_node.set_installed_state(false)

# --- 7. Removal & Cleanup ---

func _on_core_remove_requested(core_data: Dictionary, item_node: Node) -> void:
	var author: String = core_data.get("author", "")
	var arch: String = core_data.get("architecture", "")
	var core_id: String = core_data.get("id", "")

	var board_dir = _get_target_board_dir(author, arch)
	if DirAccess.dir_exists_absolute(board_dir):
		_remove_directory_recursive(board_dir)

	if not core_id.is_empty() and Platform.supports_subprocess():
		var output: Array = []
		OS.execute("arduino-cli", ["core", "uninstall", core_id], output, true)

	if is_instance_valid(item_node):
		item_node.set_installed_state(false)

func _remove_directory_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = path.path_join(file_name)
				if dir.current_is_dir():
					_remove_directory_recursive(full_path)
				else:
					DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)

# --- 8. Event Handlers ---

func _on_search_text_changed(new_text: String) -> void:
	current_search_query = new_text.strip_edges().to_lower()
	_apply_filters()

func _on_manufacturer_selected(_index: int, text: String) -> void:
	if board_manufacturer_dropdown:
		board_manufacturer_dropdown.button_text = "Manufacturer: " + text
	current_filter_manufacturer = text
	_apply_filters()

func _on_type_selected(_index: int, text: String) -> void:
	if board_type_dropdown:
		board_type_dropdown.button_text = "Type: " + text
	current_filter_type = text
	_apply_filters()
