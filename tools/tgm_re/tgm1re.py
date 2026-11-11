#!/usr/bin/env python3
"""Helpers for reading the TGM1 arcade program (tgmj set, ate-05m.3h).

See docs/TGM1_ARCADE_NOTES.md for what was found with this script.

Usage (from the repository root; disassembly needs `pip install capstone`):

  python3 tools/tgm_re/tgm1re.py ROM tables          # decode the known tables
  python3 tools/tgm_re/tgm1re.py ROM dis ADDR [N]    # disassemble N instructions
  python3 tools/tgm_re/tgm1re.py ROM refs ADDR       # code that builds ADDR (lui + lo)
  python3 tools/tgm_re/tgm1re.py ROM callers ADDR    # jal ADDR call sites
  python3 tools/tgm_re/tgm1re.py ROM base            # re-derive the load address

ROM is the path to ate-05m.3h. Addresses are RAM addresses (hex, e.g. 8001910c).
"""
import collections
import struct
import sys

# ROM offset 0 of ate-05m.3h corresponds to this RAM address (see `base`).
BASE = 0x80008778
CODE_SIZE = 0x100000  # the program code lives in the first 1 MB of the ROM

# Known tables (RAM addresses)
GRAVITY_TABLE = 0x80072C84     # 1001 x u32, 16.16 fixed point rows/frame, per level
SECTION_TABLE = 0x80073CC4     # 10 x s16: 100, 200, ... 900, 999
GRADE_TABLE = 0x80073CDC       # 18 x u32 score thresholds (index 17 = GM, 126000)
GM_FINAL_TIME = 0x80073D24     # u32 frames, inclusive (48599)
GM_CHECKPOINTS = 0x80073D28    # 2 x {u8 section, u8 grade, u16 pad, u32 frames}
PIECE_SHAPES = 0x80079E88      # [type][row][rotation][col] u8: 64 bytes per type
STATE_JUMP_TABLE = 0x8006DE34  # 0x76 x u32, player state handlers
PIECE_NAMES = {2: 'I', 3: 'Z', 4: 'S', 5: 'J', 6: 'L', 7: 'O', 8: 'T'}


class Rom:
    def __init__(self, path):
        self.data = open(path, 'rb').read()

    def off(self, addr):
        return addr - BASE

    def u8(self, a):
        return self.data[self.off(a)]

    def s16(self, a):
        return struct.unpack_from('<h', self.data, self.off(a))[0]

    def u32(self, a):
        return struct.unpack_from('<I', self.data, self.off(a))[0]

    def code_words(self):
        return struct.unpack_from('<%dI' % (CODE_SIZE // 4), self.data, 0)

    # ---------------------------------------------------------------- code
    def disasm(self, addr, count=40):
        from capstone import Cs, CS_ARCH_MIPS, CS_MODE_MIPS32, CS_MODE_LITTLE_ENDIAN
        md = Cs(CS_ARCH_MIPS, CS_MODE_MIPS32 + CS_MODE_LITTLE_ENDIAN)
        o = self.off(addr)
        for ins in md.disasm(self.data[o:o + count * 4], addr):
            print('%08x: %-8s %s' % (ins.address, ins.mnemonic, ins.op_str))

    def callers(self, target):
        enc = 0x0C000000 | ((target >> 2) & 0x3FFFFFF)
        return [BASE + i * 4 for i, w in enumerate(self.code_words()) if w == enc]

    def refs(self, target):
        """lui rX, hi followed (within 12 instructions) by an access/addiu
        through rX with the matching low half."""
        hi = ((target + 0x8000) >> 16) & 0xFFFF
        lo = target & 0xFFFF
        words = self.code_words()
        out = []
        for i, w in enumerate(words):
            if (w >> 26) == 0x0F and (w & 0xFFFF) == hi:
                rt = (w >> 16) & 31
                for v in words[i + 1:i + 12]:
                    if ((v >> 21) & 31) == rt and (v & 0xFFFF) == lo and (v >> 26) in (
                            0x09, 0x20, 0x21, 0x23, 0x24, 0x25, 0x28, 0x29, 0x2B, 0x0D):
                        out.append(BASE + i * 4)
                        break
        return out

    def function_start(self, addr):
        """Walk back to the nearest 'addiu sp, sp, -N'."""
        while True:
            w = self.u32(addr)
            if (w >> 16) == 0x27BD and (w & 0x8000):
                return addr
            addr -= 4

    def derive_base(self):
        """Pick the base that makes the most jal targets land on prologues."""
        words = self.code_words()
        prologues = [i * 4 for i, w in enumerate(words) if (w >> 16) == 0x27BD and (w & 0x8000)]
        targets = [((w & 0x3FFFFFF) << 2) | 0x80000000 for w in words if (w >> 26) == 3]
        votes = collections.Counter()
        for t in targets[:3000]:
            for p in prologues[:3000]:
                votes[t - p] += 1
        return votes.most_common(3)

    # -------------------------------------------------------------- tables
    def print_tables(self):
        print('Gravity (level: rows per frame, 16.16; shown as /256 G)')
        prev = None
        for level in range(1001):
            v = self.u32(GRAVITY_TABLE + 4 * level)
            if v != prev:
                print('  %3d: 0x%06x = %d/256 G' % (level, v, v >> 8))
                prev = v
        print('Section boundaries:', [self.s16(SECTION_TABLE + 2 * i) for i in range(10)])
        print('Grade thresholds (score to reach grade index+1):',
              [self.u32(GRADE_TABLE + 4 * i) for i in range(18)])
        print('GM at 999: time <= %d frames' % self.u32(GM_FINAL_TIME))
        for i in range(2):
            a = GM_CHECKPOINTS + 8 * i
            print('GM checkpoint: entering section %d needs grade >= %d and time <= %d frames'
                  % (self.u8(a), self.u8(a + 1), self.u32(a + 4)))
        print('Piece shapes (rotations 0-3 left to right):')
        for t in range(2, 9):
            rows = []
            for r in range(4):
                cells = []
                for rot in range(4):
                    b = self.off(PIECE_SHAPES) + t * 64 + r * 16 + rot * 4
                    cells.append(''.join('#' if self.data[b + c] else '.' for c in range(4)))
                rows.append('  '.join(cells))
            print('  %s  %s' % (PIECE_NAMES[t], ('\n     ').join(rows)))
        print('Player state handlers:')
        handlers = collections.defaultdict(list)
        for s in range(0x76):
            handlers[self.u32(STATE_JUMP_TABLE + 4 * s)].append(s)
        for h, states in sorted(handlers.items()):
            if len(states) < 10:
                print('  %08x: states %s' % (h, ' '.join('%02x' % s for s in states)))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    rom = Rom(argv[1])
    cmd = argv[2]
    if cmd == 'tables':
        rom.print_tables()
    elif cmd == 'dis':
        rom.disasm(int(argv[3], 16), int(argv[4]) if len(argv) > 4 else 40)
    elif cmd == 'refs':
        for a in rom.refs(int(argv[3], 16)):
            print('%08x (function %08x)' % (a, rom.function_start(a)))
    elif cmd == 'callers':
        for a in rom.callers(int(argv[3], 16)):
            print('%08x (function %08x)' % (a, rom.function_start(a)))
    elif cmd == 'base':
        for base, votes in rom.derive_base():
            print('base %08x: %d jal targets on prologues' % (base & 0xFFFFFFFF, votes))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
