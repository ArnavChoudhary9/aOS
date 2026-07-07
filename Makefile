BUILD := build
OBJ   := $(BUILD)/obj

NASM     := nasm
LD       := ld
OBJCOPY  := objcopy

STAGE2_OBJS := \
    $(OBJ)/stage2.o      \
    $(OBJ)/a20.o         \
    $(OBJ)/gdt.o         \
    $(OBJ)/memory.o      \
    $(OBJ)/memory_view.o \
    $(OBJ)/print.o       \
    $(OBJ)/convert.o     \
    $(OBJ)/vga.o

.PHONY: all run clean

all: $(BUILD)/disk.img

$(BUILD):
	mkdir -p $@

$(OBJ): | $(BUILD)
	mkdir -p $@

$(BUILD)/stage1.bin: boot/stage1/boot.asm | $(BUILD)
	$(NASM) -f bin $< -o $@

$(OBJ)/stage2.o: boot/stage2/stage2.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/a20.o: boot/stage2/a20.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/gdt.o: boot/stage2/gdt.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/memory.o: boot/stage2/memory.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/memory_view.o: boot/stage2/memory_view.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/print.o: boot/lib/print.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/convert.o: boot/lib/convert.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

$(OBJ)/vga.o: boot/lib/vga.asm | $(OBJ)
	$(NASM) -f elf32 $< -o $@

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

run: all
	qemu-system-x86_64 -drive format=raw,file=$(BUILD)/disk.img

clean:
	rm -rf $(BUILD)
