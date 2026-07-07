BUILD := build

all: $(BUILD)/disk.img

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/stage1.bin: boot/stage1/boot.asm | $(BUILD)
	nasm -f bin $< -o $@

$(BUILD)/stage2.bin: boot/stage2/stage2.asm | $(BUILD)
	nasm -f bin $< -o $@

$(BUILD)/disk.img: $(BUILD)/stage1.bin $(BUILD)/stage2.bin
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(BUILD)/stage1.bin of=$@ conv=notrunc status=none
	dd if=$(BUILD)/stage2.bin of=$@ bs=512 seek=1 conv=notrunc status=none

run: all
	qemu-system-x86_64 -drive format=raw,file=$(BUILD)/disk.img

clean:
	rm -rf $(BUILD)
