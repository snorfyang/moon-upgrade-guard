#!/usr/bin/env python3
"""Runs the `console` blocks of the READMEs and guides against the built CLI.

A `console` block is a transcript: a line starting with `$ ` is a command, the
lines after it are that command's expected output, and `$ echo $?` followed by a
number pins its exit status. Nothing else in these documents is executed.

CI runs this, so a documented command, its output, or its exit code cannot drift
away from the binary. All four documents must carry the same commands in the same
order; the wording around them is free to differ.
"""

from __future__ import annotations

import difflib
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / '_build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe'
DOCUMENTS = ['README.md', 'README.en.md', 'docs/guide.md', 'docs/guide.en.md']
BLOCK = re.compile(r'```console\n(.*?)```', re.S)

# The walkthrough documents `moon run src/cmd/moonupgradeguard -- ...`, which a reader
# can paste. Executing that would rebuild from source, so it is rewritten to the
# built executable: what is validated is the binary, not a source-level run.
CLI_PREFIX = 'moon run src/cmd/moonupgradeguard -- '


def argv_for(command: str) -> list[str]:
    if not command.startswith(CLI_PREFIX):
        raise SystemExit(
            f'a transcript may only invoke the CLI, found: {command!r}'
        )
    if not BINARY.is_file():
        raise SystemExit(f'{BINARY.relative_to(ROOT)} is missing; build it first')
    return [str(BINARY), *shlex.split(command[len(CLI_PREFIX):])]


def captured_lines(stdout: str) -> list[str]:
    """Splits captured output, dropping the one newline every line ends with.

    Only the captured side is adjusted: the documented lines are compared as
    written, so a blank line that crept into a document is a mismatch rather
    than something both sides shrug off.
    """
    lines = stdout.split('\n')
    if lines and lines[-1] == '':
        return lines[:-1]
    return lines


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
    for name in DOCUMENTS:
        text = (ROOT / name).read_text(encoding='utf-8')
        steps = []
        for index, block in enumerate(BLOCK.findall(text)):
            steps.extend(parse(block, f'{name} block {index + 1}'))
        transcripts[name] = steps

    primary = [step[0] for step in transcripts[DOCUMENTS[0]]]
    for name in DOCUMENTS[1:]:
        commands = [step[0] for step in transcripts[name]]
        if primary != commands:
            print(
                f'{DOCUMENTS[0]} and {name} document different commands',
                file=sys.stderr,
            )
            raise SystemExit(1)

    failures = 0
    checked = 0
    for name, steps in transcripts.items():
        for command, expected, status in steps:
            if status is None:
                failures += 1
                print(
                    f'FAIL {name}: `{command}` has no `$ echo $?` line, so its '
                    f'exit status is undocumented',
                    file=sys.stderr,
                )
                continue
            checked += 1
            result = subprocess.run(
                argv_for(command),
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            actual = captured_lines(result.stdout)
            if actual != expected:
                failures += 1
                print(f'FAIL {name}: output of `{command}`', file=sys.stderr)
                print(show(expected, result.stdout), file=sys.stderr)
            if result.returncode != status:
                failures += 1
                print(
                    f'FAIL {name}: `{command}` exited {result.returncode}, '
                    f'documented {status}',
                    file=sys.stderr,
                )

    if failures:
        print(f'{failures} problems in {checked} documented commands', file=sys.stderr)
        raise SystemExit(1)
    print(
        f'{checked} documented commands ran against '
        f'{BINARY.relative_to(ROOT)} with the documented output and exit status'
    )


if __name__ == '__main__':
    main()
