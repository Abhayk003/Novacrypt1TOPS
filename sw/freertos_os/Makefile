# Adjust PREFIX to your toolchain (xPack: riscv-none-elf-)
PREFIX  ?= riscv-none-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

ARCH    = -march=rv32im -mabi=ilp32 -mno-relax
CFLAGS  = $(ARCH) -Os -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -g \
          -fno-builtin -ffunction-sections -fdata-sections
LDFLAGS = $(ARCH) -nostdlib -nostartfiles -T link.ld -Wl,--gc-sections -Wl,-Map=fw.map

SRCS_S  = boot.S crt0.S
SRCS_C  = main.c uart.c
OBJS    = $(SRCS_S:.S=.o) $(SRCS_C:.c=.o)

all: bootrom.mem program.mem fw.lst

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

fw.elf: $(OBJS) link.ld
	$(CC) $(LDFLAGS) $(OBJS) -o $@

boot.bin: fw.elf
	$(OBJCOPY) -O binary --only-section=.boot $< $@
isram.bin: fw.elf
	$(OBJCOPY) -O binary -j .text -j .rodata -j .srodata -j .data -j .sdata $< $@

bootrom.mem: boot.bin
	python elf2mem.py boot.bin bootrom.mem
program.mem: isram.bin
	python elf2mem.py isram.bin program.mem

fw.lst: fw.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -f *.o *.elf *.bin *.mem *.map *.lst
