#!/usr/bin/env python3
"""Generates docs/diagnostics.md from the diagnostic code definitions.

The codes, their severities, and their meanings live in `diagnostic.mbt`. This
script reads them from there, so the reference cannot drift: CI regenerates the
page and fails when the committed copy differs.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'diagnostic.mbt'
TARGET = ROOT / 'docs' / 'diagnostics.md'


def read_source() -> str:
    return SOURCE.read_text(encoding='utf-8')


def parse_enum(source: str) -> list[tuple[str, str]]:
    """Returns the code variants with their doc comment, in source order."""
    block = re.search(
        r'pub\(all\) enum DiagnosticCode \{(.*?)\n\} derive', source, re.S
    )
    if block is None:
        raise SystemExit('could not find the DiagnosticCode enum')
    variants: list[tuple[str, str]] = []
    comment: list[str] = []
    for raw in block.group(1).split('\n'):
        line = raw.strip()
        if line.startswith('///'):
            comment.append(line[3:].strip())
        elif re.fullmatch(r'[A-Z][A-Za-z0-9]*', line):
            variants.append((line, ' '.join(comment)))
            comment = []
        elif line:
            raise SystemExit(f'unexpected line in the enum: {line!r}')
    if not variants:
        raise SystemExit('the enum has no variants')
    return variants


def parse_map(source: str, function: str, values: str) -> dict[str, str]:
    """Returns the arm of one match in `function`, keyed by variant."""
    body = re.search(
        rf'pub fn DiagnosticCode::{function}\(.*?\) -> \w+ \{{(.*?)\n\}}',
        source,
        re.S,
    )
    if body is None:
        raise SystemExit(f'could not find DiagnosticCode::{function}')
    found = re.findall(rf'([A-Z][A-Za-z0-9]*)\s*=>\s*(?:\n\s*)?({values})', body.group(1))
    if not found:
        raise SystemExit(f'{function} has no arms')
    return dict(found)


def main() -> None:
    source = read_source()
    variants = parse_enum(source)
    names = parse_map(source, 'name', r'"[^"]+"')
    severities = parse_map(source, 'severity', r'Info|Warning|Error')

    rows = []
    for variant, comment in variants:
        if variant not in names:
            raise SystemExit(f'{variant} has no entry in DiagnosticCode::name')
        if variant not in severities:
            raise SystemExit(f'{variant} has no entry in DiagnosticCode::severity')
        if not comment.strip():
            raise SystemExit(
                f'{variant} has no doc comment, so its meaning would be empty'
            )
        code = names[variant].strip('"')
        severity = severities[variant]
        rows.append((code, severity, comment))
    rows.sort()

    lines = [
        '# Diagnostics reference',
        '',
        'Every finding carries one of the codes below. A code and its severity are',
        'stable across releases, and the same string appears in the `code` field of',
        'the JSON report, so a pipeline can filter on it.',
        '',
        'Severity decides the verdict of a comparison that ran to the end:',
        '',
        '- `Error` blocks the upgrade: the comparison completed and found an',
        '  incompatibility, and the CLI exits `1` with the report on stdout.',
        '- `Warning` and `Info` are reported without changing the verdict, so an',
        '  upgrade that only produces them still exits `0`.',
        '',
        'Exit code `2` means the analysis could not be completed, and it does not',
        'follow from severity: an `artifact.*` code describes an artifact that could',
        'not be read or that carries no data an operation needs, and a `cli.*` code',
        'describes a command line or a file the CLI could not use. Both families',
        'carry `Error` severity, because a run that could not be completed must not',
        'look compatible. An incomplete report can still contain comparison',
        'findings: when `check` runs and one artifact has no ABI, storage is',
        'compared first and the ABI comparison then reports that it could not run.',
        'Normalization failures work the other way round: a variable whose slot is',
        'not a decimal integer is reported with `storage.entry.slot.invalid`, and',
        'the run exits `2` before any comparison happens.',
        '',
        'Locations are relative to the value the reporting layer analysed:',
        'extraction reports paths inside the artifact, the storage engine reports',
        'paths inside the layout it compared — including `transientStorage[...]` for',
        'the transient namespace — and the CLI reports the file path when it cannot',
        'read one.',
        '',
        f'This page lists {len(rows)} codes and is generated from `diagnostic.mbt` by',
        '`scripts/gen_diagnostics_doc.py`. CI regenerates it and fails when the',
        'committed copy differs, so a new code cannot ship undocumented.',
        '',
        '| code | severity | blocks | meaning |',
        '| --- | --- | --- | --- |',
    ]
    for code, severity, comment in rows:
        blocks = 'yes' if severity == 'Error' else 'no'
        lines.append(f'| `{code}` | {severity} | {blocks} | {comment} |')
    lines.append('')

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text('\n'.join(lines), encoding='utf-8')
    print(f'wrote {TARGET.relative_to(ROOT)} with {len(rows)} codes')


if __name__ == '__main__':
    sys.exit(main())
