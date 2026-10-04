@tool
class_name CustomDropdown
extends Control

signal item_selected(index: int, text: String)

@export_category("Items")
@export var items: Array[String] = [
	"Option 1",
	"Option 2",
	"Option 3"
]:
	set(value):
		items.clear()
		for v in value:
			items.append(str(v))
		if is_inside_tree():
			_rebuild()

@export var selected_index: int = 0:
	set(value):
		selected_index = clampi(value, 0, max(0, items.size() - 1))
		if is_inside_tree():
			_update_button()

@export_category("Button")
@export var button_width: float = 220.0
@export var button_height: float = 40.0
@export var button_text: String = "":
	set(value):
		button_text = value
		if is_inside_tree():
			_update_button()

@export var button_font_size: int = 16
@export var button_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT

@export_category("Popup")
@export var item_height: float = 36.0
@export var item_font_size: int = 16
@export var max_visible_items: int = 6
@export var popup_width: float = 220.0
@export var popup_offset: Vector2 = Vector2.ZERO
@export var popup_border: float = 0.0

@export_category("Scrolling")
@export var scroll_enabled: bool = true
@export var scroll_speed: float = 30.0
@export var scroll_vertical_step: int = 1

@export_category("Behavior")
@export var close_on_selection: bool = true
@export var close_on_focus_exit: bool = true
@export var open_below: bool = true

@export_category("Appearance")
@export var button_modulate: Color = Color.WHITE
@export var item_modulate: Color = Color.WHITE
@export var disabled_item_modulate: Color = Color(0.5, 0.5, 0.5, 1.0)

var button: Button
var popup: PopupPanel
var scroll: ScrollContainer
var list: VBoxContainer


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	_clear()

	button = Button.new()
	button.name = "DropdownButton"
	button.custom_minimum_size = Vector2(button_width, button_height)
	button.size = Vector2(button_width, button_height)
	button.alignment = button_alignment
	button.add_theme_font_size_override("font_size", button_font_size)
	button.modulate = button_modulate
	button.text = _get_button_text()
	button.pressed.connect(_toggle_popup)

	add_child(button)

	popup = PopupPanel.new()
	popup.name = "DropdownPopup"
	popup.size = Vector2(popup_width, _get_popup_height())
	popup.exclusive = false

	add_child(popup)

	if items.size() > max_visible_items and scroll_enabled:
		_create_scrollable_list()
	else:
		_create_normal_list()

	_update_button()


func _create_normal_list() -> void:
	list = VBoxContainer.new()
	list.name = "ItemList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	popup.add_child(list)

	_create_items()


func _create_scrollable_list() -> void:
	scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"

	scroll.custom_minimum_size = Vector2(
		popup_width,
		max_visible_items * item_height
	)

	scroll.size = Vector2(
		popup_width,
		max_visible_items * item_height
	)

	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	scroll.scroll_deadzone = 0
	scroll.mouse_default_cursor_shape = Control.CURSOR_ARROW

	popup.add_child(scroll)

	list = VBoxContainer.new()
	list.name = "ItemList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	scroll.add_child(list)

	_create_items()


func _create_items() -> void:
	for i in items.size():
		var item := Button.new()

		item.name = "Item_%d" % i
		item.text = items[i]
		item.custom_minimum_size = Vector2(
			popup_width,
			item_height
		)

		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT

		item.add_theme_font_size_override(
			"font_size",
			item_font_size
		)

		item.modulate = item_modulate

		item.pressed.connect(_on_item_pressed.bind(i))

		list.add_child(item)


func _clear() -> void:
	if button:
		button.queue_free()
		button = null

	if popup:
		popup.queue_free()
		popup = null

	scroll = null
	list = null


func _get_button_text() -> String:
	if not button_text.is_empty():
		return button_text

	if items.is_empty():
		return "Select..."

	if selected_index >= 0 and selected_index < items.size():
		return items[selected_index]

	return "Select..."


func _update_button() -> void:
	if button:
		button.text = _get_button_text()


func _get_popup_height() -> float:
	if items.is_empty():
		return item_height

	if scroll_enabled and items.size() > max_visible_items:
		return max_visible_items * item_height

	return items.size() * item_height


func _toggle_popup() -> void:
	if not popup:
		return

	if popup.visible:
		popup.hide()
		return

	_update_popup_size()

	var button_position := button.global_position
	var popup_height := popup.size.y
	var viewport_size := get_viewport_rect().size

	var popup_position := Vector2(
		button_position.x + popup_offset.x,
		button_position.y + button.size.y + popup_offset.y
	)

	if open_below:
		if popup_position.y + popup_height > viewport_size.y:
			popup_position.y = button_position.y - popup_height
	else:
		popup_position.y = button_position.y - popup_height

	if popup_position.x + popup_width > viewport_size.x:
		popup_position.x = viewport_size.x - popup_width

	popup.position = popup_position
	popup.popup()


func _update_popup_size() -> void:
	if not popup:
		return

	popup.size = Vector2(
		popup_width,
		_get_popup_height()
	)

	if scroll:
		scroll.size = popup.size


func _on_item_pressed(index: int) -> void:
	selected_index = index

	_update_button()

	item_selected.emit(
		index,
		items[index]
	)

	if close_on_selection:
		popup.hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_inside_tree():
			_update_popup_size()
