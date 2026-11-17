extends Node
## Global app state, registered as the autoload "App" (Project Settings →
## Globals). Like a UE GameInstance subsystem: one instance for the app's
## lifetime, reachable from any script as `App`.

const SCREENS_DIR := "res://scripts/ui/screens/"

var profile: LearnerProfile
var synth: SynthPlayer
var catalog: Array = []          ## [{id, title, file, confidence, note}]
var root: Control                ## where screens are shown (set by app_root)
var use_demo_singer := false     ## fake singer instead of the mic
var dev_autostart := false       ## dev: practice screens start immediately

var _source: PitchSource
var _screen: Control
var _history: Array = []         ## [[name, args], ...] for Back


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			LearnerProfile.save_path = a.trim_prefix("--profile=")
	profile = LearnerProfile.load_or_new()
	synth = SynthPlayer.new()
	add_child(synth)
	var text := FileAccess.get_file_as_string("res://songs/catalog.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		catalog = parsed
	use_demo_singer = not OS.has_feature("web")


## The active pitch source (created on first use).
func pitch_source() -> PitchSource:
	var want_fake := use_demo_singer or not OS.has_feature("web")
	if _source and (_source is FakePitchSource) != want_fake:
		_source.stop()
		_source.queue_free()
		_source = null
	if _source == null:
		_source = FakePitchSource.new() if want_fake else WebPitchSource.new()
		add_child(_source)
	return _source


## The demo singer, if that is the active source.
func fake_singer() -> FakePitchSource:
	return pitch_source() as FakePitchSource


## Start listening (on web this must follow a tap: browsers need a user gesture).
func ensure_listening() -> void:
	var s := pitch_source()
	if s.state == PitchSource.State.IDLE or s.state == PitchSource.State.ERROR:
		s.start()


func go(screen: String, args := {}, remember := true) -> void:
	if remember and _screen != null and _screen.has_meta("screen_name"):
		_history.append([_screen.get_meta("screen_name"), _screen.get_meta("screen_args")])
	if _screen:
		_screen.queue_free()
	synth.engine.release_all()
	var script: Script = load(SCREENS_DIR + screen + ".gd")
	_screen = script.new()
	_screen.set_meta("screen_name", screen)
	_screen.set_meta("screen_args", args)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_screen)
	if _screen.has_method("setup"):
		_screen.setup(args)


func back() -> void:
	if _history.is_empty():
		go("home", {}, false)
		return
	var prev: Array = _history.pop_back()
	go(prev[0], prev[1], false)


func home() -> void:
	_history.clear()
	go("home", {}, false)


func song_analysis(id: String) -> SongAnalyzer.Result:
	for s in catalog:
		if s.id == id:
			return SongAnalyzer.analyze(MusicXmlReader.load_file(s.file))
	return null


func _notification(what: int) -> void:
	# Android back button / browser back gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _screen and _screen.get_meta("screen_name") != "home":
		back()
