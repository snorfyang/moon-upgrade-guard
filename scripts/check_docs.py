#!/usr/bin/env python3
"""Checks that the public documentation is consistent with itself.

Three things are checked, all of them cheap and all of them things that rot
silently in a bilingual repository:

1. every relative link resolves to a file that exists;
2. every `X.md` and `X.en.md` pair has the same shape — the same number of
   headings, bullet points, table rows, and code fences — so a paragraph or a
   bullet that lands in one language only is caught;
3. each mirror links to the other at the top.

Wording is not compared, only shape, because the two languages legitimately read
differently.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROOT_DOCUMENTS = ('README.md', 'README.en.md', 'ROADMAP.md')
LINK = re.compile(r'\[[^\]]*\]\(([^)]+)\)')
SKIP = ('http://', 'https://', 'mailto:', '#')
SHAPE = {
    'headings': r'^#{1,6} ',
    'bullets': r'^- ',
    'table rows': r'^\| ',
    'code fences': r'^```',
}


def documents() -> list[Path]:
    paths = [ROOT / name for name in ROOT_DOCUMENTS]
    for directory in ('docs', 'fixtures'):
        paths.extend(sorted((ROOT / directory).glob('*.md')))
    return paths


def shape(path: Path) -> dict[str, int]:
    text = path.read_text(encoding='utf-8')
    return {
        name: len(re.findall(pattern, text, re.M))
        for name, pattern in SHAPE.items()
    }


def link_targets(path: Path) -> set[Path]:
    """The files this document links to, resolved."""
    return {
        (path.parent / target.split('#', 1)[0]).resolve()
        for target in LINK.findall(path.read_text(encoding='utf-8'))
        if not target.startswith(SKIP) and target.split('#', 1)[0]
    }


def check_links(path: Path) -> list[str]:
    problems = []
    for target in LINK.findall(path.read_text(encoding='utf-8')):
        if target.startswith(SKIP):
            continue
        relative = target.split('#', 1)[0]
        if relative and not (path.parent / relative).resolve().exists():
            problems.append(f'`{target}` does not resolve')
    return problems


def main() -> None:
    paths = documents()
    problems: list[str] = []
    links = 0
    for path in paths:
        name = path.relative_to(ROOT)
        if not path.is_file():
            problems.append(f'{name} does not exist')
            continue
        links += len([
            target
            for target in LINK.findall(path.read_text(encoding='utf-8'))
            if not target.startswith(SKIP)
        ])
        problems.extend(f'{name}: {problem}' for problem in check_links(path))

    pairs = 0
    for path in paths:
        if not path.name.endswith('.en.md'):
            continue
        base = path.with_name(path.name[: -len('.en.md')] + '.md')
        if not base.is_file():
            problems.append(f'{path.relative_to(ROOT)} has no Chinese primary')
            continue
        pairs += 1
        left, right = shape(base), shape(path)
        if left != right:
            problems.append(
                f'{base.relative_to(ROOT)} and {path.relative_to(ROOT)} differ: '
                + ', '.join(
                    f'{key} {left[key]} vs {right[key]}'
                    for key in SHAPE
                    if left[key] != right[key]
                )
            )
        for source, mirror in ((base, path), (path, base)):
            if mirror.resolve() not in link_targets(source):
                problems.append(
                    f'{source.relative_to(ROOT)} does not link to {mirror.name}'
                )

    if problems:
        for problem in problems:
            print(f'FAIL {problem}', file=sys.stderr)
        print(f'{len(problems)} documentation problems', file=sys.stderr)
        raise SystemExit(1)
    print(
        f'{links} relative links resolve across {len(paths)} documents, '
        f'and {pairs} language pairs match in shape'
    )


if __name__ == '__main__':
    main()
