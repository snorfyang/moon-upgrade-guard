**English** | [简体中文](README.md)

# Upgrade fixtures

Each directory holds a pair of compiler artifacts, `old.json` and `new.json`,
that exercises one compatibility rule end to end. Most hand-written cases are deliberately small
flat artifacts in the shape Foundry writes: an `abi` array plus a
`storageLayout` object. The CLI end-to-end check in `scripts/e2e.sh` runs every
pair, and the [hands-on tutorial](../docs/guide.en.md) uses several for a full walkthrough.

Each directory is self-contained: when one side is unchanged, it is a copy
rather than a shared file, so a case can be read and run on its own.

Provenance: the source code and hand-written cases belong to this repository;
`real-*` contains actual tool output generated from that source. Hand-written field shapes follow
the Solidity compiler's `storageLayout` documentation and the ABI
specification; no third-party artifact or fixture was copied.

| directory | change | `check` exit |
| --- | --- | --- |
| `compatible/` | the same contract recompiled: only compiler-generated `astId` values and the order of the type table differ | 0 |
| `append/` | a storage variable, a function, and an event are added | 0 |
| `storage-removed/` | the `owner` variable is gone | 1 |
| `storage-renamed/` | `owner` is renamed to `admin` at the same position with the same type | 0 |
| `storage-moved/` | `totalSupply` and `owner` swap slots | 1 |
| `struct-change/` | the `Config` struct gains a member | 1 |
| `storage-gap-shrink/` | a base contract spends one slot of its `__gap` on a new variable, so the gap shrinks but still ends where it ended | 0 |
| `transient-moved/` | a transient variable moves between slots | 1 |
| `transient-append/` | the new version adds a transient variable | 0 |
| `transient-removed/` | the new artifact reports no transient layout, so the old transient variable disappears | 1 |
| `storage-gap-finished/` | the `__gap` is replaced wholesale by a struct that ends where the gap ended | 0 |
| `storage-gap-unsafe/` | the same variable is added while the gap keeps its size, so the gap and the variable behind it move | 1 |
| `storage-gap-dynamic/` | the `__gap` is a dynamic array, whose slot holds a length rather than reserved bytes, so replacing it is not treated as a gap | 1 |
| `abi-function-removed/` | `transfer(address,uint256)` is gone while storage is unchanged | 1 |
| `abi-fallback-kind/` | the `fallback` handler is replaced by a named `function fallback()` with the same signature | 1 |
| `abi-event-indexed/` | the `value` parameter of `Transfer` becomes indexed | 1 |
| `invalid-json/` | `old.json` is truncated | 2 |
| `unsupported-artifact/` | `old.json` is a Hardhat per-contract artifact, which carries no storage layout | 2 |
| `contract-selector/` | a build info document holding two contracts: `Alpha` is compatible while `Beta` moves a variable, so `--contract` decides the verdict | 2 without a selector, 0 for `Alpha`, 1 for `Beta` |
| `namespaced-storage/` | `old.json` carries an ERC-7201 `@custom:storage-location` annotation, whose namespace members are not in the compiler layout | 2 |
| `schema-solc-0.5-to-0.8/` | the same contract compiled by solc 0.5.17 and solc 0.8.28, including the legacy ABI fields 0.5 emits | 0 |
| `schema-solc-0.6-to-0.8/` | the same contract compiled by solc 0.6.12 and solc 0.8.28 | 0 |
| `real-solc-compatible/` | solc Standard JSON: append a variable | 0 |
| `real-solc-incompatible/` | solc Standard JSON: narrow a variable from 256 to 128 bits | 1 |
| `real-solc-no-layout/` | solc Standard JSON: storage layout was not requested | 2 |
| `real-foundry-compatible/` | Foundry flat artifact: append a variable | 0 |
| `real-foundry-incompatible/` | Foundry flat artifact: narrow a variable | 1 |
| `real-foundry-no-layout/` | Foundry flat artifact: storage layout was not requested | 2 |
| `real-hardhat-compatible/` | Hardhat build info: append a variable | 0 |
| `real-hardhat-incompatible/` | Hardhat build info: narrow a variable | 1 |
| `real-hardhat-per-contract/` | Hardhat per-contract artifact: no storage layout | 2 |
| `real-complex-compatible/` | solc Standard JSON: packed fields, a mapping, a struct, and transient variables stay in place while `__gap` shrinks and a variable is added | 0 |
| `real-complex-incompatible/` | solc Standard JSON: packed offset, mapping value type, struct member type, and transient slots change | 1 |
| `real-custom-layout-compatible/` | solc 0.8.29 `layout at 42`: inherited and derived variables share a slot; an appended variable preserves the old layout | 0 |
| `real-custom-layout-moved/` | solc 0.8.29 moves the base from 42 to 43, shifting inherited, packed, and mapping slots | 1 |
| `schema-unsupported/` | the type table uses an `encoding` this version does not know | 2 |
| `fractional-offset/` | both sides carry an `offset` written as a fraction that rounds to an integer, refused as unusable schema data | 2 |
| `ambiguous-build-info/` | `old.json` is Hardhat build info with two contracts that both carry a storage layout | 2 |
| `missing-file/` | deliberately has no `new.json`, so the pair exercises an unreadable path | 2 |

## Real artifact matrix

The `real-*` cases use this repository's own [`Counter` source](real-artifacts/sources/old.sol)
and its [compatible](real-artifacts/sources/compatible.sol) and
[incompatible](real-artifacts/sources/incompatible.sol) versions (Apache-2.0).
Each source was copied to the same source filename in the tool project, then compiled into
`old.json` or `new.json`. Compiler output fields were not rewritten; the non-JSON notice line
printed by `solcjs` before its output was removed before saving.

| tool | pinned version | generation command and saved output |
| --- | --- | --- |
| solcjs | 0.8.28 | `solcjs --standard-json < fixtures/real-artifacts/inputs/old.json > output.txt`; compile the other three [input files](real-artifacts/inputs/compatible.json) the same way. The input source key was `src/Counter.sol`, and `outputSelection` requested `abi` and `storageLayout` (`without-layout.json` requested only `abi`). Check that `errors` contains no `severity: "error"`, remove the stdout notice line, and save the full JSON. |
| Forge | 1.7.1, solc 0.8.28 | Copy the source to `src/Counter.sol` in a temporary project, run `forge build --force --use /path/to/solc --extra-output storageLayout`, and copy `out/Counter.sol/Counter.json`; omit `--extra-output storageLayout` for the missing-layout case. |
| Hardhat | 2.27.2, solc 0.8.28 | Copy the source to `contracts/Counter.sol` in a temporary project and run `hardhat compile --force --config hardhat.config.cjs` with this [config](real-artifacts/hardhat.config.cjs); copy `artifacts/build-info/*.json`, or `artifacts/contracts/Counter.sol/Counter.json` for the missing-layout case. |

The old side of every `real-solc-*`, `real-foundry-*`, and `real-hardhat-*` pair was compiled from `old.sol`.
The compatible and incompatible new sides came from their matching sources; the missing-layout
new side uses the normal old-version compiler output. These commands only generate the committed
fixtures; running the checker and tests does not require the tools or network access.

The `real-complex-*` pairs use this repository's own [`ComplexLayout` source](real-artifacts/sources/complex-old.sol) and its [compatible](real-artifacts/sources/complex-compatible.sol) and [incompatible](real-artifacts/sources/complex-incompatible.sol) versions (Apache-2.0). The three [Standard JSON inputs](real-artifacts/inputs/complex-old.json) use the same `src/ComplexLayout.sol` source key and request `abi`, `storageLayout`, and `transientStorageLayout`. Run `npx --yes solc@0.8.28 --standard-json < fixtures/real-artifacts/inputs/complex-old.json` (likewise for the other two inputs), check for compiler errors, and remove solcjs's non-JSON notice line to obtain the complete compiler outputs in these pairs. Both `old.json` files are identical. The end-to-end checks verify their specific findings and exit codes. Fixture generation used solcjs 0.8.28; running the checks requires neither solcjs nor network access.

The three [Standard JSON inputs](real-artifacts/inputs/custom-layout-old.json) for `real-custom-layout-*` contain this repository's own `Base` and `Shifted` source (Apache-2.0): `layout at 42`, an append at the same base, and a move to `layout at 43`. Run `npx --yes solc@0.8.29 --standard-json < fixtures/real-artifacts/inputs/custom-layout-old.json` (substituting each input filename), check for compiler errors, remove solcjs's non-JSON notice line, and save the complete output. Both `old.json` files are identical; the tests need neither solc nor network access. The expected slots follow the [Solidity 0.8.29 storage layout specification](https://docs.soliditylang.org/en/v0.8.29/internals/layout_in_storage.html).

## Compiler schema matrix

The `schema-*` pairs check the field shapes that different compilers emit:

- solc 0.5.17 writes `constant` and `payable` beside `stateMutability` in ABI
  entries. Those extra fields are ignored, so a 0.5 artifact decodes like any
  other.
- solc 0.6.12 and 0.8.28 write `stateMutability` only.
- An ABI from before `stateMutability` existed (0.4 era) cannot be decoded
  exactly, because `constant` does not distinguish `pure` from `view`. Such an
  entry is refused with an error instead of being guessed at.
- An unknown `encoding` in the type table is refused, because it could change
  how the bytes are read.

The generated fixtures come from this contract, compiled by the three releases
named above with `outputSelection` set to `abi` and `storageLayout`:

```solidity
pragma solidity ^VERSION;

contract Token {
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    uint8 private flags;
    uint8 private nextFlags;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function transfer(address to, uint256 value) public returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
}
```

All three releases emit the same layout for it, which is why the two
cross-version pairs are expected to be compatible. The source is part of this
repository; the fixtures are its compiler output.

Transient storage follows the same rules as regular storage, in its own
namespace: a finding names `transientStorage[...]` so a report tells the two
address spaces apart. An artifact that reports no transient layout is read as
one with no transient variables, which is how Foundry writes an empty one; set
against an artifact that does carry them, that reads as a removal, so a version
compiled without the `transientStorageLayout` output selection blocks rather
than passing quietly.

A renamed variable is the one place where this tool is deliberately more
permissive than OpenZeppelin Upgrades Core, which treats a rename as unsafe
unless `unsafeAllowRenames` is set: the bytes stay in place, so
`storage-renamed/` reports a warning and exits `0`. See
[differential record](../docs/oz-differential.en.md).

A wrapper that holds several contracts needs `--contract NAME` or
`--contract SOURCE:NAME`; without one it is reported as ambiguous rather than
guessed at.

ERC-7201 namespaced storage is refused rather than assumed compatible. A
namespace is reached through a slot its annotation derives, and the compiler
lists only state variables in `storageLayout`, so a namespace's members are not
in the input and their compatibility is unknown.

A storage gap is the `__gap` fixed-size array convention: the bytes it covers
are unused, so a later version may take them, as long as the gap still ends
where it ended before — that is what keeps the variables declared after it in
place. The three `storage-gap-*` pairs are the safe version of that change, the
unsafe one, and the case where the convention does not apply: a dynamic array
named `__gap` holds a length in its slot, not reserved bytes.

The subcommands are independent, which two of the pairs show directly:

```bash
moon run src/cmd/moonupgradeguard -- abi fixtures/storage-removed/old.json fixtures/storage-removed/new.json
moon run src/cmd/moonupgradeguard -- storage fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json
```

Both of those exit `0`, even though `check` on either pair exits `1`.

## Running a pair by hand

```bash
# compatible: prints nothing and exits 0
moon run src/cmd/moonupgradeguard -- check fixtures/compatible/old.json fixtures/compatible/new.json

# incompatible: prints the move and exits 1
moon run src/cmd/moonupgradeguard -- check fixtures/storage-moved/old.json fixtures/storage-moved/new.json

# machine-readable: the diagnostics array on stdout
moon run src/cmd/moonupgradeguard -- check fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json --format json
```

`scripts/e2e.sh` runs all of the pairs against the built native executable and
checks the exit codes, the expected diagnostic codes, JSON validity, and that
two runs of the same input produce identical bytes.
