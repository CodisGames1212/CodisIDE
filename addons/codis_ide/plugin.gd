@tool
extends EditorPlugin

## CodisIDE editor extension.
##
## Adds Project ▸ Tools entries so the CodisIDE data folder and the IDE itself
## are one click away from inside the Godot editor. This is the GDScript
## "extension" for the IDE — a native GDExtension would additionally require
## building godot-cpp with a matching toolchain.

const BASE_SUBDIR: String = "CodisGames/CodisIDE"
const TOOL_OPEN: String = "CodisIDE: Open Data Folder"
const TOOL_PLAY: String = "CodisIDE: Play IDE"


func _enter_tree() -> void:
	add_tool_menu_item(TOOL_OPEN, _open_data_folder)
	add_tool_menu_item(TOOL_PLAY, _play_ide)


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_OPEN)
	remove_tool_menu_item(TOOL_PLAY)


func _data_dir() -> String:
	var docs: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs.is_empty():
		return ProjectSettings.globalize_path("user://").path_join(BASE_SUBDIR)
	return docs.path_join(BASE_SUBDIR)


func _open_data_folder() -> void:
	var path: String = _data_dir()
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


func _play_ide() -> void:
	get_editor_interface().play_main_scene()
