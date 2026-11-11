#!/usr/bin/env python3
"""Apply the TGM-mode graphics edits to the CHR PNGs and nametable stripes.

The edits are idempotent (they set specific tiles/cells to fixed values), so
running this more than once is harmless.

  * game tileset: tile $2A becomes ':' (timer separator)
  * type A ending tileset: tiles $17/$31/$3A/$3D become D/M/N/':' so the
    ending screen can print GRADE, TIME and GRAND MASTER
  * game nametable: a GRADE box under LEVEL (where B-type's HEIGHT box was)
    and a timer box hanging under the well
  * high score nametable: the "LV" column header becomes "GR"

Usage: python3 tools/tgm_assets.py   (from the repository root; needs Pillow)
"""
from PIL import Image

GAME_TILESET = "gfx/game_tileset.png"
ENDING_TILESET = "gfx/typeA_ending_tileset.png"
GAME_NAMETABLE = "gfx/nametables/game_nametable.bin"
HIGH_SCORES_NAMETABLE = "gfx/nametables/high_scores_nametable.bin"

COLON = [
    "........",
    "..##....",
    "..##....",
    "........",
    "..##....",
    "..##....",
    "........",
    "........",
]


def tile_origin(t):
    return (t % 16) * 8, (t // 16) * 8


def draw_glyph(img, tile, rows, color):
    px = img.load()
    ox, oy = tile_origin(tile)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[ox + x, oy + y] = color if ch == "#" else 0


def copy_glyph(src, src_tile, dst, dst_tile, color):
    spx = src.load()
    sx, sy = tile_origin(src_tile)
    rows = ["".join("#" if spx[sx + x, sy + y] else "." for x in range(8)) for y in range(8)]
    draw_glyph(dst, dst_tile, rows, color)


def patch_tilesets():
    game = Image.open(GAME_TILESET).convert("L")
    draw_glyph(game, 0x2A, COLON, 255)
    game.save(GAME_TILESET)

    ending = Image.open(ENDING_TILESET).convert("L")
    # Font letters in the game tileset: A=$0A ... so D=$0D, M=$16, N=$17.
    # The ending tileset draws its text in colour 2 (170).
    copy_glyph(game, 0x0D, ending, 0x17, 170)  # D
    copy_glyph(game, 0x16, ending, 0x31, 170)  # M
    copy_glyph(game, 0x17, ending, 0x3A, 170)  # N
    draw_glyph(ending, 0x3D, COLON, 170)       # :
    ending.save(ENDING_TILESET)


def stripe_offsets(data):
    """Map PPU address -> file offset for every literal byte of a stripe."""
    offsets = {}
    i = 0
    while i < len(data) and data[i] < 0x80:
        addr = (data[i] << 8) | data[i + 1]
        ctl = data[i + 2]
        i += 3
        inc = 32 if ctl & 0x80 else 1
        n = ctl & 0x3F or 64
        if ctl & 0x40:  # run of one repeated byte: not individually patchable
            i += 1
            continue
        for k in range(n):
            offsets[addr + k * inc] = i
            i += 1
    return offsets


def patch_nametable(path, cells):
    data = bytearray(open(path, "rb").read())
    offsets = stripe_offsets(data)
    for addr, value in cells.items():
        data[offsets[addr]] = value
    open(path, "wb").write(data)


def row_cells(row, col, tiles):
    base = 0x2000 + row * 32 + col
    return {base + k: t for k, t in enumerate(tiles)}


def patch_game_nametable():
    cells = {}
    # GRADE box (rows 23-26, cols 23-30)
    cells.update(row_cells(23, 23, [0x38] + [0x39] * 6 + [0x3A]))
    cells.update(row_cells(24, 23, [0x3B, 0x10, 0x1B, 0x0A, 0x0D, 0x0E, 0xFF, 0x3C]))
    cells.update(row_cells(25, 23, [0x3B] + [0xFF] * 6 + [0x3C]))
    cells.update(row_cells(26, 23, [0x3D] + [0x3E] * 6 + [0x3F]))
    # Timer box under the well (rows 27-29, cols 11-22)
    cells.update(row_cells(27, 11, [0x38] + [0x39] * 10 + [0x3A]))
    cells.update(row_cells(28, 11, [0x3B] + [0xFF] * 10 + [0x3C]))
    cells.update(row_cells(29, 11, [0x3D] + [0x3E] * 10 + [0x3F]))
    # No attribute changes needed: everything below row 22 already uses
    # palette 3, the same palette as the HUD boxes.
    patch_nametable(GAME_NAMETABLE, cells)


def patch_high_scores_nametable():
    data = bytearray(open(HIGH_SCORES_NAMETABLE, "rb").read())
    offsets = stripe_offsets(data)
    for addr, off in offsets.items():
        if data[off] in (0x15, 0x10) and offsets.get(addr + 1) is not None:
            nxt = data[offsets[addr + 1]]
            if (data[off], nxt) in ((0x15, 0x1F), (0x10, 0x1B)):  # "LV" (or already "GR")
                data[off] = 0x10            # G
                data[offsets[addr + 1]] = 0x1B  # R
    open(HIGH_SCORES_NAMETABLE, "wb").write(data)


if __name__ == "__main__":
    patch_tilesets()
    patch_game_nametable()
    patch_high_scores_nametable()
    print("TGM assets patched")
