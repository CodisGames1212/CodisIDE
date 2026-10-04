class_name SerialUploader
extends UploaderPlugin

## Backend backed by a native GDExtension serial driver (`CodisSerial`).
##
## Godot core has no serial-port API, so true USB uploads — including Android
## USB On-The-Go — need a native module. This class activates **only** when
## that module is present, so the project runs cleanly without it. The matching
## C++ source and build instructions ship in `res://addons/codis_serial/`.
##
## Expected native interface (any subset may exist):
##   list_ports() -> PackedStringArray
##   open(port: String, baud: int) -> bool
##   write(bytes: PackedByteArray) -> int
##   close() -> void
##   flash(fqbn: String, port: String, payload: PackedByteArray) -> bool

const SINGLETON: String = "CodisSerial"

var _native: Object = null
var _native_checked: bool = false


func _init() -> void:
	id = "serial_native"
	display_name = "USB / Serial (native driver)"
	description = "Flash over USB using the CodisSerial GDExtension (mobile OTG supported)."
	priority = 100


func is_available() -> bool:
	return _native_module() != null


func launch(sketch: Dictionary) -> void:
	_started()
	_native = _native_module()
	if _native == null:
		_report(false, "The CodisSerial native module is not installed.")
		return

	var port: String = str(sketch.get("port", ""))
	if port.is_empty():
		port = str(Ide.get_setting("selected_port", ""))
	if port.is_empty():
		_report(false, "Select a serial port in Settings first.")
		return

	var payload: PackedByteArray = _payload_for(sketch)
	if payload.is_empty():
		_report(false, "Nothing to upload (empty sketch).")
		return

	var fqbn: String = str(sketch.get("fqbn", "arduino:avr:uno"))

	# Preferred path: the native module knows the flashing protocol.
	if _native.has_method("flash"):
		log_line.emit("Flashing %s on %s via native driver…" % [fqbn, port])
		var ok: bool = bool(_native.call("flash", fqbn, port, payload))
		if ok:
			progress.emit(100)
			_report(true, "Flashed %d bytes to %s." % [payload.size(), port])
		else:
			_report(false, "Native flash failed on %s." % port)
		return

	# Fallback: raw serial write (e.g. boards that accept a serial bootloader).
	if not _native.has_method("open"):
		_report(false, "CodisSerial exposes neither flash() nor open().")
		return
	var baud: int = int(Ide.get_setting("baud", 115200))
	if not bool(_native.call("open", port, baud)):
		_report(false, "Could not open %s at %d baud." % [port, baud])
		return
	var written: int = int(_native.call("write", payload))
	if _native.has_method("close"):
		_native.call("close")
	if written > 0:
		progress.emit(100)
		_report(true, "Wrote %d bytes to %s." % [written, port])
	else:
		_report(false, "Serial write failed on %s." % port)


## Lists ports exposed by the native driver (empty when absent).
func list_ports() -> PackedStringArray:
	var native: Object = _native_module()
	if native != null and native.has_method("list_ports"):
		var result: Variant = native.call("list_ports")
		if result is PackedStringArray:
			return result
		if result is Array:
			return PackedStringArray(result)
	return PackedStringArray()


func _payload_for(sketch: Dictionary) -> PackedByteArray:
	var path: String = str(sketch.get("path", ""))
	if not path.is_empty():
		var bin_path: String = path.get_basename() + ".bin"
		if FileAccess.file_exists(bin_path):
			var bf: FileAccess = FileAccess.open(bin_path, FileAccess.READ)
			if bf != null:
				var data: PackedByteArray = bf.get_buffer(bf.get_length())
				bf.close()
				return data
	return str(sketch.get("source", "")).to_utf8_buffer()


func _native_module() -> Object:
	if not _native_checked:
		_native_checked = true
		if Engine.has_singleton(SINGLETON):
			_native = Engine.get_singleton(SINGLETON)
		elif ClassDB.class_exists(SINGLETON) and ClassDB.can_instantiate(SINGLETON):
			_native = ClassDB.instantiate(SINGLETON)
	return _native
