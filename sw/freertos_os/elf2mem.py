#!/usr/bin/env python3
# elf2mem.py - convert objcopy binary dumps into the SoC's .mem (8 hex/word/line).
# Usage:
#   riscv-none-elf-objcopy -O binary --only-section=.boot  fw.elf boot.bin
#   riscv-none-elf-objcopy -O binary -j .text -j .rodata -j .data fw.elf isram.bin
#   python3 elf2mem.py boot.bin  bootrom.mem
#   python3 elf2mem.py isram.bin program.mem
import sys
def conv(binf, memf):
    data = open(binf, 'rb').read()
    # pad to multiple of 4
    while len(data) % 4: data += b'\x00'
    with open(memf, 'w') as f:
        for i in range(0, len(data), 4):
            word = data[i] | (data[i+1]<<8) | (data[i+2]<<16) | (data[i+3]<<24)
            f.write(f"{word:08X}\n")
    print(f"{binf} -> {memf} ({len(data)//4} words)")
if __name__ == "__main__":
    conv(sys.argv[1], sys.argv[2])
