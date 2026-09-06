# z486 XL development and testing

Paths and commands in this document are relative to the repository root.

## Direct board deployment

The release-image update procedure is in the top-level
[README](../../README.md#install-a-locally-built-fpga-application). For development
on another compatible Linux installation, copy
`platform/kv260/build/app/z486-kv260/`,
`platform/kv260/build/module/z486_uio.ko`, the two userspace binaries, and
`platform/kv260/board/` to the board. Run `board/install.sh` from that copied
tree, then load and inspect the safe, stopped core with:

```bash
z486-kv260ctl load
z486-kv260ctl status
```

This path still requires a compatible Xilinx DRM/DPSUB kernel plus the z486 XL
live-audio patch. Prefer the release image unless developing the Linux port.

## Overlay behavior

The package strips its optional DTBO `__symbols__` node because nothing stacks
another overlay on top of the application. Linux still prints overlay
memory-leak warnings for `fpga-region/firmware-name`, `fpga-region/resets`, and
the DPSUB clock properties. Those properties must replace base-tree values for
runtime FPGA and live-video loading. The upstream overlay code deliberately
retains their small allocations on removal because notifier users may hold
pointers. AMD's stock Kria application produces the same warning for its FPGA
region properties.

This warning does not refer to the 256 MiB CMA buffer. In a measured
load/unload test, `CmaFree` returned exactly from 9,224 KiB to 273,104 KiB.

## Runtime behavior

The `z486-drm` helper holds the AVPG CRTC, DPSUB mode, and dynamic pixel clock;
AVPG-generated pixels are disconnected. The launcher supports writable VHD
disks, optional Linux evdev keyboard and mouse devices, direct live video, and
48 kHz DisplayPort audio.

For a development installation using the legacy MiSTer-compatible directory
layout, place ROMs and disk images under `/media/fat/games/Z486/` and run:

```bash
z486-run /media/fat/games/Z486/dos6.vhd --ram-mb 16 --audio-boost 1
```

`--ram-mb` selects 16, 32, 64, or 128 MiB and defaults to 16 MiB. This changes
memory visible to the PC, not the fixed 256 MiB CMA allocation. One scanout
path displays legacy VGA, packed 8/16/24-bit ET4000 modes through 1024x768, and
zSST as centered 4:3 (1440x1080) nearest-neighbor video. Legacy `--filter`
arguments are accepted for script compatibility but ignored with a warning.

`--audio-boost` selects saturated 1x, 2x, or 4x gain for mixed PC-speaker,
Sound Blaster, CMS, and OPL output; it defaults to 1x. Audio is sent as stereo
48 kHz PCM through the KV260 DisplayPort output.

`z486-run` selects the first keyboard and relative mouse devices listed in
`/proc/bus/input/devices`. A combined keyboard/touchpad receiver is opened once
and used for both. Pass `--keyboard /dev/input/eventX` or
`--mouse /dev/input/eventY` to override either choice. The application grabs
the selected devices while running, translates Linux key events to PS/2 scan
set 2, and turns relative mouse events into three-byte PS/2 packets.

Add `--ide-debug` or `--input-debug` to trace the corresponding protocol. The
foreground loop reports boot stage, POST, `CS:EIP`, DDR counters, video
dimensions, and IDE sector counts once per second. Stopping the launcher
flushes writable media, loads the Linux-console FPGA application, and restores
the console.

Floppy, ATAPI, joystick, OSD, and full packed-SVGA board acceptance remain
future work.

## Whole-PC simulation

The complete-PC Verilator harness has an opt-in zSST build. It uses the real
PCI configuration endpoint and portable zSST frontend, FBI, and TMU, with a
deterministic DDR response model suitable for locating Glide discovery and
command-flow failures:

```bash
make -C deps/z486-pc/verilator voodoo ZSST=../../zsst
deps/z486-pc/verilator/obj_dir_voodoo/Vz486_mister_sim \
  --headless --disk <disk-image>.vhd --zsst-debug
```

`--zsst-debug` reports PCI configuration traffic, BAR/MMIO host accesses,
renderer memory traffic, and video-state changes. `--trace` and `--trace-start`
expose the PC and zSST hierarchy in the same FST. The diagnostic DDR model
retains framebuffer and texture writes, so simulator PNG captures and compact
write replays can be compared before final board validation.
