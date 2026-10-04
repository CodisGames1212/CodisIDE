extends Control

# Signals pass library data, selected version, and node reference back to the Library Manager.
signal install_requested(lib_data: Dictionary, selected_version: String, item_node: Node)
signal remove_requested(lib_data: Dictionary, item_node: Node)

@onready var library_name: Label = $VBoxContainer/HBoxContainer/LibraryName
@onready var library_author: Label = $VBoxContainer/HBoxContainer/LibraryAuthor
@onready var description: Label = $VBoxContainer/Description
@onready var learn_more: LinkButton = $VBoxContainer/HBoxContainer2/LearnMore
@onready var install: Button = $VBoxContainer/HBoxContainer2/Install


# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

var lib_data: Dictionary = {}

var is_installed: bool = false
var is_installing: bool = false

var installed_version: String = ""
var selected_version: String = "" # Holds the latest version available


# -------------------------------------------------------------------
# Godot lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	if install:
		if not install.pressed.is_connected(_on_install_pressed):
			install.pressed.connect(_on_install_pressed)

	_update_ui_state()


# -------------------------------------------------------------------
# Public setup
# -------------------------------------------------------------------

## Called by the Library Manager when instantiating this item.
func setup(data: Dictionary) -> void:
	lib_data = data.duplicate(true)

	# ---------------------------------------------------------------
	# Basic information
	# ---------------------------------------------------------------

	if library_name:
		library_name.text = _get_string(data, "name", "Unknown Library")

	if library_author:
		var author: String = _get_string(data, "author", "Unknown")
		library_author.text = "by " + author

	if description:
		var desc: String = _get_string(
			data,
			"description",
			_get_string(data, "sentence", "No description available.")
		)

		description.text = desc

	# ---------------------------------------------------------------
	# Website / repository link
	# ---------------------------------------------------------------

	_setup_learn_more(data)

	# ---------------------------------------------------------------
	# Installation state
	# ---------------------------------------------------------------

	is_installed = bool(data.get("installed", false))
	installed_version = _normalize_version(
		str(data.get("installed_version", ""))
	)

	is_installing = false

	# ---------------------------------------------------------------
	# Determine latest version
	# ---------------------------------------------------------------

	_determine_latest_version(data)

	# ---------------------------------------------------------------
	# UI
	# ---------------------------------------------------------------

	_update_ui_state()


# -------------------------------------------------------------------
# Learn More
# -------------------------------------------------------------------

func _setup_learn_more(data: Dictionary) -> void:
	if not learn_more:
		return

	var url: String = _get_string(
		data,
		"website",
		_get_string(data, "url", "")
	)

	url = url.strip_edges()

	if url.is_empty():
		learn_more.hide()
		return

	learn_more.uri = url
	learn_more.show()


# -------------------------------------------------------------------
# Version handling
# -------------------------------------------------------------------

## Determines and sets the newest available version for installation.
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

	selected_version = valid_versions[0]


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


# -------------------------------------------------------------------
# Version comparison
# -------------------------------------------------------------------

## Returns true when A is newer than B.
func _is_version_newer(a: String, b: String) -> bool:
	return _compare_versions(a, b) > 0


## Returns true when A is older than B.
func _is_version_older(a: String, b: String) -> bool:
	return _compare_versions(a, b) < 0


## Returns:
##   1  if A > B
##   0  if A == B
##  -1  if A < B
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

	# If numeric components are identical, compare suffixes.
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
# UI state
# -------------------------------------------------------------------

## Updates the Install button based on the current library state.
func _update_ui_state() -> void:
	if not install:
		return

	if is_installing:
		install.disabled = true
		install.text = "Installing..."
		return

	install.disabled = false

	# ---------------------------------------------------------------
	# Not installed -> Install Latest
	# ---------------------------------------------------------------

	if not is_installed:
		install.text = "Install (v" + selected_version + ")"
		install.modulate = Color(0.3, 0.8, 0.3, 1.0)
		return

	# ---------------------------------------------------------------
	# Installed -> Check if Update Available or Remove
	# ---------------------------------------------------------------

	if not installed_version.is_empty() and _is_version_newer(selected_version, installed_version):
		install.text = "Update to v" + selected_version
		install.modulate = Color(0.3, 0.6, 0.9, 1.0)
		return

	# Up-to-date or version unknown -> Remove
	install.text = "Remove"
	if not installed_version.is_empty():
		install.text += " (v" + installed_version + ")"

	install.modulate = Color(0.8, 0.3, 0.3, 1.0)


# -------------------------------------------------------------------
# Download / installation progress
# -------------------------------------------------------------------

## Called continuously during active HTTP downloads.
func update_progress(percent: int) -> void:
	is_installing = true
	percent = clampi(percent, 0, 100)

	if install:
		install.disabled = true
		install.text = "Installing (" + str(percent) + "%)"


# -------------------------------------------------------------------
# Installation state
# -------------------------------------------------------------------

## Sets the final state after install, update, or removal.
func set_installed_state(installed: bool, version_str: String = "") -> void:
	is_installed = installed

	if installed:
		installed_version = _normalize_version(version_str)

		if installed_version.is_empty():
			installed_version = selected_version
	else:
		installed_version = ""

	is_installing = false

	# Keep the dictionary synchronized with the UI.
	lib_data["installed"] = is_installed

	if is_installed:
		lib_data["installed_version"] = installed_version
	else:
		lib_data.erase("installed_version")

	if install:
		install.disabled = false

	_update_ui_state()


# -------------------------------------------------------------------
# Event handlers
# -------------------------------------------------------------------

func _on_install_pressed() -> void:
	if is_installing:
		return

	if selected_version.is_empty():
		push_warning("Cannot install library: no valid version found.")
		return

	# ---------------------------------------------------------------
	# If installed & up-to-date -> Remove
	# ---------------------------------------------------------------

	if is_installed and not _is_version_newer(selected_version, installed_version):
		is_installing = true

		if install:
			install.disabled = true
			install.text = "Removing..."

		remove_requested.emit(lib_data, self)
		return

	# ---------------------------------------------------------------
	# Not installed OR an update is available -> Install Latest
	# ---------------------------------------------------------------

	is_installing = true

	if install:
		install.disabled = true
		install.text = "Installing (0%)"

	install_requested.emit(
		lib_data,
		selected_version,
		self
	)


# -------------------------------------------------------------------
# Utility
# -------------------------------------------------------------------

func _get_string(data: Dictionary, key: String, fallback: String = "") -> String:
	var value = data.get(key, fallback)

	if value == null:
		return fallback

	var result: String = str(value).strip_edges()

	if result.is_empty():
		return fallback

	return result
