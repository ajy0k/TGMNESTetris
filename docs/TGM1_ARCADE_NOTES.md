# TGM1 arcade program notes

Notes from reading the program of *Tetris The Grand Master* (Arika, 1998,
Japanese set `tgmj`) to check the rules used by the NES port in
[`tgm.asm`](../tgm.asm). They cover the parts of the game logic that decide
how the game plays: timings, gravity, rotation, randomizer, levels, scoring
and grading. Graphics, sound, menus and attract mode were not studied.

Every address below is a RAM address in the running program. Each finding
is marked:

* **verified**: read directly from the code or data;
* **inferred**: the most likely reading, not traced all the way;
* **unknown**: looked at, not worked out.

All of it can be re-checked with [`tools/tgm_re/tgm1re.py`](../tools/tgm_re/tgm1re.py)
(see [Reproducing](#reproducing)).

## Summary

| Rule | Arcade value | Where |
|---|---|---|
| Gravity | per-level table, 4/256 G at 0 ... 20G from 500 | `$80072C84` |
| Lock delay | 30 frames, reset when the piece steps down | state `$14` |
| Lock to next piece, no line clear | 31 frames (3 flash + 1 lock + 25 ARE + 1 + spawn) | states `$1E` `$3C` `$64` `$0A` |
| Extra frames for a line clear | 41 (40-frame timer + 1 collapse frame) | states `$28` `$32` |
| DAS | move, then every frame from the 16th frame held | `$8001965C` |
| Wall kick | right then left, blocked if the first collision is in the middle column; I never kicks | `$8001910C` |
| Randomizer | C `rand()` LCG, 4-piece history, 3 checked rolls + 1 unchecked | state `$0A` |
| Levels | +1 per piece (at the end of ARE), +n per n lines, stop at x99 / 998 | `$80029DDC` |
| Score | (ceil(level / 4) + soft) x lines x combo, x4 on an all clear | state `$1E` |
| Grades | 18 score thresholds, 400 ... 120000, 126000 | `$80073CDC` |
| GM | 300: grade 1 and <= 15300 frames; 500: S4 and <= 27000; 999: 126000 and <= 48599 | `$80073D24` |

"Frame" means one pass of the game loop (one video frame). The game times
everything, including the clock shown on screen, in frames.

## The ROM set

| File | Size | Contents |
|---|---|---|
| `ate-05m.3h` | 4 MB | Program code and game data. Starts with `Licensed by Sony Computer Entertainment Inc.(SCEI)` (the board is the PlayStation-based Sony ZN-1). Everything below comes from this file. |
| `ate_02.2e` | 128 KB | Sound program: `Q1 SOUND DRIVER Version 1.00.02.03.1998 (C)1997,1998 ARIKA`. |
| `ate-01m.3a`, `ate-06m.4h` | 4 MB each | Data (graphics/samples). Not examined. |
| `atej_04.2h` | 512 KB | No readable strings. Not examined. |

### Load address

The CPU is a little-endian MIPS R3000. **ROM offset 0 of `ate-05m.3h`
corresponds to RAM address `$80008778`**, so `RAM = offset + $80008778`.
This was found by trying candidate bases and counting how many `jal`
targets in the first 1 MB land on a function prologue (`addiu sp, sp, -N`).
`$80008778` won with 887 hits; the next best had 389. It was then confirmed
by the data tables below being referenced from code at exactly those
addresses.

A second copy of the grade table sits at ROM offset `$163CDC`. That part of
the ROM was not looked at (it may be a second copy of the program).

## Memory map

### Globals

| Address | Use | Status |
|---|---|---|
| `$80176938` | Player 1 structure (player 2 at `+$5A8`) | verified |
| `$801C2120` | Buttons newly pressed this frame, one u16 per player | verified |
| `$801C2128` | Buttons held, one u16 per player | verified |
| `$8012B030` | Soft-drop frame counter, one u8 per player | verified |
| `$801C1208` | Global mode flags. Bits 0-1: game logic waits (pause/freeze); bit 3: an alternate mode (two-player?) that changes several rules, including capping the level at 199 | inferred |

Button bits follow the PlayStation pad layout: `$1000` up, `$2000` right,
`$4000` down, `$8000` left. A player flag (`$10000000` in the flags word)
swaps the directions: with it set the code treats `$1000` as down and swaps
left and right (purpose unknown). Bit `$0010` starts a rotation (inferred,
from `$80013ADC`).

### Player structure (offsets from `$80176938`)

| Offset | Size | Meaning | Status |
|---|---|---|---|
| `$24` | u8 | Which update routine runs (5 cases; gameplay = `$80011550`) | verified |
| `$25` | u8 | Player state, index into the state table | verified |
| `$28` | s16 | General delay timer (line clear, ARE) | verified |
| `$30` | u32 | Flags. `$100000`: game finished (level 999). `$200000`: end sequence done, go to state `$6E`. `$0800`: skip the rest of the line clear wait (purpose unknown). Others unknown. | partly verified |
| `$34` | u8 | Player number (0/1) | verified |
| `$3A` | s16 | DAS counter | verified |
| `$3C` | s16 | Lock delay counter | verified |
| `$40` | u32 | Randomizer seed | verified |
| `$44` | u8 x 8 | Piece history, newest first (the randomizer checks the first 4) | verified |
| `$4C` | u32 | Rows cleared by the last piece, one bit per row (0 = no lines) | verified |
| `$50` | u32 | Combo | verified |
| `$54` | u32 | Game clock, frames | verified (its increment was not traced) |
| `$58`, `$70` | u32 | Clock copied here when the grade changes | verified |
| `$5C` | u32 | Score | verified |
| `$62` | u16 | Level | verified |
| `$64` | u16 | Grade: 0 = 9 ... 8 = 1, 9 = S1 ... 17 = S9, 18 = GM | verified |
| `$66` | u16 | Section (level / 100, 0-9) | verified |
| `$68` | u8 | GM checkpoints passed: bit 0 = level 300, bit 1 = level 500 | verified |
| `$6C` | s32 | Lock flash counter | verified |
| `$76` | u16 | Pieces dealt | verified |
| `$9A` | u16 | Next piece (type) | verified |
| `$9C` | u16 | Current piece: low nibble = type, high nibble = variant (`$50` takes a separate rotation path) | verified |
| `$9E` | s16 | Rotation, 0-3 | verified |
| `$A2` | s16 | Column | verified |
| `$A4` | u32 | Row as 16.16 fixed point: the low half is the fraction, `$A6` is the row. Rows count **upwards** (moving down = row - 1) | verified |
| `$BC` | s16 x 12 x 22 | Playfield, 24 bytes per row, 12 columns including the walls | inferred |

Piece types: 2 = I, 3 = Z, 4 = S, 5 = J, 6 = L, 7 = O, 8 = T.

## Frame loop

`$8001B1B4` runs one game frame (one of several mode-specific copies):

1. `$800107CC` for player 1, then for player 2. This picks a routine by
   player `$24`; during play that is `$80011550`, the player state machine.
2. `$8004FEA0` (not examined).
3. `$800155B4`: draws everything, including both players' pieces
   (`$80017B74`).
4. `$8003A8B0`: once-per-frame bookkeeping. It updates grades
   (`$8002A378`), handles section changes and the x99 stop (`$80029DDC`)
   and checks for GM at 999 (`$8002A460`).

Because drawing happens after the game logic, a counter that the drawing
code changes is seen by the logic one frame later. That matters for the
lock flash.

## Player state machine (`$80011550`)

The state is player `$25`, dispatched through a 118-entry table at
`$8006DE34`. States not listed point to an empty handler.

| State | Handler | Role | Status |
|---|---|---|---|
| `$00` | `$800116B0` | Start of game | inferred |
| `$0A` | `$800133B8` | Spawn: deal the next piece, roll the randomizer | verified |
| `$14` | `$8001384C` | Active piece: input, rotation, gravity, lock delay | verified |
| `$1E` | `$80013EF0` | Lock: wait for the flash, place the piece, clear lines, score | verified |
| `$28` | `$8001486C` | Line clear wait | verified |
| `$32` | `$800148F8` | Collapse cleared rows | verified |
| `$3C` | `$80014A90` | ARE | verified |
| `$46` | `$80014BA8` | Rows rising from below (two-player garbage?) | inferred |
| `$50`, `$51` | `$80014CC0`, `$80014D3C` | Part of the rising-rows sequence | unknown |
| `$5A`-`$60` | `$80011714` ... `$80012FD8` | Game start sequence | unknown |
| `$64` | `$80013354` | One frame between ARE and spawn | verified |
| `$6E`-`$75` | `$80014DAC` ... `$80015568` | Game over and end-of-game sequence | inferred |

Most handlers start by checking `$801C1208 & 3` and the player flags, and
do nothing that frame if the game is paused or frozen.

### Piece life cycle, frame by frame

L is the frame on which the lock delay runs out (or down is held on the
ground).

| Frame | State | What happens |
|---|---|---|
| L | `$14` | Lock counter reaches 0: lock flash counter `$6C` = 1, state = `$1E`. Drawing that frame: `$6C` 1 -> 2 (piece drawn white). |
| L+1, L+2 | `$1E` | Waits while `$6C` > 0. Drawing: 2 -> 3, then 3 -> 4. |
| L+3 | `$1E` | Still waiting. Drawing: `$6C` >= 4, plays a sound and sets `$6C` = -1. |
| L+4 | `$1E` | `$6C` = -1: reset to 0, place the piece (`$80019470`, inferred), find full rows, score. Lines: state `$28` with timer 40. No lines: state `$3C` with timer 25. |
| L+5 ... L+29 | `$3C` | ARE: timer 25 -> 0. When it hits 0: state `$64`, level + 1. |
| L+30 | `$64` | State = `$0A`. |
| L+31 | `$0A` | New piece appears (lock counter = 30), state = `$14`. It cannot move this frame. |
| L+32 | `$14` | First frame the new piece can move. |

With a line clear, L+5 to L+44 is state `$28` counting 40 frames down,
L+45 is state `$32` (collapse, then state `$3C` with timer 25), and the ARE
follows. **The next piece appears 31 frames after L without a line clear and
72 frames after L with one.** The usual figures "ARE 30, line clear 41" come
from this sum.

### Lock delay (state `$14`, around `$80013E00`-`$80013EE8`)

* The lock counter `$3C` is set to 30 when the piece spawns and every time
  it moves down a row.
* Each frame the piece is resting on something, the counter goes down by 1
  (the landing frame included; a sound plays on the first such frame).
* Holding down (`$4000`) on the ground sets the counter to 0.
* At 0 the piece locks. So a piece with no input locks on its 30th frame on
  the ground. Moving or rotating does not reset the counter.

### Gravity (`$80013C94` onward)

* Gravity = `gravityTable[level]`, a 16.16 number of rows per frame.
* Holding down adds 1 to the soft-drop counter at `$8012B030 + player` and
  raises gravity to at least 1 row per frame (`$10000`).
* The piece's row (`$A4`, 16.16) goes down by the gravity, one row at a
  time with collision checks.
* A debug-looking override sets gravity to `$400` when bit 1 of
  `$801859A0` and button bit `$40` are both set (unknown).

The table at `$80072C84` (ROM offset `$6A50C`) has 1001 u32 entries, one per
level from 0 to 1000. In 256ths of a cell per frame:

```
level:   0   30  35  40  50  60  70  80  90 100 120 140 160 170 200 220 230 233 236 239 243 247 251 300 330  360  400  420 450  500
G/256:   4    6   8  10  12  16  32  48  64  80  96 112 128 144   4  32  64  96 128 160 192 224 256 512 768 1024 1280 1024 768 5120
```

5120/256 = 20G.

### DAS (`$8001965C`)

Called each active frame with the player structure and player number.
For each horizontal direction, checking `$2000` first and then `$8000`:

* Not held: nothing.
* Newly pressed: DAS counter `$3A` = 0 and move this frame.
* Held: if `$3A` < 14, add 1 and don't move; otherwise move.

The result is a move on the first frame, nothing for 14 frames, then a move
on every frame from the 16th on. If both directions are held, `$8000` wins.

During ARE (state `$3C`) the counter keeps counting while either
direction is held and is reset to 0 when neither is, so a direction held
through ARE moves the new piece on its first frame. The collapse state
`$32` resets the counter, so after a line clear only the 25 frames of ARE
count, which is still enough to charge it.

### Rotation and wall kicks (`$8001910C`)

Shapes are in a table at `$80079E88`: `[type][row][rotation][column]`,
one byte per cell, 64 bytes per piece type. Rows run top to bottom. Each
piece sits in a 4x4 box; the 3-wide pieces use its top-left 3x3 (rows 0-2).

```
      rot 0   rot 1   rot 2   rot 3
I     ....    ..#.    ....    ..#.
      ####    ..#.    ####    ..#.
      ....    ..#.    ....    ..#.
      ....    ..#.    ....    ..#.
T     ....    .#..    ....    .#..
      ###.    .##.    .#..    ##..
      .#..    .#..    ###.    .#..
J     ....    .##.    ....    .#..
      ###.    .#..    #...    .#..
      ..#.    .#..    ###.    ##..
L     ....    .#..    ....    ##..
      ###.    .#..    ..#.    .#..
      #...    .##.    ###.    .#..
S     ....    #...  (same as 0/1)
      .##.    ##..
      ##..    .#..
Z     ....    ..#.  (same as 0/1)
      ##..    .##.
      .##.    .#..
O     .##. in rows 1-2, all rotations
```

These are the ARS shapes: T, J and L spawn flat side up, I lies in row 1
and stands in column 2. Rotation +1 is counter-clockwise (T rotation 1
points right). The NES port's shapes in `main.asm` (`orientationTable`)
match this table.

The routine is called with the rotated orientation. It returns 0 if the
piece can take it (possibly moved one column) and non-zero if not:

1. Go through the rotated piece's cells in reading order (box rows top to
   bottom, columns left to right). Skip empty cells and cells outside the
   field array.
2. The first cell that overlaps something in the field (blocks, the walls
   and presumably the floor are all non-zero cells) decides:
   * I piece: fail (I never kicks);
   * the cell is in box column 1, the middle column: fail;
   * otherwise try column + 1, then column - 1, and take the first that
     fits. If neither fits, fail.
3. If no cell overlaps, the rotation fits where it is.

This is the "centre column rule". Two details are easy to get wrong:

* Only cells of the rotated piece count. A block elsewhere in the 3x3 box
  does not decide anything.
* It applies to every piece except I, including S and Z. The O piece never
  overlaps, because its rotations are identical.

Pieces with variant `$50` in `$9C` go through a separate branch that works on
a grid of half cells (probably a "big" mode). It was not studied.

There are six calls to this routine in the active state, at `$800139F0`,
`$80013A38`, `$80013A7C`, `$80013B18`, `$80013B60` and `$80013BA4`
(rotation buttons and variants). Initial rotation (IRS) was not checked.

### Randomizer (state `$0A`, `$80013424`)

The random number generator at `$8001A9B8` is the C library `rand()`:

```
seed = seed * 1103515245 + 12345        (seed: player + $40)
return (seed >> 10) & $7FFF
```

A piece is `rand() % 7`, computed with the reciprocal multiply `$24924925`.
Piece numbers 0-6 are I, Z, S, J, L, O, T (the type is the number + 2).

Picking the next piece:

1. Roll a piece and count how often it appears in history slots 0-3
   (player `$44`-`$47`).
2. If it isn't there, take it.
3. Otherwise roll again, up to 3 checked rolls in total. If the third is
   also in the history, a fourth roll is taken **without checking it**.

That gives the same distribution as "4 tries, keep the last one". The
history (8 bytes) is shifted by one and the new piece written to slot 0.
Then the current piece becomes the old next piece (`$9C` = `$9A`) and the
roll becomes the new next piece.

How the history starts, and the "first piece is never S, Z or O" rule,
were **not** found in this code. The NES port follows the clone on both.

### Levels and sections

* **Per piece:** at the end of ARE (state `$3C`), if the game isn't finished
  and level < 999, level + 1.
* **Per line:** when lines are cleared (state `$1E`, around `$800141A0`), the
  level goes up by the number of lines. The single and double cases were
  read; triples and Tetrises presumably follow.
* **Sections and the stop (`$80029DDC`):** once per frame,
  `$8002A2E8` works out the section from the level using the boundaries
  at `$80073CC4` (100, 200, ..., 900, 999). If that differs from the stored
  section (`$66`):
  * if the last piece cleared no lines (`$4C` = 0), the level is set back
    to the boundary - 1 (99, 199, ..., 899, 998);
  * if it did, the section goes up by one, the GM checkpoint test
    (`$8002A228`) runs and a sound plays.

  In the alternate mode (`$801C1208` bit 3) the stop is skipped.

The stop is applied in the bookkeeping step, which runs after drawing. So
for one frame the level holds the boundary value (300, 999, ...) before it
is set back. Whether that frame shows on screen was not checked.

### Scoring (state `$1E`, `$80014244`-`$800147C8`)

When a piece locks with n lines:

* Combo (`$50`): no lines resets it to 1, a single leaves it alone, n >= 2
  adds 2(n - 1).
* `value = (ceil(level / 4) + soft) * n * combo`, where:
  * `level` already includes the n lines just added, so this is the
    wiki's `ceil((level_before + lines) / 4)`;
  * `soft` is the u8 soft-drop counter at `$8012B030 + player`, i.e.
    frames down was held, not rows dropped.
* `score += value`, or `score += value * 4` when `$8001A040` returns true.
  That function is assumed to test for an empty field (an all clear,
  inferred).

Where the soft-drop counter is reset was not traced.

### Grades (`$8002A378`) and GM

**Grade update** runs every frame unless the game has finished. While
grade < 17 and score >= `gradeTable[grade]`, the grade goes up by one, the
clock is copied to `$58`/`$70` and a sound plays. Table at `$80073CDC`
(ROM offset `$6B564`):

```
index:  0    1    2    3    4    5    6    7     8     9     10    11    12    13    14     15     16     17
score:  400  800  1400 2000 3500 5500 8000 12000 16000 22000 30000 40000 52000 66000 82000 100000 120000 126000
```

Reaching index g gives grade g + 1 (index 7 = 12000 gives grade 8, "1";
index 16 = 120000 gives 17, "S9"). Entry 17 (126000) is only used by the GM
test.

**Checkpoints** (`$8002A228`) run when the section goes up. The data is at
`$80073D28`: two records of {u8 section, u8 grade, 2 bytes padding, u32
frames}.

| Entering section | Needs grade | Needs clock | Sets `$68` bit |
|---|---|---|---|
| 3 (level 300) | >= 8 ("1", 12000 points) | <= 15300 frames (4:15:00) | 0 |
| 5 (level 500) | >= 12 ("S4", 40000 points) | <= 27000 frames (7:30:00) | 1 |

**GM test** (`$8002A460`) runs when the level reaches 999 (`$80073CD6`). It
calls `$80053178` to start the end sequence and sets the finished flag
`$100000`. The grade becomes 18 (GM) if all of these hold:

* grade >= 17;
* score >= 126000 (grade table entry 17);
* clock <= 48599 frames (the u32 at `$80073D24`), i.e. **strictly under**
  13:30:00;
* `$68` = 3 (both checkpoints passed).

### End of the game

Once the finished flag is set, the player routine calls `$80053228` every
frame. That calls `$8005326C` (no GM) or `$80053C6C` (GM): two sub-state
machines that drive the end sequence. Gameplay continues meanwhile; ARE
skips the level increment once the game has finished. When a sequence ends
it sets flag `$200000`, and the player state machine moves to state `$6E`.

The length of this credit roll was **not** worked out. It appears to end
when the staff credits finish rather than on a single timer. The routines
contain 300 and 600 frame timers (`$800537AC`, `$80053D60`) whose purpose
wasn't confirmed. The NES port uses an estimate (`TGM_ROLL_FRAMES` = 3238).

## Function index

| Address | Role | Status |
|---|---|---|
| `$8001B1B4` | One game frame (one of several mode-specific copies) | verified |
| `$800107CC` | Player update dispatcher | verified |
| `$80011550` | Player state machine (table at `$8006DE34`) | verified |
| `$80017B74` | Draws a piece; advances the lock flash counter | verified |
| `$800155B4` | Draws the game | inferred |
| `$80018F7C` | Collision test (player, column, row, rotation), non-zero = blocked | verified |
| `$8001910C` | Rotation with wall kick | verified |
| `$80019470` | Called when a piece locks (presumably writes it to the field) | inferred |
| `$8001965C` | DAS / horizontal input | verified |
| `$8001A040` | All-clear test used for the x4 bonus | inferred |
| `$8001A3E0` | Called at the end of ARE | unknown |
| `$8001A9B8` | `rand()` (seed pointer, update flag) | verified |
| `$80029DDC` | Section changes and the x99 stop, both players | verified |
| `$8002A228` | GM checkpoint test | verified |
| `$8002A2E8` | Level -> section index | verified |
| `$8002A33C` | Section index -> boundary level | verified |
| `$8002A378` | Grade update | verified |
| `$8002A460` | Level 999: finish the game, GM test | verified |
| `$8002A544` | Grade threshold lookup | verified |
| `$8003A8B0` | Per-frame bookkeeping (grades, sections, GM) | verified |
| `$8003F028` | Play a sound effect (`a1` = id) | inferred |
| `$80053178` | Start the end sequence | inferred |
| `$80053228` | End sequence per frame, picks `$8005326C` or `$80053C6C` by grade | verified |

## Compared with the NES port and the C++ clone

| Rule | Arcade | NES port (`tgm.asm`) | C++ clone (`Tetris/`) |
|---|---|---|---|
| Gravity table | as above | same | same |
| Lock delay | 30 | same | same |
| Lock -> next piece | 31 / 72 frames | same (measured) | same |
| DAS | 1st frame, then from the 16th | same | same |
| Kick rule | first colliding cell of the rotated piece; all pieces but I | same (since the arcade check) | scans the whole 3x3 box, L/J/T only |
| Randomizer | 3 checked rolls + 1 unchecked | 4 checked rolls, keep the last: same distribution | same as the NES port |
| Level used in score | after adding the lines | same | adds the lines twice |
| Soft drop in score | frames down was held | same | rows dropped |
| All-clear bonus | x4 | same | missing |
| GM at 500 | 7:30:00 | same | 7:00:00 |
| GM at 999 | <= 48599 frames | same (since the arcade check) | <= 13:30:00 |
| GM checkpoints | when the section goes up | when the level first passes 300 / 500 | only when the level equals 300 / 500 exactly |
| Clock value used for the GM tests | the frame the piece is placed, 4 frames after the lock | same (the clock is noted 4 frames after the lock) | the current frame |
| Level +1 per piece | end of ARE | at spawn, 2 frames later (no visible difference) | at spawn |
| Lock flash | 3 frames, piece white | not drawn (the frames are still counted) | 3 frames |
| Credit roll | length not found | 3238 frames (estimate) | none |

## Open questions

* Credit roll length and what the end sequence does frame by frame.
* Initial randomizer history and the first-piece rule.
* IRS: whether and how a held rotation applies at spawn.
* Where the clock (`$54`) and the soft-drop counter are updated and reset.
* The alternate mode (`$801C1208` bit 3), variant `$50` pieces, the rising-
  rows states `$46`/`$50`/`$51` and flag `$0800`.
* What the second copy of the tables at ROM offset `$163CDC` belongs to.

## Reproducing

Python 3 with `capstone` for disassembly (`pip install capstone`).
`ROM` is the path to `ate-05m.3h`:

```
python3 tools/tgm_re/tgm1re.py ROM tables            # print all the tables above
python3 tools/tgm_re/tgm1re.py ROM base              # re-derive the load address
python3 tools/tgm_re/tgm1re.py ROM dis 8001910c 120  # disassemble
python3 tools/tgm_re/tgm1re.py ROM refs 80073cdc     # code using an address
python3 tools/tgm_re/tgm1re.py ROM callers 8002a378  # calls to a function
```

Useful starting points: the state handlers in the table above, the
kick routine `$8001910C`, and `refs` on any table address.
