#!/usr/bin/env python3
"""Reject stale cross-built libmpv DLLs missing independent subtitle options.

This is a cross-build capability check, not a Windows playback test. Actual
SRT/ASS rendering is covered by mpv/test/secondary_subtitle_style.py against
native libmpv. Option names below must be compiled into the packaged DLL.
"""
import argparse
from pathlib import Path

REQUIRED_OPTIONS = (
    b'secondary-sub-style\0',
    b'secondary-sub-ass-style-overrides\0',
    b'secondary-sub-ass-styles\0',
    b'secondary-sub-hdr-peak\0',
    b'secondary-image-subs-hdr-peak\0',
)


def verify(library):
    data = library.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('Expected a Windows PE library: {}'.format(library))
    missing = [name[:-1].decode() for name in REQUIRED_OPTIONS if name not in data]
    if missing:
        raise ValueError('Rebuild mpv from the updated zcopy branch; missing: ' + ', '.join(missing))
    print('Verified independent subtitle option markers: {}'.format(library))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    args = parser.parse_args()
    verify(args.library)
