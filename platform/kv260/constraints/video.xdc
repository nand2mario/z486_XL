set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -hierarchical -filter {NAME =~ */scanout/aclk}]] \
    -group [get_clocks -quiet -of_objects [get_pins -hierarchical -filter {NAME =~ */scanout/video_clk}]]

# The sound generators use handshake synchronizers and the remaining mixer
# controls use two-flop synchronizers when crossing from the system clock.
# The dedicated audio-clock MMCM is not phase-related to the system clock.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_pl_0] \
    -group [get_clocks -quiet clk_out1_z486_platform_audio_clk_wiz_0]
