extends SceneTree
## Draws the placeholder app icon (until there's real branding) and saves it
## at the sizes the web app / PWA needs.
##   Godot_console.exe --path . --resolution 512x512 -s res://tools/make_icon.gd
## (Needs a window, not --headless, because it renders.)

const SIZES := [512, 192, 180, 144]
const OUT_DIR := "res://icons"


class IconArt extends Control:
	func _draw() -> void:
		var s := size.x
		var bg := Color("14151f")
		var lane := Color(1, 1, 1, 0.16)
		var gold := Color("ffd27a")
		var green := Color("8cf0a6")
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		# Lanes (like the pitch trace), with "do" in gold.
		for i in 5:
			var y := s * (0.24 + 0.13 * i)
			var col := gold if i == 3 else lane
			draw_line(Vector2(s * 0.1, y), Vector2(s * 0.9, y), col, s * (0.012 if i == 3 else 0.006))
		# A sung line sliding up and landing on the gold lane.
		var pts := PackedVector2Array()
		var land_y := s * (0.24 + 0.13 * 3)
		for k in 41:
			var u := k / 40.0
			var x := lerpf(s * 0.16, s * 0.74, u)
			var rise := clampf(u / 0.55, 0.0, 1.0)
			var ease := 1.0 - pow(1.0 - rise, 3.0)
			var y := lerpf(s * 0.86, land_y, ease)
			if u > 0.55:
				y += sin((u - 0.55) * 40.0) * s * 0.012 * (1.0 - (u - 0.55) * 1.5)
			pts.append(Vector2(x, y))
		draw_polyline(pts, green, s * 0.045, true)
		draw_circle(Vector2(s * 0.76, land_y), s * 0.06, green)
		draw_circle(Vector2(s * 0.76, land_y), s * 0.027, bg)


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(512, 512)
	var art := IconArt.new()
	art.size = Vector2(512, 512)
	root.add_child(art)
	_render.call_deferred()


func _render() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.crop(512, 512)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for size in SIZES:
		var copy := img.duplicate() as Image
		if size != 512:
			copy.resize(size, size, Image.INTERPOLATE_LANCZOS)
		copy.save_png(ProjectSettings.globalize_path("%s/icon_%d.png" % [OUT_DIR, size]))
		print("wrote icons/icon_%d.png" % size)
	quit()
