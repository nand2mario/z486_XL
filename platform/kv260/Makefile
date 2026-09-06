VIVADO ?= $(HOME)/Xilinx/Vivado/2024.2/bin/vivado
BOOTGEN ?= $(HOME)/Xilinx/Vivado/2024.2/bin/bootgen
DTC ?= dtc
FDTPUT ?= fdtput

BUILD := build
BIT_DIR := $(BUILD)/vivado/z486_kv260.runs/impl_1
BIT := $(BIT_DIR)/z486_platform_wrapper.bit
BIT_BIN := $(BIT_DIR)/z486_platform_wrapper.bit.bin
APP := $(BUILD)/app/z486-kv260
CONSOLE_BIT_DIR := $(BUILD)/console_vivado/z486_console.runs/impl_1
CONSOLE_BIT := $(CONSOLE_BIT_DIR)/z486_console_platform_wrapper.bit
CONSOLE_BIT_BIN := $(CONSOLE_BIT_DIR)/z486_console_platform_wrapper.bit.bin
CONSOLE_APP := $(BUILD)/app/z486-console
MEMORY_MAP_INPUT := memory_map.json
MEMORY_MAP_GENERATOR := scripts/generate_memory_map.py
MEMORY_MAP_OUTPUTS := include/z486_kv260_memory_map.h \
	rtl/z486_kv260_memory_map_pkg.sv

.PHONY: all validate synth console sim package package-files overlay userspace module memory-map clean

all: memory-map
	$(VIVADO) -mode batch -source scripts/build.tcl

validate: memory-map
	$(VIVADO) -mode batch -source scripts/build.tcl -tclargs validate

synth: memory-map
	$(VIVADO) -mode batch -source scripts/build.tcl -tclargs synth

console: $(CONSOLE_BIT)

sim:
	$(MAKE) -C sim

package: all console
	$(MAKE) package-files

package-files: $(APP)/z486_kv260.bit.bin $(APP)/z486_kv260.dtbo \
	$(APP)/shell.json $(CONSOLE_APP)/z486_console.bit.bin \
	$(CONSOLE_APP)/z486_console.dtbo $(CONSOLE_APP)/shell.json

overlay: $(BUILD)/z486_kv260.dtbo

$(BIT_BIN): $(BIT)
	printf 'all:\n{\n  %s\n}\n' 'z486_platform_wrapper.bit' > $(BIT_DIR)/z486_platform_wrapper.bif
	cd $(BIT_DIR) && $(BOOTGEN) -arch zynqmp -image z486_platform_wrapper.bif \
		-w -process_bitstream bin

$(CONSOLE_BIT): console/scripts/build.tcl console/constraints/kv260_console.xdc
	$(VIVADO) -mode batch -source console/scripts/build.tcl
	test -s $@

$(CONSOLE_BIT_BIN): $(CONSOLE_BIT)
	printf 'all:\n{\n  %s\n}\n' 'z486_console_platform_wrapper.bit' > $(CONSOLE_BIT_DIR)/z486_console_platform_wrapper.bif
	cd $(CONSOLE_BIT_DIR) && $(BOOTGEN) -arch zynqmp -image z486_console_platform_wrapper.bif \
		-w -process_bitstream bin

$(BUILD)/z486_kv260.dtbo: overlay/z486_kv260.dtso
	mkdir -p $(BUILD)
	$(DTC) -@ -I dts -O dtb -o $@ $<
	# Symbols are only needed by overlays stacked on top of this one. Keeping
	# them makes Linux copy properties into the live tree that it cannot free.
	$(FDTPUT) -r $@ /__symbols__

$(BUILD)/z486_console.dtbo: console/overlay/z486_console.dtso
	mkdir -p $(BUILD)
	$(DTC) -@ -I dts -O dtb -o $@ $<

$(APP)/z486_kv260.bit.bin: $(BIT_BIN)
	mkdir -p $(APP)
	cp $< $@

$(APP)/z486_kv260.dtbo: $(BUILD)/z486_kv260.dtbo
	mkdir -p $(APP)
	cp $< $@

$(APP)/shell.json: package/shell.json
	mkdir -p $(APP)
	cp $< $@

$(CONSOLE_APP)/z486_console.bit.bin: $(CONSOLE_BIT_BIN)
	mkdir -p $(CONSOLE_APP)
	cp $< $@

$(CONSOLE_APP)/z486_console.dtbo: $(BUILD)/z486_console.dtbo
	mkdir -p $(CONSOLE_APP)
	cp $< $@

$(CONSOLE_APP)/shell.json: package/shell.json
	mkdir -p $(CONSOLE_APP)
	cp $< $@

userspace:
	$(MAKE) -C userspace

module:
	$(MAKE) -C kernel
	mkdir -p $(BUILD)/module
	cp kernel/z486_uio.ko $(BUILD)/module/

memory-map: $(MEMORY_MAP_OUTPUTS)

$(MEMORY_MAP_OUTPUTS): $(MEMORY_MAP_INPUT) $(MEMORY_MAP_GENERATOR)
	python3 $(MEMORY_MAP_GENERATOR) $(MEMORY_MAP_INPUT) \
		include/z486_kv260_memory_map.h rtl/z486_kv260_memory_map_pkg.sv

clean:
	$(MAKE) -C userspace clean
	$(MAKE) -C kernel clean
	rm -rf build sim/obj_dir *.jou *.log .Xil
