class_name MasteryRules
extends Resource
## When a skill counts as mastered. Sensible defaults now; tune later from real
## learner data (this is a Resource so presets can be saved as .tres).

@export var window := 20                  ## look at the last N scored notes
@export_range(0.5, 1.0) var accuracy := 0.8  ## share of those notes landed
@export var min_days := 2                 ## practiced on at least this many days
@export var min_notes := 20               ## total scored notes before mastery is possible
