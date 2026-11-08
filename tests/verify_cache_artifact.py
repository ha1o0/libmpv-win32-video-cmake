#!/usr/bin/env python3
"""Reject cached Windows DLLs missing the Floe v4 background cache writer.

This checks compiled markers, not Windows playback or performance. Run mpv's
test/floe_cache_http.py and test/floe_cache_performance.py on Windows as well.
"""
import argparse
from pathlib import Path

REQUIRED = (b'Disk cache background writer v4.\n\0', b'.inventory-v1\0')


def verify(library):
    data = library.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('Expected a Windows PE library: {}'.format(library))
    if any(marker not in data for marker in REQUIRED):
        raise ValueError('Rebuild the updated mpv zcopy source: Floe cache v4 is missing')
    print('Verified Floe cache v4 compiled markers: {}'.format(library))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    verify(parser.parse_args().library)
