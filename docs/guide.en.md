**English** | [简体中文](guide.md)

# From compiler artifacts to an upgrade report

This tutorial runs an upgrade preflight check on real solc artifacts committed to the repository, then shows how to use your own. MoonUpgradeGuard compares storage layout and ABI in existing artifacts only: it does not compile source, connect to a chain, or prove business logic or the entire upgrade safe. The commands and output here can be reproduced from this repository.

## 1. Obtain comparable artifacts

Both versions need the target contract's `storageLayout`; retain `abi` too if you want an ABI comparison. Keep the full compiler artifact rather than extracting one field. These are the paths verified by this repository:

| Source | What to keep |
| --- | --- |
| solc Standard JSON | Request `abi` and `storageLayout` in `settings.outputSelection` and save the full compiler output; request `transientStorageLayout` too if needed. See the [Solidity compiler documentation](https://docs.soliditylang.org/en/v0.8.28/using-the-compiler.html). |
| Foundry | Use `forge build --extra-output storageLayout` for a flat artifact with layout, then take `out/<source>/<contract>.json`. The [real artifact fixtures](../fixtures/README.en.md#real-artifact-matrix) record a pinned recipe. |
| Hardhat | Request the layout in Solidity `outputSelection` and use `artifacts/build-info/*.json`; a per-contract artifact normally lacks it. The repository includes a [verified configuration](../fixtures/real-artifacts/hardhat.config.cjs). |

For example, save this complete solc 0.8.28 Standard JSON input as `input.json`, then save the full output with `solc --standard-json < input.json > old.json`. Replace the source under `sources` for the new version and compile it likewise into `new.json`. If the compiler reports errors, fix the source or settings before treating its output as a comparable artifact.

```json
{
  "language": "Solidity",
  "sources": {
    "src/Counter.sol": {
      "content": "// SPDX-License-Identifier: Apache-2.0\npragma solidity 0.8.28;\ncontract Counter { uint256 public value; }\n"
    }
  },
  "settings": {
    "outputSelection": {
      "*": {"*": ["abi", "storageLayout"]}
    }
  }
}
```

Select the same contract on both sides. Standard JSON and build info can contain several contracts; use `--contract NAME` or `--contract SOURCE:NAME`. An ambiguous selection produces exit code `2` rather than a guessed result. See the [README input section](../README.en.md#inputs) for more shapes and limitations.

## 2. Run a compatible check

Install [MoonBit](https://www.moonbitlang.com/), clone the repository, and run these commands from its root. A first build may need to populate the MoonBit module cache. Alternatively, download a native executable from [Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) and replace `moon run src/cmd/moonupgradeguard --` below with its path.

```bash
git clone https://github.com/snorfyang/moon-upgrade-guard.git
cd moon-upgrade-guard
moon update
moon build --target native
```

In `real-solc-compatible`, the new `Counter` only adds a variable and function. The findings are informational, so the exit code is still `0`:

```console
$ moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-compatible/old.json fixtures/real-solc-compatible/new.json --contract Counter
info[abi.function.added] abi.functions: function "extra()" was added to the new ABI (new: extra())
info[storage.entry.added] src/Counter.sol:Counter storage[1]: variable "extra" was added at slot 1, offset 0 (new: extra)
$ echo $?
0
```

`check` compares storage and an ABI when both sides have one; `storage` and `abi` check those layers separately. Exit code `0` only means no blocking incompatibility was found, not that the upgrade has been audited.

## 3. Read an incompatible report

`real-solc-incompatible` narrows `value` from `uint256` to `uint128`. That changes the interpretation of existing storage and the output type of `value()`, so both layers report an error:

```console
$ moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-incompatible/old.json fixtures/real-solc-incompatible/new.json --contract Counter
error[abi.function.outputs.changed] abi.functions["value()"].outputs: function "value()" changed its output types from "uint256" to "uint128" (old: uint256, new: uint128)
error[storage.entry.type.changed] src/Counter.sol:Counter storage[0]: storage type of "value" changed from "uint256" to "uint128" (old: uint256, new: uint128)
$ echo $?
1
```

Each line gives a severity, stable code, location, explanation, and available old/new values. `Error` blocks; `Warning` needs human review; `Info` covers additions and other non-blocking changes. See the [diagnostics reference](diagnostics.en.md) for each code, and the [artifact fixtures](../fixtures/README.en.md) for real cases involving packing, mappings, structs, gaps, and transient storage.

Here `storage[0]` names the first variable in the normalized layout, not a Solidity source line; `old: uint256, new: uint128` identifies the concrete type change to review.

## 4. Machine-readable reports and CI

With `--format json`, stdout is always a JSON array of findings. `code` is useful for automation, `message` for people, and `location` plus `oldValue`/`newValue` for investigation. An error from one input also has `input: "old"` or `input: "new"`; cross-version comparison findings omit this field.

```bash
moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-incompatible/old.json fixtures/real-solc-incompatible/new.json --contract Counter --format json
```

For example, the storage finding contains a stable code, location, and both types. The full array also contains the ABI finding shown above:

```json
{
  "code": "storage.entry.type.changed",
  "severity": "error",
  "location": {"contract": "src/Counter.sol:Counter", "path": "storage[0]"},
  "message": "storage type of \"value\" changed from \"uint256\" to \"uint128\"",
  "oldValue": "uint256",
  "newValue": "uint128"
}
```

Let the exit code gate a CI job. Do not turn `1` or `2` into success or rely on searching the prose output:

```yaml
- name: upgrade compatibility
  run: |
    moon build --target native
    _build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe \
      check build/old.json build/new.json --contract Counter --format json
```

Replace `build/old.json`, `build/new.json`, and `Counter` with the artifacts and contract selector from your pipeline. Do not put private keys or unpublished deployment details in diagnostic examples.

## 5. Distinguish incompatibility from invalid input

Exit code `1` means a completed comparison found a blocking change; `2` means a file, selector, or schema could not be analyzed. Never treat `2` as compatible. Here the old artifact is truncated JSON, so the report identifies `input: "old"`:

```console
$ moon run src/cmd/moonupgradeguard -- check fixtures/invalid-json/old.json fixtures/invalid-json/new.json --format json
[
  {
    "code": "artifact.json.invalid",
    "severity": "error",
    "input": "old",
    "location": {"path": "$"},
    "message": "artifact is not valid JSON: Unexpected end of file"
  }
]
$ echo $?
2
```

If a layout is missing, confirm that the saved compiler output contains `storageLayout`; in particular, do not use a Hardhat per-contract artifact in place of build info. For an ambiguous contract selection, add `--contract`. Do not bypass unknown encodings or unsupported namespaces to proceed with deployment. Authorization, initialization, business logic, and deployment still need separate review.
