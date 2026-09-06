# z486 KV260 platform

This directory contains the KV260-specific shell for the complete z486 PC.
The portable PC and Voodoo Graphics implementations enter through the pinned
`deps/z486-pc` and `deps/zsst` submodules. Hardware adapters, Linux runtime,
and image packaging that depend on the KV260 live here; shared Xilinx build
orchestration stays at the repository root.

The main data paths are:

```text
CPU/main memory --32-bit--+
ISA DMA ---------32-bit--+--> fair bridge --> 128-bit AXI HP0 --> PS DDR
ROM/packed VGA --64-bit--+

legacy VGA renderer --requested rows--+
packed ET4000 FB ----128-bit AXI HP3--+--> two RGB565 line buffers
zSST front buffer ---128-bit AXI HP3--+--> 4:3 nearest 1080p60 --> PS DPSUB

PC speaker/SB/CMS/OPL --> stereo mixer --> 48 kHz live audio --> PS DPSUB
```

## Build

Prerequisites are Vivado 2024.2, Verilator, `dtc`/`fdtput`, an AArch64 cross
compiler, and a configured `linux-xlnx` build tree for the kernel module.

```bash
make sim       # run the board-integration simulation suite
make synth     # synthesize the complete headless PC
make           # synthesize, place, route, and build the bitstream
make package   # build deployable FPGA application directories
make userspace # cross-compile z486-main and z486-drm for AArch64
make module    # build the CMA/UIO module against the configured kernel
```

The repository-level Makefile exposes the common `sim`, `userspace`, and
`bitstream` targets. SD-image building and installation are documented in the
top-level [README](../../README.md).

## Technical documentation

- [KV260 architecture](../../doc/kv260/architecture.md): DDR integration, L2,
  scanout, startup safety, and implementation results.
- [Control interface](../../doc/kv260/control-interface.md): UIO ABI register map and
  performance-counter semantics.
- [Development and testing](../../doc/kv260/development.md): direct board deployment,
  runtime behavior, overlay details, and whole-PC simulation.
