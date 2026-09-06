# SD-only z486 XL boot. No firmware writes, environment saves or fallback flash.
if test "${devtype}" = "mmc"; then
    if part uuid mmc ${devnum}:2 xl_rootuuid; then
        setenv bootargs "root=PARTUUID=${xl_rootuuid} rootwait rw earlycon console=ttyPS1,115200 console=tty1 audit=0 loglevel=3 clk_ignore_unused uio_pdrv_genirq.of_id=generic-uio cma=800M video=DP-1:1920x1080@60e"
        setenv xl_conf conf-kv260-revB
        if test "${card1_rev}" = "A" || test "${card1_rev}" = "Z"; then
            setenv xl_conf conf-kv260-revA
        fi
        if load mmc ${devnum}:${distro_bootpart} 0x10000000 image.fit; then
            bootm 0x10000000#${xl_conf}
        fi
    fi
fi
echo "z486 XL SD boot failed; no flash fallback attempted"
