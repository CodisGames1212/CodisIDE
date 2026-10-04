class_name UploadManager
extends Node

## Registry + dispatcher for the upload backends.
##
## Owns one instance of every [UploaderPlugin] and hands the toolbar the list
## of ones that actually work on the current platform, best-first. The active
## upload is tracked so the UI can show progress and offer a Cancel.

signal upload_started(uploader: UploaderPlugin)
signal upload_finished(success: bool, message: String)

var uploaders: Array[UploaderPlugin] = []

var active: UploaderPlugin = null


func _ready() -> void:
	_register()


func _register() -> void:
	# Order here is irrelevant — visibility and preference are decided by each
	# uploader's is_available() and priority.
	add_uploader(SerialUploader.new())
	add_uploader(CliUploader.new())
	add_uploader(OtaUploader.new())


func add_uploader(uploader: UploaderPlugin) -> void:
	uploaders.append(uploader)
	add_child(uploader)
	uploader.finished.connect(_on_uploader_finished)


## Every backend usable right now, highest priority first.
func available() -> Array[UploaderPlugin]:
	var list: Array[UploaderPlugin] = []
	for uploader in uploaders:
		if uploader.is_available():
			list.append(uploader)
	list.sort_custom(func(a: UploaderPlugin, b: UploaderPlugin) -> bool:
		return a.priority > b.priority)
	return list


## The backend that should be used when the user does not pick one.
func default_uploader() -> UploaderPlugin:
	var list: Array[UploaderPlugin] = available()
	return list[0] if not list.is_empty() else null


func find(id: String) -> UploaderPlugin:
	for uploader in uploaders:
		if uploader.id == id:
			return uploader
	return null


## Runs [param uploader] (or the default) on [param sketch]. Returns false when
## no backend is available or one is already running.
func upload(sketch: Dictionary, uploader: UploaderPlugin = null) -> bool:
	var target: UploaderPlugin = uploader if uploader != null else default_uploader()
	if target == null:
		upload_finished.emit(false, "No upload backend is available on this device.")
		return false
	if active != null and active.is_running():
		upload_finished.emit(false, "An upload is already in progress.")
		return false
	active = target
	upload_started.emit(target)
	target.launch(sketch)
	return true


func cancel() -> void:
	if active != null and active.is_running():
		active.cancel()


func _on_uploader_finished(success: bool, message: String) -> void:
	active = null
	upload_finished.emit(success, message)
