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
| `storage-moved/` | `totalSupply` and `owner` swap slots | 1 |
| `struct-change/` | the `Config` struct gains a member | 1 |
| `storage-gap-shrink/` | a base contract spends one slot of its `__gap` on a new variable, so the gap shrinks but still ends where it ended | 0 |
| `storage-gap-unsafe/` | the same variable is added while the gap keeps its size, so the gap and the variable behind it move | 1 |
| `abi-function-removed/` | `transfer(address,uint256)` is gone while storage is unchanged | 1 |
| `abi-event-indexed/` | the `value` parameter of `Transfer` becomes indexed | 1 |
| `invalid-json/` | `old.json` is truncated | 2 |
| `unsupported-artifact/` | `old.json` is a Hardhat per-contract artifact, which carries no storage layout | 2 |
| `namespaced-storage/` | `old.json` carries an ERC-7201 `@custom:storage-location` annotation, whose namespace members are not in the compiler layout | 2 |
| `ambiguous-build-info/` | `old.json` is Hardhat build info with two contracts that both carry a storage layout | 2 |
| `missing-file/` | deliberately has no `new.json`, so the pair exercises an unreadable path | 2 |

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
