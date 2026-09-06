# z486_XL KV260 architecture

This document collects some notes about the z486_XL design on the KV260.

## CMA-based memory architecture

The programmable logic needs a large physical DDR range for PC memory and the
two graphics devices, but Linux normally manages memory through virtual and
non-contiguous addresses. The `z486_uio` driver therefore allocates one 256 MiB
DMA-coherent buffer from Linux's Contiguous Memory Allocator (CMA). Its physical
base is selected at runtime rather than fixed in the bitstream. The driver
publishes the control registers as UIO map 0 and the buffer as UIO map 1, then
programs the buffer's DMA address and size into the stopped FPGA core.

`z486-main` maps the same buffer into userspace, initializes the PC memory and
BIOS areas, and verifies that the hardware reports the expected size. Because
the mapping is DMA-coherent, userspace can initialize CPU-visible memory and
graphics storage without explicit cache-maintenance operations. The core is
released from reset only after the address, size, ROMs, and runtime options are
valid; stopping or unloading it drains memory traffic before the allocation is
released.

The physical base varies, but offsets within the allocation are fixed by
`platform/kv260/memory_map.json`:

| CMA offset | Size | Use |
| --- | ---: | --- |
| `0x00000000`–`0x07ffffff` | 128 MiB | Guest physical-address range. Runtime settings expose 16, 32, 64, or 128 MiB of RAM; normal PC decoding still applies to the VGA and BIOS holes in the first MiB. |
| `0x08000000`–`0x09ffffff` | 32 MiB | Reserved. |
| `0x0a000000`–`0x0a7fffff` | 8 MiB | zSST FBI framebuffer and depth-buffer storage. |
| `0x0a800000`–`0x0affffff` | 8 MiB | zSST TMU texture storage. |
| `0x0b000000`–`0x0f7fffff` | 72 MiB | Reserved. |
| `0x0f800000`–`0x0fffffff` | 8 MiB | Packed ET4000 framebuffer aperture. |

The design uses three independent 128-bit Zynq UltraScale+ high-performance
ports. These are named `S_AXI_HP*` from the processing system's point of view:
the FPGA logic is the AXI master and the PS DDR controller is the slave.

| Interface | FPGA client | Purpose |
| --- | --- | --- |
| `S_AXI_HP0_FPD` | PC memory bridge | CPU/L1 and L2 traffic, ISA DMA, and the auxiliary ROM/packed-VGA memory path. The bridge arbitrates the narrower PC-side clients onto one 128-bit port. |
| `S_AXI_HP1_FPD` | Unused | Reserved for possible future expansion. |
| `S_AXI_HP2_FPD` | zSST renderer | Independent reads and writes to FBI and TMU storage. |
| `S_AXI_HP3_FPD` | Video scanout | Read-only fetches from packed VGA or the active zSST front buffer into line buffers. |

Separating CPU, renderer, and scanout traffic allows them to remain concurrent
even though they ultimately share system DDR. Low-bandwidth control travels in
the opposite direction over `M_AXI_HPM0_FPD`: Linux uses it to access the z486
UIO registers and the Xilinx display, clock, and GPIO blocks. Those registers
are PL peripherals and are not part of the CMA address map.

## DDR and L2 cache

The auxiliary port retains MiSTer's `0x3000_0000` convention, but the KV260
bridge strips that prefix. Thus `0x300c_0000` aliases guest offset
`0x000c_0000`, and the packed framebuffer at `0x3f80_0000` occupies allocation
offset `0x0f80_0000`.

The bridge defaults to a 512 KiB direct-mapped, write-back UltraRAM L2 with
64-byte lines. Qualified L1 fills hit on-chip or fetch four 128-bit AXI beats
(`ARSIZE=4`, `ARLEN=3`); the requested 16 bytes return to L1 in one pulse after
the complete burst. Scalar reads and the VGA/ROM hole bypass allocation. DMA
and auxiliary accesses snoop the cache, device accesses remain ordered, and
dirty state drains before stop or FPGA reconfiguration. Set
`Z486_L2_WRITEBACK=0` only to build the older write-through comparison design.

L2 size is parameterized by `L2_SIZE_KIB`, which defaults to 512.
`L2_ENABLE=0` restores the single-beat baseline for isolated tests. Data uses
synchronous UltraRAM; tags use block RAM and are scrubbed on platform reset,
invalidation, or DDR-base change. Accesses bypass while scrubbing, and
in-flight AXI work drains normally with its cache fill discarded. Only the
explicit L1-fill marker qualifies reads for caching; ordinary RAM addresses
alone do not trigger allocation. The backing CMA base must be 64-byte aligned;
the allocator is page-aligned.

The legacy four-DWORD protocol is retained only by the DE10-Nano SDRAM backend.
The SDRAM/DDR split is confined to
`deps/z486-pc/src/memory/split_sdram_backend.sv`, instantiated only by the
DE10-Nano and legacy simulator wrappers.

## Startup and memory safety

Reset leaves `run=0`, so loading the programmable-logic design cannot make an
unconfigured AXI master touch Linux memory. Software must allocate coherent
memory, write its physical base and size, populate ROM locations, and only
then set the run bit. The `platform/kv260/kernel` and
`platform/kv260/userspace` directories implement this Linux boot path.

The KV260 build stores the four 64 KiB VGA planes in common-clock UltraRAM.
Each plane packs eight adjacent bytes into a 64-bit word, so its 8Kx64 memory
occupies two UltraRAMs while retaining byte writes and independent host/video
addresses. Portable MiSTer and simulation builds retain the original
dual-clock RAM implementation.

## Implementation results

The routed combined PC+zSST shell uses 94,503 LUTs (90,977 as logic), 58,701
flip-flops, 45 RAMB36s, 18 RAMB18s, 8 UltraRAMs, and 105 DSPs. The PC accounts
for 50,332 LUTs and 19 DSPs, zSST for 32,689 LUTs and 85 DSPs, and shared direct
scanout for 3,187 LUTs, four RAMB36s, and one DSP.

The build closes the 100 MHz PC/AXI clock and 150 MHz output-video clock with
0.073 ns overall WNS and 0.012 ns WHS. Vivado reports no unconstrained internal
endpoints, unrouted nets, or DRC errors. The corresponding production
DE10-Nano build excludes zSST and uses its original `ascal`; it fits at
37,839/41,910 ALMs (90%).
