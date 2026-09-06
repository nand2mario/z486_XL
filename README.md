# z486 XL: FPGA 486 PC with Voodoo Graphics

z486 XL is an experimental FPGA PC for the [AMD Kria KV260 Vision AI
Starter Kit](https://www.amd.com/en/products/system-on-modules/kria/k26/kv260-vision-ai-starter-kit.html).
It combines the [z486](https://github.com/nand2mario/z486) PC with the
[zSST](https://github.com/nand2mario/zSST) Voodoo Graphics implementation and
uses the KV260's onboard DDR, so no external SDRAM module or FPGA add-on board
is needed.

The current system runs the PC at 100 MHz and provides a 512 KiB write-back L2
cache, VGA and zSST video, VHD disks, Sound Blaster 16 audio, USB keyboard and
mouse input, DisplayPort/HDMI output, and USB-drive automounting. Tomb Raider
is currently the only 3dfx game tested; this remains an
early compatibility and performance release.

## Install a release image

Download the latest `z486_XL-sd-kv260-*.wic.xz` from
[Releases](https://github.com/nand2mario/z486_XL/releases) and write it directly
to a microSD card with Balena Etcher or another image writer. Boot the KV260,
then log in as `root` with password `1` and change the password with `passwd`.

Copy VHD disk images to `/root/games` over SFTP/SCP, or use a USB drive mounted
below `/media`. Start a disk with:

```sh
z486-run /root/games/game.vhd
```

Press Ctrl+Alt+Esc to stop the PC and return to the Linux console. Run
`z486-run --help` for RAM and audio-gain options.

## Source layout

- `deps/z486-pc` pins [z486_MiSTer](https://github.com/nand2mario/z486_MiSTer),
  including its nested [z486](https://github.com/nand2mario/z486) CPU submodule.
- `deps/zsst` pins [zSST](https://github.com/nand2mario/zSST).
- `platform/kv260` contains everything specific to the currently supported
  board: its Vivado shell, DDR and L2 integration, Linux driver and userspace,
  board-level simulations, and SD-image definition.
- `container` and `scripts` provide shared Xilinx build infrastructure. The
  top-level Makefile selects `BOARD=kv260` by default, leaving room for other
  Xilinx boards under `platform/`.

Clone all dependencies with:

```sh
git clone --recurse-submodules https://github.com/nand2mario/z486_XL.git
cd z486_XL
```

Useful development targets are:

```sh
make sim        # run KV260 integration simulations with Verilator
make userspace  # cross-build the AArch64 board application
make bitstream  # build the FPGA application with Vivado 2024.2
```

The video path depends on Xilinx's [AV Pattern Generator DRM
driver](https://github.com/Xilinx/linux-xlnx/commit/5643e6e0318ed87297795893b18ddb147c0fb141),
introduced in Xilinx Linux 2025.2. DisplayPort audio also needs the live-audio
patch included here. The kernels in AMD's official KV260 SD images predate this
interface, so use a locally built FPGA application either by [installing it in
a z486 XL image](#install-a-locally-built-fpga-application) or by building the
complete Linux image below. A complete image build can take several hours.

The SD-image builder uses Docker and pinned AMD Embedded Development Framework
layers. It also needs the PC and VGA BIOS `boot0.rom` and `boot1.rom`, which
can be downloaded from the [MiSTer ao486
release](https://github.com/MiSTer-devel/ao486_MiSTer/tree/master/releases).
Place them in `roms/`, or set `Z486_ROM_DIR` to the directory containing them,
then run:

```sh
make bootstrap
make container
make image
```

### Install a locally built FPGA application

After `make bitstream`, stop any running guest with Ctrl+Alt+Esc and copy the
new application directory to the board:

```sh
scp -r platform/kv260/build/app/z486-kv260 root@<board-address>:/tmp/
ssh root@<board-address>
z486-kv260ctl unload
install -m 0644 /tmp/z486-kv260/z486_kv260.bit.bin \
  /tmp/z486-kv260/z486_kv260.dtbo \
  /tmp/z486-kv260/shell.json \
  /lib/firmware/xilinx/z486-kv260/
```

The next `z486-run` invocation loads the updated application. These directions
assume the board is already running a z486 XL SD image.

`make image` packages the latest successful local FPGA build. Build details,
interfaces, resource use, and standalone board commands are documented in
[`platform/kv260/README.md`](platform/kv260/README.md).

## License

z486 XL-owned source is licensed under the Apache License 2.0. Its submodules
and included Linux patches retain their own licenses and notices.
