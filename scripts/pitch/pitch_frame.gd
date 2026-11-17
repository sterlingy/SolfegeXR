class_name PitchFrame
extends RefCounted
## One pitch estimate from a PitchSource.
## (RefCounted is Godot's ref-counted plain object, roughly a UE USTRUCT you pass by handle.)

var time: float        ## seconds, in the source's own clock
var frequency: float   ## Hz (meaningless when confidence is low)
var confidence: float  ## 0..1
var rms: float         ## input loudness 0..1


func _init(p_time := 0.0, p_frequency := 0.0, p_confidence := 0.0, p_rms := 0.0) -> void:
	time = p_time
	frequency = p_frequency
	confidence = p_confidence
	rms = p_rms
