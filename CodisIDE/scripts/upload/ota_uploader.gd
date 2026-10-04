class_name OtaUploader
extends UploaderPlugin

## Platform-agnostic backend that streams a sketch to a board over the network.
##
## This is the **mobile-first** path: it only needs a TCP socket, which every
## platform (Android, iOS, desktop) exposes, so it works where USB access is
## impossible or needs a native driver.
##
## Wire protocol (little host, the "Codis build bridge"):
##   [4 bytes big-endian length][payload][optional trailing newline]
##   Host replies with a single line: `OK` on success, `ERR: <reason>` otherwise.
## The payload is a compiled `.bin` when one sits next to the sketch, otherwise
## the raw UTF-8 source (the bridge compiles it).

enum State { IDLE, CONNECTING, SENDING, WAITING, DONE, FAILED }

const CHUNK: int = 4096
const TIMEOUT_SECS: float = 20.0

var _tcp: StreamPeerTCP = null
var _stream: PackedByteArray = PackedByteArray()
var _sent: int = 0
var _state: int = State.IDLE
var _response: String = ""
var _elapsed: float = 0.0


func _init() -> void:
	id = "network_ota"
	display_name = "Network / OTA (Wi-Fi)"
	description = "Stream the sketch to a host over Wi-Fi. Works on desktop and mobile."
	priority = 50
	set_process(false)


func is_available() -> bool:
	# Every platform with a network stack can use this; always offered.
	return true


func launch(sketch: Dictionary) -> void:
	_started()
	_state = State.IDLE
	_response = ""
	_sent = 0

	var host: String = str(Ide.get_setting("ota_host", ""))
	var port: int = int(Ide.get_setting("ota_port", 3232))
	if host.is_empty():
		_report(false, "Set an OTA host in Settings ▸ Upload first.")
		return

	var body: PackedByteArray = _build_payload(sketch)
	if body.is_empty():
		_report(false, "Nothing to upload (empty sketch).")
		return

	var n: int = body.size()
	var header: PackedByteArray = PackedByteArray()
	header.resize(4)
	header.encode_u32(0, n)
	_stream = header
	_stream.append_array(body)

	_tcp = StreamPeerTCP.new()
	var err: int = _tcp.connect_to_host(host, port)
	if err != OK:
		_report(false, "Could not start connection to %s:%d (%d)." % [host, port, err])
		return

	log_line.emit("Connecting to %s:%d … (%d bytes)" % [host, port, n])
	_state = State.CONNECTING
	_elapsed = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if _state == State.IDLE or _state == State.DONE or _state == State.FAILED:
		set_process(false)
		return

	_elapsed += delta
	if _elapsed > TIMEOUT_SECS:
		_fail("Upload timed out after %.0fs." % TIMEOUT_SECS)
		return

	if _tcp == null:
		_fail("Connection was lost.")
		return
	_tcp.poll()

	match _state:
		State.CONNECTING:
			match _tcp.get_status():
				StreamPeerTCP.STATUS_CONNECTED:
					log_line.emit("Connected — sending.")
					_state = State.SENDING
				StreamPeerTCP.STATUS_ERROR:
					_fail("Connection refused by %s." % str(Ide.get_setting("ota_host", "")))
		State.SENDING:
			var end: int = mini(_sent + CHUNK, _stream.size())
			var res: Array = _tcp.put_partial_data(_stream.slice(_sent, end))
			if int(res[0]) != OK:
				return  # buffer full this frame; try again next frame
			_sent += int(res[1])
			progress.emit(int(float(_sent) / float(_stream.size()) * 100.0))
			if _sent >= _stream.size():
				_state = State.WAITING
				log_line.emit("Sent %d bytes — waiting for device…" % _sent)
		State.WAITING:
			var avail: int = _tcp.get_available_bytes()
			if avail > 0:
				_response += _tcp.get_utf8_string(avail)
				if _response.contains("\n"):
					_evaluate(_response.strip_edges())


func _evaluate(line: String) -> void:
	if line.begins_with("OK"):
		_fail_or_ok(true, "Device acknowledged the upload. (%s)" % line)
	else:
		_fail_or_ok(false, line if not line.is_empty() else "Device rejected the upload.")


func _build_payload(sketch: Dictionary) -> PackedByteArray:
	var path: String = str(sketch.get("path", ""))
	if not path.is_empty():
		var bin_path: String = path.get_basename() + ".bin"
		if FileAccess.file_exists(bin_path):
			var bf: FileAccess = FileAccess.open(bin_path, FileAccess.READ)
			if bf != null:
				var data: PackedByteArray = bf.get_buffer(bf.get_length())
				bf.close()
				log_line.emit("Using compiled firmware: %s" % bin_path)
				return data
	return str(sketch.get("source", "")).to_utf8_buffer()


func _fail(message: String) -> void:
	_fail_or_ok(false, message)


func _fail_or_ok(success: bool, message: String) -> void:
	_state = State.DONE if success else State.FAILED
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	set_process(false)
	if success:
		progress.emit(100)
	_report(success, message)
