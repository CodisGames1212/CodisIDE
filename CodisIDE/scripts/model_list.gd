extends VBoxContainer

@onready var model_search: LineEdit = $ModelSearch
@onready var model_container: VBoxContainer = $ScrollContainer/ModelContainer

const MODEL = preload("uid://bmyf0rk0h0hd7")

# Default Hugging Face API Endpoint for model searches
const HF_API_URL: String = "https://huggingface.co/api/models"

# Mobile Compatibility Constraints
const MAX_MOBILE_PARAMS_B: float = 3.0  # Max 3 Billion parameters for mobile capability
const MOBILE_LIBRARIES: Array[String] = ["gguf", "onnx", "tflite", "onnxruntime"]

# Only free, open-source model families are offered (image/closed models skipped).
const OPEN_SOURCE_FAMILIES: Array[String] = [
	"gemma", "qwen", "smollm", "llama", "phi", "mistral", "deepseek",
	"tinyllama", "granite", "falcon", "olmo", "stablelm", "zephyr",
]

# Dynamic Node References
var search: LineEdit
var library_type: CustomDropdown
var library_topic: CustomDropdown
var scroll_container: ScrollContainer
var models_container: VBoxContainer

# Tracking models & registries
var all_models: Array[Dictionary] = []
var filtered_models: Array[Dictionary] = [] # Cache of filtered results
var unique_types: Dictionary = {}
var unique_topics: Dictionary = {}

var current_filter_type: String = "All"
var current_filter_topic: String = "All"
var current_search_query: String = ""

# Directory paths
var base_models_dir: String = ""

# Active downloads tracker
var active_downloads: Dictionary = {}

# --- Virtualization Parameters ---
@export var ITEM_HEIGHT: float = 120.0  # Estimated height of each Model item row
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
	_fetch_models()

func _process(_delta: float) -> void:
	_update_download_progresses()

# --- 1. Robust Node Resolution ---

func _resolve_node_references() -> void:
	search = model_search if model_search else (_find_node("Search", ["ModelSearch", "HBoxContainer/Search", "Search"]) as LineEdit)
	models_container = model_container if model_container else (_find_node("ModelsContainer", ["ScrollContainer/ModelContainer", "ScrollContainer/ModelsContainer", "ModelsContainer"]) as VBoxContainer)

	scroll_container = _find_node("ScrollContainer", ["ScrollContainer"]) as ScrollContainer
	# These live on the LibraryManager tab; absent here is expected, not an error.
	library_type = _find_node("LibraryType", ["HBoxContainer/HBoxContainer2/LibraryType", "HBoxContainer/LibraryType"], true) as CustomDropdown
	library_topic = _find_node("LibraryTopic", ["HBoxContainer/HBoxContainer2/LibraryTopic", "HBoxContainer/LibraryTopic"], true) as CustomDropdown

func _find_node(unique_name: String, fallbacks: Array[String], optional: bool = false) -> Node:
	if has_node("%" + unique_name):
		return get_node("%" + unique_name)
	for path in fallbacks:
		if has_node(path):
			return get_node(path)
	if not optional:
		printerr("ModelManager Warning: Could not find node for '", unique_name, "'. Check scene hierarchy or enable 'Access as Unique Name'.")
	return null

# --- 2. File System Setup ---

func _init_directories() -> void:
	# Cross-platform paths come from the IDE: Documents on desktop, user://
	# inside a mobile sandbox.
	var ide_root: Node = get_node_or_null("/root/Ide")
	if ide_root != null:
		base_models_dir = str(ide_root.get("models_dir"))
	else:
		var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if not docs_dir.is_empty():
			base_models_dir = docs_dir.path_join("CodisGames/CodisIDE/AI/Models")
		else:
			base_models_dir = ProjectSettings.globalize_path("user://").path_join("CodisGames/CodisIDE/AI/Models")

	_ensure_path_exists(base_models_dir)

func _ensure_path_exists(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

func _safe_dir_name(raw_name: String) -> String:
	var safe_name = raw_name.validate_filename().strip_edges().replace("/", "_")
	while safe_name.ends_with("."):
		safe_name = safe_name.trim_suffix(".")
	return safe_name if not safe_name.is_empty() else "UnknownModel"

func _get_target_model_dir(repo_id: String) -> String:
	var clean_name = _safe_dir_name(repo_id)
	var target_dir = base_models_dir.path_join(clean_name)
	return target_dir

# --- 3. Setup Controls ---

func _setup_search() -> void:
	if search:
		search.placeholder_text = "Search HuggingFace models..."
		if not search.text_changed.is_connected(_on_search_text_changed):
			search.text_changed.connect(_on_search_text_changed)
		if not search.text_submitted.is_connected(_on_search_submitted):
			search.text_submitted.connect(_on_search_submitted)

func _setup_dropdowns() -> void:
	if library_type:
		library_type.button_text = "Task: All"
		library_type.items = ["All"]
		if not library_type.item_selected.is_connected(_on_type_selected):
			library_type.item_selected.connect(_on_type_selected)

	if library_topic:
		library_topic.button_text = "Library: All"
		library_topic.items = ["All"]
		if not library_topic.item_selected.is_connected(_on_topic_selected):
			library_topic.item_selected.connect(_on_topic_selected)

func _setup_scroll_listener() -> void:
	if scroll_container:
		var v_scroll = scroll_container.get_v_scroll_bar()
		if v_scroll and not v_scroll.value_changed.is_connected(_on_scroll_changed):
			v_scroll.value_changed.connect(_on_scroll_changed)

# --- 4. Fetching & Parsing HuggingFace Models ---

func _fetch_models(search_term: String = "") -> void:
	_show_loading_message("Fetching mobile-compatible AI models...")

	# Request models sorted by downloads to surface lightweight, highly popular models
	var url = HF_API_URL + "?limit=100&full=true&sort=downloads"
	if not search_term.is_empty():
		url += "&search=" + search_term.uri_encode()

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_models_downloaded.bind(http_request))

	if http_request.request(url) != OK:
		http_request.queue_free()
		_show_loading_message("Failed to connect to HuggingFace.")

func _show_loading_message(message: String) -> void:
	var target_container = model_container if model_container else models_container
	if not target_container: return

	for child in target_container.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_container.add_child(label)

func _on_models_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
			_parse_models_json(json.data)
			_finalize_model_list()
			return

	_show_loading_message("Failed to download model list.")

func _parse_models_json(models_array: Array) -> void:
	all_models.clear()
	unique_types.clear()
	unique_topics.clear()

	for item in models_array:
		if not item is Dictionary: continue

		var repo_id: String = item.get("id", "")
		if repo_id.is_empty(): continue

		var tags: Array = item.get("tags", [])
		var library_name: String = "Other"

		# Identify mobile-supported framework/formats
		for tag in tags:
			if tag is String:
				var lower_tag = tag.to_lower()
				if lower_tag in MOBILE_LIBRARIES:
					library_name = lower_tag
					break

		# Filter out models that do not use mobile-friendly runtimes
		if library_name == "Other":
			continue

		# Keep only open-source model families (Gemma, Qwen, SmolLM, ...).
		if not _is_open_source(repo_id):
			continue

		# Check model parameters size
		var params_str = _extract_parameter_count(repo_id)
		var param_val = _parse_parameter_value(params_str)

		# Filter out models exceeding mobile parameter limit (3B)
		if param_val > MAX_MOBILE_PARAMS_B:
			continue

		var pipeline_tag: String = item.get("pipeline_tag", "uncategorized")
		if pipeline_tag.is_empty(): pipeline_tag = "uncategorized"

		unique_types[pipeline_tag] = true
		unique_topics[library_name] = true

		var target_dir = _get_target_model_dir(repo_id)
		var is_installed = _directory_has_files(target_dir)

		var likes = item.get("likes", 0)
		var downloads = item.get("downloads", 0)
		var desc = "Likes: " + str(likes) + " | Downloads: " + str(downloads)

		# Mobile estimation metrics
		var storage_str = "< 2.0 GB" if param_val <= 1.0 else "~2.5 GB"
		var ram_str = "< 2.0 GB" if param_val <= 1.0 else "~3.5 GB"

		all_models.append({
			"name": repo_id,
			"repo_id": repo_id,
			"type": pipeline_tag,
			"category": library_name,
			"description": desc,
			"storage": storage_str,
			"ram": ram_str,
			"parameters": params_str,
			"url": "https://huggingface.co/" + repo_id,
			"installed": is_installed,
			"download_path": target_dir if is_installed else ""
		})

## True when the repository belongs to a known open-source model family.
func _is_open_source(repo_id: String) -> bool:
	var lower_id := repo_id.to_lower()
	for family in OPEN_SOURCE_FAMILIES:
		if lower_id.contains(family):
			return true
	return false


func _extract_parameter_count(repo_id: String) -> String:
	var lower_id = repo_id.to_lower()
	var regex = RegEx.new()
	regex.compile("(\\d+(\\.\\d+)?)[b|m]")
	var match = regex.search(lower_id)
	if match:
		return match.get_string().to_upper()
	return "N/A"

func _parse_parameter_value(param_str: String) -> float:
	if param_str == "N/A":
		return 1.0 # Default fallback assumption for unlabelled small models

	var val_str = param_str.substr(0, param_str.length() - 1)
	var unit = param_str.right(1).to_upper()
	var val = val_str.to_float()

	if unit == "M":
		return val / 1000.0 # Convert Million to Billion
	return val

func _directory_has_files(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				dir.list_dir_end()
				return true
			file_name = dir.get_next()
		dir.list_dir_end()
	return false

# --- 5. Filtering & Virtualized Display ---

func _finalize_model_list() -> void:
	all_models.sort_custom(func(a, b): return a["name"] < b["name"])

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
	filtered_models.clear()
	_last_first_visible = -1
	_last_last_visible = -1

	for model_data in all_models:
		if current_filter_type != "All" and model_data["type"] != current_filter_type:
			continue
		if current_filter_topic != "All" and model_data["category"] != current_filter_topic:
			continue
		if not current_search_query.is_empty():
			var search_space = (model_data["name"] + " " + model_data["type"] + " " + model_data["category"]).to_lower()
			if not search_space.contains(current_search_query):
				continue
		filtered_models.append(model_data)

	if scroll_container:
		scroll_container.scroll_vertical = 0

	_update_visible_items(true)

func _on_scroll_changed(_value: float) -> void:
	_update_visible_items(false)

func _update_visible_items(force_refresh: bool = false) -> void:
	var target_container = model_container if model_container else models_container
	if not target_container or not scroll_container: return

	var total_items = filtered_models.size()

	if total_items == 0:
		for child in target_container.get_children():
			child.queue_free()
		var label = Label.new()
		label.text = "No compatible mobile models found."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		target_container.add_child(label)
		return

	var scroll_y = scroll_container.scroll_vertical
	var viewport_h = scroll_container.size.y

	var first_visible = max(0, int(scroll_y / ITEM_HEIGHT) - BUFFER_ITEMS)
	var last_visible = min(total_items - 1, int((scroll_y + viewport_h) / ITEM_HEIGHT) + BUFFER_ITEMS)

	if not force_refresh and first_visible == _last_first_visible and last_visible == _last_last_visible:
		return

	_last_first_visible = first_visible
	_last_last_visible = last_visible

	for child in target_container.get_children():
		child.queue_free()

	# 1. Top Spacer
	_spacer_top = Control.new()
	_spacer_top.custom_minimum_size.y = first_visible * ITEM_HEIGHT
	target_container.add_child(_spacer_top)

	# 2. Render active slice directly into model_container
	for i in range(first_visible, last_visible + 1):
		var model_data = filtered_models[i]
		var item = MODEL.instantiate()
		target_container.add_child(item)
		item.setup(model_data)
		item.install_requested.connect(_on_model_install_requested)
		item.remove_requested.connect(_on_model_remove_requested)

		for req in active_downloads:
			if active_downloads[req]["model_data"]["name"] == model_data["name"]:
				active_downloads[req]["node"] = item

	# 3. Bottom Spacer
	var remaining_items = max(0, total_items - (last_visible + 1))
	_spacer_bottom = Control.new()
	_spacer_bottom.custom_minimum_size.y = remaining_items * ITEM_HEIGHT
	target_container.add_child(_spacer_bottom)

# --- 6. Installation & Progress ---

func _on_model_install_requested(model_data: Dictionary, download_path: String, item_node: Node) -> void:
	var repo_id: String = model_data.get("repo_id", "")
	if repo_id.is_empty():
		if is_instance_valid(item_node): item_node.set_installed_state(false)
		return

	var tree_url = "https://huggingface.co/api/models/" + repo_id + "/tree/main"
	var http_request = HTTPRequest.new()
	add_child(http_request)

	active_downloads[http_request] = {
		"node": item_node, "model_data": model_data, "target_path": download_path
	}

	http_request.request_completed.connect(_on_repo_tree_downloaded.bind(http_request))
	if http_request.request(tree_url) != OK:
		active_downloads.erase(http_request)
		http_request.queue_free()
		if is_instance_valid(item_node): item_node.set_installed_state(false)

func _on_repo_tree_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	var info = active_downloads.get(http_request, {})
	active_downloads.erase(http_request)
	http_request.queue_free()

	if info.is_empty(): return
	var item_node = info["node"]
	var model_data = info["model_data"]
	var target_path = info["target_path"]

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
			_download_model_files(json.data, model_data, target_path, item_node)
			return

	if is_instance_valid(item_node):
		item_node.set_installed_state(false)

func _download_model_files(files_tree: Array, model_data: Dictionary, target_path: String, item_node: Node) -> void:
	var repo_id: String = model_data.get("repo_id", "")
	_ensure_path_exists(target_path)

	for file_info in files_tree:
		if not file_info is Dictionary: continue
		var path_str: String = file_info.get("path", "")
		if path_str.is_empty() or path_str.begins_with("."): continue

		var file_url = "https://huggingface.co/" + repo_id + "/resolve/main/" + path_str
		var file_http = HTTPRequest.new()
		add_child(file_http)

		active_downloads[file_http] = {
			"node": item_node, "model_data": model_data, "file_path": target_path.path_join(path_str)
		}

		file_http.request_completed.connect(_on_model_file_downloaded.bind(file_http))
		file_http.request(file_url)

func _update_download_progresses() -> void:
	for http_request in active_downloads.keys():
		var body_size = http_request.get_body_size()
		var downloaded = http_request.get_downloaded_bytes()
		if body_size > 0:
			var percent = int((float(downloaded) / float(body_size)) * 100)
			var item_node = active_downloads[http_request]["node"]
			if is_instance_valid(item_node):
				item_node.update_progress(percent)

func _on_model_file_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	var info = active_downloads.get(http_request, {})
	active_downloads.erase(http_request)
	http_request.queue_free()

	if info.is_empty(): return
	var item_node = info["node"]
	var model_data = info["model_data"]
	var file_path = info["file_path"]

	if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 302):
		var base_dir = file_path.get_base_dir()
		_ensure_path_exists(base_dir)

		var f = FileAccess.open(file_path, FileAccess.WRITE)
		if f:
			f.store_buffer(body)
			f.close()

		model_data["installed"] = true
		model_data["download_path"] = file_path.get_base_dir()
		if is_instance_valid(item_node):
			item_node.set_installed_state(true)

# --- 7. Removal & Cleanup ---

func _on_model_remove_requested(model_data: Dictionary, item_node: Node) -> void:
	var repo_id: String = model_data.get("repo_id", "")
	var target_dir = _get_target_model_dir(repo_id)

	if DirAccess.dir_exists_absolute(target_dir):
		_remove_directory_recursive(target_dir)

	model_data["installed"] = false
	model_data["download_path"] = ""

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

func _on_search_submitted(new_text: String) -> void:
	current_search_query = new_text.strip_edges().to_lower()
	_fetch_models(current_search_query)

func _on_type_selected(_index: int, text: String) -> void:
	if library_type:
		library_type.button_text = "Task: " + text
	current_filter_type = text
	_apply_filters()

func _on_topic_selected(_index: int, text: String) -> void:
	if library_topic:
		library_topic.button_text = "Library: " + text
	current_filter_topic = text
	_apply_filters()
