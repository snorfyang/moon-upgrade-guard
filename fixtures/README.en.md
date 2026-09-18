**English** | [简体中文](README.md)

# Upgrade fixtures

Each directory holds a pair of compiler artifacts, `old.json` and `new.json`,
that exercises one compatibility rule end to end. They are deliberately small
flat artifacts in the shape Foundry writes: an `abi` array plus a
`storageLayout` object. The CLI end-to-end check in `scripts/e2e.sh` runs every
pair, and the examples in the top-level README use the first two.

Each directory is self-contained: when one side is unchanged, it is a copy
rather than a shared file, so a case can be read and run on its own.

Provenance: every file here was written for this repository. Field shapes follow
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
| `abi-function-removed/` | `transfer(address,uint256)` is gone while storage is unchanged | 1 |
| `abi-event-indexed/` | the `value` parameter of `Transfer` becomes indexed | 1 |
| `invalid-json/` | `old.json` is truncated | 2 |
| `unsupported-artifact/` | `old.json` is a Hardhat per-contract artifact, which carries no storage layout | 2 |
| `contract-selector/` | a build info document holding two contracts: `Alpha` is compatible while `Beta` moves a variable, so `--contract` decides the verdict | 2 without a selector, 0 for `Alpha`, 1 for `Beta` |
| `namespaced-storage/` | `old.json` carries an ERC-7201 `@custom:storage-location` annotation, whose namespace members are not in the compiler layout | 2 |
| `schema-solc-0.5-to-0.8/` | the same contract compiled by solc 0.5.17 and solc 0.8.28, including the legacy ABI fields 0.5 emits | 0 |
| `schema-solc-0.6-to-0.8/` | the same contract compiled by solc 0.6.12 and solc 0.8.28 | 0 |
| `schema-unsupported/` | the type table uses an `encoding` this version does not know | 2 |
| `ambiguous-build-info/` | `old.json` is Hardhat build info with two contracts that both carry a storage layout | 2 |
| `missing-file/` | deliberately has no `new.json`, so the pair exercises an unreadable path | 2 |

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

A storage gap is the `__gap` array convention: the bytes it covers are
unused, so a later version may take them, as long as the gap still ends where it
ended before — that is what keeps the variables declared after it in place. The
two `storage-gap-*` pairs are the safe and the unsafe version of that change.

The subcommands are independent, which two of the pairs show directly:

```bash
moon run cmd/moonupgradeguard -- abi fixtures/storage-removed/old.json fixtures/storage-removed/new.json
moon run cmd/moonupgradeguard -- storage fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json
```

Both of those exit `0`, even though `check` on either pair exits `1`.

## Running a pair by hand

```bash
# compatible: prints nothing and exits 0
moon run cmd/moonupgradeguard -- check fixtures/compatible/old.json fixtures/compatible/new.json

# incompatible: prints the move and exits 1
moon run cmd/moonupgradeguard -- check fixtures/storage-moved/old.json fixtures/storage-moved/new.json

# machine-readable: the diagnostics array on stdout
moon run cmd/moonupgradeguard -- check fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json --format json
```

`scripts/e2e.sh` runs all of the pairs against the built native executable and
checks the exit codes, the expected diagnostic codes, JSON validity, and that
two runs of the same input produce identical bytes.
