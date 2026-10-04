extends TabContainer

## Multi-tab sketch editor. Each tab is a [CodeEdit] whose metadata stores the
## absolute file path. Sketches live in `Documents/CodisGames/CodisIDE/Codes`.

const DEFAULT_SKETCH: String = """// CodisIDE sketch
void setup() {
	// put your setup code here, to run once:
}

void loop() {
	// put your main code here, to run repeatedly:
}
"""

var save_file_dialog: FileDialog
var open_file_dialog: FileDialog
var _untitled_counter: int = 1


func _ready() -> void:
	var tab_bar := get_tab_bar()
	tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	if not tab_bar.tab_close_pressed.is_connected(_on_tab_closed):
		tab_bar.tab_close_pressed.connect(_on_tab_closed)

	_setup_dialogs()
	_setup_context_menu()
	create_new_tab("Sketch%d" % _untitled_counter, DEFAULT_SKETCH)
	_untitled_counter += 1

	# Re-skin when the IDE theme changes.
	if not Ide.theme_changed.is_connected(_on_theme_changed):
		Ide.theme_changed.connect(_on_theme_changed)


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

## Creates a new [CodeEdit] tab and returns it.
func create_new_tab(title: String = "Untitled", content: String = "", file_path: String = "") -> CodeEdit:
	var editor := CodeEdit.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_configure_editor(editor, file_path)

	add_child(editor)
	var tab_idx: int = get_tab_count() - 1
	set_tab_title(tab_idx, title)
	set_tab_metadata(tab_idx, file_path)
	editor.text = content
	editor.tag_saved_version()
	current_tab = tab_idx
	_update_tab_title(tab_idx)
	return editor


## Opens a file into a new tab, reusing a blank current tab when possible.
func open_file(file_path: String, file_content: String) -> void:
	for i in range(get_tab_count()):
		if get_tab_metadata(i) == file_path:
			current_tab = i
			return

	var editor := get_current_tab_control() as CodeEdit
	var meta: Variant = get_tab_metadata(current_tab) if current_tab >= 0 else null
	if editor and editor.text.strip_edges().is_empty() and (meta == null or str(meta).is_empty()):
		set_tab_title(current_tab, file_path.get_file())
		set_tab_metadata(current_tab, file_path)
		editor.set_meta("file_path", file_path)
		editor.text = file_content
		editor.tag_saved_version()
		Ide.apply_highlighter(editor)
		_update_tab_title(current_tab)
		return

	create_new_tab(file_path.get_file(), file_content, file_path)


func _on_tab_closed(tab_idx: int) -> void:
	var child := get_child(tab_idx)
	if child:
		child.queue_free()
	if get_tab_count() <= 0:
		create_new_tab("Sketch%d" % _untitled_counter, DEFAULT_SKETCH)
		_untitled_counter += 1


# ---------------------------------------------------------------------------
# Editor configuration
# ---------------------------------------------------------------------------

func _configure_editor(editor: CodeEdit, file_path: String) -> void:
	editor.gutters_draw_line_numbers = bool(Ide.get_setting("show_line_numbers", true))
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if bool(Ide.get_setting("word_wrap", false)) else TextEdit.LINE_WRAPPING_NONE
	editor.add_theme_font_size_override("font_size", int(Ide.get_setting("font_size", 15)))
	editor.indent_automatic = true
	editor.indent_size = 4
	editor.auto_brace_completion_enabled = true
	editor.highlight_current_line = true
	editor.set_meta("file_path", file_path)
	Ide.apply_highlighter(editor, Ide.current_theme_id())
	if not editor.text_changed.is_connected(_on_editor_text_changed.bind(editor)):
		editor.text_changed.connect(_on_editor_text_changed.bind(editor))
	if not editor.gui_input.is_connected(_on_editor_gui_input.bind(editor)):
		editor.gui_input.connect(_on_editor_gui_input.bind(editor))


func _on_editor_text_changed(editor: CodeEdit) -> void:
	var idx: int = get_tab_idx_from_control(editor)
	if idx >= 0:
		_update_tab_title(idx)


# ---------------------------------------------------------------------------
# Touch context menu (long-press on mobile, right-click on desktop)
# ---------------------------------------------------------------------------

var _context_menu: PopupMenu
var _context_editor: CodeEdit
var _long_press_timer: Timer


## Builds the shared copy/paste popup and its long-press timer.
func _setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "EditContextMenu"
	_context_menu.add_item("Cut", 0)
	_context_menu.add_item("Copy", 1)
	_context_menu.add_item("Paste", 2)
	_context_menu.add_separator()
	_context_menu.add_item("Select All", 3)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

	_long_press_timer = Timer.new()
	_long_press_timer.name = "LongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = 0.5
	_long_press_timer.timeout.connect(_on_long_press)
	add_child(_long_press_timer)


func _on_editor_gui_input(event: InputEvent, editor: CodeEdit) -> void:
	if event is not InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	# Right-click opens the menu immediately on desktop.
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not Platform.is_mobile():
		_context_editor = editor
		_queue_context_menu(mb.global_position)
		return
	if mb.pressed:
		_context_editor = editor
		if Platform.is_mobile():
			# A held touch becomes a long-press; a quick move cancels it.
			_long_press_timer.start()
	else:
		_long_press_timer.stop()


func _on_long_press() -> void:
	if _context_editor == null:
		return
	_queue_context_menu(get_viewport().get_mouse_position())


## Shows the popup on the next frame so the touch event finishes first.
func _queue_context_menu(at: Vector2) -> void:
	_show_context_menu.call_deferred(at)


func _show_context_menu(at: Vector2) -> void:
	if _context_menu == null or _context_editor == null:
		return
	var has_selection := _context_editor.has_selection()
	_context_menu.set_item_disabled(0, not has_selection)
	_context_menu.set_item_disabled(1, not has_selection)
	_context_menu.position = Vector2i(at)
	_context_menu.popup()


func _on_context_action(id: int) -> void:
	if _context_editor == null:
		return
	match id:
		0: _context_editor.cut()
		1: _context_editor.copy()
		2: _context_editor.paste()
		3: _context_editor.select_all()


func _on_theme_changed(_theme_id: String) -> void:
	for i in range(get_tab_count()):
		var editor := get_child(i) as CodeEdit
		if editor:
			Ide.apply_highlighter(editor, Ide.current_theme_id())


func _update_tab_title(idx: int) -> void:
	var editor := get_child(idx) as CodeEdit
	if editor == null:
		return
	var path: String = str(get_tab_metadata(idx))
	var base: String = path.get_file() if not path.is_empty() else "Sketch"
	var dirty: String = " *" if editor.get_version() != editor.get_saved_version() else ""
	set_tab_title(idx, base + dirty)
	editor.set_meta("file_path", path)


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

## Returns the [CodeEdit] of the currently selected tab.
func get_current_editor() -> CodeEdit:
	return get_current_tab_control() as CodeEdit


## Returns the absolute path of the current tab, or "" for an unsaved sketch.
func get_current_path() -> String:
	if current_tab < 0:
		return ""
	return str(get_tab_metadata(current_tab))


## Creates a fresh sketch in a new tab.
func new_sketch() -> void:
	create_new_tab("Sketch%d" % _untitled_counter, DEFAULT_SKETCH)
	_untitled_counter += 1


## Applies AI-generated code to the active editor as a single undoable edit.
func apply_code(new_code: String, editor: CodeEdit = null) -> void:
	var target := editor if editor else get_current_editor()
	if target == null:
		return
	target.begin_complex_operation()
	target.select_all()
	target.insert_text_at_caret(new_code)
	target.end_complex_operation()
	target.deselect()
	var idx: int = get_tab_idx_from_control(target)
	if idx >= 0:
		_update_tab_title(idx)


# ---------------------------------------------------------------------------
# Save / open
# ---------------------------------------------------------------------------

## Saves the current tab. Unsaved tabs prompt for a location inside Codes/.
func save_current() -> bool:
	var editor := get_current_editor()
	if editor == null:
		return false
	var path: String = get_current_path()
	if path.is_empty():
		save_file_dialog.current_file = "sketch.ino"
		save_file_dialog.popup_centered(Vector2i(720, 520))
		return true
	Ide.write_text_file(path, editor.text)
	editor.tag_saved_version()
	_update_tab_title(current_tab)
	Ide.status_message.emit("Saved " + path.get_file())
	return true


func save_current_as() -> void:
	var editor := get_current_editor()
	if editor:
		save_file_dialog.current_file = "sketch.ino"
		save_file_dialog.popup_centered(Vector2i(720, 520))


func open_dialog() -> void:
	open_file_dialog.current_dir = Ide.codes_dir
	open_file_dialog.popup_centered(Vector2i(720, 520))


# ---------------------------------------------------------------------------
# Dialogs
# ---------------------------------------------------------------------------

func _setup_dialogs() -> void:
	open_file_dialog = FileDialog.new()
	open_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_file_dialog.access = _dialog_access()
	open_file_dialog.use_native_dialog = false
	open_file_dialog.filters = PackedStringArray([
		"*.ino, *.c, *.cpp, *.h, *.gd, *.txt, *.json ; Sketches"
	])
	open_file_dialog.file_selected.connect(_on_open_file_selected)
	add_child(open_file_dialog)

	save_file_dialog = FileDialog.new()
	save_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_file_dialog.access = _dialog_access()
	save_file_dialog.use_native_dialog = false
	save_file_dialog.current_dir = Ide.codes_dir
	save_file_dialog.filters = PackedStringArray([
		"*.ino ; Arduino Sketch", "*.cpp ; C++ Source", "*.h ; C++ Header", "*.gd ; GDScript", "*.txt ; Text File"
	])
	save_file_dialog.file_selected.connect(_on_save_file_selected)
	add_child(save_file_dialog)


## FileDialog access mode: mobile sandboxes forbid absolute filesystem paths,
## so those platforms browse their own user:// tree instead.
func _dialog_access() -> FileDialog.Access:
	return FileDialog.ACCESS_USERDATA if Ide.uses_user_space else FileDialog.ACCESS_FILESYSTEM


func _on_open_file_selected(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		open_file(file_path, Ide.read_text_file(file_path))


func _on_save_file_selected(file_path: String) -> void:
	var editor := get_current_editor()
	if editor == null:
		return
	Ide.write_text_file(file_path, editor.text)
	var idx: int = current_tab
	set_tab_metadata(idx, file_path)
	editor.set_meta("file_path", file_path)
	editor.tag_saved_version()
	_update_tab_title(idx)
	Ide.status_message.emit("Saved " + file_path.get_file())
