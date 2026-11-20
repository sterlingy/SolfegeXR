class_name HtmlDoc
extends RefCounted
## Turns the app's own simple HTML pages (site/manual, site/privacy) into
## RichTextLabel BBCode, so they can be read inside XR, where a browser page
## can't be shown. Handles what those pages use: headings, paragraphs, lists,
## tables, bold/italic/code, links and element ids (for in-page links).
## Not a general HTML renderer.

const H1 := 56
const H2 := 46
const H3 := 40
const LINK_COLOR := "#7fd3ff"
const MUTED_COLOR := "#a9abbb"
## Whole elements left out: page furniture and pictures that can't be shown.
const SKIP := ["head", "style", "script", "svg", "button"]
## Elements whose class marks them as for the web page only.
const SKIP_CLASSES := ["hint", "open-app"]

var title := ""
var text := ""                 ## BBCode for a RichTextLabel
## element id -> the first words shown at that element (find them in
## RichTextLabel.get_parsed_text() to scroll there)
var anchors := {}


static func from_file(path: String) -> HtmlDoc:
	return from_html(FileAccess.get_file_as_string(path))


static func from_html(html: String) -> HtmlDoc:
	var doc := HtmlDoc.new()
	doc._convert(html)
	return doc


func _convert(html: String) -> void:
	var t := RegEx.create_from_string(r"(?is)<title>(.*?)</title>").search(html)
	if t:
		title = _decode(t.get_string(1)).strip_edges()
	html = RegEx.create_from_string(r"(?s)<!--.*?-->").sub(html, "", true)
	html = RegEx.create_from_string(r"<![^>]*>").sub(html, "", true)  # <!doctype html>
	html = _count_table_columns(html)
	var tag_re := RegEx.create_from_string(r"<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>")
	var out := ""
	var pos := 0
	var skip_stack: Array[String] = []   # tag names being skipped (nested)
	var lists: Array = []                 # [kind, counter] for each open ul/ol
	for m in tag_re.search_all(html):
		if skip_stack.is_empty():
			out += _text(html.substr(pos, m.get_start() - pos))
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2).to_lower()
		var attrs := m.get_string(3)
		if not skip_stack.is_empty():
			# Only track the element being skipped (and nested ones of the same name).
			if tag == skip_stack[-1]:
				if closing:
					skip_stack.pop_back()
				elif not attrs.ends_with("/"):
					skip_stack.append(tag)
			continue
		if not closing and (tag in SKIP or _has_class(attrs, SKIP_CLASSES)):
			if not attrs.ends_with("/") and tag not in ["br", "img", "meta", "link"]:
				skip_stack.append(tag)
			continue
		if not closing:
			var id := _attr(attrs, "id")
			if id != "" and not id.contains(char(2)):
				# Marked here, measured after tidying (see _tidy).
				var t_out := _tag(tag, closing, attrs, lists)
				var nl := t_out.rfind("\n")
				out += t_out.substr(0, nl + 1) + char(1) + id + char(2) + t_out.substr(nl + 1)
				continue
		out += _tag(tag, closing, attrs, lists)
	if skip_stack.is_empty():
		out += _text(html.substr(pos))
	text = _tidy(out)


func _tag(tag: String, closing: bool, attrs: String, lists: Array) -> String:
	match tag:
		"h1":
			return "[/b][/font_size]\n\n" if closing else "\n[font_size=%d][b]" % H1
		"h2":
			return "[/b][/font_size]\n" if closing else "\n\n[font_size=%d][b]" % H2
		"h3":
			return "[/b][/font_size]\n" if closing else "\n\n[font_size=%d][b]" % H3
		"p", "div", "section", "header", "nav", "figure":
			return "\n\n" if closing else "\n"
		"figcaption":
			return "[/i][/color]\n" if closing else "\n[color=%s][i]" % MUTED_COLOR
		"footer":
			return "[/color]\n" if closing else "\n\n[color=%s]" % MUTED_COLOR
		"br":
			return "\n"
		"strong", "b", "th":
			if tag == "th":
				return "[/b][/cell]" if closing else "[cell][b]"
			return "[/b]" if closing else "[b]"
		"em", "i":
			return "[/i]" if closing else "[i]"
		"code":
			return "[/code]" if closing else "[code]"
		"a":
			if closing:
				return "[/color][/url]"
			var href := _attr(attrs, "href")
			return "[url=%s][color=%s]" % [href.replace("]", ""), LINK_COLOR]
		"ul", "ol":
			if closing:
				if not lists.is_empty():
					lists.pop_back()
				return "\n"
			lists.append([tag, 0])
			return "\n"
		"li":
			if closing:
				return "\n"
			var indent := "    ".repeat(maxi(lists.size() - 1, 0))
			if not lists.is_empty() and lists[-1][0] == "ol":
				lists[-1][1] += 1
				return "\n%s  %d. " % [indent, lists[-1][1]]
			return "\n%s  •  " % indent
		"table":
			if closing:
				return "[/table]\n"
			return "\n[table=%d]" % maxi(1, _attr(attrs, "data-cols").to_int())
		"td":
			return "[/cell]" if closing else "[cell]"
	return ""


## Text between tags: whitespace collapsed, entities decoded, [ escaped.
func _text(s: String) -> String:
	if s.is_empty():
		return ""
	s = RegEx.create_from_string(r"\s+").sub(s, " ", true)
	return _decode(s).replace("[", "[lb]")


## Tables: [table=N] needs the column count up front; store it on the tag.
func _count_table_columns(html: String) -> String:
	var table_re := RegEx.create_from_string(r"(?is)<table([^>]*)>(.*?)</table>")
	var row_re := RegEx.create_from_string(r"(?is)<tr[^>]*>(.*?)</tr>")
	var cell_re := RegEx.create_from_string(r"(?i)<t[hd][\s>]")
	var out := ""
	var pos := 0
	for m in table_re.search_all(html):
		var first := row_re.search(m.get_string(2))
		var cols := cell_re.search_all(first.get_string(1)).size() if first else 1
		out += html.substr(pos, m.get_start() - pos)
		out += "<table data-cols=\"%d\"%s>%s</table>" % [cols, m.get_string(1), m.get_string(2)]
		pos = m.get_end()
	return out + html.substr(pos)


func _tidy(s: String) -> String:
	s = RegEx.create_from_string(r"[ \t]+\n").sub(s, "\n", true)
	s = RegEx.create_from_string(r"\n[ \t]+(?![ ]*(•|\d+\.))").sub(s, "\n", true)
	s = RegEx.create_from_string(r"\n{3,}").sub(s, "\n\n", true)
	s = s.strip_edges()
	# Element ids: remember the text that follows each one, as displayed, so
	# the reader can find it in RichTextLabel.get_parsed_text() (character
	# counts drift: tables add separators of their own).
	var marker := RegEx.create_from_string("\u0001([^\u0002]*)\u0002")
	var m := marker.search(s)
	while m:
		var after := s.substr(m.get_end(), 400).replace("\u0001", "").replace("\u0002", "")
		var plain := RegEx.create_from_string(r"\[(?!lb\])[^\]]*\]").sub(after, "", true).replace("[lb]", "[")
		anchors[m.get_string(1)] = plain.strip_edges().left(40).split("\n")[0]
		s = s.substr(0, m.get_start()) + s.substr(m.get_end())
		m = marker.search(s)
	return s


static func _attr(attrs: String, name: String) -> String:
	var m := RegEx.create_from_string(r'(?i)\b%s\s*=\s*"([^"]*)"' % name).search(attrs)
	return m.get_string(1) if m else ""


static func _has_class(attrs: String, classes: Array) -> bool:
	var cls := _attr(attrs, "class").split(" ", false)
	for c in classes:
		if c in cls:
			return true
	return false


static func _decode(s: String) -> String:
	var named := {"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
		"&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
		"&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&rarr;": "→", "&larr;": "←",
		"&middot;": "·", "&times;": "×", "&eacute;": "é", "&egrave;": "è"}
	for k in named:
		s = s.replace(k, named[k])
	var num := RegEx.create_from_string(r"&#(x?)([0-9a-fA-F]+);")
	var out := ""
	var pos := 0
	for m in num.search_all(s):
		out += s.substr(pos, m.get_start() - pos)
		var code := m.get_string(2).hex_to_int() if m.get_string(1) == "x" else m.get_string(2).to_int()
		out += String.chr(code)
		pos = m.get_end()
	return out + s.substr(pos)
