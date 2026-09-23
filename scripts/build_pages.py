#!/usr/bin/env python3
"""Build the public documentation site from an explicit source allowlist."""

import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / '_build/pages-src'
PAGES = {
    'docs/index.md': 'index.md',
    'docs/index.en.md': 'en/index.md',
    'docs/getting-started.md': 'getting-started.md',
    'docs/getting-started.en.md': 'en/getting-started.md',
    'ROADMAP.md': 'roadmap.md',
    'docs/diagnostics.md': 'diagnostics.md',
    'docs/diagnostics.en.md': 'en/diagnostics.md',
    'docs/oz-differential.md': 'oz-differential.md',
    'docs/oz-differential.en.md': 'en/oz-differential.md',
    'docs/references.md': 'references.md',
    'docs/references.en.md': 'en/references.md',
    'fixtures/README.md': 'fixtures.md',
    'fixtures/README.en.md': 'en/fixtures.md',
}
LINK = re.compile(r'\]\(([^)]+)\)')
REPOSITORY = 'https://github.com/snorfyang/moon-upgrade-guard/blob/main/'


def rewrite_links(text: str, source: Path, destination: Path) -> str:
    def replace(match: re.Match) -> str:
        target = match.group(1)
        if target.startswith(('http://', 'https://', 'mailto:', '#')):
            return match.group(0)
        path, separator, fragment = target.partition('#')
        resolved = (source.parent / path).resolve()
        if not resolved.is_file() or not resolved.is_relative_to(ROOT):
            raise ValueError(f'{source.relative_to(ROOT)}: invalid link {target}')
        relative = resolved.relative_to(ROOT).as_posix()
        if relative in PAGES:
            mapped = Path(PAGES[relative])
            link = os.path.relpath(mapped, destination.parent)
        else:
            link = REPOSITORY + relative
        return '](' + link + (separator + fragment if separator else '') + ')'

    return LINK.sub(replace, text)


def main() -> None:
    if STAGING.exists():
        shutil.rmtree(STAGING)
    for source_name, destination_name in PAGES.items():
        source = ROOT / source_name
        destination = Path(destination_name)
        output = STAGING / destination
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            rewrite_links(source.read_text(encoding='utf-8'), source, destination),
            encoding='utf-8',
        )
    subprocess.run(['mkdocs', 'build', '--strict'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
