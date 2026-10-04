extends Node

## Headless smoke test for the local (Ollama) AI path.
## Run: godot --headless res://CodisIDE/tests/ai_smoke.tscn


func _ready() -> void:
	var mgr := AIManager.new()
	add_child(mgr)
	mgr.generation_started.connect(func(label: String) -> void: print("[smoke] STARTED ", label))
	mgr.generation_finished.connect(func(text: String) -> void:
		print("[smoke] FINISHED: ", text.substr(0, 300))
		get_tree().quit())
	mgr.generation_failed.connect(func(message: String) -> void:
		print("[smoke] FAILED: ", message)
		get_tree().quit())

	print("[smoke] mode=", mgr.mode(), " active=", mgr.active_label())
	mgr.generate("Reply with exactly: hello world", "You are a concise assistant.")

	await get_tree().create_timer(25.0).timeout
	print("[smoke] TIMEOUT - no result")
	get_tree().quit()
