class_name LocalCodeAnalyzer
extends RefCounted

## Offline, dependency-free code analysis engine used by the AI assistant.
##
## It reads the active sketch, reports issues (with line numbers and
## suggestions) and, where it can do so safely, produces an automatically
## corrected version of the file. Analysis runs entirely on the device — the
## only "model" it needs is the selected local model name used to tag results.

enum Severity { INFO, WARNING, ERROR }

const CPP_CONTROL: PackedStringArray = [
	"if", "else", "for", "while", "do", "switch", "case", "default",
]

const CPP_TYPES: PackedStringArray = [
	"void", "int", "float", "double", "char", "bool", "long", "short", "byte",
	"unsigned", "signed", "const", "static", "String", "word", "boolean",
]


## Runs every applicable rule against [param code].
##
## [param model_name] is purely descriptive and is echoed in the summary so the
## UI can show which local model produced the report.
##
## Returns a dictionary:
##   issues      : Array[Dictionary] {severity, line, message, suggestion}
##   summary     : String
##   score       : int (0-100)
##   fixed_code  : String (best-effort corrected source)
##   has_changes : bool
static func analyze(code: String, model_name: String = "local") -> Dictionary:
	var lang: String = _detect_language(code)
	var issues: Array[Dictionary] = []

	if code.strip_edges().is_empty():
		return {
			"issues": issues,
			"summary": "No code to analyze. Open or write a sketch first.",
			"score": 100,
			"fixed_code": code,
			"has_changes": false,
			"language": lang,
		}

	var lines: PackedStringArray = code.split("\n")

	_check_balance(lines, issues)
	if lang == "gdscript":
		_check_gdscript(lines, issues)
	else:
		_check_arduino(lines, issues)

	var fixed_code: String = _apply_fixes(code, issues, lang)
	var has_changes: bool = fixed_code != code
	var score: int = _score(issues)

	return {
		"issues": issues,
		"summary": _build_summary(issues, lang, model_name),
		"score": score,
		"fixed_code": fixed_code,
		"has_changes": has_changes,
		"language": lang,
	}


# ---------------------------------------------------------------------------
# Language / helpers
# ---------------------------------------------------------------------------

static func _detect_language(code: String) -> String:
	if code.contains("func ") and code.contains("extends") and not code.contains("void setup"):
		return "gdscript"
	if code.contains("void setup") or code.contains("void loop") or code.contains("#include"):
		return "cpp"
	return "cpp"


## Removes string literals and comments so bracketed detection is reliable.
static func _scrub(line: String) -> String:
	var out := ""
	var in_str := false
	var in_chr := false
	var i := 0
	while i < line.length():
		var c := line[i]
		var nxt := line[i + 1] if i + 1 < line.length() else ""
		if not in_str and not in_chr:
			if c == "/" and nxt == "/":
				break
			if c == "\"":
				in_str = true
			elif c == "'":
				in_chr = true
			else:
				out += c
		else:
			if c == "\"" and in_str:
				in_str = false
			elif c == "'" and in_chr:
				in_chr = false
		i += 1
	return out


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

static func _check_balance(lines: PackedStringArray, issues: Array[Dictionary]) -> void:
	var depth := {"{": 0, "(": 0, "[": 0}
	var pairs := {"}": "{", ")": "(", "]": "["}
	var open_lines := {"{": 0, "(": 0, "[": 0}
	var order: Array[String] = []

	for idx in lines.size():
		var scrubbed: String = _scrub(lines[idx])
		for ch in scrubbed:
			if ch in ["{", "(", "["]:
				depth[ch] += 1
				order.append(ch)
				open_lines[ch] = idx + 1
			elif ch in pairs:
				var opener: String = pairs[ch]
				depth[opener] = max(0, int(depth[opener]) - 1)
				if not order.is_empty() and order.back() == opener:
					order.pop_back()

	for opener in ["{", "(", "["]:
		if int(depth[opener]) > 0:
			issues.append({
				"severity": Severity.ERROR,
				"line": int(open_lines[opener]),
				"message": "Unbalanced '%s' — %d unclosed." % [opener, depth[opener]],
				"suggestion": "Close the bracket opened near line %d." % int(open_lines[opener]),
			})


static func _check_arduino(lines: PackedStringArray, issues: Array[Dictionary]) -> void:
	var has_setup := false
	var has_loop := false
	var serial_begin := false
	var uses_serial := false
	var used_outputs: Array[int] = []
	var pinmodes: Array[int] = []

	for idx in lines.size():
		var line: String = lines[idx]
		var stripped: String = _scrub(line).strip_edges()
		var lineno: int = idx + 1

		if stripped.begins_with("void setup") or stripped.begins_with("void setup"):
			has_setup = true
		if stripped.begins_with("void loop"):
			has_loop = true
		if stripped.contains("Serial.begin"):
			serial_begin = true
		if stripped.contains("Serial.print") or stripped.contains("Serial.write") or stripped.contains("Serial.println"):
			uses_serial = true

		var pm: int = _extract_first_pin_arg(stripped, "pinMode")
		if pm >= 0:
			pinmodes.append(pm)
		var dw: int = _extract_first_pin_arg(stripped, "digitalWrite")
		if dw >= 0:
			used_outputs.append(dw)
		var aw: int = _extract_first_pin_arg(stripped, "analogWrite")
		if aw >= 0:
			used_outputs.append(aw)

		# Assignment inside a condition: if (x = 5)
		if _has_condition_assignment(stripped):
			issues.append({
				"severity": Severity.WARNING,
				"line": lineno,
				"message": "Assignment '=' used inside a condition.",
				"suggestion": "Use '==' for comparison, or add extra parentheses if intentional.",
			})

		# Missing semicolon on statement-like lines.
		if _looks_unterminated(stripped):
			issues.append({
				"severity": Severity.WARNING,
				"line": lineno,
				"message": "Statement may be missing a trailing ';'.",
				"suggestion": "Add ';' at the end of the line.",
			})

		# Long blocking delays.
		var delay_ms: int = _extract_delay(stripped)
		if delay_ms >= 500:
			issues.append({
				"severity": Severity.INFO,
				"line": lineno,
				"message": "Blocking delay(%d) freezes the sketch." % delay_ms,
				"suggestion": "Consider non-blocking timing with millis().",
			})

	if not has_setup:
		issues.append({"severity": Severity.ERROR, "line": 1,
			"message": "Missing 'void setup()'.", "suggestion": "Add void setup() { }."})
	if not has_loop:
		issues.append({"severity": Severity.ERROR, "line": 1,
			"message": "Missing 'void loop()'.", "suggestion": "Add void loop() { }."})
	if uses_serial and not serial_begin:
		issues.append({"severity": Severity.WARNING, "line": 1,
			"message": "Serial output used but Serial.begin() not found.",
			"suggestion": "Call Serial.begin(9600); in setup()."})

	for pin in used_outputs:
		if not pinmodes.has(pin):
			issues.append({
				"severity": Severity.WARNING, "line": 1,
				"message": "Pin %d is written to without pinMode()." % pin,
				"suggestion": "Add pinMode(%d, OUTPUT); in setup()." % pin,
			})


static func _check_gdscript(lines: PackedStringArray, issues: Array[Dictionary]) -> void:
	for idx in lines.size():
		var stripped: String = _scrub(lines[idx]).strip_edges()
		var lineno: int = idx + 1
		if stripped.begins_with("if") and _has_condition_assignment(stripped):
			issues.append({
				"severity": Severity.WARNING, "line": lineno,
				"message": "Assignment '=' inside an 'if' condition.",
				"suggestion": "Use '==' for comparison in GDScript.",
			})


# ---------------------------------------------------------------------------
# Fix generation
# ---------------------------------------------------------------------------

static func _apply_fixes(code: String, issues: Array[Dictionary], lang: String) -> String:
	var lines: Array[String] = []
	for l in code.split("\n"):
		lines.append(l)

	var need_serial := false
	var extra_setup: Array[String] = []
	var open_outputs: Array[int] = []

	for issue in issues:
		var msg: String = str(issue["message"])
		var line_no: int = int(issue["line"]) - 1

		if msg.begins_with("Statement may be missing") and line_no >= 0 and line_no < lines.size():
			if not lines[line_no].rstrip("\r").ends_with(";"):
				lines[line_no] = _add_semicolon(lines[line_no])
		elif msg.begins_with("Assignment") and line_no >= 0 and line_no < lines.size():
			lines[line_no] = _fix_condition_assignment(lines[line_no])
		elif msg.contains("Serial.begin() not found"):
			need_serial = true
		elif msg.contains("without pinMode()"):
			var pin_str: String = msg.trim_prefix("Pin ").trim_suffix(" is written to without pinMode().")
			open_outputs.append(int(pin_str))

	if need_serial:
		extra_setup.append("\tSerial.begin(9600);")
	for pin in open_outputs:
		extra_setup.append("\tpinMode(%d, OUTPUT);" % pin)

	if not extra_setup.is_empty():
		lines = _insert_into_setup(lines, extra_setup)

	return "\n".join(lines)


static func _add_semicolon(line: String) -> String:
	var trimmed: String = line.rstrip(" \t\r")
	var comment_pos: int = trimmed.find("//")
	if comment_pos >= 0:
		var head: String = trimmed.substr(0, comment_pos).rstrip(" ")
		var tail: String = trimmed.substr(comment_pos)
		return head + "; " + tail
	return trimmed + ";"


static func _fix_condition_assignment(line: String) -> String:
	# Replace the first standalone '=' (not ==, !=, <=, >=) inside parentheses.
	var result := ""
	var i := 0
	var replaced := false
	while i < line.length():
		var c := line[i]
		var prev := line[i - 1] if i > 0 else ""
		var nxt := line[i + 1] if i + 1 < line.length() else ""
		if c == "=" and nxt != "=" and prev != "=" and prev != "!" and prev != "<" and prev != ">" and not replaced:
			result += "=="
			replaced = true
		else:
			result += c
		i += 1
	return result


static func _insert_into_setup(lines: Array[String], extra: Array[String]) -> Array[String]:
	for i in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.begins_with("void setup"):
			# Find the opening brace (same line or next).
			if stripped.contains("{"):
				var insert_at := i + 1
				for j in range(extra.size() - 1, -1, -1):
					lines.insert(insert_at, extra[j])
				return lines
			if i + 1 < lines.size():
				lines.insert(i + 1, "{")
				var insert_at2 := i + 2
				for j in range(extra.size() - 1, -1, -1):
					lines.insert(insert_at2, extra[j])
				return lines
	return lines


# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------

static func _extract_first_pin_arg(stripped: String, fn_name: String) -> int:
	if not stripped.begins_with(fn_name):
		return -1
	var start: int = stripped.find("(")
	if start < 0:
		return -1
	var arg: String = stripped.substr(start + 1).split(",")[0].strip_edges()
	if arg.is_valid_int():
		return int(arg)
	return -1


static func _extract_delay(stripped: String) -> int:
	if not stripped.begins_with("delay("):
		return -1
	var start: int = stripped.find("(")
	if start < 0:
		return -1
	var arg: String = stripped.substr(start + 1).split(")")[0].strip_edges()
	if arg.is_valid_int():
		return int(arg)
	return -1


static func _has_condition_assignment(stripped: String) -> bool:
	var cond_start: int = stripped.find("(")
	if cond_start < 0:
		return false
	var cond: String = stripped.substr(cond_start)
	if not (cond.contains("if ") or cond.contains("while ") or cond.begins_with("if") or cond.begins_with("while")):
		# Only inspect actual conditions.
		if stripped.begins_with("if") or stripped.begins_with("while"):
			pass
		else:
			return false
	var inner: String = stripped
	# Single '=' not part of ==, !=, <=, >=
	for i in inner.length():
		if inner[i] == "=":
			var prev: String = inner[i - 1] if i > 0 else ""
			var nxt: String = inner[i + 1] if i + 1 < inner.length() else ""
			if prev != "=" and prev != "!" and prev != "<" and prev != ">" and nxt != "=":
				return true
	return false


static func _looks_unterminated(stripped: String) -> bool:
	if stripped.is_empty():
		return false
	if stripped.begins_with("#") or stripped.begins_with("//"):
		return false
	for kw in CPP_CONTROL:
		if stripped.begins_with(kw + " ") or stripped == kw:
			return false
	# Already terminated / structural lines.
	for ch in [";", "{", "}", ":", ",", "\\"]:
		if stripped.ends_with(ch):
			return false
	if stripped.ends_with(")") and _looks_like_signature(stripped):
		return false
	# A function-call statement, declaration, or assignment.
	var call_re := RegEx.new()
	call_re.compile("^[A-Za-z_][A-Za-z0-9_\\.\\[\\]>\\-]*\\s*\\(.*\\)\\s*$")
	var assign_re := RegEx.new()
	assign_re.compile("^[A-Za-z_][A-Za-z0-9_\\s\\[\\]<>\\.\\*&]*\\s*=\\s*.+$")
	if stripped.contains("(") and not stripped.ends_with(")") and call_re.search(stripped) == null:
		# e.g. `doThing(x` — likely a broken line, skip to avoid noise.
		return false
	return call_re.search(stripped) != null or assign_re.search(stripped) != null


static func _looks_like_signature(stripped: String) -> bool:
	for t in CPP_TYPES:
		if stripped.begins_with(t + " "):
			return true
	# `Foo bar(...)` constructor-ish declarations
	var sig_re := RegEx.new()
	sig_re.compile("^[A-Za-z_][A-Za-z0-9_]*\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\(.*\\)\\s*$")
	return sig_re.search(stripped) != null


static func _score(issues: Array[Dictionary]) -> int:
	var penalty := 0
	for issue in issues:
		match int(issue["severity"]):
			Severity.ERROR: penalty += 20
			Severity.WARNING: penalty += 8
			_: penalty += 3
	return clampi(100 - penalty, 0, 100)


static func _build_summary(issues: Array[Dictionary], lang: String, model_name: String) -> String:
	var errors := 0
	var warnings := 0
	var infos := 0
	for issue in issues:
		match int(issue["severity"]):
			Severity.ERROR: errors += 1
			Severity.WARNING: warnings += 1
			_: infos += 1

	if issues.is_empty():
		return "Model '%s' found no issues. Code looks clean." % model_name

	return "Model '%s' analysed the %s source: %d error(s), %d warning(s), %d note(s)." % [
		model_name, ("GDScript" if lang == "gdscript" else "Arduino/C++"), errors, warnings, infos
	]
