extends Control
## Free sing: the original pitch-trace sandbox (scenes/main.tscn), with a Back button.


func setup(_args: Dictionary) -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene)
	var back := UI.flat_button("‹ Back", func(): App.back())
	back.position = Vector2(20, 0)
	add_child(back)
