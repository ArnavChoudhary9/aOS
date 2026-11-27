BUILD := build
OBJ   := $(BUILD)/obj

NASM     := nasm
LD       := ld
OBJCOPY  := objcopy

STAGE2_OBJS := \
    $(OBJ)/stage2.o      \
    $(OBJ)/a20.o         \
    $(OBJ)/gdt.o         \
    $(OBJ)/idt.o         \
    $(OBJ)/pic.o         \
    $(OBJ)/memory.o      \
    $(OBJ)/memory_view.o \
    $(OBJ)/print.o       \
    $(OBJ)/convert.o     \
    $(OBJ)/vga.o         \
    $(OBJ)/debug.o       \
    $(OBJ)/timer.o       \
    $(OBJ)/keyboard.o    \
    $(OBJ)/ata.o

.PHONY: all run debug clean

all: $(BUILD)/disk.img

$(BUILD):
	mkdir -p $@

$(OBJ): | $(BUILD)
	mkdir -p $@

# ── Stage 1 ──────────────────────────────────────────────────────────────────

$(BUILD)/stage1.bin: boot/stage1/boot.asm | $(BUILD)
	$(NASM) -f bin $< -o $@

# ── Stage 2 modules ──────────────────────────────────────────────────────────

$(OBJ)/stage2.o: boot/stage2/stage2.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/a20.o: boot/stage2/a20.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/gdt.o: boot/stage2/gdt.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/idt.o: boot/stage2/idt.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/pic.o: boot/stage2/pic.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/memory.o: boot/stage2/memory.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/memory_view.o: boot/stage2/memory_view.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

# ── Library modules ───────────────────────────────────────────────────────────

$(OBJ)/print.o: boot/lib/print.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/convert.o: boot/lib/convert.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/vga.o: boot/lib/vga.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/debug.o: boot/lib/debug.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

# ── Device drivers ────────────────────────────────────────────────────────────

$(OBJ)/timer.o: boot/drivers/timer.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/keyboard.o: boot/drivers/keyboard.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/ata.o: boot/drivers/ata.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

# ── Link and package ─────────────────────────────────────────────────────────

$(BUILD)/stage2.elf: $(STAGE2_OBJS) boot/linker/stage2.ld
	$(LD) -m elf_i386 -T boot/linker/stage2.ld \
	    -Map=$(BUILD)/stage2.map \
	    -o $@ $(STAGE2_OBJS)

$(BUILD)/stage2.bin: $(BUILD)/stage2.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/disk.img: $(BUILD)/stage1.bin $(BUILD)/stage2.bin
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(BUILD)/stage1.bin of=$@ conv=notrunc status=none
	dd if=$(BUILD)/stage2.bin of=$@ bs=512 seek=1 conv=notrunc status=none

# ── QEMU targets ──────────────────────────────────────────────────────────────

# if=ide is required for the ATA PIO driver (ports 0x1F0-0x1F7 / 0x3F6).
run: all
	qemu-system-x86_64 \
	    -drive format=raw,file=$(BUILD)/disk.img,if=ide \
	    -monitor none

# GDB server on :1234; QEMU pauses until GDB connects.
# Connect with:
#   gdb -ex "target remote :1234" -ex "symbol-file build/stage2.elf" -ex "set arch i386"
debug: all
	qemu-system-x86_64 \
	    -drive format=raw,file=$(BUILD)/disk.img,if=ide \
	    -s -S \
	    -monitor stdio

clean:
	rm -rf $(BUILD)
