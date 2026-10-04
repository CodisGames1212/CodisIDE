extends VBoxContainer

const Library = preload("uid://bbjobmqom3c5k")

var PACKAGE_URLS: Array[String] = [
	"https://downloads.arduino.cc/libraries/library_index.json"
]

# Dynamic Node References
var search: LineEdit
var library_type: CustomDropdown
var library_topic: CustomDropdown
var scroll_container: ScrollContainer
var libraries_container: VBoxContainer

# Tracking libraries & registries
var unique_libraries: Dictionary = {}
var requests_pending: int = 0

var all_libraries: Array[Dictionary] = []
var filtered_libraries: Array[Dictionary] = [] # Cache of filtered results
var unique_types: Dictionary = {}
var unique_topics: Dictionary = {}

var current_filter_type: String = "All"
var current_filter_topic: String = "All"
var current_search_query: String = ""

# Directory paths
var base_libraries_dir: String = ""
var registries_dir: String = ""

# Active downloads tracker
var active_downloads: Dictionary = {}

# --- Virtualization Parameters ---
@export var ITEM_HEIGHT: float = 120.0  # Estimated height of each Library item row
@export var BUFFER_ITEMS: int = 5        # Items to render above and below visible area

var _spacer_top: Control
var _spacer_bottom: Control
var _last_first_visible: int = -1
var _last_last_visible: int = -1

func _ready() -> void:
	_resolve_node_references()
	_init_directories()
	_setup_search()
	_setup_dropdowns()
	_setup_scroll_listener()
	_fetch_all_libraries()

func _process(_delta: float) -> void:
	_update_download_progresses()

# --- 1. Robust Node Resolution ---

func _resolve_node_references() -> void:
	search = _find_node("Search", ["HBoxContainer/Search", "Search"]) as LineEdit
	scroll_container = _find_node("ScrollContainer", ["ScrollContainer"]) as ScrollContainer
	libraries_container = _find_node("LibrariesContainer", ["ScrollContainer/LibrariesContainer", "LibrariesContainer"]) as VBoxContainer
	library_type = _find_node("LibraryType", ["HBoxContainer/HBoxContainer2/LibraryType", "HBoxContainer/LibraryType"]) as CustomDropdown
	library_topic = _find_node("LibraryTopic", ["HBoxContainer/HBoxContainer2/LibraryTopic", "HBoxContainer/LibraryTopic"]) as CustomDropdown

func _find_node(unique_name: String, fallbacks: Array[String]) -> Node:
	if has_node("%" + unique_name):
		return get_node("%" + unique_name)
	for path in fallbacks:
		if has_node(path):
			return get_node(path)
	printerr("LibraryManager Warning: Could not find node for '", unique_name, "'. Check scene hierarchy or enable 'Access as Unique Name'.")
	return null

# --- 2. File System Setup ---

func _init_directories() -> void:
	# Cross-platform paths come from the IDE: Documents on desktop, user://
	# inside a mobile sandbox.
	var ide_root: Node = get_node_or_null("/root/Ide")
	if ide_root != null:
		base_libraries_dir = str(ide_root.get("libraries_dir"))
	else:
		var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if not docs_dir.is_empty():
			base_libraries_dir = docs_dir.path_join("CodisGames/CodisIDE/Libraries")
		else:
			base_libraries_dir = ProjectSettings.globalize_path("user://").path_join("CodisGames/CodisIDE/Libraries")

	registries_dir = base_libraries_dir.path_join(".Registries")
	_ensure_path_exists(registries_dir)

func _ensure_path_exists(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

func _safe_dir_name(raw_name: String) -> String:
	var safe_name = raw_name.validate_filename().strip_edges()
	while safe_name.ends_with("."):
		safe_name = safe_name.trim_suffix(".")
	return safe_name if not safe_name.is_empty() else "Unknown"

func _get_target_library_dir(lib_name: String) -> String:
	var clean_name = _safe_dir_name(lib_name)
	var target_dir = base_libraries_dir.path_join(clean_name)
	_ensure_path_exists(target_dir)
	return target_dir

# --- 3. Setup Controls ---

func _setup_search() -> void:
	if search:
		search.placeholder_text = "Search libraries by name, author, or keyword..."
		if not search.text_changed.is_connected(_on_search_text_changed):
			search.text_changed.connect(_on_search_text_changed)

func _setup_dropdowns() -> void:
	if library_type:
		library_type.button_text = "Type: All"
		library_type.items = ["All"]
		if not library_type.item_selected.is_connected(_on_type_selected):
			library_type.item_selected.connect(_on_type_selected)

	if library_topic:
		library_topic.button_text = "Topic: All"
		library_topic.items = ["All"]
		if not library_topic.item_selected.is_connected(_on_topic_selected):
			library_topic.item_selected.connect(_on_topic_selected)

func _setup_scroll_listener() -> void:
	if scroll_container:
		var v_scroll = scroll_container.get_v_scroll_bar()
		if v_scroll and not v_scroll.value_changed.is_connected(_on_scroll_changed):
			v_scroll.value_changed.connect(_on_scroll_changed)

# --- 4. Registry Downloading & Parsing ---

func _fetch_all_libraries() -> void:
	unique_libraries.clear()
	unique_types.clear()
	unique_topics.clear()
	requests_pending = PACKAGE_URLS.size()

	_show_loading_message("Downloading library registries (" + str(requests_pending) + " remaining)...")

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
		_finalize_library_list()

func _show_loading_message(message: String) -> void:
	if not libraries_container: return
	for child in libraries_container.get_children():
		child.queue_free()
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	libraries_container.add_child(label)

func _on_registry_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, url: String) -> void:
	http_request.queue_free()
	var filename = url.get_file()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_save_registry_file(filename, body)
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			_parse_library_index(json.data)
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
				_parse_library_index(json.data)

func _parse_library_index(data: Dictionary) -> void:
	if data.has("libraries"):
		for lib in data["libraries"]:
			var lib_name: String = lib.get("name", "")
			if lib_name.is_empty(): continue

			var key = lib_name.to_lower()
			var author = lib.get("author", lib.get("maintainer", "Unknown"))
			var category = lib.get("category", "Uncategorized")
			var types_array = lib.get("types", ["Contributed"])
			var lib_type = types_array[0] if types_array.size() > 0 else "Contributed"
			var version_str = lib.get("version", "1.0.0")
			var download_url = lib.get("url", "")

			if not unique_libraries.has(key):
				unique_types[lib_type] = true
				unique_topics[category] = true

				var target_dir = _get_target_library_dir(lib_name)
				var marker_path = target_dir.path_join("installed.json")
				var is_installed = false
				var installed_version = ""

				if FileAccess.file_exists(marker_path):
					var file = FileAccess.open(marker_path, FileAccess.READ)
					if file:
						var json = JSON.new()
						if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
							is_installed = true
							installed_version = json.data.get("version", "")
						file.close()

				unique_libraries[key] = {
					"name": lib_name,
					"author": author,
					"sentence": lib.get("sentence", ""),
					"description": lib.get("paragraph", lib.get("sentence", "No description available.")),
					"website": lib.get("website", ""),
					"category": category,
					"type": lib_type,
					"installed": is_installed,
					"installed_version": installed_version,
					"versions": [],
					"version_map": {}
				}

			if not unique_libraries[key]["version_map"].has(version_str):
				unique_libraries[key]["version_map"][version_str] = download_url
				unique_libraries[key]["versions"].append(version_str)

# --- 5. Filtering & Virtualized Display ---

func _finalize_library_list() -> void:
	all_libraries.clear()
	for key in unique_libraries:
		var lib_data = unique_libraries[key]
		lib_data["versions"].sort_custom(func(a, b): return a.naturalnocasecmp_to(b) > 0)
		all_libraries.append(lib_data)

	all_libraries.sort_custom(func(a, b): return a["name"] < b["name"])

	if library_type:
		var type_list: Array[String] = ["All"]
		var type_keys: Array = unique_types.keys()
		type_keys.sort()
		type_list.append_array(type_keys)
		library_type.items = type_list

	if library_topic:
		var topic_list: Array[String] = ["All"]
		var topic_keys: Array = unique_topics.keys()
		topic_keys.sort()
		topic_list.append_array(topic_keys)
		library_topic.items = topic_list

	_apply_filters()

func _apply_filters() -> void:
	filtered_libraries.clear()
	_last_first_visible = -1
	_last_last_visible = -1

	for lib_data in all_libraries:
		if current_filter_type != "All" and lib_data["type"] != current_filter_type:
			continue
		if current_filter_topic != "All" and lib_data["category"] != current_filter_topic:
			continue
		if not current_search_query.is_empty():
			var search_space = (lib_data["name"] + " " + lib_data["author"] + " " + lib_data["category"] + " " + lib_data["sentence"]).to_lower()
			if not search_space.contains(current_search_query):
				continue
		filtered_libraries.append(lib_data)

	if scroll_container:
		scroll_container.scroll_vertical = 0

	_update_visible_items(true)

func _on_scroll_changed(_value: float) -> void:
	_update_visible_items(false)

func _update_visible_items(force_refresh: bool = false) -> void:
	if not libraries_container or not scroll_container: return

	var total_items = filtered_libraries.size()

	if total_items == 0:
		for child in libraries_container.get_children():
			child.queue_free()
		var label = Label.new()
		label.text = "No matching libraries found."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		libraries_container.add_child(label)
		return

	var scroll_y = scroll_container.scroll_vertical
	var viewport_h = scroll_container.size.y

	var first_visible = max(0, int(scroll_y / ITEM_HEIGHT) - BUFFER_ITEMS)
	var last_visible = min(total_items - 1, int((scroll_y + viewport_h) / ITEM_HEIGHT) + BUFFER_ITEMS)

	# Avoid unnecessary DOM manipulations if visible slice hasn't changed
	if not force_refresh and first_visible == _last_first_visible and last_visible == _last_last_visible:
		return

	_last_first_visible = first_visible
	_last_last_visible = last_visible

	# Clean up previous container state
	for child in libraries_container.get_children():
		child.queue_free()

	# 1. Top Spacer
	_spacer_top = Control.new()
	_spacer_top.custom_minimum_size.y = first_visible * ITEM_HEIGHT
	libraries_container.add_child(_spacer_top)

	# 2. Render only the active slice
	for i in range(first_visible, last_visible + 1):
		var lib_data = filtered_libraries[i]
		var item = Library.instantiate()
		libraries_container.add_child(item)
		item.setup(lib_data)
		item.install_requested.connect(_on_library_install_requested)
		item.remove_requested.connect(_on_library_remove_requested)

		# Re-bind node to active download tracker if in progress
		for req in active_downloads:
			if active_downloads[req]["lib_data"]["name"] == lib_data["name"]:
				active_downloads[req]["node"] = item

	# 3. Bottom Spacer
	var remaining_items = max(0, total_items - (last_visible + 1))
	_spacer_bottom = Control.new()
	_spacer_bottom.custom_minimum_size.y = remaining_items * ITEM_HEIGHT
	libraries_container.add_child(_spacer_bottom)

# --- 6. Installation, Extraction & Progress ---

func _on_library_install_requested(lib_data: Dictionary, selected_version: String, item_node: Node) -> void:
	var download_url: String = lib_data.get("version_map", {}).get(selected_version, "")
	if download_url.is_empty():
		if is_instance_valid(item_node): item_node.set_installed_state(false)
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)

	active_downloads[http_request] = {
		"node": item_node, "lib_data": lib_data, "version": selected_version
	}

	http_request.request_completed.connect(_on_library_downloaded.bind(http_request))
	if http_request.request(download_url) != OK:
		active_downloads.erase(http_request)
		http_request.queue_free()
		if is_instance_valid(item_node): item_node.set_installed_state(false)

func _update_download_progresses() -> void:
	for http_request in active_downloads.keys():
		var body_size = http_request.get_body_size()
		var downloaded = http_request.get_downloaded_bytes()
		if body_size > 0:
			var percent = int((float(downloaded) / float(body_size)) * 100)
			var item_node = active_downloads[http_request]["node"]
			if is_instance_valid(item_node):
				item_node.update_progress(percent)

func _on_library_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	var info = active_downloads.get(http_request, {})
	active_downloads.erase(http_request)
	http_request.queue_free()

	if info.is_empty(): return
	var item_node = info["node"]
	var lib_data = info["lib_data"]
	var selected_version = info["version"]

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var target_dir = _get_target_library_dir(lib_data["name"])
		var zip_path = target_dir.path_join("temp_library.zip")

		var file = FileAccess.open(zip_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()

			_extract_zip(zip_path, target_dir)
			DirAccess.remove_absolute(zip_path)

			var marker = FileAccess.open(target_dir.path_join("installed.json"), FileAccess.WRITE)
			if marker:
				var save_data = {"name": lib_data["name"], "version": selected_version, "author": lib_data["author"]}
				marker.store_string(JSON.stringify(save_data))
				marker.close()

		lib_data["installed"] = true
		lib_data["installed_version"] = selected_version

		if is_instance_valid(item_node):
			item_node.set_installed_state(true, selected_version)
	else:
		if is_instance_valid(item_node):
			item_node.set_installed_state(false)

func _extract_zip(zip_path: String, dest_dir: String) -> void:
	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	if err != OK:
		printerr("Failed to open ZIP: ", zip_path)
		return

	for file_name in reader.get_files():
		var out_path = dest_dir.path_join(file_name)

		if file_name.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(out_path)
		else:
			var base = out_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(base):
				DirAccess.make_dir_recursive_absolute(base)

			var f = FileAccess.open(out_path, FileAccess.WRITE)
			if f:
				f.store_buffer(reader.read_file(file_name))
				f.close()

	reader.close()

# --- 7. Removal & Cleanup ---

func _on_library_remove_requested(lib_data: Dictionary, item_node: Node) -> void:
	var lib_name: String = lib_data.get("name", "")
	var target_dir = _get_target_library_dir(lib_name)

	if DirAccess.dir_exists_absolute(target_dir):
		_remove_directory_recursive(target_dir)

	lib_data["installed"] = false
	lib_data["installed_version"] = ""

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

func _on_type_selected(_index: int, text: String) -> void:
	if library_type:
		library_type.button_text = "Type: " + text
	current_filter_type = text
	_apply_filters()

func _on_topic_selected(_index: int, text: String) -> void:
	if library_topic:
		library_topic.button_text = "Topic: " + text
	current_filter_topic = text
	_apply_filters()
