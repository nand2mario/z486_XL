VERILATOR ?= verilator
XL_ROOT := ../../..
PC_ROOT ?= $(XL_ROOT)/deps/z486-pc
ZSST_ROOT ?= $(XL_ROOT)/deps/zsst
BRIDGE_BUILD := obj_dir
CONTROL_BUILD := obj_dir_control
IDE_BUILD := obj_dir_ide
PCI_BUILD := obj_dir_pci
SCANOUT_BUILD := obj_dir_shared_scanout

.PHONY: all clean

all: bridge l2 control ide pci shared-scanout audio v68-area-perf zsst-write-pairing zsst-reset-drain

.PHONY: audio
audio:
	$(VERILATOR) --binary --assert --timing --top-module tb_z486_dp_audio \
		-Wall -Wno-fatal -Mdir obj_dir_audio ../rtl/z486_dp_audio.sv \
		tb_z486_dp_audio.sv
	./obj_dir_audio/Vtb_z486_dp_audio

.PHONY: l2
l2:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_ddr_axi_bridge \
		-GTEST_L2=1 --Mdir obj_dir_l2 ../rtl/z486_l2_cache.sv \
		../rtl/z486_ddr_axi_bridge.sv tb_z486_ddr_axi_bridge.sv
	./obj_dir_l2/Vtb_z486_ddr_axi_bridge

.PHONY: l2-write-perf
l2-write-perf:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_ddr_axi_bridge \
		-GTEST_L2=1 -GWRITE_RESPONSE_DELAY=20 --Mdir obj_dir_l2_write_perf \
		../rtl/z486_l2_cache.sv ../rtl/z486_ddr_axi_bridge.sv tb_z486_ddr_axi_bridge.sv
	./obj_dir_l2_write_perf/Vtb_z486_ddr_axi_bridge

.PHONY: l2-wb-bridge
l2-wb-bridge:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_ddr_wb_bridge \
		--Mdir obj_dir_wb_bridge ../rtl/z486_l2_cache.sv ../rtl/z486_l2_wb_store.sv \
		../rtl/z486_l2_wb_controller.sv ../rtl/z486_l2_line_axi.sv \
		../rtl/z486_ddr_axi_bridge.sv ../rtl/z486_ddr_wb_bridge.sv tb_z486_ddr_wb_bridge.sv
	./obj_dir_wb_bridge/Vtb_z486_ddr_wb_bridge

.PHONY: l2-wb-bridge-xpm
l2-wb-bridge-xpm:
	mkdir -p obj_dir_wb_bridge_xpm
	cd obj_dir_wb_bridge_xpm && xvlog --sv \
		$(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv \
		../../rtl/z486_l2_cache.sv ../../rtl/z486_l2_wb_store.sv \
		../../rtl/z486_l2_wb_controller.sv ../../rtl/z486_l2_line_axi.sv \
		../../rtl/z486_ddr_axi_bridge.sv ../../rtl/z486_ddr_wb_bridge.sv ../tb_z486_ddr_wb_bridge.sv
	cd obj_dir_wb_bridge_xpm && xelab tb_z486_ddr_wb_bridge -s wb_bridge -L unisims_ver -L unimacro_ver
	cd obj_dir_wb_bridge_xpm && xsim wb_bridge -runall -log xsim.log
	grep -q 'PASS assembled WB bridge' obj_dir_wb_bridge_xpm/xsim.log
	! grep -E 'Fatal:|Error:|ERROR:' obj_dir_wb_bridge_xpm/xsim.log

.PHONY: l2-line-axi
l2-line-axi:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_l2_line_axi \
		--Mdir obj_dir_line_axi ../rtl/z486_l2_line_axi.sv tb_z486_l2_line_axi.sv
	./obj_dir_line_axi/Vtb_z486_l2_line_axi

.PHONY: l2-wb-controller
l2-wb-controller:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_l2_wb_controller \
		--Mdir obj_dir_wb_controller ../rtl/z486_l2_cache.sv ../rtl/z486_l2_wb_store.sv \
		../rtl/z486_l2_wb_controller.sv tb_z486_l2_wb_controller.sv
	./obj_dir_wb_controller/Vtb_z486_l2_wb_controller

.PHONY: l2-wb-store
l2-wb-store:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_z486_l2_wb_store \
		--Mdir obj_dir_wb_store ../rtl/z486_l2_cache.sv ../rtl/z486_l2_wb_store.sv \
		tb_z486_l2_wb_store.sv
	./obj_dir_wb_store/Vtb_z486_l2_wb_store

.PHONY: l2-wb-store-xpm
l2-wb-store-xpm:
	mkdir -p obj_dir_wb_store_xpm
	cd obj_dir_wb_store_xpm && xvlog --sv \
		$(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv \
		../../rtl/z486_l2_cache.sv ../../rtl/z486_l2_wb_store.sv ../tb_z486_l2_wb_store.sv
	cd obj_dir_wb_store_xpm && xelab tb_z486_l2_wb_store -s wb_store -L unisims_ver -L unimacro_ver
	cd obj_dir_wb_store_xpm && xsim wb_store -runall -log xsim.log
	grep -q 'PASS: write-back storage' obj_dir_wb_store_xpm/xsim.log
	! grep -E 'Fatal:|Error:|ERROR:' obj_dir_wb_store_xpm/xsim.log

# Check the synthesis-side XPM memories too, not only the Verilator model.
# Run with Vivado's bin directory on PATH (settings64.sh also sets XILINX_VIVADO).
XILINX_VIVADO ?= $(abspath $(dir $(shell command -v vivado))/..)
.PHONY: l2-xpm
l2-xpm:
	mkdir -p obj_dir_l2_xpm
	cd obj_dir_l2_xpm && xvlog --sv \
		$(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv \
		../../rtl/z486_l2_cache.sv ../../rtl/z486_ddr_axi_bridge.sv \
		../tb_z486_ddr_axi_bridge.sv
	cd obj_dir_l2_xpm && xelab tb_z486_ddr_axi_bridge -generic_top TEST_L2=1 \
		-s l2_xpm -L unisims_ver -L unimacro_ver
	cd obj_dir_l2_xpm && xsim l2_xpm -runall -log xsim.log
	grep -q 'PASS: 512 KiB L2' obj_dir_l2_xpm/xsim.log
	! grep -E 'Fatal:|Error:|ERROR:' obj_dir_l2_xpm/xsim.log

.PHONY: v68-area-perf
v68-area-perf:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_v68_area_perf \
		--Mdir obj_dir_v68 $(ZSST_ROOT)/sst1_pkg.sv \
		$(ZSST_ROOT)/sst1_perf_counters.sv $(ZSST_ROOT)/tmu/sst1_tmu.sv \
		../rtl/zsst/zsst_board_perf.sv tb_v68_area_perf.sv
	./obj_dir_v68/Vtb_v68_area_perf

.PHONY: zsst-reset-drain
zsst-reset-drain:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_zsst_reset_drain \
		--Mdir obj_dir_zsst_reset_drain $(ZSST_ROOT)/sst1_pkg.sv \
		../rtl/zsst/zsst_reset_guard.sv ../rtl/zsst/sst1_axi_bridge.sv tb_zsst_reset_drain.sv
	./obj_dir_zsst_reset_drain/Vtb_zsst_reset_drain

.PHONY: zsst-write-pairing
zsst-write-pairing:
	$(VERILATOR) --binary --assert --timing -Wno-fatal --top-module tb_zsst_write_pairing \
		--Mdir obj_dir_zsst_pairing $(ZSST_ROOT)/sst1_pkg.sv \
		../rtl/zsst/zsst_mem_request_fifo.sv ../rtl/zsst/sst1_axi_bridge.sv \
		tb_zsst_write_pairing.sv
	./obj_dir_zsst_pairing/Vtb_zsst_write_pairing

.PHONY: bridge control ide pci shared-scanout zsst-capture

zsst-capture:
	$(VERILATOR) --binary --timing -Wno-fatal --top-module tb_zsst_debug_capture \
		--Mdir obj_dir_zsst_capture $(ZSST_ROOT)/sst1_pkg.sv \
		../rtl/zsst/zsst_debug_capture.sv tb_zsst_debug_capture.sv
	./obj_dir_zsst_capture/Vtb_zsst_debug_capture

bridge:
	$(VERILATOR) --binary --timing --top-module tb_z486_ddr_axi_bridge \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Mdir $(BRIDGE_BUILD) ../rtl/z486_ddr_axi_bridge.sv \
		tb_z486_ddr_axi_bridge.sv
	./$(BRIDGE_BUILD)/Vtb_z486_ddr_axi_bridge

control:
	$(VERILATOR) --binary --timing --top-module tb_z486_control \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Mdir $(CONTROL_BUILD) ../rtl/z486_control.sv tb_z486_control.sv
	./$(CONTROL_BUILD)/Vtb_z486_control

ide:
	$(VERILATOR) --binary --timing --top-module tb_z486_ide_tunnel \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Mdir $(IDE_BUILD) ../rtl/z486_control.sv \
		$(PC_ROOT)/src/common/dpram.v $(PC_ROOT)/src/soc/ide.v tb_z486_ide_tunnel.sv
	./$(IDE_BUILD)/Vtb_z486_ide_tunnel

pci:
	$(VERILATOR) --binary --timing --top-module tb_zsst_pci_config \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Mdir $(PCI_BUILD) $(PC_ROOT)/src/voodoo/zsst_pci_config.sv \
		tb_zsst_pci_config.sv
	./$(PCI_BUILD)/Vtb_zsst_pci_config

shared-scanout:
	$(VERILATOR) --binary --timing --top-module tb_z486_shared_scanout \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Mdir $(SCANOUT_BUILD) ../rtl/z486_shared_scanout.sv \
		tb_z486_shared_scanout.sv
	./$(SCANOUT_BUILD)/Vtb_z486_shared_scanout

clean:
	rm -rf $(BRIDGE_BUILD) $(CONTROL_BUILD) $(IDE_BUILD) $(PCI_BUILD) \
		$(SCANOUT_BUILD)
	rm -rf obj_dir_audio
