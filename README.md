# MoonUpgradeGuard

MoonUpgradeGuard is a MoonBit-native compatibility checker for upgrades of
EVM smart contracts. It compares Solidity compiler artifacts from two contract
versions and reports storage-layout and ABI changes that may make a proxy
upgrade unsafe.

The project is at an early stage. Its intended inputs are Solidity Standard
JSON output and common Foundry or Hardhat artifacts. The first release will
focus on deterministic, offline analysis with stable text and JSON diagnostics.

## Planned scope

- Parse and normalize Solidity `storageLayout` data.
- Compare storage slots, byte offsets, encodings, and recursive types.
- Identify removed, reordered, inserted, or type-changed state variables.
- Compare public ABI functions, events, and custom errors.
- Provide library APIs and a native CLI suitable for CI.
- Include reproducible safe and unsafe upgrade fixtures.

## Non-goals

- Compiling Solidity source code.
- Deploying or upgrading contracts.
- Managing wallets, private keys, or RPC endpoints.
- Replacing professional smart-contract audits.
- Proving business-logic equivalence between contract versions.

## Status

The package currently provides:

- a stable diagnostic model with deterministic text and JSON rendering;
- normalization of Solidity `storageLayout` data into a backend-independent
  storage model with lossless slot numbers;
- artifact extraction from a raw `storageLayout` object, a flat artifact such
  as Foundry writes, solc Standard JSON output, and Hardhat build info;
- storage-layout comparison across slots, offsets, fixed and dynamic arrays,
  mappings, structs, and recursive type graphs;
- ABI comparison for functions, events, custom errors, selectors, and topics.
- a native CLI with deterministic text or JSON output and CI-friendly exit
  codes.

## CLI

Run the CLI from the repository:

```bash
moon run cmd/moonupgradeguard -- check old.json new.json
moon run cmd/moonupgradeguard -- storage old.json new.json
moon run cmd/moonupgradeguard -- abi old.json new.json --format json
```

`check` always compares storage and also compares ABI when both artifacts carry
one. If exactly one artifact has an ABI, it reports invalid input instead of
silently skipping that comparison. `storage` accepts standalone layouts, while
`abi` requires an ABI on both sides.

Exit code `0` means no blocking incompatibility was found, `1` means the
comparison found an incompatible change, and `2` means the command or input was
invalid. A successful report is a preflight result, not proof that an upgrade
is safe in every respect.

Two facts are worth knowing when choosing an input:

- A Hardhat per-contract artifact does not embed a storage layout, and
  Hardhat's default compiler settings do not request one. Extract from a build
  info file compiled with `storageLayout` in `outputSelection`, or from a
  standalone layout file.
- Transient storage layouts are detected but not compared. The presence of
  transient storage variables is reported as an informational finding rather
  than ignored.

## License

Apache License 2.0.
