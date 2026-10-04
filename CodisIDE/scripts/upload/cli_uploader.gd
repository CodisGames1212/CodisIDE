class_name CliUploader
extends UploaderPlugin

## Desktop backend that shells out to `arduino-cli` to compile and flash.
##
## Only available where [method Platform.supports_subprocess] is true and the
## tool is on `PATH`, so it never appears on mobile.

func _init() -> void:
	id = "arduino_cli"
	display_name = "Arduino CLI (USB / desktop)"
	description = "Compile and upload with the arduino-cli tool over a serial port."
	priority = 90


func is_available() -> bool:
	return Platform.supports_subprocess() and _command_on_path("arduino-cli")


func launch(sketch: Dictionary) -> void:
	_started()
	if not is_available():
		_report(false, "arduino-cli was not found on PATH.")
		return

	var sketch_name: String = str(sketch.get("name", "sketch")).get_basename()
	if sketch_name.is_empty():
		sketch_name = "sketch"

	# arduino-cli requires the sketch folder to be named like the .ino file.
	var dir_user: String = "user://codis_upload/" + sketch_name
	var dir_abs: String = ProjectSettings.globalize_path(dir_user)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var ino_abs: String = dir_abs.path_join(sketch_name + ".ino")

	var f: FileAccess = FileAccess.open(ino_abs, FileAccess.WRITE)
	if f == null:
		_report(false, "Could not write temporary sketch (%s)." % ino_abs)
		return
	f.store_string(str(sketch.get("source", "")))
	f.close()

	var fqbn: String = str(sketch.get("fqbn", "arduino:avr:uno"))
	var port: String = str(sketch.get("port", ""))
	log_line.emit("Sketch written to %s" % ino_abs)

	var args: Array = ["compile", "--upload", "--fqbn", fqbn]
	if not port.is_empty():
		args.append_array(["-p", port])
	args.append(ino_abs)

	log_line.emit("Running: arduino-cli " + " ".join(PackedStringArray(args)))
	var out: Array = []
	var code: int = OS.execute("arduino-cli", args, out, true)
	for line in out:
		log_line.emit(str(line))
	if code == 0:
		_report(true, "Upload complete (exit code 0).")
	else:
		_report(false, "arduino-cli failed with exit code %d." % code)


## Scans `PATH` for an executable without spawning a process.
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
