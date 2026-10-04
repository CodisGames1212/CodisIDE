class_name Platform
extends RefCounted

## Small, dependency-free description of what the *current* platform can do.
##
## CodisIDE targets desktop **and** mobile (Android/iOS). These helpers let the
## rest of the IDE branch on capabilities instead of hard-coding platforms:
## mobile has no subprocess, no native file dialog and a sandboxed filesystem,
## so every feature that would break there is routed through here.

static func os_name() -> String:
	return OS.get_name()


static func is_mobile() -> bool:
	var n: String = OS.get_name()
	return n == "Android" or n == "iOS"


static func is_desktop() -> bool:
	var n: String = OS.get_name()
	return n == "Windows" or n == "macOS" or n == "Linux" or n == "X11" \
		or n == "FreeBSD" or n == "NetBSD" or n == "OpenBSD"


static func is_web() -> bool:
	return OS.get_name() == "Web"


## Mobile sandboxes forbid spawning external processes; there is no
## [method OS.execute] and no `PATH` to scan.
static func supports_subprocess() -> bool:
	return is_desktop()


## Native OS file dialogs are unavailable on mobile (and unreliable on some
## Linux setups). When false the IDE uses Godot's built-in [FileDialog].
static func supports_native_file_dialog() -> bool:
	return is_desktop()


## Whether `user://` paths should be used instead of absolute Documents paths.
static func uses_user_space() -> bool:
	return is_mobile() or is_web()


## Opens a folder in the OS file manager. Returns false when unsupported
## (mobile has no general-purpose folder browser to hand off to).
static func open_folder(path: String) -> bool:
	if not is_desktop():
		return false
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	return OS.shell_open(path) == OK


## Path separator for the host OS (`\` on Windows, `/` elsewhere).
static func path_separator() -> String:
	return "\\" if OS.get_name() == "Windows" else "/"


## Human-readable summary used in the About/Settings panel.
static func describe() -> String:
	var kind := "Mobile" if is_mobile() else ("Web" if is_web() else "Desktop")
	return "%s (%s)" % [os_name(), kind]
