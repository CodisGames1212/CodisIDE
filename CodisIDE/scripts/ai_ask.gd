extends TextEdit

@export_category("Auto Resize")
@export var min_height: float = 38.0
@export var max_height: float = 300.0

func _ready() -> void:
	text_changed.connect(_update_height)
	_update_height()


func _update_height() -> void:
	var line_height: float = get_line_height()
	var line_count: int = get_line_count()

	var content_height: float = (line_count * line_height) + 20.0

	var new_height: float = clampf(
		content_height,
		min_height,
		max_height
	)

	custom_minimum_size.y = new_height

	# Allow scrolling after reaching max height.
	scroll_vertical = content_height > max_height
