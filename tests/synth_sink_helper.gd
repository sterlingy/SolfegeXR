class_name TestSynthSink
extends RefCounted
## Records what SynthEngine sends to a sink (stand-in for the web synth).

var t := 0.0
var notes: Array = []
var stops: Array = []
var releases := 0


func time() -> float:
	return t


func note(v: Dictionary) -> void:
	notes.append(v)


func stop_kind(kind: int) -> void:
	stops.append(kind)


func release_all() -> void:
	releases += 1
