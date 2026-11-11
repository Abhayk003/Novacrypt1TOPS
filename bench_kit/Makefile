# Universal bare-metal Dhrystone/CoreMark builder.  Per-project config lives ONLY in platform.h.
#   make fetch                       # clone benchmark sources once
#   make coremark dhrystone          # build ELF/BIN/HEX for your core
#   make PLAT_DEFS=-DPLAT_QEMU qemu-coremark   # golden run on QEMU before touching RTL
.RECIPEPREFIX := >
PREFIX    ?= riscv64-unknown-elf-
ARCH      ?= rv64imafdc_zicsr_zifencei   # _zicsr is REQUIRED by binutils >= 2.38 for CSR/rdcycle
ABI       ?= lp64d
OPT       ?= -O2
PLAT_DEFS ?=
CORE_ITER ?= 10          # CoreMark iterations  (raise so HW run lasts >= 10 s)
DHRY_RUNS ?= 2000        # Dhrystone runs       (raise so HW run lasts >= 2 s)
COREMARK_DIR ?= third_party/coremark
DHRY_DIR     ?= third_party/dhrystone
BUILD := build
QEMU  ?= qemu-system-riscv64

CC := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
SIZE := $(PREFIX)size
empty :=
space := $(empty) $(empty)

BASE_FLAGS := -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany $(OPT) -ffreestanding -fno-common \
              -ffunction-sections -fdata-sections $(PLAT_DEFS) -I.
FLAGS_STR  := $(subst $(space),_,$(strip -march=$(ARCH) -mabi=$(ABI) $(OPT)))
LDFLAGS    := -nostdlib -nostartfiles -Wl,--gc-sections -T $(BUILD)/link.ld
LIBS       := -lgcc
COMMON_OBJ := $(BUILD)/crt0.o $(BUILD)/platform.o $(BUILD)/minilibc.o

CM_SRC := $(addprefix $(COREMARK_DIR)/,core_list_join.c core_main.c core_matrix.c core_state.c core_util.c) \
          $(addprefix $(BUILD)/cm_port/,core_portme.c ee_printf.c cvt.c)
CM_FLAGS := -I$(COREMARK_DIR) -I$(BUILD)/cm_port -DITERATIONS=$(CORE_ITER) -DPERFORMANCE_RUN=1 \
            -DFLAGS_STR=\"$(FLAGS_STR)\"
DH_SRC   := $(DHRY_DIR)/dhry_1.c $(DHRY_DIR)/dhry_2.c
DH_FLAGS := -Ishim -I$(DHRY_DIR) -std=gnu89 -fno-builtin -DTIME -DNOENUM -DDHRY_ITERS=$(DHRY_RUNS) -w

.PHONY: all fetch coremark dhrystone clean
.SECONDARY:
all: coremark dhrystone
fetch:
> ./scripts/fetch_sources.sh
$(BUILD):
> mkdir -p $(BUILD) logs results

$(BUILD)/link.ld: link.ld.in platform.h | $(BUILD)
> $(CC) -E -P -x c $(PLAT_DEFS) -I. $< -o $@
$(BUILD)/%.o: %.S platform.h | $(BUILD)
> $(CC) $(BASE_FLAGS) -c $< -o $@
$(BUILD)/%.o: %.c platform.h | $(BUILD)
> $(CC) $(BASE_FLAGS) -c $< -o $@
$(BUILD)/cm_port/.stamp: scripts/make_coremark_port.py | $(BUILD)
> python3 scripts/make_coremark_port.py $(COREMARK_DIR)/barebones $(BUILD)/cm_port && touch $@

$(BUILD)/coremark.elf: $(BUILD)/cm_port/.stamp $(COMMON_OBJ) $(BUILD)/link.ld
> $(CC) $(BASE_FLAGS) $(CM_FLAGS) $(CM_SRC) $(COMMON_OBJ) $(LDFLAGS) -Wl,-Map=$@.map $(LIBS) -o $@
$(BUILD)/dhrystone.elf: $(COMMON_OBJ) $(BUILD)/link.ld
> $(CC) $(BASE_FLAGS) $(DH_FLAGS) $(DH_SRC) $(COMMON_OBJ) $(LDFLAGS) -Wl,-Map=$@.map $(LIBS) -o $@

$(BUILD)/%.bin: $(BUILD)/%.elf
> $(OBJCOPY) -O binary $< $@
$(BUILD)/%.hex: $(BUILD)/%.elf
> $(OBJCOPY) -O verilog $< $@
$(BUILD)/%.dump: $(BUILD)/%.elf
> $(OBJDUMP) -d $< > $@

# ---- $readmemh images for your testbench: build/<bench>.imem.hex (+ .dmem.hex when PLAT_HARVARD=1) ----
WORD_BYTES ?= 4          # 4 = one 32-bit word per line; 1 = byte per line
IMEM_DEPTH ?= 0          # >0: zero-pad to your memory depth (in words/bytes) to avoid X's
DMEM_DEPTH ?= 0
HARVARD := $(shell echo PLAT_HARVARD | $(CC) -E -P -x c -include platform.h $(PLAT_DEFS) - 2>/dev/null | tail -n1)
ifeq ($(HARVARD),1)
IMG_I := -j .text
IMG_D := -j .rodata -j .data
IMG_TARGETS = $(BUILD)/$*.imem.hex $(BUILD)/$*.dmem.hex
else
IMG_TARGETS = $(BUILD)/$*.imem.hex
endif
$(BUILD)/%.imem.bin: $(BUILD)/%.elf
> $(OBJCOPY) -O binary $(IMG_I) $< $@
$(BUILD)/%.dmem.bin: $(BUILD)/%.elf
> $(OBJCOPY) -O binary $(IMG_D) $< $@
$(BUILD)/%.imem.hex: $(BUILD)/%.imem.bin
> python3 scripts/bin2memh.py $< $@ --bytes $(WORD_BYTES) $(if $(filter-out 0,$(IMEM_DEPTH)),--depth $(IMEM_DEPTH))
$(BUILD)/%.dmem.hex: $(BUILD)/%.dmem.bin
> python3 scripts/bin2memh.py $< $@ --bytes $(WORD_BYTES) $(if $(filter-out 0,$(DMEM_DEPTH)),--depth $(DMEM_DEPTH))
images-%: $(BUILD)/%.elf
> $(MAKE) $(IMG_TARGETS)

coremark dhrystone: %: $(BUILD)/%.bin $(BUILD)/%.hex $(BUILD)/%.dump
> @$(SIZE) $(BUILD)/$@.elf
> @{ echo "compiler: $$($(CC) --version | head -1)"; echo "flags: $(BASE_FLAGS)"; \
>    echo "iterations/runs: coremark=$(CORE_ITER) dhrystone=$(DHRY_RUNS)"; } > $(BUILD)/$@.info

# ---- golden functional run on QEMU (use with PLAT_DEFS=-DPLAT_QEMU) ----
qemu-%: $(BUILD)/%.elf
> mkdir -p logs && timeout 600 $(QEMU) -nographic -machine virt -bios none -kernel $< | tee logs/$*.log
report-%:
> python3 scripts/parse_results.py $* logs/$*.log --info $(BUILD)/$*.info
clean:
> rm -rf $(BUILD)
