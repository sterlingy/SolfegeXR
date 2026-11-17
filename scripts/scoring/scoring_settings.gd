class_name ScoringSettings
extends Resource
## Learner-level scoring parameters. A Resource (like a UE DataAsset) so presets
## can be saved as .tres and tuned without code changes.

@export_range(10.0, 100.0) var tolerance_cents := 50.0
@export var onset_grace := 0.15
@export var smoothing_window := 0.18
@export_range(0.3, 1.0) var landed_ratio := 0.7


## Tolerance tightens as the learner improves: 50 cents for beginners down
## to 25 for confident singers. `skill` is 0..1. Tune with real data later.
static func for_skill(skill: float) -> ScoringSettings:
	var s := ScoringSettings.new()
	s.tolerance_cents = lerpf(50.0, 25.0, clampf(skill, 0.0, 1.0))
	return s


func apply(n: NoteScorer) -> void:
	n.tolerance_cents = tolerance_cents
	n.onset_grace = onset_grace
	n.smoothing_window = smoothing_window
	n.landed_ratio = landed_ratio
