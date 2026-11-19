"""Generate MusicXML (and a MIDI test fixture) for the curated songs.

Melodies are written in a compact notation below, transcribed from memory of
the public-domain tunes. They NEED CHECKING in MuseScore (see `confidence`).
No lyrics yet: lyric versions are still being chosen.

Notation, space-separated tokens ("|" bar lines are checked, not required):
    <pitch><dur>[.][~][,]
    pitch: r (rest) | C4, F#4, Bb3 ...
    dur:   w h q e s (default q);  "." dotted;  "~" tie to next;  "," breath after
Run:  python tools/songs/make_songs.py
"""
import json
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "songs")

DIVISIONS = 4  # per quarter note -> 16th-note resolution
DUR = {"w": 16, "h": 8, "q": 4, "e": 2, "s": 1}
TYPES = {16: ("whole", 0), 12: ("half", 1), 8: ("half", 0), 6: ("quarter", 1),
         4: ("quarter", 0), 3: ("eighth", 1), 2: ("eighth", 0), 1: ("16th", 0)}
STEPS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
TOKEN = re.compile(r"^(r|[A-G](?:#|b)?\d)([whqes])?(\.)?(~)?(,)?$")

SONGS = [
    dict(id="01_ode_to_joy", title="Ode to Joy", fifths=0, mode="major", time=(4, 4), tempo=100,
         confidence="high", note="Beethoven, Symphony No. 9 theme. Stepwise; the first song.",
         parts=[("Melody", """
            E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | E4q. D4e D4h, |
            E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4q. C4e C4h, |
            D4 D4 E4 C4 | D4 E4e F4e E4 C4 | D4 E4e F4e E4 D4 | C4 D4 G3h, |
            E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4q. C4e C4h |""")]),
    dict(id="02_when_the_saints", title="When the Saints Go Marching In", fifths=0, mode="major",
         time=(4, 4), tempo=110, confidence="medium", note="Narrow range (an octave).",
         parts=[("Melody", """
            rq C4 E4 F4 | G4w | rq C4 E4 F4 | G4w, | rq C4 E4 F4 | G4h E4h | C4h E4h | D4w, |
            rq E4 E4 D4 | C4h. C4 | E4h G4 G4 | F4w, | rq E4 F4 G4 | E4h C4 D4 | C4w |""")]),
    dict(id="03_coming_round_the_mountain", title="She'll Be Coming 'Round the Mountain", fifths=1,
         mode="major", time=(4, 4), tempo=120, pickup=1, confidence="low",
         note="Repeated notes; group sing-along. Melody especially uncertain in phrases 3-4.",
         parts=[("Melody", """
            D4e E4e | G4 G4 G4 E4 | D4 B3 D4 G4 | A4h. G4e A4e, |
            B4 B4 B4 D5 | B4 A4 G4 A4 | B4h. B4e C5e, |
            D5 D5 D5 B4 | C5 C5 C5 A4 | B4 B4 A4 G4 | A4h. G4e A4e, |
            B4 B4 A4 G4 | A4 A4 B4 A4 | G4h. |""")]),
    dict(id="04_oh_susanna", title="Oh! Susanna", fifths=0, mode="major", time=(4, 4), tempo=120,
         pickup=1, confidence="medium", note="Steps plus small leaps. Lyrics: later standard verses.",
         parts=[("Melody", """
            C4e D4e | E4 G4 G4q. A4e | G4 E4 C4q. D4e | E4 E4 D4 C4 | D4h. C4e D4e, |
            E4 G4 G4q. A4e | G4 E4 C4q. D4e | E4 E4 D4 D4 | C4h. rq, |
            F4 F4 A4h | A4 G4 G4 E4 | C4 D4h C4e D4e, |
            E4 G4 G4q. A4e | G4 E4 C4q. D4e | E4 E4 D4 D4 | C4h. |""")]),
    dict(id="05_auld_lang_syne", title="Auld Lang Syne", fifths=-1, mode="major", time=(4, 4),
         tempo=80, pickup=1, confidence="medium",
         note="Sol-to-do leap at the start. Verse high confidence; chorus medium.",
         parts=[("Melody", """
            C4 | F4q. F4e F4 A4 | G4q. F4e G4 A4 | F4q. F4e A4 C5 | D5h. D5, |
            C5q. A4e A4 F4 | G4q. F4e G4 A4 | F4q. D4e D4 C4 | F4h. D5, |
            C5q. A4e A4 F4 | G4q. F4e G4 A4 | F4q. F4e A4 C5 | D5h. D5, |
            C5q. A4e A4 F4 | G4q. F4e G4 A4 | F4q. D4e D4 C4 | F4h. |""")]),
    dict(id="06_amazing_grace", title="Amazing Grace", fifths=1, mode="major", time=(3, 4), tempo=80,
         pickup=1, confidence="medium", note="Pentatonic; sustained notes.",
         parts=[("Melody", """
            D4 | G4h B4e G4e | B4h A4 | G4h E4 | D4h D4 | G4h B4e G4e | B4h A4 | D5h.~ | D5h, B4 |
            D5q. B4e D5e B4e | G4h D4 | E4q. G4e G4e E4e | D4h D4 | G4h B4e G4e | B4h A4 | G4h |""")]),
    dict(id="07_drunken_sailor", title="Drunken Sailor", fifths=0, mode="dorian", time=(2, 4),
         tempo=110, confidence="high", note="D Dorian; tests the minor/mode setting.",
         parts=[("Melody", """
            A4e A4e A4e A4e | A4e D4e F4e A4e | G4e G4e G4e G4e | G4e C4e E4e G4e |
            A4e A4e A4e A4e | A4e B4e C5e D5e | C5e A4e G4e E4e | D4 D4, |
            A4 A4 | A4e D4e F4e A4e | G4 G4 | G4e C4e E4e G4e |
            A4 A4 | A4e B4e C5e D5e | C5e A4e G4e E4e | D4 D4 |""")]),
    dict(id="08_take_me_out_to_the_ball_game", title="Take Me Out to the Ball Game", fifths=0,
         mode="major", time=(3, 4), tempo=150, confidence="low",
         note="Chromatic notes (G#, F#). 1908 lyrics. Second half especially uncertain.",
         parts=[("Melody", """
            C5h A4 | G4 E4 G4~ | G4h. | D4h., | C5h A4 | G4 E4 G4~ | G4h. | G4h., |
            A4 G#4 A4 | E4 F4 G4 | A4h F4 | D4h., | A4h A4 | A4 B4 C5 | D5 B4 A4 | G4 E4 D4, |
            C5h A4 | G4 E4 G4~ | G4h D4 | C4 D4 E4 | F4 G4 A4 | A4h., |
            A4 B4 C5 | C5h. | C5 C5 B4 | A4 G4 F#4 | G4h. | A4h. | B4h. | C5h. |""")]),
    dict(id="09_shenandoah", title="Shenandoah", fifths=2, mode="major", time=(4, 4), tempo=70,
         pickup=1, confidence="low", note="Long phrases, breath control, wide range.",
         parts=[("Melody", """
            A3 | D4q. D4e D4h | E4 F#4 G4 B4 | A4w, | D5 C#5 B4h | A4 B4 A4 F#4 | A4w, |
            B4q. B4e B4h | F#4 A4 F#4 E4 | D4w, | E4 F#4 D4h | F#4 B4 A4h | E4 F#4 E4h | D4h. |""")]),
    dict(id="10_danny_boy", title="Danny Boy (Londonderry Air)", fifths=0, mode="major", time=(4, 4),
         tempo=66, pickup=1.5, confidence="low", note="Wide range; the graduation song.",
         parts=[]),  # filled in below
]


def danny_boy():
    # Written out separately to keep the long line readable.
    return """
        C4e D4e E4e | F4h. E4e F4e | A4q. G4e F4 D4 | C4h. A3e C4e | D4h. C4e D4e | E4h~ E4e, C4e D4e E4e |
        F4h. E4e F4e | A4q. G4e F4 D4 | C4h. D4e E4e | F4h. G4e F4e | E4h~ E4e, G4e A4e B4e |
        C5h. B4e C5e | D5q. C5e B4 G4 | E4h~ E4e, C5e B4e C5e | A4h. G4e A4e | B4q. A4e G4 E4 |
        D4h~ D4e, C4e D4e E4e | F4h. A4e C5e | D5q. C5e A4 F4 | C5h. D5e E5e | F5h. E5e D5e |
        C5q. A4e F4 D4 | C4h. D4e E4e | F4h~ F4e |"""


SONGS[9]["parts"] = [("Melody", danny_boy())]

# Shchedryk ("Carol of the Bells" melody): the 4-note folk ostinato is public domain.
# This is an ORIGINAL layered arrangement around it, written for the app, not
# Leontovych's 1916 score (an exact transcription needs a score source).
_OSTINATO = "Bb4 A4e Bb4e G4 | " * 16
SONGS.append(dict(
    id="11_carol_of_the_bells", title="Shchedryk (Carol of the Bells), layered", fifths=-2,
    mode="minor", time=(3, 4), tempo=150, confidence="arrangement",
    note="Original 4-part layering on the public-domain folk ostinato; not Leontovych's exact score.",
    parts=[
        ("Bells (ostinato)", _OSTINATO),
        ("Descant", "rh. | " * 4 + "D5h. | C5h. | Bb4h. | A4h. | D5 C5 Bb4 | A4 Bb4 C5 | D5h.~ | D5h., |"
                    " D5 Eb5 D5 | C5 D5 C5 | Bb4 C5 Bb4 | A4h. |"),
        ("Thirds", "rh. | " * 8 + "G4 F#4e G4e Eb4 | " * 7 + "D4h. |"),
        ("Bass", "rh. | " * 12 + "G3h. | F3h. | Eb3h. | D3h. |"),
    ]))


# Traditional English carol (public domain), the usual "London" tune. Listed
# before Carol of the Bells, which stays the finale (and keeps its id).
SONGS.insert(len(SONGS) - 1, dict(
    id="12_god_rest_you_merry", title="God Rest You Merry, Gentlemen", fifths=1, mode="minor",
    time=(4, 4), tempo=100, pickup=1, confidence="low",
    note="E minor; a second minor-key song. Refrain (\"O tidings of comfort and joy\") especially uncertain.",
    parts=[("Melody", """
        E4 | E4 B4 B4 A4 | G4 F#4 E4 D4 | E4 F#4 G4 A4 | B4h. E4 |
        E4 B4 B4 A4 | G4 F#4 E4 D4 | E4 F#4 G4 A4 | B4h., B4 |
        C5 A4 B4 C5 | D5 E5 B4 A4 | G4 E4 F#4 G4 | A4h G4 A4 |
        B4h C5 B4 | B4 A4 G4 F#4 | E4h G4 F#4 | E4h G4 A4 | B4h C5 B4 | B4 A4 G4 F#4 | E4h. |""")]))


BAR_WARNINGS = []


def parse_notes(text, measure_div, pickup_div, where=""):
    notes = []
    sums, bar_sum = [], 0
    for tok in text.split():
        if tok == "|":
            sums.append(bar_sum)
            bar_sum = 0
            continue
        m = TOKEN.match(tok)
        if not m:
            raise ValueError("bad token %r" % tok)
        pitch, d, dot, tie, breath = m.groups()
        dur = DUR[d or "q"]
        if dot:
            dur = dur * 3 // 2
        notes.append(dict(pitch=pitch, dur=dur, tie=bool(tie), breath=bool(breath)))
        bar_sum += dur
    if bar_sum:
        sums.append(bar_sum)
    for i, got in enumerate(sums if measure_div else []):
        expected = measure_div
        if i == 0 and pickup_div:
            expected = pickup_div
        elif i == len(sums) - 1 and pickup_div:
            expected = measure_div - pickup_div  # final bar completes the pickup
        if got != expected:
            BAR_WARNINGS.append("%s bar %d: %s/16ths, expected %s" % (where, i, got, expected))
    return notes


def to_measures(notes, measure_div, pickup_div):
    """Split notes into measures, tying notes across bar lines."""
    measures, cur, room = [], [], (pickup_div or measure_div)
    for n in notes:
        remaining = n["dur"]
        first = True
        while remaining > 0:
            take = min(remaining, room)
            piece = dict(pitch=n["pitch"], dur=take, tie_stop=not first and n["pitch"] != "r",
                         tie_start=(remaining > take or n["tie"]) and n["pitch"] != "r",
                         breath=n["breath"] and remaining == take)
            cur.append(piece)
            remaining -= take
            room -= take
            first = False
            if room == 0:
                measures.append(cur)
                cur, room = [], measure_div
    if cur:
        measures.append(cur)
    # Mark tie_stop on notes following a tie_start of the same pitch.
    flat = [n for m in measures for n in m]
    for a, b in zip(flat, flat[1:]):
        if a["tie_start"] and a["pitch"] == b["pitch"]:
            b["tie_stop"] = True
    return measures


def split_representable(div):
    out = []
    for d in sorted(TYPES, reverse=True):
        while div >= d:
            out.append(d)
            div -= d
    return out


def pitch_xml(p):
    step, rest = p[0], p[1:]
    alter = 0
    if rest.startswith("#"):
        alter, rest = 1, rest[1:]
    elif rest.startswith("b"):
        alter, rest = -1, rest[1:]
    s = "<pitch><step>%s</step>" % step
    if alter:
        s += "<alter>%d</alter>" % alter
    return s + "<octave>%s</octave></pitch>" % rest


def note_xml(n, dur, tie_start, tie_stop, breath):
    x = "<note>"
    x += "<rest/>" if n["pitch"] == "r" else pitch_xml(n["pitch"])
    x += "<duration>%d</duration>" % dur
    if tie_stop:
        x += '<tie type="stop"/>'
    if tie_start:
        x += '<tie type="start"/>'
    x += "<voice>1</voice>"
    t, dots = TYPES[dur]
    x += "<type>%s</type>" % t + "<dot/>" * dots
    if tie_start or tie_stop or breath:
        x += "<notations>"
        if tie_stop:
            x += '<tied type="stop"/>'
        if tie_start:
            x += '<tied type="start"/>'
        if breath:
            x += "<articulations><breath-mark/></articulations>"
        x += "</notations>"
    return x + "</note>"


def song_xml(s):
    beats, beat_type = s["time"]
    measure_div = beats * DIVISIONS * 4 // beat_type
    pickup_div = int(s.get("pickup", 0) * DIVISIONS)
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
           '"http://www.musicxml.org/dtds/partwise.dtd">',
           '<score-partwise version="4.0">',
           "<work><work-title>%s</work-title></work>" % s["title"].replace("&", "&amp;"),
           "<identification><encoding><software>SolfegeApp make_songs.py</software></encoding>"
           "<miscellaneous><miscellaneous-field name=\"confidence\">%s</miscellaneous-field>"
           "</miscellaneous></identification>" % s["confidence"],
           "<part-list>"]
    for i, (name, _) in enumerate(s["parts"]):
        out.append('<score-part id="P%d"><part-name>%s</part-name></score-part>' % (i + 1, name))
    out.append("</part-list>")
    lengths = []
    for i, (name, text) in enumerate(s["parts"]):
        measures = to_measures(parse_notes(text, measure_div, pickup_div, s["id"] + "/" + name), measure_div, pickup_div)
        lengths.append(sum(n["dur"] for m in measures for n in m))
        out.append('<part id="P%d">' % (i + 1))
        for mi, m in enumerate(measures):
            implicit = ' implicit="yes"' if mi == 0 and pickup_div else ""
            out.append('<measure number="%d"%s>' % (mi if pickup_div else mi + 1, implicit))
            if mi == 0:
                out.append("<attributes><divisions>%d</divisions><key><fifths>%d</fifths><mode>%s</mode>"
                           "</key><time><beats>%d</beats><beat-type>%d</beat-type></time>"
                           "<clef><sign>%s</sign><line>%d</line></clef></attributes>"
                           % (DIVISIONS, s["fifths"], s["mode"], beats, beat_type,
                              *(("F", 4) if "Bass" in name else ("G", 2))))
                if i == 0:
                    out.append('<direction placement="above"><direction-type><metronome>'
                               "<beat-unit>quarter</beat-unit><per-minute>%d</per-minute></metronome>"
                               '</direction-type><sound tempo="%d"/></direction>' % (s["tempo"], s["tempo"]))
            for n in m:
                pieces = split_representable(n["dur"])
                for pi, d in enumerate(pieces):
                    last = pi == len(pieces) - 1
                    out.append(note_xml(n, d,
                                        tie_start=(n["tie_start"] or not last) and n["pitch"] != "r",
                                        tie_stop=(n["tie_stop"] or pi > 0) and n["pitch"] != "r",
                                        breath=n["breath"] and last))
            out.append("</measure>")
        out.append("</part>")
    out.append("</score-partwise>")
    return "\n".join(out), lengths


def midi_for(s):
    """Format-1 MIDI of the first part (test fixture for MidiReader)."""
    tpq = 480
    name, text = s["parts"][0]
    events, tick = [], 0
    for n in parse_notes(text, 0, 0):
        ticks = n["dur"] * tpq // DIVISIONS
        if n["pitch"] != "r":
            p = n["pitch"]
            midi = 12 * (int(p[-1]) + 1) + STEPS[p[0]] + (1 if "#" in p else -1 if "b" in p[1:] else 0)
            events.append((tick, 0x90, midi, 90))
            events.append((tick + ticks, 0x80, midi, 0))
        tick += ticks
    events.sort(key=lambda e: (e[0], e[1] == 0x90))

    def vlq(v):
        b = [v & 0x7F]
        v >>= 7
        while v:
            b.insert(0, (v & 0x7F) | 0x80)
            v >>= 7
        return bytes(b)

    meta = vlq(0) + b"\xff\x51\x03" + (60000000 // s["tempo"]).to_bytes(3, "big")
    meta += vlq(0) + b"\xff\x59\x02" + struct.pack("bB", s["fifths"], 1 if s["mode"] == "minor" else 0)
    meta += vlq(0) + b"\xff\x03" + bytes([len(s["title"])]) + s["title"].encode()
    meta += vlq(0) + b"\xff\x2f\x00"
    trk, last = vlq(0) + b"\xff\x03" + bytes([len(name)]) + name.encode(), 0
    for t, st, k, v in events:
        trk += vlq(t - last) + bytes([st, k, v])
        last = t
    trk += vlq(0) + b"\xff\x2f\x00"
    chunk = lambda tag, data: tag + struct.pack(">I", len(data)) + data
    return chunk(b"MThd", struct.pack(">HHH", 1, 2, tpq)) + chunk(b"MTrk", meta) + chunk(b"MTrk", trk)


def main():
    os.makedirs(OUT, exist_ok=True)
    catalog = []
    for s in SONGS:
        xml, lengths = song_xml(s)
        if len(set(lengths)) > 1:
            print("WARNING %s: parts differ in length %s" % (s["id"], lengths))
        path = os.path.join(OUT, s["id"] + ".musicxml")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(xml)
        catalog.append(dict(id=s["id"], title=s["title"], file="res://songs/%s.musicxml" % s["id"],
                            confidence=s["confidence"], note=s["note"]))
        print("wrote", os.path.relpath(path, ROOT))
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(catalog, f, indent=2)
    fixtures = os.path.join(ROOT, "tests", "fixtures")
    os.makedirs(fixtures, exist_ok=True)
    with open(os.path.join(fixtures, "ode_to_joy.mid"), "wb") as f:
        f.write(midi_for(SONGS[0]))
    print("wrote tests/fixtures/ode_to_joy.mid")
    for w in BAR_WARNINGS:
        print("BAR CHECK", w)


if __name__ == "__main__":
    main()
