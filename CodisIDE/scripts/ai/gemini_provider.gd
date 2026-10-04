class_name GeminiProvider
extends AIProvider

## Online provider for Google **Gemini** (generativelanguage API).
## The API key and model name come from Settings ▸ AI.

const ENDPOINT: String = "https://generativelanguage.googleapis.com/v1beta/models"
const DEFAULT_MODEL: String = "gemini-2.0-flash"


func _init() -> void:
	id = "gemini"
	display_name = "Google Gemini (online)"
	is_local = false


func api_key() -> String:
	return str(Ide.get_setting("api_key_gemini", "")).strip_edges()


func model() -> String:
	var m: String = str(Ide.get_setting("gemini_model", "")).strip_edges()
	return m if not m.is_empty() else DEFAULT_MODEL


func is_available() -> bool:
	return not api_key().is_empty()


func label() -> String:
	return "Gemini · " + model()


func generate(prompt: String, system: String) -> void:
	if api_key().is_empty():
		failed.emit("No Gemini API key set. Open Settings ▸ AI.")
		return
	var url := "%s/%s:generateContent?key=%s" % [ENDPOINT, model(), api_key()]
	var body: Dictionary = {"contents": [{"parts": [{"text": prompt}]}]}
	if not system.is_empty():
		body["systemInstruction"] = {"parts": [{"text": system}]}
	_post_json(url, PackedStringArray(["Content-Type: application/json"]), body, _on_generate)


func _on_generate(result: int, code: int, data: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Network error contacting Gemini.")
		return
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("candidates") is Array:
		var candidates: Array = parsed["candidates"]
		if not candidates.is_empty() and candidates[0] is Dictionary:
			var parts: Array = candidates[0].get("content", {}).get("parts", [])
			var text: String = ""
			for part in parts:
				if part is Dictionary:
					text += str(part.get("text", ""))
			completed.emit(text)
			return
	if parsed is Dictionary and parsed.has("error"):
		var err: Variant = parsed["error"]
		failed.emit(str(err.get("message", "Gemini error")) if err is Dictionary else str(err))
	else:
		failed.emit("Unexpected Gemini response (HTTP %d)." % code)
