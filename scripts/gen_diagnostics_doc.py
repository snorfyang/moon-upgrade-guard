#!/usr/bin/env python3
"""Generates the diagnostics reference in every documented language.

The codes, their severities, and their English meanings live in `diagnostic.mbt`.
The Chinese meanings live in the table below, and the script refuses to run when
a code has no meaning in some language, or when a translation refers to a code
that no longer exists. CI regenerates both pages and fails when a committed copy
differs, so neither language can drift from the source or from the other.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'diagnostic.mbt'

LANGUAGES = {
    'zh': {
        'target': ROOT / 'docs' / 'diagnostics.md',
        'mirror': 'diagnostics.en.md',
        'label': '**简体中文** | [English](diagnostics.en.md)',
        'title': '# 诊断码手册',
        'columns': ('诊断码', '严重度', '是否阻断', '含义'),
        'blocks': ('是', '否'),
        'prose': [
            '每个诊断项都带有下面某个诊断码。诊断码及其严重度在版本之间保持稳定，同一个字符串',
            '会出现在 JSON 报告的 `code` 字段里，因此流水线可以直接用它做过滤。',
            '',
            '严重度决定**一次跑到底的比较**的结论：',
            '',
            '- `Error` 阻断升级：比较完整执行并发现不兼容，CLI 以 `1` 退出，报告写在 stdout 上。',
            '- `Warning` 与 `Info` 会被报告但不改变结论，因此只产生它们的升级仍然以 `0` 退出。',
            '',
            '退出码 `2` 表示**分析未能完成**，它与严重度无关：`artifact.*` 诊断码描述无法读取、',
            '或缺少某项操作所需数据的产物；`cli.*` 诊断码描述 CLI 无法使用的命令行或文件。这两类都',
            '是 `Error` 级，因为未完成的分析绝不能看起来兼容。未完成的报告里仍可能包含比较结论：',
            '`check` 运行时若一边没有 ABI，存储会先被比较，随后 ABI 比较报告自己无法运行；反方向的',
            '情形是规范化失败——例如某个变量的 slot 不是十进制整数，会报告',
            '`storage.entry.slot.invalid`，并在任何比较发生之前就以 `2` 退出。',
            '',
            '位置相对于产生它的那一层所分析的值：提取层报告产物内部的路径，存储引擎报告它所比较的',
            '布局内部的路径（transient 命名空间为 `transientStorage[...]`），CLI 在无法读取文件时',
            '报告该文件路径。',
        ],
        'generated': (
            '本页共 {count} 个诊断码，由 `scripts/gen_diagnostics_doc.py` 从 `diagnostic.mbt` '
            '生成。CI 会重新生成，并在提交内容与源码不一致时失败，因此新诊断码不可能没有文档。'
        ),
        'codes': {
            'abi.error.added': '自定义错误签名只出现在新 ABI 中。',
            'abi.error.removed': '旧 ABI 中的自定义错误签名在新 ABI 中缺失。',
            'abi.event.added': '事件签名只出现在新 ABI 中。',
            'abi.event.anonymous.changed': '事件签名不变，但匿名性发生变化。',
            'abi.event.indexed.changed': '事件签名不变，但 indexed 参数发生变化。',
            'abi.event.removed': '旧 ABI 中的事件签名在新 ABI 中缺失。',
            'abi.function.added': '函数签名只出现在新 ABI 中。',
            'abi.function.mutability.changed': '函数签名不变，但状态可变性发生变化。',
            'abi.function.mutability.incompatible': '函数失去了现有调用方所依赖的状态可变性行为。',
            'abi.function.outputs.changed': '函数签名不变，但返回类型列表发生变化。',
            'abi.function.removed': '旧 ABI 中的函数签名在新 ABI 中缺失。',
            'abi.signature.collision': '同一个 selector 或 event topic 在两个版本中属于不同的签名。',
            'artifact.abi.missing': '需要比较 ABI 的操作拿到了一个不含 ABI 的产物。',
            'artifact.contract.ambiguous': '产物中有多个合约带有存储布局。',
            'artifact.contract.missing': '产物中没有合约匹配所请求的选择器。',
            'artifact.field.invalid': '已识别的产物字段类型或取值不正确。',
            'artifact.json.invalid': '产物文本不是合法 JSON。',
            'artifact.layout.missing': '产物中没有存储布局。',
            'artifact.namespaced-storage.unsupported': '产物提到 ERC-7201 命名空间存储，而该内容无法从编译产物中定位。',
            'artifact.shape.ambiguous': '产物同时匹配多种已识别的外层形态。',
            'artifact.shape.unsupported': '产物根节点不属于任何已识别的外层形态。',
            'cli.argument.invalid': '命令行包含 CLI 不支持的内容。',
            'cli.input.unreadable': 'CLI 无法读取输入文件。',
            'storage.entry.added': '存储变量只出现在新布局中。',
            'storage.entry.field.missing': '存储变量缺少必需字段。',
            'storage.entry.label.changed': '存储变量在同一位置、类型不变的情况下被重命名。',
            'storage.entry.offset.changed': '存储变量在同一个 slot 内移动。',
            'storage.entry.offset.invalid': '字节 offset 超出 slot 范围 `0..=31`。',
            'storage.entry.removed': '旧布局中的存储变量在新布局中缺失。',
            'storage.entry.slot.changed': '存储变量移动到了另一个 slot。',
            'storage.entry.slot.invalid': 'slot 不是非负十进制整数。',
            'storage.entry.type.changed': '存储变量位置不变，但语义类型发生变化。',
            'storage.entry.type.missing': '存储变量引用的类型 id 在布局中不存在。',
            'storage.gap.changed': '存储 gap 在结束位置不变的前提下被缩减、移动或占用。',
            'storage.type.array-length.invalid': '定长数组的 label 未给出可用的十进制元素个数。',
            'storage.type.encoding.unsupported': '存储类型使用了本版本不支持的编码。',
            'storage.type.field.missing': '存储类型缺少必需字段。',
            'storage.type.id.duplicate': '同一个存储类型 id 被定义多次。',
            'storage.type.id.missing': '存储类型缺少编译器 id。',
            'storage.type.reference.missing': '存储类型引用的另一个类型 id 在布局中不存在。',
            'storage.type.size.invalid': '`numberOfBytes` 不是十进制整数。',
        },
    },
    'en': {
        'target': ROOT / 'docs' / 'diagnostics.en.md',
        'mirror': 'diagnostics.md',
        'label': '[简体中文](diagnostics.md) | **English**',
        'title': '# Diagnostics reference',
        'columns': ('code', 'severity', 'blocks', 'meaning'),
        'blocks': ('yes', 'no'),
        'prose': [
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
        ],
        'generated': (
            'This page lists {count} codes and is generated from `diagnostic.mbt` by '
            '`scripts/gen_diagnostics_doc.py`. CI regenerates it and fails when the '
            'committed copy differs, so a new code cannot ship undocumented.'
        ),
        'codes': None,  # filled from the doc comments in diagnostic.mbt
    },
}


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
    """Returns the arms of one match in `function`, keyed by variant."""
    body = re.search(
        rf'pub fn DiagnosticCode::{function}\(.*?\) -> \w+ \{{(.*?)\n\}}',
        source,
        re.S,
    )
    if body is None:
        raise SystemExit(f'could not find DiagnosticCode::{function}')
    found = re.findall(
        rf'([A-Z][A-Za-z0-9]*)\s*=>\s*(?:\n\s*)?({values})', body.group(1)
    )
    if not found:
        raise SystemExit(f'{function} has no arms')
    return dict(found)


def codes() -> list[tuple[str, str, str]]:
    """Returns (code, severity, English meaning) for every code."""
    source = SOURCE.read_text(encoding='utf-8')
    names = parse_map(source, 'name', r'"[^"]+"')
    severities = parse_map(source, 'severity', r'Info|Warning|Error')
    rows = []
    for variant, comment in parse_enum(source):
        if variant not in names:
            raise SystemExit(f'{variant} has no entry in DiagnosticCode::name')
        if variant not in severities:
            raise SystemExit(f'{variant} has no entry in DiagnosticCode::severity')
        if not comment.strip():
            raise SystemExit(
                f'{variant} has no doc comment, so its English meaning would be empty'
            )
        rows.append((names[variant].strip('"'), severities[variant], comment))
    return sorted(rows)


def render(language: str, rows: list[tuple[str, str, str]]) -> str:
    config = LANGUAGES[language]
    meanings = config['codes']
    if meanings is None:
        meanings = {code: meaning for code, _, meaning in rows}
    missing = [code for code, _, _ in rows if not meanings.get(code, '').strip()]
    if missing:
        raise SystemExit(f'{language}: no meaning for {", ".join(missing)}')
    stale = sorted(set(meanings) - {code for code, _, _ in rows})
    if stale:
        raise SystemExit(f'{language}: meanings for unknown codes {", ".join(stale)}')

    blocked, allowed = config['blocks']
    lines = [config['label'], '', config['title'], '', *config['prose'], '']
    lines.append(config['generated'].format(count=len(rows)))
    lines.append('')
    lines.append('| ' + ' | '.join(config['columns']) + ' |')
    lines.append('| --- | --- | --- | --- |')
    for code, severity, _ in rows:
        block = blocked if severity == 'Error' else allowed
        lines.append(f'| `{code}` | {severity} | {block} | {meanings[code]} |')
    lines.append('')
    document = '\n'.join(lines)
    if language == 'zh':
        return re.sub(r'(?<=[\u4e00-\u9fff])\n[ \t]*(?=[\u4e00-\u9fff])', '', document)
    return document


def main() -> None:
    rows = codes()
    for language in LANGUAGES:
        target = LANGUAGES[language]['target']
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(language, rows), encoding='utf-8')
        print(f'wrote {target.relative_to(ROOT)} with {len(rows)} codes')


if __name__ == '__main__':
    sys.exit(main())
