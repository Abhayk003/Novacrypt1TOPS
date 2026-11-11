# build_freertos.ps1 - build FreeRTOS blinky for the RV32IM SoC (PowerShell).
# Run from the rv32_fw folder. Produces bootrom.mem + program.mem.

$ARCH = "-march=rv32im_zicsr","-mabi=ilp32","-mno-relax"
$INC  = "-IFreeRTOS\Source\include","-I."     # FreeRTOSConfig.h is in . (rv32_fw)
$CF   = $ARCH + $INC + @("-Os","-ffreestanding","-nostdlib","-nostartfiles",
        "-Wall","-fno-builtin","-ffunction-sections","-fdata-sections","-g")

$CC = "riscv-none-elf-gcc"

# --- assemble startup + port asm ---
& $CC $CF -c boot.S -o boot.o
& $CC $CF -c crt0.S -o crt0.o
& $CC $CF -c FreeRTOS\Source\portASM.S -o portASM.o

# --- compile C: app + drivers + kernel ---
$CSRC = @("main.c","uart.c","libc_stubs.c","irq_ext.c",
          "FreeRTOS\Source\tasks.c","FreeRTOS\Source\queue.c","FreeRTOS\Source\list.c",
          "FreeRTOS\Source\port.c","FreeRTOS\Source\heap_4.c")
$OBJS = @("boot.o","crt0.o","portASM.o")
foreach ($f in $CSRC) {
    $o = [System.IO.Path]::GetFileNameWithoutExtension($f) + ".o"
    & $CC $CF -c $f -o $o
    $OBJS += $o
}

# --- link ---
& $CC $ARCH -nostdlib -nostartfiles -T link.ld "-Wl,--gc-sections" "-Wl,-Map=fw.map" $OBJS -lgcc -o fw.elf
if (-not (Test-Path fw.elf)) { Write-Host "LINK FAILED - stopping (see error above)" -ForegroundColor Red; exit 1 }

# --- images ---
riscv-none-elf-objcopy -O binary --only-section=.boot fw.elf boot.bin
riscv-none-elf-objcopy -O binary -j .text -j .rodata -j .srodata -j .data -j .sdata fw.elf isram.bin
python elf2mem.py boot.bin bootrom.mem
python elf2mem.py isram.bin program.mem

# --- disassembly + size ---
riscv-none-elf-objdump -d fw.elf > fw.lst
Write-Host "=== section sizes ==="
riscv-none-elf-size fw.elf
Write-Host "Build done: bootrom.mem + program.mem"