extends TestCase
## HtmlDoc: the manual and privacy pages as BBCode for reading inside XR.


func test_basic_formatting() -> void:
	var d := HtmlDoc.from_html("""<html><head><title>T &amp; U</title><style>p{}</style></head><body>
<h1>Big</h1><p>Hello <strong>bold</strong> and <em>it</em> [x] &rsquo;</p>
<ul><li>one</li><li>two</li></ul><ol><li>first</li><li>second</li></ol>
<h2 id="sec">Part</h2><p><a href="#sec">jump</a></p></body></html>""")
	assert_eq(d.title, "T & U")
	assert_true(d.text.contains("[b]bold[/b]"), d.text)
	assert_true(d.text.contains("[i]it[/i]"))
	assert_true(d.text.contains("[lb]x]"), "square brackets escaped")
	assert_true(d.text.contains("’"), "entities decoded")
	assert_true(d.text.contains("•  one") and d.text.contains("•  two"), "bullets")
	assert_true(d.text.contains("1. first") and d.text.contains("2. second"), "numbers")
	assert_true(d.text.contains("[url=#sec]"), "links kept")
	assert_false(d.text.contains("p{}"), "style dropped")
	assert_true(d.anchors.has("sec"), "id recorded")
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = d.text
	var shown := label.get_parsed_text()
	assert_eq(d.anchors.sec, "Part")
	assert_true(shown.find(d.anchors.sec) >= 0, "findable in the displayed text")
	label.free()


func test_table_column_count() -> void:
	var d := HtmlDoc.from_html("<table><tr><th>A</th><th>B</th><th>C</th></tr><tr><td>1</td><td>2</td><td>3</td></tr></table>")
	assert_true(d.text.contains("[table=3]"), d.text)
	assert_eq(d.text.count("[cell]"), 6)
	assert_eq(d.text.count("[/cell]"), 6)


func test_real_pages_convert() -> void:
	for page in ["manual", "privacy"]:
		var d := HtmlDoc.from_file("res://site/%s/index.html" % page)
		assert_true(d.title.contains("Solfège Master XR"), page + " title: " + d.title)
		assert_true(d.text.length() > 2000, page + " has its text")
		assert_false(d.text.contains("<"), page + " has no leftover tags")
		assert_false(d.text.contains("Opened from the app?"), page + " web-only hint dropped")
		# Every opened BBCode tag that needs closing is closed.
		for tag in ["b", "i", "url", "table", "cell", "font_size", "color", "code"]:
			var opens := RegEx.create_from_string(r"\[%s[=\]]" % tag).search_all(d.text).size()
			assert_eq(d.text.count("[/%s]" % tag), opens, "%s: [%s] balanced" % [page, tag])
	var manual := HtmlDoc.from_file("res://site/manual/index.html")
	for id in ["quick-start", "trouble", "settings", "privacy"]:
		assert_true(manual.anchors.has(id), "manual anchor " + id)
