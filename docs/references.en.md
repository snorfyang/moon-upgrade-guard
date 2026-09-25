[简体中文](references.md) | **English**

# References and licensing

This page records the primary specifications the rules follow, the licences of
the dependencies, and where every fixture comes from. The aim is simple: a reader
should be able to trace each comparison rule to public documentation, and to tell
where a file in this repository came from and under which licence it is used.

## Specifications the rules follow

- **Storage layout**: the slot a variable occupies, its byte offset, `encoding`,
  `numberOfBytes`, and the `types` table (mapping key and value, array base,
  struct members) follow the [Solidity storage layout documentation](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html).
  That page also says the output is experimental and can change in non-breaking
  releases, which is why an unrecognized shape fails explicitly here instead of
  being assumed compatible.
- **ABI**: canonical signatures, selectors (the first four bytes of the Keccak-256
  hash of the signature), event topics (the signature hash), and indexed
  parameters follow the [Solidity ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html).
- **Artifact shapes**: the `contracts.<source>.<contract>` structure of solc
  Standard JSON output follows the [compiler input and output documentation](https://docs.soliditylang.org/en/latest/using-the-compiler.html);
  the field names of a flat Foundry artifact, and of a Hardhat artifact and build
  info, come from their own public documentation.
- **Transient storage**: transient storage has its own address space, its
  semantics follow [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153), and its
  layout comes from the compiler's `transientStorageLayout` output.
- **Namespaces and unstructured slots**: [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201)
  namespaces and assembly-assigned slots such as [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967)
  are both outside what the compiler's `storageLayout` can see, but they differ in
  detectability here. ERC-7201 requires an `erc7201` annotation in the source, and an
  artifact that carries the AST keeps that marker in its text; the tool scans for it
  and reports `artifact.namespaced-storage.unsupported` — an Error that blocks the
  upgrade — on an artifact that carries it, instead of reporting compatible. The scan
  only sees artifact text: a bare `storageLayout` object or a flattened artifact
  without the AST carries no marker, so this check does not fire there either.
  EIP-1967, like every slot written by assembly, leaves no detectable marker in
  compiler output, so it is **undetectable and not validated** — an artifact that
  omits such slots can be reported compatible, and confirming them is the reader's
  responsibility. The shared principle is that storage invisible in the artifact
  cannot be verified here.
- **Keccak-256**: the implementation follows the Keccak specification
  (Keccak-f[1600] with the `0x01` padding Ethereum uses, not the `0x06` padding of
  SHA-3). Tests pin published known-answer values, including the empty input,
  `abc`, padding boundary lengths, and the published four-byte selector collision
  pair.

## Dependencies and licences

Building and running depend on the MoonBit ecosystem only:

- **MoonBit standard library** (shipped with the toolchain): Apache-2.0.
- **moonbitlang/async 0.21.3**: Apache-2.0; the CLI uses it for its asynchronous
  runtime and for reading files.

Tools used for development only, not part of the product:

- **OpenZeppelin Upgrades Core**: MIT; called only by
  `scripts/oz-differential.mjs` for behavioural comparison.
- **solc**: GPL-3.0; only its output is used, to generate the `schema-solc-*`
  fixtures, and solc itself is not redistributed.
- **pycryptodome**: BSD-2-Clause / Apache-2.0 dual licence; used to produce the
  reference digests in the Keccak tests, and not redistributed.
- **Material for MkDocs 9.7.7**: MIT; used only to build the documentation site,
  not included in the checker or release package.
- **MkDocs**: BSD-2-Clause; installed with the documentation build dependencies
  and used only to generate static pages.

## Where the fixtures come from

- Except for the OpenZeppelin case below, fixtures were written or generated
  from this repository's own source; no third-party test data was copied.
- The `schema-solc-*` pairs come from a contract that lives in this repository,
  compiled by solc 0.5.17, 0.6.12, and 0.8.28; the source and the way it is
  compiled are recorded in the [fixture catalogue](../fixtures/README.en.md).
- `real-oz-erc20-4.9.3-to-4.9.6` contains compiler output generated from the MIT-licensed OpenZeppelin Contracts Upgradeable 4.9.3 and 4.9.6 sources; no Solidity source was copied. Its source versions, generation scope, and commands are in the [fixture catalogue](../fixtures/README.en.md), with the upstream copyright notice and licence in its [LICENSE](../fixtures/real-oz-erc20-4.9.3-to-4.9.6/LICENSE).
- Fixtures and test code written by this repository are Apache-2.0; the OpenZeppelin-generated artifacts retain the MIT provenance and notice above.

## Relationship to OpenZeppelin Upgrades Core

OpenZeppelin Upgrades Core was used to understand the public behaviour of a mature
tool and as the reference for the differential comparison; its published source
was read to align the gap rule. No Upgrades Core source, test, or fixture was copied; the Contracts Upgradeable case above stores only versioned compiler output. The harness compares behaviour only, and the outcome is recorded in the
[differential record](oz-differential.en.md), which lists the one deliberate
difference.

## Project licence

This repository is licensed under the [Apache License 2.0](../LICENSE), and so is
the package published to the MoonBit package registry; `moon package --list` shows
the files that would be published.
