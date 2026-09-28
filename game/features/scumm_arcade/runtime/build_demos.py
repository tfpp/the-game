#!/usr/bin/env python3
"""Package pinned original DOS demo data for the shared SCUMM interpreter."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
DEMOS = {
    'samnmax': ('samnmax-dos-demo-en.zip', '3b13c9337324c23e262a9fa5a84778216e1eeacf689b24e81cf9ad9b6e00d0c7'),
    'atlantis': ('atlantis-dos-demo1-en.zip', 'a7e66c4b10f83b2ac25cdbbccb7790b4c022e6df006548c381f2b9ef09ee6361'),
    'pass': ('pass-dos-en.zip', 'db319acdc8e846a213f64dea46e3444ed8c580a8e3da74dcc20eb67fd6983ecd'),
    'tentacle': ('dott-dos-ni-demo-en.zip', 'b77f03981da3815a352330f39f54d46e187bb05503cf1c832bb0d14539f15964'),
}
DATA_SUFFIXES = {'.000', '.001', '.lfl', '.lec', '.sm0', '.sm1', '.sou', '.txt', '.me'}


def build(cache):
    cache.mkdir(parents=True, exist_ok=True)
    dist = HERE / 'dist'
    dist.mkdir(exist_ok=True)
    for game, (filename, expected) in DEMOS.items():
        archive = cache / filename
        url = 'https://downloads.scummvm.org/frs/demos/scumm/' + filename
        if not archive.exists():
            urllib.request.urlretrieve(url, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Demo digest mismatch: {archive}')
        files = []
        with zipfile.ZipFile(archive) as source:
            for name in sorted(source.namelist()):
                if Path(name).name != name:
                    raise ValueError(f'Unexpected nested demo file: {name}')
                if Path(name).suffix.lower() in DATA_SUFFIXES:
                    # Passport uses legacy ZIP implode, supported by Info-ZIP.
                    try:
                        content = source.read(name)
                    except NotImplementedError:
                        content = subprocess.check_output(['unzip', '-p', str(archive), name])
                    files.append((name, content))
        header = json.dumps([[name, len(data)] for name, data in files], separators=(',', ':')).encode()
        data = struct.pack('<I', len(header)) + header + b''.join(data for _, data in files)
        (dist / f'{game}.pak').write_bytes(data)
        print(game, len(data), hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=HERE.parents[3] / 'build/scumm-arcade/demos')
    build(parser.parse_args().cache)
