MoonUpgradeGuard compares the storage layout and ABI of existing Solidity compiler artifacts before an EVM proxy upgrade. It reports deterministic diagnostics and exit codes for CI. Passing this preflight check does not prove an upgrade safe in every respect.

Changes since v0.1.0:

- JSON findings produced by one artifact now include `"input": "old"` or `"input": "new"`. Comparison findings omit the field. An `abi` check where both inputs lack an ABI now emits one finding for each input. This changes the JSON report contract.
- Regression tests now cover real solc, Foundry, and Hardhat artifacts, including nested storage types and transient storage.
- Bilingual documentation is available on [GitHub Pages](https://snorfyang.github.io/moon-upgrade-guard/).

The Linux x86_64 and macOS arm64 assets are native CLI executables. After downloading, run `chmod +x <filename>` before use if the executable bit was not preserved.

Known limitations:
- The tool does not compile Solidity, inspect business logic, connect to a chain, or execute bytecode.
- ERC-7201 namespaced storage is rejected only when an `erc7201` marker is present in the artifact text; its members are not compared.
- EIP-1967 and other slots written through assembly are not detectable from `storageLayout` and are not checked.
- Constructor ABI entries are not compared. A Hardhat single-contract artifact without `storageLayout` is not sufficient input.

See the [README](https://github.com/snorfyang/moon-upgrade-guard#readme) for supported inputs, commands, and further limitations.
