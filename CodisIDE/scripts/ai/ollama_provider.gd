class_name OllamaProvider
extends AIProvider

## Local inference through an Ollama-compatible HTTP server.
##
## Defaults to 127.0.0.1 on desktop. On mobile and Web, configure a server
## endpoint reachable from the device/browser; this script does not bundle the
## Ollama runtime. Open-source models can run on that server without sending
## prompts to a hosted AI provider.

const DEFAULT_BASE_URL: String = "http://127.0.0.1:11434"
## Fallback used until the user picks a model in Settings.
const DEFAULT_MODEL: String = "qwen2.5:1.5b"

var _models_handler: Callable = Callable()
var _pull_handler: Callable = Callable()
var _pull_name: String = ""


func _init() -> void:
	id = "ollama"
	display_name = "Ollama (offline)"
	is_local = true


func is_available() -> bool:
	# The server is probed on demand; Ollama is "available" whenever selected.
	return true


func endpoint() -> String:
	var configured: String = str(Ide.get_setting("local_ai_endpoint", DEFAULT_BASE_URL)).strip_edges()
	return configured.trim_suffix("/") if not configured.is_empty() else DEFAULT_BASE_URL


func model() -> String:
	var m: String = str(Ide.get_setting("local_model", ""))
	return m if not m.is_empty() else DEFAULT_MODEL


func label() -> String:
	return "Ollama · " + model()


func generate(prompt: String, system: String) -> void:
	var body: Dictionary = {
		"model": model(),
		"prompt": prompt,
		"stream": false,
		"keep_alive": "10m",
		"options": {"temperature": 0.2, "num_predict": 768},
	}
	if not system.is_empty():
		body["system"] = system
	_post_json(endpoint() + "/api/generate",
		PackedStringArray(["Content-Type: application/json"]), body, _on_generate)


func _on_generate(result: int, code: int, data: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Local model request failed (HTTP %d) at %s. Check that an Ollama-compatible server is running and reachable from this device." % [code, endpoint()])
		return
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if parsed is Dictionary and parsed.has("response"):
		completed.emit(str(parsed["response"]))
	else:
		failed.emit("Unexpected response from Ollama.")


func list_models(handler: Callable) -> void:
	_models_handler = handler
	_http_get(endpoint() + "/api/tags", _on_list_models)


func _on_list_models(result: int, code: int, data: PackedByteArray) -> void:
	var names := PackedStringArray()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if parsed is Dictionary and parsed.get("models") is Array:
			for m in parsed["models"]:
				if m is Dictionary:
					names.append(str(m.get("name", "")))
	if _models_handler.is_valid():
		_models_handler.call(names)
	_models_handler = Callable()


## Pulls a model and reports it back once the server has it.
func pull(model_name: String, handler: Callable) -> void:
	_pull_handler = handler
	_pull_name = model_name
	_post_json(endpoint() + "/api/pull",
		PackedStringArray(["Content-Type: application/json"]),
		{"name": model_name, "stream": false},
		_on_pull)


func _on_pull(_result: int, _code: int, _data: PackedByteArray) -> void:
	if _pull_handler.is_valid():
		_pull_handler.call(_pull_name)
	_pull_handler = Callable()


func unload() -> void:
	# keep_alive:0 tells Ollama to evict the model from memory right away.
	_post_json(endpoint() + "/api/generate",
		PackedStringArray(["Content-Type: application/json"]),
		{"model": model(), "keep_alive": 0},
		_on_unload)


func _on_unload(_result: int, _code: int, _data: PackedByteArray) -> void:
	pass
