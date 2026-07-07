BUILD_DIR := build

all:
	mkdir -p $(BUILD_DIR)
	nasm -f bin boot/stage1/boot.asm -o $(BUILD_DIR)/boot.bin

run: all
	qemu-system-x86_64 -drive format=raw,file=$(BUILD_DIR)/boot.bin

clean:
	rm -rf $(BUILD_DIR)
