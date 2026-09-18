#!/usr/bin/env python3
"""Runs the `console` blocks of the READMEs against the built CLI.

A `console` block is a transcript: a line starting with `$ ` is a command, the
lines after it are that command's expected output, and `$ echo $?` followed by a
number pins its exit status. Nothing else in the READMEs is executed.

CI runs this, so a documented command, its output, or its exit code cannot drift
away from the binary. Both READMEs must carry the same commands in the same
order; the wording around them is free to differ.
"""

from __future__ import annotations

import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = '_build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe'
READMES = ['README.md', 'README.en.md']
BLOCK = re.compile(r'```console\n(.*?)```', re.S)


def parse(block: str, where: str) -> list[tuple[str, list[str], int | None]]:
    """Turns one block into (command, expected output, expected status)."""
    steps: list[tuple[str, list[str], int | None]] = []
    command: str | None = None
    output: list[str] = []
    status: int | None = None
    pinning = False
    for line in block.strip('\n').split('\n'):
        if line.startswith('$ '):
            if line[2:].strip() == 'echo $?':
                if command is None:
                    raise SystemExit(f'{where}: `echo $?` has no command before it')
                pinning = True
                continue
            if command is not None:
                steps.append((command, output, status))
            command, output, status, pinning = line[2:], [], None, False
        elif pinning:
            try:
                status = int(line.strip())
            except ValueError:
                raise SystemExit(f'{where}: expected an exit code, got {line!r}')
            pinning = False
        elif command is None:
            raise SystemExit(f'{where}: output before any command: {line!r}')
        else:
            output.append(line)
    if pinning:
        raise SystemExit(f'{where}: `echo $?` without a number')
    if command is not None:
        steps.append((command, output, status))
    return steps


def show(expected: list[str], actual: str) -> str:
    return '\n'.join(
        difflib.unified_diff(
            expected,
            actual.split('\n'),
            'documented',
            'actual',
            lineterm='',
        )
    )


def main() -> None:
    transcripts: dict[str, list[tuple[str, list[str], int | None]]] = {}
    for name in READMES:
        text = (ROOT / name).read_text(encoding='utf-8')
        steps = []
        for index, block in enumerate(BLOCK.findall(text)):
            steps.extend(parse(block, f'{name} block {index + 1}'))
        transcripts[name] = steps

    primaries = [step[0] for step in transcripts[READMES[0]]]
    others = [step[0] for step in transcripts[READMES[1]]]
    if primaries != others:
        print('the READMEs document different commands:', file=sys.stderr)
        for left, right in zip(primaries, others):
            if left != right:
                print(f'  {READMES[0]}: {left}\n  {READMES[1]}: {right}', file=sys.stderr)
        raise SystemExit(1)

    failures = 0
    for name, steps in transcripts.items():
        for command, expected, status in steps:
            result = subprocess.run(
                ['/bin/sh', '-c', command],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            if result.stdout.strip('\n') != '\n'.join(expected).strip('\n'):
                failures += 1
                print(f'FAIL {name}: output of `{command}`', file=sys.stderr)
                print(show(expected, result.stdout), file=sys.stderr)
            if status is not None and result.returncode != status:
                failures += 1
                print(
                    f'FAIL {name}: `{command}` exited {result.returncode}, '
                    f'documented {status}',
                    file=sys.stderr,
                )

    checks = sum(len(steps) for steps in transcripts.values())
    if failures:
        print(f'{failures} of {checks} documented commands disagree', file=sys.stderr)
        raise SystemExit(1)
    print(f'{checks} documented commands match the binary')


if __name__ == '__main__':
    main()
