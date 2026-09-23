**English** | [简体中文](getting-started.md)

# Getting started

## Prepare two artifacts

Use existing Solidity compiler artifacts from before and after the upgrade as `OLD` and `NEW`. Supported inputs include solc Standard JSON, Foundry flat artifacts, Hardhat build info containing `storageLayout`, and standalone `storageLayout` objects. A Hardhat single-contract artifact normally lacks the layout and is not enough for a storage check.

If a file contains several contracts, select one with `--contract NAME` or `--contract SOURCE:NAME`. For runnable inputs, start with the [artifact fixtures](../fixtures/README.en.md).

## Run a check

Download the native Linux x86_64 or macOS arm64 executable from [GitHub Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) and rename it to `moonupgradeguard`. To build it yourself, see the [hands-on tutorial](guide.en.md). Run `chmod +x moonupgradeguard` first if the download is not executable.

```bash
./moonupgradeguard check OLD NEW --format text
./moonupgradeguard check OLD NEW --format json
```

`check` compares storage layout and also compares ABI when both sides contain one. Replace `check` with `storage` or `abi` to check only that layer. See the [README CLI section](../README.en.md#cli) for all options and the [hands-on tutorial](guide.en.md) for a worked example.

## Handle the result

- `0`: no blocking incompatibility was found; this is a preflight result, not proof of safety.
- `1`: a blocking incompatibility was found; inspect the diagnostic location and old/new values.
- `2`: the command or input is invalid; correct it rather than treating it as compatible.

JSON output is always an array of findings. Errors from one input include `input: "old"` or `input: "new"`; comparison findings omit that field. See the [diagnostics reference](diagnostics.en.md) for every code.
