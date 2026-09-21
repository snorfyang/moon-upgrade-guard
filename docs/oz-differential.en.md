**English** | [简体中文](oz-differential.md)

# Differential check against OpenZeppelin Upgrades Core

The storage engine is compared with the mature reference implementation,
[`@openzeppelin/upgrades-core`](https://github.com/OpenZeppelin/openzeppelin-upgrades),
on every fixture pair. Both tools are given the same artifacts and asked for a
verdict; the question is not whether they word things the same way, but whether
they agree on whether a change blocks an upgrade, and whether each disagreement
is understood.

The comparison runs the reference against the compiler's own `storageLayout`
object, which is the shape its comparator consumes, and runs the CLI's `storage`
subcommand. A pair counts as compared when the engine reached a verdict (exit
`0` or `1`); an engine exit of `2` means the artifact was refused, which is not
a verdict to compare.

This is a development tool, not part of CI: it needs Node and an installed copy
of the reference package, while the test suite stays offline.

## Reproducing

```bash
npm install --prefix /tmp/ozdiff @openzeppelin/upgrades-core
moon build --target native
OZ_UPGRADES_CORE=/tmp/ozdiff/node_modules/@openzeppelin/upgrades-core \
  node scripts/oz-differential.mjs
```

Run against `@openzeppelin/upgrades-core` 1.46.0, the output is:

```console
reference: @openzeppelin/upgrades-core 1.46.0
engine:    _build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe

- abi-event-indexed: engine exit 0 | reference pass | agree
- abi-fallback-kind: engine exit 0 | reference pass | agree
- abi-function-removed: engine exit 0 | reference pass | agree
- ambiguous-build-info: engine exit 2 | reference skip (no storageLayout) | n/a
- append: engine exit 0 | reference pass | agree
- compatible: engine exit 0 | reference pass | agree
- contract-selector: engine exit 2 | reference skip (no storageLayout) | n/a
- fractional-offset: engine exit 2 | reference pass | n/a
- invalid-json: engine exit 2 | reference skip (error: Expected ',' or '}' after property value in JSON at position 50 (line 4 column 1)) | n/a
- missing-file: no pair
- namespaced-storage: engine exit 2 | reference pass | n/a
- real-foundry-compatible: engine exit 0 | reference pass | agree
- real-foundry-incompatible: engine exit 1 | reference typechange | agree
- real-foundry-no-layout: engine exit 2 | reference skip (no storageLayout) | n/a
- real-hardhat-compatible: engine exit 0 | reference skip (no storageLayout) | n/a
- real-hardhat-incompatible: engine exit 1 | reference skip (no storageLayout) | n/a
- real-hardhat-per-contract: engine exit 2 | reference skip (no storageLayout) | n/a
- real-solc-compatible: engine exit 0 | reference skip (no storageLayout) | n/a
- real-solc-incompatible: engine exit 1 | reference skip (no storageLayout) | n/a
- real-solc-no-layout: engine exit 2 | reference skip (no storageLayout) | n/a
- schema-solc-0.5-to-0.8: engine exit 0 | reference pass | agree
- schema-solc-0.6-to-0.8: engine exit 0 | reference pass | agree
- schema-unsupported: engine exit 2 | reference rename | n/a
- storage-gap-dynamic: engine exit 1 | reference replace | agree
- storage-gap-finished: engine exit 0 | reference pass | agree
- storage-gap-shrink: engine exit 0 | reference pass | agree
- storage-gap-unsafe: engine exit 1 | reference layoutchange | agree
- storage-moved: engine exit 1 | reference delete, insert, layoutchange | agree
- storage-removed: engine exit 1 | reference delete | agree
- storage-renamed: engine exit 0 | reference rename | DIFFER
- struct-change: engine exit 1 | reference typechange | agree
- transient-append: engine exit 0 | reference skip (transient layout) | n/a
- transient-moved: engine exit 1 | reference skip (transient layout) | n/a
- transient-removed: engine exit 1 | reference skip (transient layout) | n/a
- unsupported-artifact: engine exit 2 | reference skip (no storageLayout) | n/a

compared 17 pairs, 1 divergences
  storage-renamed: engine exit 0 vs reference rename
```

## What the agreement covers

- **Storage gaps.** `storage-gap-shrink` is the case that motivated the rule:
  a base contract spends one slot of its `__gap` on a new variable, so the gap
  shrinks while still ending where it ended. Both tools pass it. The reference
  decides this with `endMatchesGap`, and the engine uses the same test, which is
  why the two agree here rather than by accident.
- **A dynamic array is not a gap.** `storage-gap-dynamic` replaces a dynamic
  array named `__gap` with a new variable: the reference reports `replace`
  (the name and the type both change in one position, and a dynamic array's
  slot is not a gap it recognizes), and both block. The engine compares the
  dynamic array as an ordinary variable and reaches the same verdict more
  directly: that slot holds an array length, not reserved bytes.
- **Finishing a gap.** `storage-gap-finished` replaces a `__gap` wholesale with a
  struct that ends where the gap ended. Both tools accept it, again because the
  rule is the same one: a gap covers unused bytes, so only its end has to be
  preserved.
- **Appends.** `append` adds a variable, a function, and an event: both tools
  pass, because an addition that moves nothing is safe.
- **Moves, removals, and type changes.** `storage-moved`, `storage-removed`, and
  `struct-change` are blocking in both. In particular a struct that gains a
  member is a type change for both tools, so the engine's conservative reading
  of recursive type changes matches the reference rather than exceeding it.
- **Compiler versions.** The `schema-solc-*` pairs, produced by real solc 0.5.17,
  0.6.12, and 0.8.28, pass in both.
- **Real Foundry artifacts.** The two flat artifacts that append a variable or
  narrow its width respectively pass and block in both tools.

## The one deliberate difference

| pair | engine | reference |
| --- | --- | --- |
| `storage-renamed` | warning, exit `0` | `rename`, blocking |

Renaming a variable without moving it leaves every byte where it was, so the
storage layout is still compatible. The reference treats a rename as unsafe
unless `unsafeAllowRenames` is passed, because the new name may carry a new
meaning. The engine reports a warning instead, and says so in the public
documentation: the layout is compatible, the meaning needs review.

Switching to the stricter policy is a severity change plus snapshot updates, not
a reimplementation, but it would change the compatibility contract for existing
users, so it is left as an explicit decision rather than a silent one.

## Pairs the comparison cannot cover

- `ambiguous-build-info` and `contract-selector` hold several contracts, so they
  need `--contract`; the harness passes no selector and the engine reports the
  ambiguity.
- `real-solc-*` and `real-hardhat-*` are complete compiler wrappers. This harness
  passes only top-level `storageLayout` objects to the reference, so it skips them.
- `invalid-json` and `missing-file` are rejected before any layout exists.
- `unsupported-artifact` is a Hardhat per-contract artifact, which carries no
  storage layout at all.
- `schema-unsupported` uses an `encoding` the engine does not know. The engine
  refuses the artifact (exit `2`) because the encoding decides how bytes are
  read; the reference does not validate the field and reports an unrelated
  rename. Refusing is the deliberate choice: an unknown shape that can affect
  compatibility must not be reported as compatible.
- Pairs that carry a transient storage layout are skipped: this harness gives
  the reference the regular layout, so its verdict says nothing about the
  transient namespace, which this engine compares separately.
- `namespaced-storage` is refused by the engine (exit `2`). The reference passes
  it here only because the fixture carries a single documentation string rather
  than a real compilation AST; its namespace support reads the AST, which this
  tool does not analyse. Both facts are recorded as limitations.

## Provenance

The reference was used to understand public behaviour and its published source
(`storage/gap.ts`, `storage/compare.ts`) was read to align the gap rule. No
source code, test, or fixture was copied: every fixture in this repository was
written or generated here, and the harness compares behaviour only.
