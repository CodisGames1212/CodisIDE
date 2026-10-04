class_name AIProvider
extends Node

## Base class for an AI backend — either a **local** runtime (Ollama) or an
## **online** API (Gemini, OpenAI-compatible). Concrete providers implement
## [method generate]; the [AIManager] picks the active one from settings and
## guarantees only one model runs at a time.

signal completed(text: String)
signal failed(message: String)

var id: String = "base"
var display_name: String = "AI Provider"
var is_local: bool = false


## Whether this provider has everything it needs (server reachable / key set).
func is_available() -> bool:
	return false


## Human label shown in the UI, e.g. "Ollama · qwen2.5:1.5b".
func label() -> String:
	return display_name


func generate(_prompt: String, _system: String) -> void:
	failed.emit("%s is not implemented." % display_name)


## Asynchronously lists models this provider can run; calls
## [param handler] with a PackedStringArray.
func list_models(handler: Callable) -> void:
	handler.call(PackedStringArray())


## Releases any model the provider is holding in memory / stops work.
func unload() -> void:
	pass


func cancel() -> void:
	pass


# --- HTTP helpers -----------------------------------------------------------

func _post_json(url: String, headers: PackedStringArray, body: Dictionary, on_done: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		http.queue_free()
		on_done.call(result, code, data))
	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		on_done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())


func _http_get(url: String, on_done: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		http.queue_free()
		on_done.call(result, code, data))
	var err: int = http.request(url)
	if err != OK:
		http.queue_free()
		on_done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
