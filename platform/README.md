# Board platforms

z486 XL targets Xilinx devices. Each supported board has one directory below
`platform/`; `kv260` is currently the only implementation.

A platform owns everything tied to its board, including FPGA constraints and
shells, memory and display adapters, overlays, kernel and userspace support,
simulations, and its Linux image definition. Shared dependency pins, build
containers, and build dispatch remain at the repository root.

The root Makefile expects a platform Makefile to provide these targets:

- `sim`: run board-integration tests.
- `userspace`: build its host-side application.
- `package`: build its deployable FPGA application.

If the platform supplies an SD image, put its BitBake layer, configuration,
boot files, and image helper scripts below `platform/<board>/linux`. Select a
platform with `make BOARD=<board> <target>`.
