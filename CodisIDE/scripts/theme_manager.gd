class_name ThemeManager
extends RefCounted

## Builds complete Godot [Theme] resources (UI + code syntax highlighting) for
## CodisIDE. Every theme is generated programmatically from a colour palette so
## new themes can be added by appending one dictionary entry to [member THEMES].

## Ordered list used by menus. The id is the dictionary key in [member THEMES].
const THEME_ORDER: PackedStringArray = [
	"arduino_dark",
	"arduino_light",
	"dracula",
	"monokai",
	"nord",
	"solarized_dark",
	"one_dark",
	"high_contrast",
]

## Human readable names for the settings menu.
const THEME_NAMES: Dictionary = {
	"arduino_dark": "Arduino Dark",
	"arduino_light": "Arduino Light",
	"dracula": "Dracula",
	"monokai": "Monokai",
	"nord": "Nord",
	"solarized_dark": "Solarized Dark",
	"one_dark": "One Dark",
	"high_contrast": "High Contrast",
}

## Every palette must provide these keys. `base` is the window/editor background,
## `surface` is used for panels/inputs, `raised` for buttons, `accent` for the
## brand colour and `text`/`text_dim` for foregrounds.
const THEMES: Dictionary = {
	"arduino_dark": {
		"base": Color("16181d"), "surface": Color("1e2128"), "raised": Color("272b34"),
		"accent": Color("00a1d6"), "accent_text": Color("ffffff"),
		"text": Color("e6e6e6"), "text_dim": Color("8a9099"), "border": Color("333842"),
		"sel": Color("2f6f8f"),
		"kw": Color("d78bd6"), "str": Color("c3e88d"), "num": Color("f78c6c"),
		"comment": Color("6a8a6a"), "func": Color("82aaff"), "type": Color("ffd479"),
		"symbol": Color("89ddff"), "caret": Color("00a1d6"), "line": Color("23272f"),
		"gutter": Color("5a616b"),
	},
	"arduino_light": {
		"base": Color("f4f4f4"), "surface": Color("ffffff"), "raised": Color("e9e9ec"),
		"accent": Color("00979d"), "accent_text": Color("ffffff"),
		"text": Color("1c1c1c"), "text_dim": Color("5c636e"), "border": Color("c9ccd1"),
		"sel": Color("b7e1e3"),
		"kw": Color("a626a4"), "str": Color("50a14f"), "num": Color("986801"),
		"comment": Color("a0a1a7"), "func": Color("4078f2"), "type": Color("c18401"),
		"symbol": Color("0184bc"), "caret": Color("00979d"), "line": Color("eceef1"),
		"gutter": Color("9aa0a6"),
	},
	"dracula": {
		"base": Color("282a36"), "surface": Color("21222c"), "raised": Color("343746"),
		"accent": Color("bd93f9"), "accent_text": Color("282a36"),
		"text": Color("f8f8f2"), "text_dim": Color("8b93a7"), "border": Color("44475a"),
		"sel": Color("44475a"),
		"kw": Color("ff79c6"), "str": Color("f1fa8c"), "num": Color("bd93f9"),
		"comment": Color("6272a4"), "func": Color("50fa7b"), "type": Color("8be9fd"),
		"symbol": Color("ffb86c"), "caret": Color("f8f8f0"), "line": Color("343746"),
		"gutter": Color("6272a4"),
	},
	"monokai": {
		"base": Color("272822"), "surface": Color("1e1f1c"), "raised": Color("3a3b34"),
		"accent": Color("a6e22e"), "accent_text": Color("272822"),
		"text": Color("f8f8f2"), "text_dim": Color("8a887d"), "border": Color("49483e"),
		"sel": Color("49483e"),
		"kw": Color("f92672"), "str": Color("e6db74"), "num": Color("ae81ff"),
		"comment": Color("75715e"), "func": Color("a6e22e"), "type": Color("66d9ef"),
		"symbol": Color("f92672"), "caret": Color("f8f8f0"), "line": Color("3a3b34"),
		"gutter": Color("75715e"),
	},
	"nord": {
		"base": Color("2e3440"), "surface": Color("2b303b"), "raised": Color("3b4252"),
		"accent": Color("88c0d0"), "accent_text": Color("2e3440"),
		"text": Color("eceff4"), "text_dim": Color("8f9aad"), "border": Color("434c5e"),
		"sel": Color("434c5e"),
		"kw": Color("81a1c1"), "str": Color("a3be8c"), "num": Color("b48ead"),
		"comment": Color("616e88"), "func": Color("88c0d0"), "type": Color("8fbcbb"),
		"symbol": Color("81a1c1"), "caret": Color("88c0d0"), "line": Color("3b4252"),
		"gutter": Color("616e88"),
	},
	"solarized_dark": {
		"base": Color("002b36"), "surface": Color("073642"), "raised": Color("0a4250"),
		"accent": Color("268bd2"), "accent_text": Color("fdf6e3"),
		"text": Color("eee8d5"), "text_dim": Color("93a1a1"), "border": Color("0d4a58"),
		"sel": Color("0d4a58"),
		"kw": Color("859900"), "str": Color("2aa198"), "num": Color("d33682"),
		"comment": Color("586e75"), "func": Color("268bd2"), "type": Color("b58900"),
		"symbol": Color("cb4b16"), "caret": Color("268bd2"), "line": Color("073642"),
		"gutter": Color("586e75"),
	},
	"one_dark": {
		"base": Color("282c34"), "surface": Color("21252b"), "raised": Color("323842"),
		"accent": Color("61afef"), "accent_text": Color("282c34"),
		"text": Color("abb2bf"), "text_dim": Color("7f848e"), "border": Color("3b4048"),
		"sel": Color("3e4451"),
		"kw": Color("c678dd"), "str": Color("98c379"), "num": Color("d19a66"),
		"comment": Color("5c6370"), "func": Color("61afef"), "type": Color("e5c07b"),
		"symbol": Color("56b6c2"), "caret": Color("528bff"), "line": Color("2c313a"),
		"gutter": Color("5c6370"),
	},
	"high_contrast": {
		"base": Color("000000"), "surface": Color("0a0a0a"), "raised": Color("1a1a1a"),
		"accent": Color("00ffff"), "accent_text": Color("000000"),
		"text": Color("ffffff"), "text_dim": Color("c0c0c0"), "border": Color("ffffff"),
		"sel": Color("005f5f"),
		"kw": Color("ff00ff"), "str": Color("00ff00"), "num": Color("ffff00"),
		"comment": Color("00ffff"), "func": Color("00ff00"), "type": Color("ffff00"),
		"symbol": Color("ffffff"), "caret": Color("ffffff"), "line": Color("141414"),
		"gutter": Color("c0c0c0"),
	},
}

## C / C++ / Arduino keywords used for syntax highlighting.
const CPP_KEYWORDS: PackedStringArray = [
	"void", "int", "float", "double", "char", "bool", "long", "short", "byte",
	"unsigned", "signed", "const", "static", "volatile", "return", "if", "else",
	"for", "while", "do", "switch", "case", "default", "break", "continue",
	"struct", "class", "enum", "typedef", "sizeof", "new", "delete", "true",
	"false", "nullptr", "NULL", "HIGH", "LOW", "INPUT", "OUTPUT",
	"INPUT_PULLUP", "LED_BUILTIN", "PROGMEM", "String", "boolean", "word",
	"setup", "loop", "pinMode", "digitalWrite", "digitalRead", "analogRead",
	"analogWrite", "delay", "delayMicroseconds", "millis", "micros",
]

## GDScript keywords (used when the active file is a .gd script).
const GD_KEYWORDS: PackedStringArray = [
	"if", "elif", "else", "for", "while", "match", "break", "continue", "pass",
	"return", "class", "class_name", "extends", "func", "var", "const", "enum",
	"signal", "static", "await", "yield", "is", "as", "and", "or", "not", "in",
	"self", "super", "true", "false", "null", "void", "int", "float", "String",
	"bool", "Array", "Dictionary", "Vector2", "Vector3", "preload", "load",
]


## Returns true when [param id] is a known theme.
static func has_theme(id: String) -> bool:
	return THEMES.has(id)


## Human readable label for a theme id (falls back to the raw id).
static func theme_label(id: String) -> String:
	return str(THEME_NAMES.get(id, id))


## Returns the ordered list of available theme ids.
static func list_themes() -> PackedStringArray:
	return THEME_ORDER.duplicate()


## Builds a full UI [Theme] for the given id. Unknown ids fall back to
## `arduino_dark`.
static func build_theme(id: String) -> Theme:
	var p: Dictionary = THEMES.get(id, THEMES["arduino_dark"])
	var theme := Theme.new()
	theme.default_font_size = 15

	var base: Color = p["base"]
	var surface: Color = p["surface"]
	var raised: Color = p["raised"]
	var accent: Color = p["accent"]
	var accent_text: Color = p["accent_text"]
	var text: Color = p["text"]
	var text_dim: Color = p["text_dim"]
	var border: Color = p["border"]
	var sel: Color = p["sel"]

	# --- Panels / containers -------------------------------------------------
	theme.set_stylebox("panel", "Panel", _sb(surface, border, 6, 1))
	theme.set_stylebox("panel", "PanelContainer", _sb(surface, border, 6, 1))
	theme.set_stylebox("panel", "PopupPanel", _sb(raised, border, 8, 1))
	theme.set_stylebox("panel", "TabContainer", _sb(base, Color(0, 0, 0, 0), 6, 0))

	theme.set_color("font_color", "Label", text)
	theme.set_color("font_color", "RichTextLabel", text)
	theme.set_color("default_color", "RichTextLabel", text)

	theme.set_color("font_color", "LinkButton", accent)
	theme.set_color("font_hover_color", "LinkButton", accent.lightened(0.2))
	theme.set_color("font_pressed_color", "LinkButton", accent.darkened(0.2))

	# --- Buttons -------------------------------------------------------------
	theme.set_stylebox("normal", "Button", _sb(raised, border, 6, 1))
	theme.set_stylebox("hover", "Button", _sb(raised.lightened(0.08), accent, 6, 1))
	theme.set_stylebox("pressed", "Button", _sb(raised.darkened(0.1), accent, 6, 1))
	theme.set_stylebox("disabled", "Button", _sb(surface, border, 6, 1))
	theme.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), accent, 6, 2))
	theme.set_color("font_color", "Button", text)
	theme.set_color("font_hover_color", "Button", text)
	theme.set_color("font_pressed_color", "Button", accent)
	theme.set_color("font_disabled_color", "Button", text_dim)
	theme.set_color("font_focus_color", "Button", text)
	theme.set_constant("h_separation", "Button", 6)

	# --- Check buttons / option buttons -------------------------------------
	theme.set_stylebox("normal", "OptionButton", _sb(raised, border, 6, 1))
	theme.set_stylebox("hover", "OptionButton", _sb(raised.lightened(0.08), accent, 6, 1))
	theme.set_stylebox("pressed", "OptionButton", _sb(raised.darkened(0.1), accent, 6, 1))
	theme.set_color("font_color", "OptionButton", text)
	theme.set_color("font_hover_color", "OptionButton", text)

	# --- Text inputs ---------------------------------------------------------
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type, _sb(surface, border, 6, 1))
		theme.set_stylebox("focus", type, _sb(surface, accent, 6, 1))
		theme.set_stylebox("read_only", type, _sb(base, border, 6, 1))
		theme.set_color("font_color", type, text)
		theme.set_color("font_placeholder_color", type, text_dim)
		theme.set_color("font_selected_color", type, text)
		theme.set_color("selection_color", type, sel)
		theme.set_color("caret_color", type, p["caret"])
		theme.set_color("current_line_color", type, p["line"])
		theme.set_color("line_number_color", type, p["gutter"])
	theme.set_constant("line_spacing", "CodeEdit", 3)

	# --- Tabs ----------------------------------------------------------------
	theme.set_stylebox("panel", "TabContainer", _sb(base, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("tab_unselected", "TabContainer", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("tab_selected", "TabContainer", _sb(raised, accent, 6, 0))
	theme.set_stylebox("tab_hovered", "TabContainer", _sb(raised.lightened(0.05), Color(0, 0, 0, 0), 6, 0))
	theme.set_color("font_selected_color", "TabContainer", text)
	theme.set_color("font_unselected_color", "TabContainer", text_dim)
	theme.set_color("font_hovered_color", "TabContainer", text)

	theme.set_stylebox("tab_unselected", "TabBar", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("tab_selected", "TabBar", _sb(raised, accent, 6, 0))
	theme.set_stylebox("tab_hovered", "TabBar", _sb(raised.lightened(0.05), Color(0, 0, 0, 0), 6, 0))
	theme.set_color("font_selected_color", "TabBar", text)
	theme.set_color("font_unselected_color", "TabBar", text_dim)

	# --- Popups / lists ------------------------------------------------------
	theme.set_stylebox("panel", "PopupMenu", _sb(raised, border, 8, 1))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", accent_text)
	theme.set_color("font_separator_color", "PopupMenu", text_dim)
	theme.set_color("font_disabled_color", "PopupMenu", text_dim)
	theme.set_stylebox("hover", "PopupMenu", _sb(accent, Color(0, 0, 0, 0), 6, 0))
	theme.set_constant("item_start_padding", "PopupMenu", 8)

	theme.set_stylebox("panel", "ItemList", _sb(surface, border, 6, 1))
	theme.set_color("font_color", "ItemList", text)
	theme.set_color("font_selected_color", "ItemList", accent_text)

	# --- Scrollbars / separators / splits -----------------------------------
	theme.set_stylebox("scroll", "VScrollBar", _sb(base, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber", "VScrollBar", _sb(border, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _sb(accent, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _sb(accent, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("scroll", "HScrollBar", _sb(base, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber", "HScrollBar", _sb(border, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber_highlight", "HScrollBar", _sb(accent, Color(0, 0, 0, 0), 6, 0))
	theme.set_stylebox("grabber_pressed", "HScrollBar", _sb(accent, Color(0, 0, 0, 0), 6, 0))

	theme.set_stylebox("separator", "HSeparator", _sb(border, Color(0, 0, 0, 0), 0, 0))
	theme.set_stylebox("separator", "VSeparator", _sb(border, Color(0, 0, 0, 0), 0, 0))

	theme.set_stylebox("split_bar_background", "HSplitContainer", _sb(base, Color(0, 0, 0, 0), 0, 0))
	theme.set_stylebox("split_bar_background", "VSplitContainer", _sb(base, Color(0, 0, 0, 0), 0, 0))

	# --- Progress / tooltips -------------------------------------------------
	theme.set_stylebox("background", "ProgressBar", _sb(surface, border, 6, 1))
	theme.set_stylebox("fill", "ProgressBar", _sb(accent, Color(0, 0, 0, 0), 6, 0))
	theme.set_color("font_color", "ProgressBar", text)

	theme.set_stylebox("panel", "TooltipPanel", _sb(raised, border, 6, 1))
	theme.set_color("font_color", "TooltipLabel", text)

	# Root window background.
	theme.set_color("background", "Root", base)

	return theme


## Builds a syntax [CodeHighlighter] for the given theme id. Set the returned
## resource on a [CodeEdit] with `set_syntax_highlighter`.
static func build_highlighter(id: String, language: String = "cpp") -> CodeHighlighter:
	var p: Dictionary = THEMES.get(id, THEMES["arduino_dark"])
	var hl := CodeHighlighter.new()

	hl.number_color = p["num"]
	hl.symbol_color = p["symbol"]
	hl.function_color = p["func"]
	hl.member_variable_color = p["symbol"]

	# Comments (line + block).
	hl.add_color_region("//", "", p["comment"], true)
	hl.add_color_region("/*", "*/", p["comment"], false)

	# Strings and chars.
	hl.add_color_region("\"", "\"", p["str"], false)
	hl.add_color_region("'", "'", p["str"], false)

	# Preprocessor directives.
	hl.add_color_region("#", "", p["type"], true)

	var keywords: PackedStringArray = GD_KEYWORDS if language == "gdscript" else CPP_KEYWORDS
	for kw in keywords:
		hl.add_keyword_color(kw, p["kw"])

	# Type-ish tokens common to both languages.
	for t in ["void", "int", "float", "double", "char", "bool", "long", "String", "Vector2", "Vector3", "Dictionary", "Array"]:
		hl.add_keyword_color(t, p["type"])

	return hl


## Convenience: build a rounded flat StyleBox.
static func _sb(bg: Color, border_color: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	else:
		sb.set_border_width_all(0)
	return sb
