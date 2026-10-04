class_name UploaderPlugin
extends Node

## Base class for every code-upload backend.
##
## An *uploader* takes a sketch (source + metadata) and pushes it to a board.
## Concrete subclasses live next to this file and are registered by
## [UploadManager]. Adding mobile support means adding a subclass, not
## rewriting the toolbar.
##
## A sketch dictionary passed to [method launch] uses these keys:
## [code]name[/code], [code]source[/code], [code]path[/code] (may be ""),
## [code]fqbn[/code] and [code]port[/code].

signal log_line(text: String)
signal progress(percent: int)
signal finished(success: bool, message: String)

## Stable identifier used in settings and menu items.
var id: String = "uploader"
## Label shown to the user.
var display_name: String = "Uploader"
## One-line description shown in the upload chooser.
var description: String = ""
## Higher = preferred when several uploaders are available on this platform.
var priority: int = 0

var _cancelled: bool = false
var _running: bool = false


## Whether this backend can run on the current platform / configuration.
## Subclasses override this.
func is_available() -> bool:
	return true


## Starts an upload. Subclasses override this and must eventually emit
## [signal finished].
func launch(_sketch: Dictionary) -> void:
	finished.emit(false, "%s is not implemented." % display_name)


## Requests cancellation of a running upload.
func cancel() -> void:
	_cancelled = true


func is_running() -> bool:
	return _running


# --- Helpers for subclasses -------------------------------------------------

## Emits [signal finished] once and clears the running flag.
func _report(success: bool, message: String) -> void:
	if not _running and not success:
		# Guard against double-reporting a cancelled upload.
		return
	_running = false
	set_process(false)
	finished.emit(success, message)


func _started() -> void:
	_running = true
	_cancelled = false
