class_name OpenAICompatibleProvider
extends AIProvider

## Online provider for any OpenAI **Chat Completions**-compatible endpoint
## (OpenAI itself, OpenRouter, Groq, Together, a local LM Studio server, …).
## The base URL, model and key all come from Settings.

func _init() -> void:
	id = "openai"
	display_name = "OpenAI-compatible (online)"
	is_local = false


func base_url() -> String:
	var u: String = str(Ide.get_setting("online_base_url", "")).strip_edges()
	return u if not u.is_empty() else "https://api.openai.com/v1"


func api_key() -> String:
	return str(Ide.get_setting("api_key_openai", "")).strip_edges()


func model() -> String:
	var m: String = str(Ide.get_setting("online_model", "")).strip_edges()
	return m if not m.is_empty() else "gpt-4o-mini"


func is_available() -> bool:
	return not api_key().is_empty()


func label() -> String:
	return "Online · " + model()


func generate(prompt: String, system: String) -> void:
	var messages: Array = []
	if not system.is_empty():
		messages.append({"role": "system", "content": system})
	messages.append({"role": "user", "content": prompt})
	var body: Dictionary = {"model": model(), "messages": messages, "temperature": 0.2}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key(),
	])
	_post_json(base_url().trim_suffix("/") + "/chat/completions", headers, body, _on_generate)


func _on_generate(result: int, code: int, data: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Network error contacting the online API.")
		return
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("choices") is Array:
		var choices: Array = parsed["choices"]
		if not choices.is_empty() and choices[0] is Dictionary:
			var message: Dictionary = choices[0].get("message", {})
			completed.emit(str(message.get("content", "")))
			return
	if parsed is Dictionary and parsed.has("error"):
		var err: Variant = parsed["error"]
		failed.emit(str(err.get("message", "API error")) if err is Dictionary else str(err))
	else:
		failed.emit("Unexpected API response (HTTP %d)." % code)
