#!/usr/bin/env python3
"""Build the pinned SCUMM interpreter and demo into a portable WASM module.

Requires Python 3.10+, make, and Emscripten 3.1.74. No system installation or
repository-wide compiler settings are changed. Downloads are SHA-256 checked.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile
from build_demos import build as build_demos

HERE = Path(__file__).resolve().parent
SOURCE_URL = 'https://github.com/scummvm/scummvm/archive/refs/tags/v2.9.0.tar.gz'
SOURCE_SHA = 'a627ba02ee9c1f475ded46bc820be6bd4918ae2d0f689f3b7437e531b271b619'
DEMO_URL = 'https://downloads.scummvm.org/frs/demos/scumm/monkey1-dos-ega-demo-en.zip'
DEMO_SHA = '1cb530fc4ab1d1f005e6630de31fe1a4186a7ad5d1a2b73e126e898e5e9039d0'


def download(url, destination, digest):
    if not destination.exists():
        print(f'Downloading {url}', flush=True)
        temporary = destination.with_suffix('.download')
        urllib.request.urlretrieve(url, temporary)
        temporary.replace(destination)
    actual = hashlib.sha256(destination.read_bytes()).hexdigest()
    if actual != digest:
        raise RuntimeError(f'SHA-256 mismatch: {destination}; remove it and retry')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emsdk', type=Path, default=os.environ.get('EMSDK'))
    parser.add_argument('--cache', type=Path, default=HERE.parents[3] / 'build/scumm-arcade')
    parser.add_argument('--jobs', type=int, default=8)
    args = parser.parse_args()
    if not args.emsdk:
        parser.error('Pass --emsdk=PATH or activate Emscripten 3.1.74 first')
    sdk = args.emsdk.resolve()
    work = args.cache.resolve()
    work.mkdir(parents=True, exist_ok=True)
    source_archive, demo_archive = work / 'scummvm.tar.gz', work / 'demo.zip'
    download(SOURCE_URL, source_archive, SOURCE_SHA)
    download(DEMO_URL, demo_archive, DEMO_SHA)
    source = work / 'scummvm-2.9.0'
    if not source.exists():
        with tarfile.open(source_archive) as archive:
            # Extract only the verified upstream archive; reject paths outside work.
            for entry in archive.getmembers():
                if not (work / entry.name).resolve().is_relative_to(work):
                    raise ValueError('Unsafe archive path')
            archive.extractall(work, filter='data')
    demo = work / 'demo'
    demo.mkdir(exist_ok=True)
    with zipfile.ZipFile(demo_archive) as archive:
        archive.extractall(demo)
    ini = work / 'arcade.ini'
    ini.write_text('[scummvm]\nrandom_seed=19791015\nconfirm_exit=false\nextrapath=/demo\n')
    shutil.copyfile(HERE / 'arcade_backend.cpp', source / 'backends/platform/null/null.cpp')
    configure = source / 'configure'
    text = configure.read_text()
    text = text.replace('wasm*-emscripten)\n\t\t\t_backend="sdl"',
                        'wasm*-emscripten)\n\t\t\t_backend="null"')
    text = text.replace(
        'append_var LDFLAGS "--pre-js ./dists/emscripten/custom_shell-pre.js '
        '--post-js ./dists/emscripten/custom_shell-post.js '
        '--shell-file ./dists/emscripten/custom_shell.html"',
        ': # Custom arcade module supplies its own JS host')
    configure.write_text(text)

    def run(command):
        subprocess.run(['bash', '-c', 'source "$1/emsdk_env.sh" >/dev/null 2>&1; '
                        'shift; exec "$@"', '_', str(sdk), *command], cwd=source, check=True)

    run(['emconfigure', './configure', '--host=wasm32-unknown-emscripten',
         '--backend=null', '--disable-all-engines', '--enable-engine=scumm',
         '--disable-engine=scumm_7_8,he', '--disable-detection-full',
         '--opengl-mode=none', '--disable-debug', '--disable-mt32emu'])
    # The generic POSIX null backend enables an OSS MIDI device that WASM lacks.
    config = source / 'config.h'
    config.write_text(config.read_text().replace('#define USE_SEQ_MIDI', '#undef USE_SEQ_MIDI'))
    # No SDL, DOM, real clock, OS audio callbacks, or platform-dependent interpreter.
    with (source / 'config.mk').open('a') as config:
        config.write('\nEXEEXT := .js\nLDFLAGS += -s MODULARIZE=1 -s EXPORT_NAME=ScummArcade '
                     '-s ENVIRONMENT=web,worker,node -s EXPORTED_RUNTIME_METHODS=callMain,FS '
                     '-s EXPORTED_FUNCTIONS=_main,_arcade_input -s EXIT_RUNTIME=1 '
                     f'--embed-file "{demo}@/demo" --embed-file "{ini}@/arcade.ini"\n')
    run(['emmake', 'make', f'-j{args.jobs}'])
    dist = HERE / 'dist'
    dist.mkdir(exist_ok=True)
    for name in ('scummvm.js', 'scummvm.wasm'):
        shutil.copyfile(source / name, dist / name)
    shutil.copyfile(source / 'COPYING', HERE / 'COPYING')
    shutil.copyfile(source / 'COPYRIGHT', HERE / 'SCUMMVM-COPYRIGHT')
    build_demos(work / 'demos')
    print('Built', dist)
    print('WASM SHA-256:', hashlib.sha256((dist / 'scummvm.wasm').read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
