extends Node
## Global app state, registered as the autoload "App" (Project Settings →
## Globals). Like a UE GameInstance subsystem: one instance for the app's
## lifetime, reachable from any script as `App`.

const SCREENS_DIR := "res://scripts/ui/screens/"

## The syllable the learner is aiming at right now (practice), for the XR hand sign.
signal target_syllable_changed(syllable: String)

var profile: LearnerProfile
var synth: SynthPlayer
var catalog: Array = []          ## [{id, title, file, confidence, note}]
var root: Control                ## where screens are shown (set by app_root)
var use_demo_singer := false     ## fake singer instead of the mic
var dev_autostart := false       ## dev: practice screens start immediately

var _source: PitchSource
var _screen: Control
var _history: Array = []         ## [[name, args], ...] for Back


## The brand name, for window and browser-tab titles. The project's
## config/name stays "SolfegeApp" because it names the save-data folder.
const DISPLAY_NAME := "Solfège Master XR"


func _ready() -> void:
	# Deferred: Godot sets the title from config/name after autoloads are ready.
	DisplayServer.window_set_title.call_deferred(DISPLAY_NAME)
	UI.install_music_font()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			LearnerProfile.save_path = a.trim_prefix("--profile=")
	profile = LearnerProfile.load_or_new()
	synth = SynthPlayer.new()
	add_child(synth)
	synth.engine.timbre = profile.timbre as SynthEngine.Timbre
	var text := FileAccess.get_file_as_string("res://songs/catalog.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		catalog = parsed
	# Desktop/mobile builds use the real mic too; --demo (dev) or the Settings
	# toggle switches to the demo singer.
	use_demo_singer = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/platform.js"), true)


## iPhone/iPad (every iOS browser is Safari underneath).
func is_ios() -> bool:
	if not OS.has_feature("web"):
		return OS.get_name() == "iOS"
	return bool(JavaScriptBridge.eval("!!(window.solfegePlatform && window.solfegePlatform.isIOS())", true))


## Safari 16.4+ can play tones with the silent switch on.
func ios_handles_silent_switch() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!navigator.audioSession", true))


## A short tip for iPhone users who might not hear the tones, or "".
func ios_audio_tip() -> String:
	if not is_ios() or profile.has_headphones:
		return ""
	if ios_handles_silent_switch():
		return "On iPhone: if the tones are quiet, turn the volume up, or use headphones."
	return "On iPhone: turn off silent mode (the switch on the side) to hear the tones, or use headphones."


## The active pitch source (created on first use).
func pitch_source() -> PitchSource:
	var want_fake := use_demo_singer
	if _source and (_source is FakePitchSource) != want_fake:
		_source.stop()
		_source.queue_free()
		_source = null
	if _source == null:
		if want_fake:
			_source = FakePitchSource.new()
		elif OS.has_feature("web"):
			_source = WebPitchSource.new()
		else:
			_source = NativePitchSource.new()
		add_child(_source)
	return _source


## The demo singer, if that is the active source.
func fake_singer() -> FakePitchSource:
	return pitch_source() as FakePitchSource


## Start listening (on web this must follow a tap: browsers need a user gesture).
func ensure_listening() -> void:
	var s := pitch_source()
	if s is WebPitchSource:
		(s as WebPitchSource).device_id = profile.mic_device_id
	elif s is NativePitchSource and profile.mic_device_id != "":
		AudioServer.input_device = profile.mic_device_id
	if s.state == PitchSource.State.IDLE or s.state == PitchSource.State.ERROR:
		s.start()


## Open the user manual (served next to the app at manual/).
func open_manual() -> void:
	open_site_page("manual")


## Open one of the plain pages served next to the app (manual, privacy).
func open_site_page(page: String) -> void:
	# In XR (or its desktop preview) the page opens in a window in the scene:
	# a new browser tab would leave or hide the XR session.
	if XRMode.doc_requested.get_connections().size() > 0:
		XRMode.doc_requested.emit(page)
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(new URL('%s/', location.href).href, '_blank')" % page, true)
	else:
		OS.shell_open(ProjectSettings.globalize_path("res://site/%s/index.html" % page))


## Choose a microphone; remembered in the profile.
func select_mic(id: String) -> void:
	if id == "demo":
		return
	profile.mic_device_id = id
	profile.save()
	pitch_source().select_device(id)


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


## Built-in songs plus the learner's imported ones.
func all_songs() -> Array:
	var out := catalog.duplicate()
	for e in SongLibrary.list():
		out.append({id = e.id, title = e.title, file = e.file, confidence = "yours",
			note = "Imported " + str(e.imported_on), imported = true})
	return out


func song_entry(id: String) -> Dictionary:
	for s in all_songs():
		if s.id == id:
			return s
	return {}


## The song analysed for the part this learner sings: the one they picked,
## else the melody.
func song_analysis(id: String) -> SongAnalyzer.Result:
	var entry := song_entry(id)
	if entry.is_empty():
		return null
	var song := SongLibrary.parse_file(entry.file)
	if song == null:
		return null
	return SongAnalyzer.analyze(song, part_for(song, id, profile))


## Which voice of `song` the learner sings: their saved choice, else the
## melody (the tune people know; a lone bass line is a choice, not a default).
static func part_for(song: Song, id: String, p: LearnerProfile) -> Song.Part:
	var chosen := song.part_named(p.song_parts.get(id, ""))
	return chosen if chosen != null else song.melody()


## The part whose written range sits closest to the learner's voice (a bass
## gets the bass line); ties go to the earlier part. Shown as a suggestion.
static func best_fit_part(song: Song, p: LearnerProfile) -> Song.Part:
	var best: Song.Part = null
	var best_shift := 999
	for part in song.singable_parts():
		var shift := absi(SongAnalyzer.analyze(song, part).transposition_for(p.voice_low, p.voice_high))
		if shift < best_shift:
			best = part
			best_shift = shift
	return best if best != null else song.melody()


func _notification(what: int) -> void:
	# Android back button / browser back gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _screen and _screen.get_meta("screen_name") != "home":
		back()
