# z486 XL control interface

The Linux driver exposes the z486 control block through UIO. Find its physical
address through `/sys/class/uio/uio*/maps/map0/addr`.

## Register map

| Offset | Access | Meaning |
| ---: | --- | --- |
| `0x00` | R | Magic `0x5a343836` (`Z486`) |
| `0x04` | R | ABI version (`1.9`) |
| `0x08` | R/W | Status and run bit 0 |
| `0x0c` | R/W | Coherent DDR allocation base bits 31:0 |
| `0x10` | R/W | Coherent DDR allocation base bits 39:32 |
| `0x14` | R | Accepted logical request count |
| `0x18` | R | Returned read-beat count |
| `0x1c` | R | AXI stall-cycle count |
| `0x20` | R | AXI response-error count |
| `0x24` | R/W | Coherent DDR allocation size in bytes |
| `0x28` | R | Boot stage, BIOS-loaded, first-instruction, and POST status |
| `0x2c` | R | Current CPU `CS` |
| `0x30` | R | Current CPU `EIP` |
| `0x34` | R | Management busy and floppy/IDE request fields |
| `0x38` | R/W | Management address |
| `0x3c` | R/W | Management write data |
| `0x40` | R | Management read data |
| `0x44` | R/W | Management command/status (`1` read, `2` write) |
| `0x48` | R | PS/2 TX-empty flags and keyboard/mouse host commands |
| `0x4c` | W | Queue one keyboard byte when keyboard TX is empty |
| `0x50` | W | Queue one mouse byte when mouse TX is empty |
| `0x54` | W | Clear keyboard/mouse host-command flags |
| `0x58` | R/W | Video run/freeze; legacy filter field is ignored |
| `0x5c` | R | Detected source width/height minus one |
| `0x60` | R | Physical HDMI frame count |
| `0x64` | R | Reserved; always zero (old scaler write bursts) |
| `0x68` | R | Packed/zSST scanout read bursts |
| `0x6c` | R | Reserved; always zero (old scaler write beats) |
| `0x70` | R | Packed/zSST scanout read beats |
| `0x74` | R | Missed line-buffer deadlines |
| `0x78` | R | Sticky AXI-range/response and underflow bits |
| `0x7c` | R/W | Guest RAM size code; 0–3 select 16–128 MiB while stopped |
| `0x80` | R | Active source: 0 legacy VGA, 1 packed VGA, 2 zSST |
| `0x84` | R | Source-row requests accepted |
| `0x88` | R | Source rows completed successfully |
| `0x8c` | R | Guest-visible native VGA retraces |
| `0x90` | R | AXI scanout outstanding-request high-water mark |
| `0xa0` | R/W | Rising bit 0 requests an atomic performance snapshot |
| `0xa4` | R/W | Performance counter index |
| `0xa8` | R | Selected snapshot counter (32 bits) |
| `0xac` | R | Snapshot sequence number |
| `0xb0` | R | Bits 0/1/2: PC/renderer/scanout AXI bridges drained |
| `0xb4` | R | L2 hits (live, 32-bit wrapping) |
| `0xb8` | R | L2 misses (live, 32-bit wrapping) |
| `0xbc` | R | L2 DDR fill beats (live, 32-bit wrapping) |
| `0xc0` | R | L2 size in KiB in bits 31:16; bit 1 enabled, bit 0 ready |
| `0xc4` | R/W | Audio boost: 0/1/2 select saturated 1x/2x/4x gain |

## Performance counters

ABI 1.7 replaced the temporary 8192-entry AXI capture buffer with counters.
The capture RTL and regression remain available for deliberate debug builds,
but are not synthesized into the board image. Run `zsst-perf --seconds 5` while
a game is active. It samples every 0.2 seconds to handle 32-bit wrap, including
occupancy integrals, without clearing counters or stopping rendering. Only one
counter reader may use the shared index and snapshot registers at a time.

Indices 0–79 follow `deps/zsst/sst1_perf_counters.sv`; indices 128–143 are
documented in `platform/kv260/rtl/zsst/zsst_board_perf.sv`, with their event
vector in `platform/kv260/rtl/z486_zsst.sv`. Snapshots are immediate and
coherent across both banks, including during busy rendering.

The counters help compare FBI activity, swap rate, host blocking, PC-backend
waits, texture-cache misses, and AXI pressure. These are overlapping event
categories: backend waits are not architectural CPU stalls or retirement
counts, and HDMI refresh counts are not rendered game frames. Counter maxima
are measured since reset.
