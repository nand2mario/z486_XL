.DEFAULT_GOAL := help
BOARD ?= kv260
PLATFORM_DIR := platform/$(BOARD)
PLATFORM_BUILD := $(PLATFORM_DIR)/Makefile
PLATFORM_BITBAKE := /platform-source/linux/scripts/bitbake.sh
PLATFORM_STAGE_FPGA := $(PLATFORM_DIR)/linux/scripts/stage-fpga.sh

.PHONY: help check-platform check-roms sim bitstream userspace bootstrap container shell parse rootfs image stage-fpga
help:
	@echo 'BOARD=kv260 selects the target board (currently the only supported board)'
	@echo 'sim: run board integration tests; bitstream: build the FPGA application'
	@echo 'userspace: cross-build the selected board application'
	@echo 'bootstrap: fetch pinned AMD layers; container: build host tools; shell: enter build container'
	@echo 'stage-fpga: package and stage the latest successful FPGA build'
	@echo 'image: rebuild current userspace and an SD image with that FPGA build'

check-platform:
	@test -f '$(PLATFORM_BUILD)' || { echo 'Unsupported BOARD=$(BOARD)' >&2; exit 2; }

check-roms:
	@rom_dir="$${Z486_ROM_DIR:-roms}"; \
	  test -f "$$rom_dir/boot0.rom" || { echo "Missing $$rom_dir/boot0.rom" >&2; exit 2; }; \
	  test -f "$$rom_dir/boot1.rom" || { echo "Missing $$rom_dir/boot1.rom" >&2; exit 2; }

sim: check-platform
	$(MAKE) -C $(PLATFORM_DIR) sim
bitstream: check-platform
	$(MAKE) -C $(PLATFORM_DIR) package
userspace: check-platform
	$(MAKE) -C $(PLATFORM_DIR) userspace
bootstrap:
	bash scripts/bootstrap.sh
container:
	bash scripts/container.sh build
shell: check-platform
	Z486_XL_BOARD=$(BOARD) bash scripts/container.sh bash -i
parse: check-platform
	Z486_XL_BOARD=$(BOARD) bash scripts/container.sh bash $(PLATFORM_BITBAKE) -p z486-xl-rootfs
rootfs: check-platform
	Z486_XL_BOARD=$(BOARD) bash scripts/container.sh bash $(PLATFORM_BITBAKE) z486-xl-rootfs
image: check-platform check-roms stage-fpga
	Z486_XL_BOARD=$(BOARD) bash scripts/container.sh bash $(PLATFORM_BITBAKE) z486-xl-sd
stage-fpga: check-platform
	Z486_XL_BOARD=$(BOARD) bash $(PLATFORM_STAGE_FPGA)
