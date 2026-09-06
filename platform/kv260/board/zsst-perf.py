#!/usr/bin/env python3
"""Read ABI 1.7/1.8 counters without stopping the game (requires root).

Snapshots are atomic, including while rendering. 32-bit counters wrap; sample
every 0.2 seconds so even 127-entry occupancy integrals cannot wrap twice at
100 MHz. Do not run another counter reader concurrently (shared index port).
"""
import argparse
import ctypes
import json
import mmap
import os
from pathlib import Path
import time

NAMES = {
    2: 'cycles', 3: 'renderer_busy', 4: 'raster_candidates',
    5: 'pixel_issue', 6: 'pixel_retire', 7: 'tmu_accept', 8: 'tmu_retire',
    11: 'pixel_pass', 23: 'texture_lookup', 24: 'texture_hit',
    25: 'texture_miss', 26: 'texture_replay', 29: 'texture_fill_requests',
    30: 'texture_fill_beats', 48: 'mem_requests', 49: 'mem_writes',
    51: 'mem_response_beats', 54: 'mem_write_bytes',
    61: 'tmu_arb_wait', 62: 'fbi_arb_wait', 63: 'response_backpressure',
    64: 'tmu_rob_occupancy_sum', 66: 'texture_wait_occupancy_sum',
    68: 'texture_mshr_occupancy_sum', 70: 'fbi_pending_occupancy_sum',
    72: 'fbi_join_occupancy_sum',
    128: 'board_cycles', 129: 'fbi_active', 130: 'swaps',
    131: 'host_blocked', 132: 'host_writes', 133: 'host_reads',
    134: 'host_responses', 135: 'request_fifo_blocked',
    136: 'axi_bridge_blocked', 137: 'pc_mem_accept_wait',
    138: 'pc_mem_read_wait', 139: 'fbi_and_pc_read_wait',
    140: 'renderer_idle_pc_mem_not_waiting', 141: 'axi_write_beats',
    142: 'axi_read_beats', 143: 'axi_write_responses',
    200: 'l2_hits', 201: 'l2_misses', 202: 'l2_fill_beats',
}
MAXIMA = {65, 67, 69, 71, 73, 74, 75, 76, 77}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=5)
    parser.add_argument('--uio', default='uio0')
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error('--seconds must be positive')
    base = int(Path('/sys/class/uio', args.uio, 'maps/map0/addr').read_text(), 0)
    fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
    regs = mmap.mmap(fd, 4096, flags=mmap.MAP_SHARED,
                     prot=mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
    # Aligned volatile-sized MMIO transactions; pack_into may emit byte stores.
    words = (ctypes.c_uint32 * 1024).from_buffer(regs)

    def read(offset):
        return words[offset // 4]

    def write(offset, value):
        words[offset // 4] = value

    abi = read(4)
    if read(0) != 0x5a343836 or abi not in (0x10007, 0x10008):
        raise SystemExit('Requires z486 control ABI 1.7/1.8; no registers changed')

    indices = list(range(80)) + list(range(128, 144))
    if abi == 0x10008:
        indices += [200, 201, 202]

    def snapshot():
        sequence = read(0xac)
        write(0xa0, 0)
        read(0xa0)  # complete the low request before the rising edge
        write(0xa0, 1)
        deadline = time.monotonic() + 1
        while read(0xac) == sequence:
            if time.monotonic() > deadline:
                raise RuntimeError('Snapshot timeout: is the guest running?')
        values = {}
        for index in indices:
            if index >= 200:
                values[index] = read(0xb4 + (index - 200) * 4)
                continue
            write(0xa4, index)
            read(0xa4)  # allow synchronous counter read to settle
            values[index] = read(0xa8)
        return values

    previous = snapshot()
    video_sources = {read(0x80) & 3}
    total = dict.fromkeys(indices, 0)
    start = time.monotonic()
    last = start
    while time.monotonic() - start < args.seconds:
        time.sleep(min(0.2, max(0, args.seconds - (time.monotonic() - start))))
        current = snapshot()
        video_sources.add(read(0x80) & 3)
        now = time.monotonic()
        if now - last > 0.30:
            raise RuntimeError('Sampling delayed; occupancy deltas may have wrapped twice')
        for i in indices:
            total[i] = max(total[i], current[i]) if i in MAXIMA else \
                total[i] + ((current[i] - previous[i]) & 0xffffffff)
        previous, last = current, now
    cycles = total[128]
    if not cycles:
        raise SystemExit('No active guest cycles measured')
    elapsed = last - start
    out = {
        'abi': f'{abi >> 16}.{abi & 0xffff}',
        'video_sources': [{0: 'VGA', 1: 'packed', 2: 'zSST'}.get(i, str(i))
                          for i in sorted(video_sources)],
        'elapsed_seconds': elapsed,
        'measured_clock_mhz': cycles / elapsed / 1e6,
        'swaps_per_second': total[130] / elapsed,
        'percent_cycles': {NAMES[i]: 100 * total[i] / cycles for i in
                           (3, 129, 131, 135, 136, 137, 138, 139, 140, 61, 62, 63)},
        'mean_occupancy': {NAMES[i]: total[i] / cycles for i in (64, 66, 68, 70, 72)},
        'counts': {NAMES.get(i, f'p{i}'): total[i] for i in indices if i >= 2},
        'note': 'Wait categories overlap; PC backend waits are not CPU retirement stalls. Maxima are since reset.',
    }
    if abi == 0x10008:
        accesses = total[200] + total[201]
        l2_status = read(0xc0)
        write_back = bool(l2_status & 4)
        out['l2'] = {'size_kib': l2_status >> 16,
                     'ready': bool(l2_status & 1),
                     'policy': 'write-back' if write_back else 'write-through',
                     'access_scope': 'CPU/DMA/aux cached reads and writes' if write_back else 'CPU L1 line-fill lookups',
                     'hit_percent': 100 * total[200] / accesses if accesses else None,
                     'note': 'L2 counters are live reads adjacent to the GPU snapshot, not part of its atomic bank.'}
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
