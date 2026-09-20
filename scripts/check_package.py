#!/usr/bin/env python3
"""Build the MoonBit package and compare its contents with the public file list."""

import difflib
from pathlib import Path
import subprocess
import tempfile
import zipfile


root = Path(__file__).resolve().parent.parent
expected = (root / 'scripts/package-files.txt').read_text().splitlines()

with tempfile.TemporaryDirectory() as target_dir:
    subprocess.run(
        ['moon', 'package', '--target-dir', target_dir], cwd=root, check=True
    )
    packages = list((Path(target_dir) / 'publish').glob('*.zip'))
    if len(packages) != 1:
        raise SystemExit(f'expected one package, found {len(packages)}')
    with zipfile.ZipFile(packages[0]) as package:
        actual = sorted(package.namelist())

if actual != expected:
    print(''.join(difflib.unified_diff(
        [name + '\n' for name in expected],
        [name + '\n' for name in actual],
        fromfile='expected package files',
        tofile='actual package files',
    )), end='')
    raise SystemExit(1)

print(f'package: {len(actual)} files match scripts/package-files.txt')
