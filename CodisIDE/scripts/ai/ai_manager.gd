class_name AIManager
extends Node

## Owns every [AIProvider] and enforces the "only one model at a time" rule.
##
## The active provider is chosen from settings: `ai_mode` is `"offline"` (local
## Ollama) or `"online"` (Gemini / OpenAI-compatible). Before a generation runs,
## all *other* providers are told to [method AIProvider.unload] so a second
## model is never left resident in memory.

signal generation_started(label: String)
signal generation_finished(text: String)
signal generation_failed(message: String)

var providers: Array[AIProvider] = []

var _busy: bool = false


func _ready() -> void:
	add_provider(OllamaProvider.new())
	add_provider(GeminiProvider.new())
	add_provider(OpenAICompatibleProvider.new())


func add_provider(provider: AIProvider) -> void:
	providers.append(provider)
	add_child(provider)


# ---------------------------------------------------------------------------
# Active provider
# ---------------------------------------------------------------------------

func mode() -> String:
	return str(Ide.get_setting("ai_mode", "offline"))


func _wanted_id() -> String:
	if mode() == "online":
		return "openai" if str(Ide.get_setting("online_provider", "gemini")) == "openai" else "gemini"
	return "ollama"


func active() -> AIProvider:
	var want := _wanted_id()
	for provider in providers:
		if provider.id == want:
			return provider
	return null


## e.g. "Ollama · qwen2.5:1.5b" or "Gemini · gemini-2.0-flash".
func active_label() -> String:
	var provider := active()
	return provider.label() if provider != null else "None"


func is_running() -> bool:
	return _busy


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func generate(prompt: String, system: String) -> void:
	var provider := active()
	if provider == null:
		generation_failed.emit("No AI provider is configured.")
		return
	if not provider.is_available():
		generation_failed.emit("%s is not configured. Open Settings ▸ AI." % provider.display_name)
		return
	if _busy:
		generation_failed.emit("A generation is already running — press Stop first.")
		return

	# Only one model runs at a time: release the others first.
	for other in providers:
		if other != provider:
			other.unload()

	_busy = true
	if not provider.completed.is_connected(_on_completed):
		provider.completed.connect(_on_completed)
	if not provider.failed.is_connected(_on_failed):
		provider.failed.connect(_on_failed)
	generation_started.emit(provider.label())
	provider.generate(prompt, system)


## Cancels the current generation and evicts the local model from memory.
func stop() -> void:
	_busy = false
	for provider in providers:
		provider.cancel()
	var provider := active()
	if provider != null:
		provider.unload()
	generation_failed.emit("Stopped.")


func _on_completed(text: String) -> void:
	_busy = false
	generation_finished.emit(text)


func _on_failed(message: String) -> void:
	_busy = false
	generation_failed.emit(message)


# ---------------------------------------------------------------------------
# Model discovery
# ---------------------------------------------------------------------------

## Lists models installed in the local Ollama runtime.
func list_local_models(handler: Callable) -> void:
	for provider in providers:
		if provider.id == "ollama":
			provider.list_models(handler)
			return
	handler.call(PackedStringArray())


## Pulls an Ollama model by name; [param handler] is called when done.
func pull_local_model(model_name: String, handler: Callable) -> void:
	for provider in providers:
		if provider.id == "ollama" and provider.has_method("pull"):
			provider.call("pull", model_name, handler)
			return
	handler.call(model_name)
