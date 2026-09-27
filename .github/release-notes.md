MoonUpgradeGuard compares the storage layout and ABI of existing Solidity compiler artifacts before an EVM proxy upgrade. It reports deterministic diagnostics and exit codes for CI. Passing this preflight check does not prove an upgrade safe in every respect.

Changes since v0.2.0:

- ERC-7201 detection now reads contract struct annotations in the compiler AST, avoiding false positives from unrelated ABI or metadata strings. Namespaced storage itself is still not compared.
- Offline regression fixtures cover real OpenZeppelin ERC20Upgradeable releases: 4.9.3 to 4.9.6 remains compatible, while 4.9.3 to 5.0.0 is blocked. A real 5.0.0 AST fixture verifies explicit refusal of ERC-7201 storage.
- Regression fixtures also cover Solidity 0.8.29 custom storage-layout bases.
- The [documentation site](https://snorfyang.github.io/moon-upgrade-guard/) now has its own home page, quickstart, and bilingual hands-on tutorial.

The Linux x86_64 and macOS arm64 assets are native CLI executables. After downloading, run `chmod +x <filename>` before use if the executable bit was not preserved.

Known limitations:
- The tool does not compile Solidity, inspect business logic, connect to a chain, or execute bytecode.
- ERC-7201 namespaced storage is rejected only when a contract struct annotation is visible in the artifact AST. Its members are not compared; without an AST, this storage may be invisible to the checker.
- EIP-1967 and other slots written through assembly are not detectable from `storageLayout` and are not checked.
- Constructor ABI entries are not compared. A Hardhat single-contract artifact without `storageLayout` is not sufficient input.

See the [README](https://github.com/snorfyang/moon-upgrade-guard#readme) for supported inputs, commands, and further limitations.
