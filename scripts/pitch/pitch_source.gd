@abstract
class_name PitchSource
extends Node
## Platform-independent pitch input. Everything above this class is shared
## across web, Android and XR; only subclasses know where the audio comes from.
##
## Subclasses: WebPitchSource (JS AudioWorklet), FakePitchSource (editor demo).
## Later: a native GDExtension source using AudioEffectCapture.

signal state_changed(state: State, message: String)

enum State { IDLE, STARTING, RUNNING, ERROR }

var state: State = State.IDLE


@abstract func start() -> void
@abstract func stop() -> void

## Returns every frame produced since the last call, oldest first.
@abstract func poll() -> Array[PitchFrame]

## Current time on the same clock as PitchFrame.time.
@abstract func now() -> float


func describe() -> String:
	return ""


func _set_state(s: State, message := "") -> void:
	if s == state and message == "":
		return
	state = s
	state_changed.emit(s, message)
