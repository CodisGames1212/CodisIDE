extends Control

# Signals pass core_data, target version, and self so the Manager can target directory operations and update UI states
signal install_requested(core_data: Dictionary, target_version: String, item_node: Node)
signal remove_requested(core_data: Dictionary, item_node: Node)

@onready var board_name: Label = $VBoxContainer/HBoxContainer/BoardName
@onready var board_author: Label = $VBoxContainer/HBoxContainer/BoardAuthor
@onready var description: Label = $VBoxContainer/Description
@onready var learn_more: LinkButton = $VBoxContainer/HBoxContainer2/LearnMore
@onready var install: Button = $VBoxContainer/HBoxContainer2/Install


var core_data: Dictionary = {}
var is_installed: bool = false
var is_installing: bool = false

var installed_version: String = ""
var target_version: String = ""


func _ready() -> void:
	if install:
		if not install.pressed.is_connected(_on_install_pressed):
			install.pressed.connect(_on_install_pressed)

	_update_ui_state()


# Called by the Board Manager when instantiating this scene
func setup(data: Dictionary) -> void:
	core_data = data.duplicate(true)

	if board_name:
		board_name.text = data.get("name", "Unknown Board Family")
	if board_author:
		board_author.text = "by " + str(data.get("author", "Unknown"))
	if description:
		description.text = data.get("description", "No description available.")

	_setup_learn_more(data)

	is_installed = bool(data.get("installed", false))
	installed_version = _normalize_version(str(data.get("installed_version", "")))
	is_installing = false

	_determine_latest_version(data)
	_update_ui_state()


func _setup_learn_more(data: Dictionary) -> void:
	if not learn_more:
		return

	var url: String = str(data.get("url", data.get("website", ""))).strip_edges()
	if url.is_empty():
		learn_more.hide()
	else:
		learn_more.uri = url
		learn_more.show()


# -------------------------------------------------------------------
# Version handling
# -------------------------------------------------------------------

func _determine_latest_version(data: Dictionary) -> void:
	var versions: Array = []
	var versions_data = data.get("versions", [])

	if versions_data is Array:
		versions = versions_data

	var valid_versions: Array[String] = []

	for version_data in versions:
		var version_string: String = ""
		if version_data is Dictionary:
			version_string = str(version_data.get("version", ""))
		else:
			version_string = str(version_data)

		version_string = _normalize_version(version_string)

		if not version_string.is_empty() and not valid_versions.has(version_string):
			valid_versions.append(version_string)

	if valid_versions.is_empty():
		var fallback: String = _get_default_version(data)
		if fallback.is_empty():
			fallback = "1.0.0"
		valid_versions.append(fallback)

	# Sort newest -> oldest
	valid_versions.sort_custom(_compare_versions_descending)
	target_version = valid_versions[0]


func _get_default_version(data: Dictionary) -> String:
	var version: String = str(data.get("version", ""))
	if version.is_empty():
		version = str(data.get("latest_version", ""))
	return _normalize_version(version)


func _normalize_version(version: String) -> String:
	version = version.strip_edges()
	if version.begins_with("v") or version.begins_with("V"):
		version = version.substr(1)
	return version


func _is_version_newer(a: String, b: String) -> bool:
	return _compare_versions(a, b) > 0


func _compare_versions(a: String, b: String) -> int:
	var a_clean: String = _normalize_version(a)
	var b_clean: String = _normalize_version(b)

	var a_parts: PackedStringArray = a_clean.split(".")
	var b_parts: PackedStringArray = b_clean.split(".")

	var max_parts: int = maxi(a_parts.size(), b_parts.size())

	for i in range(max_parts):
		var a_part: String = "0"
		var b_part: String = "0"

		if i < a_parts.size():
			a_part = a_parts[i]
		if i < b_parts.size():
			b_part = b_parts[i]

		var a_number: int = _version_part_number(a_part)
		var b_number: int = _version_part_number(b_part)

		if a_number > b_number:
			return 1
		if a_number < b_number:
			return -1

	var a_suffix: String = _version_suffix(a_clean)
	var b_suffix: String = _version_suffix(b_clean)

	if a_suffix.is_empty() and not b_suffix.is_empty():
		return 1
	if not a_suffix.is_empty() and b_suffix.is_empty():
		return -1
	if a_suffix > b_suffix:
		return 1
	if a_suffix < b_suffix:
		return -1

	return 0


func _version_part_number(part: String) -> int:
	var number_text: String = ""
	for character in part:
		if character >= "0" and character <= "9":
			number_text += character
		else:
			break

	if number_text.is_empty():
		return 0
	return int(number_text)


func _version_suffix(version: String) -> String:
	var dash_index: int = version.find("-")
	if dash_index == -1:
		return ""
	return version.substr(dash_index + 1).to_lower()


func _compare_versions_descending(a: String, b: String) -> bool:
	return _compare_versions(a, b) > 0


# -------------------------------------------------------------------
# UI & State
# -------------------------------------------------------------------

# Updates button label and styling based on installed state & versions
func _update_ui_state() -> void:
	if not install:
		return

	if is_installing:
		install.disabled = true
		install.text = "Installing..."
		return

	install.disabled = false

	# State 1: Not installed
	if not is_installed:
		if target_version.is_empty():
			install.text = "Install"
		else:
			install.text = "Install (v" + target_version + ")"
		install.modulate = Color(0.3, 0.8, 0.3, 1.0) # Greenish tint
		return

	# State 2: Installed, but newer version available
	if not installed_version.is_empty() and _is_version_newer(target_version, installed_version):
		install.text = "Update to v" + target_version
		install.modulate = Color(0.3, 0.6, 0.9, 1.0) # Blueish tint
		return

	# State 3: Installed & Up-to-date
	install.text = "Remove"
	if not installed_version.is_empty():
		install.text += " (v" + installed_version + ")"
	install.modulate = Color(0.8, 0.3, 0.3, 1.0) # Reddish tint


# Called continuously by the Board Manager during active HTTP downloads
func update_progress(percent: int) -> void:
	is_installing = true
	percent = clampi(percent, 0, 100)
	if install:
		install.disabled = true
		install.text = "Installing (" + str(percent) + "%)"


# Sets final state after install, update, or removal finishes
func set_installed_state(installed: bool, version_str: String = "") -> void:
	is_installed = installed

	if installed:
		installed_version = _normalize_version(version_str)
		if installed_version.is_empty():
			installed_version = target_version
	else:
		installed_version = ""

	is_installing = false
	core_data["installed"] = is_installed

	if is_installed:
		core_data["installed_version"] = installed_version
	else:
		core_data.erase("installed_version")

	if install:
		install.disabled = false

	_update_ui_state()


func _on_install_pressed() -> void:
	if is_installing:
		return

	# Installed & up to date -> Remove
	if is_installed and not _is_version_newer(target_version, installed_version):
		is_installing = true
		if install:
			install.disabled = true
			install.text = "Removing..."
		remove_requested.emit(core_data, self)
		return

	# Not installed OR an update is available -> Install / Update
	is_installing = true
	if install:
		install.disabled = true
		install.text = "Installing (0%)"

	install_requested.emit(core_data, target_version, self)
