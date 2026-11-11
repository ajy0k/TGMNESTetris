# Tetris

This is a disassembly of Tetris (NES).

It builds the following rom:

* Tetris (U) [!].nes `md5: ec58574d96bee8c8927884ae6e7a2508`

To set up the repository, see [**INSTALL.md**](INSTALL.md).

## TGM mode (this branch)

On this branch the game plays by the rules of *Tetris The Grand Master* (TGM1)
while keeping the NES Tetris look: same screens, HUD, music and endings. The
rules engine is in [`tgm.asm`](tgm.asm); hooks into the original code are
marked with `TGM:` comments in `main.asm`.

Build with a system cc65 (`brew install cc65`) and Pillow:

	make            # or: make PYTHON=/path/to/python-with-pillow

Graphics edits (extra glyphs, the GRADE box and the timer box) are applied to
the PNG/nametable sources by `tools/tgm_assets.py`, which has already been run.

**Rules**

* Arika Rotation System: pieces spawn flat side up; a blocked rotation kicks
  one cell right, then left, unless the first cell of the rotated piece that
  hits something (reading top to bottom, left to right) is in the middle
  column. I and O never kick. Holding a rotate button while the next piece
  appears rotates it (IRS).
* Levels 0-999: +1 per piece, +1 per line. The level stops at x99 and 998
  until you clear a line.
* TGM1 gravity curve, reaching 20G at level 500. Lock delay 30 frames (resets
  only when the piece steps down), 30 frames ARE, 41 frame line clear, DAS 16.
* TGM randomizer (4 piece history, 4 rolls, first piece never S, Z or O).
* Score = (ceil((level + lines) / 4) + frames down was held) x lines x combo,
  x4 for clearing the whole field. Grades 9 to S9 come from the score.
* Grand Master: level 300 with 12,000 points by 4:15:00, level 500 with
  40,000 by 7:30:00, level 999 with 126,000 before 13:30:00.
* Level 999 ends the game and starts a 20G credit roll. Survive it (or top out
  in it) to reach the ending: the rocket depends on your grade, and a Grand
  Master launches the cathedral.

The rule numbers (gravity table, grade and GM thresholds, lock delay, ARE,
line clear time, DAS, scoring, randomizer and kick rule) were checked against
the TGM1 arcade program (`ate-05m.3h`). The credit roll length is an estimate.
The findings, with addresses, are in
[`docs/TGM1_ARCADE_NOTES.md`](docs/TGM1_ARCADE_NOTES.md); the script used is
[`tools/tgm_re/tgm1re.py`](tools/tgm_re/tgm1re.py).

**Controls**: left/right move, down soft drops and locks, B rotates
counter-clockwise, A rotates clockwise, Select hides NEXT, Start pauses.

**Menus**: A-TYPE is the normal game, B-TYPE is TGM's 20G mode. The level
chosen on the level menu picks the starting section (level x100); starting
above 0 rules out the GM grade. The high score tables record the grade in the
`GR` column.


Thanks to https://github.com/ejona86 for creating an info file and other files used to generate the disassembly code and other parts of the disassembly. (Original repository link:  https://github.com/ejona86/taus)

CHR png converting tools repository link: https://github.com/qalle2/nes-util
