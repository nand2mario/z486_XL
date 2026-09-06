#!/usr/bin/env python3
"""Run inside the build container. Checks init-shell boot, not board hardware."""
import argparse
import os
from pathlib import Path
import selectors
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel")
    parser.add_argument("rootfs")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--log", required=True)
    parser.add_argument("--counters", action="store_true",
                        help="also check packaged zsst-perf and its Python imports")
    parser.add_argument("--login", action="store_true",
                        help="normal init and console login using public root / 1")
    parser.add_argument("--sd", action="store_true",
                        help="input is a full WIC disk with root on partition 2")
    parser.add_argument("--min-root-mib", type=int, default=0,
                        help="require at least this many MiB in the mounted root filesystem")
    args = parser.parse_args()
    script = Path(__file__).with_name("qemu-smoke.sh")
    # The QEMU wrapper uses snapshot-only disk writes; no image mutation.
    proc = subprocess.Popen(
        ["bash", str(script), args.kernel, args.rootfs],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        env=dict(os.environ, XL_QEMU_NORMAL_BOOT="1" if args.login else "0",
                 XL_QEMU_ROOT="/dev/vda2" if args.sd else "/dev/vda"),
    )
    counter_check = "zsst-perf --help >/dev/null && " if args.counters else ""
    mount_setup = "" if args.login else "mount -t proc proc /proc && mount -t sysfs sysfs /sys && "
    size_check = (f"test $(df -Pm / | awk 'NR == 2 {{print $2}}') -ge {args.min_root_mib} && "
                  if args.min_root_mib else "")
    command = (mount_setup +
        "uname -r && python3 -c 'print(12345)' && "
        "test -x /usr/bin/z486-main && test -x /usr/bin/z486-drm && "
        "test -x /usr/bin/z486-run && test -x /usr/sbin/z486-kv260ctl && "
        "bash -n /usr/bin/z486-run /usr/sbin/z486-kv260ctl && "
        "z486-run --help | grep '^Usage: z486-run ' && "
        "(z486-run >/tmp/z486-run-noargs 2>&1; test $? -eq 2) && "
        "grep '^Usage: z486-run ' /tmp/z486-run-noargs && "
        "z486-main --help 2>&1 | grep '^usage: z486-main ' && "
        "z486-drm --help 2>&1 | grep '^usage: z486-drm ' && "
        "test -x /usr/sbin/fancontrol && bash -n /usr/sbin/fancontrol && "
        "grep -q '^FCTEMPS=.*pwm-fan.*ams.*temp1_input$' /etc/fancontrol && "
        "test -L /etc/systemd/system/multi-user.target.wants/fancontrol.service && "
        + counter_check + size_check +
        "modprobe z486_uio && test -d /sys/module/z486_uio && "
        "printf '\\nXL_ROOTFS_%s\\n' PASS\n"
    )
    # Splitting the marker in printf keeps command echo from producing a pass.
    deadline = time.monotonic() + args.timeout
    output = b""
    sent = False
    login_state = 0
    try:
        with open(args.log, "xb") as log, selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while time.monotonic() < deadline:
                if not selector.select(timeout=1):
                    if proc.poll() is not None:
                        break
                    continue
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    break
                log.write(chunk)
                log.flush()
                output = (output + chunk)[-65536:]
                if args.login and login_state == 0 and b"login:" in output:
                    proc.stdin.write(b"root\n")
                    proc.stdin.flush()
                    login_state = 1
                    output = b""
                elif args.login and login_state == 1 and b"Password:" in output:
                    proc.stdin.write(b"1\n")
                    proc.stdin.flush()
                    login_state = 2
                    output = b""
                ready = (args.login and login_state == 2 and b"# " in output) or (
                    not args.login and b"sh-5.2#" in output)
                if not sent and ready:
                    proc.stdin.write(command.encode())
                    proc.stdin.flush()
                    sent = True
                if b"XL_ROOTFS_PASS" in output:
                    mode = "console root/1 login" if args.login else "init shell"
                    print(f"PASS: {mode}, Python, z486 executable startup, fan control, UIO module load")
                    return
        raise SystemExit("FAIL: rootfs smoke test; inspect log (timeout or guest exit)")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    main()
