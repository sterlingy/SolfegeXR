# Curated songs: check these in MuseScore

The melodies in `songs/*.musicxml` were transcribed from memory by Claude and **need checking**. Open each one in MuseScore (File → Open), fix any wrong notes or rhythms, then either:
- save over the `.musicxml` file (MuseScore: File → Export → MusicXML, uncompressed), or
- tell Claude the corrections, and it will update `tools/songs/make_songs.py`, the source of truth, and regenerate.

None of the files have lyrics yet; those wait until you've chosen lyric versions.

| # | Song | Key | Confidence | What to check |
|---|---|---|---|---|
| 1 | Ode to Joy | C major | high | — |
| 2 | When the Saints | C major | medium | phrase 3 ("Oh Lord I want to be in that number") |
| 3 | She'll Be Coming 'Round the Mountain | G major | **low** | phrases 3–4 especially |
| 4 | Oh! Susanna | C major | medium | chorus rhythm |
| 5 | Auld Lang Syne | F major | medium | chorus |
| 6 | Amazing Grace | G major | medium | second half |
| 7 | Drunken Sailor | D Dorian | high | — |
| 8 | Take Me Out to the Ball Game | C major | **low** | second half ("Let me root, root, root" onward) |
| 9 | Shenandoah | D major | **low** | whole tune |
| 10 | Danny Boy | C major | **low** | whole tune, especially the high section |
| 12 | God Rest You Merry, Gentlemen | E minor | high | Read from the Open Hymnal score (Stainer, 1918, public domain), tempo 160 as printed. The second "comfort and joy;" ends on A as printed (the familiar tune sings D). Listed before Carol, which stays the finale |
| 11 | Shchedryk (Carol of the Bells), layered | G minor | arrangement | Original 4-part layering on the public-domain folk ostinato. **Not** Leontovych's 1916 score; that needs a score source, e.g. a public-domain edition on IMSLP. |

Regenerate after editing the source:
```
python tools/songs/make_songs.py
```
The script checks that every bar adds up, allowing for pickup bars, and writes `songs/catalog.json` plus `tests/fixtures/ode_to_joy.mid`, a test file for the MIDI reader.
