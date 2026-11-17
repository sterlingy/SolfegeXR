class_name Skills
extends RefCounted
## The one skill model shared by the core curriculum and generated song courses.
## Order = core curriculum order.

enum Id {
	PITCH_MATCH,      ## land a single note (sirens, slides)
	SUSTAIN,          ## hold a note steady
	STEPS,            ## move by a scale step
	SMALL_LEAPS,      ## thirds
	LARGE_LEAPS,      ## fourths and wider
	PHRASES,          ## phrases and songs
	MINOR_MODES,      ## minor keys and modes
	CHROMATIC,        ## notes outside the key (only when that toggle is on)
	BACKING_TRACK,    ## singing with accompaniment
	ENSEMBLE,         ## singing alongside other voices
}

const NAMES := {
	Id.PITCH_MATCH: "Matching a note",
	Id.SUSTAIN: "Holding a note",
	Id.STEPS: "Steps",
	Id.SMALL_LEAPS: "Small leaps",
	Id.LARGE_LEAPS: "Big leaps",
	Id.PHRASES: "Phrases and songs",
	Id.MINOR_MODES: "Minor keys and modes",
	Id.CHROMATIC: "Notes outside the scale",
	Id.BACKING_TRACK: "Singing with a backing track",
	Id.ENSEMBLE: "Singing with other voices",
}


static func core_order() -> Array[Id]:
	var out: Array[Id] = []
	for id in Id.values():
		out.append(id)
	return out


static func display_name(id: Id) -> String:
	return NAMES.get(id, "?")
