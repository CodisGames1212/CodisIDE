extends Control

# Signals pass model data, local save path, and node reference back to the Model Manager.
signal install_requested(model_data: Dictionary, download_path: String, item_node: Node)
signal remove_requested(model_data: Dictionary, item_node: Node)

@onready var model_name: Label = $VBoxContainer/ModelName
@onready var storage: Label = $VBoxContainer/HBoxContainer3/HBoxContainer/Storage
@onready var ram: Label = $VBoxContainer/HBoxContainer3/HBoxContainer2/RAM
@onready var paramenter: Label = $VBoxContainer/HBoxContainer3/HBoxContainer3/Paramenter
@onready var description: Label = $VBoxContainer/Description
@onready var learn_more: LinkButton = $VBoxContainer/HBoxContainer2/LearnMore
@onready var install: Button = $VBoxContainer/HBoxContainer2/Install

# -------------------------------------------------------------------
# Configuration & Constants
# -------------------------------------------------------------------

const BASE_SAVE_SUBPATH: String = "CodisGames/CodisIDE/AI/Models"

# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

var model_data: Dictionary = {}

var is_installed: bool = false
var is_installing: bool = false

var target_download_path: String = ""
var hf_repo_id: String = "" # e.g. "TheBloke/Llama-2-7B-GGUF"


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

## Called by the AI Model Manager when instantiating this item.
func setup(data: Dictionary) -> void:
	model_data = data.duplicate(true)

	# ---------------------------------------------------------------
	# HuggingFace & Directory Details
	# ---------------------------------------------------------------

	hf_repo_id = _get_string(data, "repo_id", _get_string(data, "hf_repo", ""))

	# Determine folder path on disk
	var folder_name: String = _get_string(data, "folder_name", hf_repo_id.replace("/", "_"))
	target_download_path = _get_models_base_dir().path_join(folder_name)

	# Check disk state to see if model folder exists
	is_installed = DirAccess.dir_exists_absolute(target_download_path) or bool(data.get("installed", false))
	is_installing = false

	# ---------------------------------------------------------------
	# Basic UI Metadata
	# ---------------------------------------------------------------

	if model_name:
		model_name.text = _get_string(data, "name", hf_repo_id if not hf_repo_id.is_empty() else "Unknown Model")

	if description:
		description.text = _get_string(data, "description", "No description available.")

	if storage:
		storage.text = _get_string(data, "storage", "N/A")

	if ram:
		ram.text = _get_string(data, "ram", "N/A")

	if paramenter:
		paramenter.text = _get_string(data, "parameters", _get_string(data, "parameter", "N/A"))

	# ---------------------------------------------------------------
	# Website / HuggingFace Repo Link
	# ---------------------------------------------------------------

	_setup_learn_more(data)

	# ---------------------------------------------------------------
	# UI State
	# ---------------------------------------------------------------

	_update_ui_state()


# -------------------------------------------------------------------
# Learn More Link Setup
# -------------------------------------------------------------------

func _setup_learn_more(data: Dictionary) -> void:
	if not learn_more:
		return

	var url: String = _get_string(data, "url", _get_string(data, "website", ""))

	# Fallback to standard HuggingFace URL if repo_id exists
	if url.is_empty() and not hf_repo_id.is_empty():
		url = "https://huggingface.co/" + hf_repo_id

	url = url.strip_edges()

	if url.is_empty():
		learn_more.hide()
		return

	learn_more.uri = url
	learn_more.show()


# -------------------------------------------------------------------
# Directory Utilities
# -------------------------------------------------------------------

## Resolves the target directory: Documents/CodisGames/CodisIDE/AI/Models
func _get_models_base_dir() -> String:
	# Single cross-platform source of truth: the IDE resolves Documents
	# (desktop) or user:// (mobile sandbox) and exposes the Models folder.
	var ide_root: Node = get_node_or_null("/root/Ide")
	if ide_root != null:
		return str(ide_root.get("models_dir"))
	var docs_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs_dir.is_empty():
		return ProjectSettings.globalize_path("user://").path_join(BASE_SAVE_SUBPATH)
	return docs_dir.path_join(BASE_SAVE_SUBPATH)


# -------------------------------------------------------------------
# UI state
# -------------------------------------------------------------------

## Updates the Install/Download button based on the current model state.
func _update_ui_state() -> void:
	if not install:
		return

	if is_installing:
		install.disabled = true
		install.text = "Downloading..."
		return

	install.disabled = false

	# ---------------------------------------------------------------
	# Not installed -> Download / Install Model
	# ---------------------------------------------------------------
	if not is_installed:
		install.text = "Download Model"
		install.modulate = Color(0.3, 0.8, 0.3, 1.0)
		return

	# ---------------------------------------------------------------
	# Installed -> Remove / Delete Model
	# ---------------------------------------------------------------
	install.text = "Delete Model"
	install.modulate = Color(0.8, 0.3, 0.3, 1.0)


# -------------------------------------------------------------------
# Download Progress
# -------------------------------------------------------------------

## Called continuously during active downloads from HTTP/HF downloader manager.
func update_progress(percent: int) -> void:
	is_installing = true
	percent = clampi(percent, 0, 100)

	if install:
		install.disabled = true
		install.text = "Downloading (" + str(percent) + "%)"


# -------------------------------------------------------------------
# Installation state setters
# -------------------------------------------------------------------

## Sets the final state after model download or removal finishes.
func set_installed_state(installed: bool) -> void:
	is_installed = installed
	is_installing = false

	model_data["installed"] = is_installed
	model_data["download_path"] = target_download_path if is_installed else ""

	if install:
		install.disabled = false

	_update_ui_state()


# -------------------------------------------------------------------
# Event Handlers
# -------------------------------------------------------------------

func _on_install_pressed() -> void:
	if is_installing:
		return

	if hf_repo_id.is_empty():
		push_warning("Cannot download model: Missing HuggingFace repo_id in model data.")
		return

	# ---------------------------------------------------------------
	# Remove installed model
	# ---------------------------------------------------------------
	if is_installed:
		is_installing = true

		if install:
			install.disabled = true
			install.text = "Deleting..."

		remove_requested.emit(model_data, self)
		return

	# ---------------------------------------------------------------
	# Download / Install model
	# ---------------------------------------------------------------
	is_installing = true

	if install:
		install.disabled = true
		install.text = "Downloading (0%)"

	# Include resolved target folder in data dictionary for downloader reference
	var active_data: Dictionary = model_data.duplicate()
	active_data["download_path"] = target_download_path
	active_data["repo_id"] = hf_repo_id

	install_requested.emit(active_data, target_download_path, self)


# -------------------------------------------------------------------
# Helper Utility
# -------------------------------------------------------------------

func _get_string(data: Dictionary, key: String, fallback: String = "") -> String:
	var value = data.get(key, fallback)

	if value == null:
		return fallback

	var result: String = str(value).strip_edges()

	if result.is_empty():
		return fallback

	return result
