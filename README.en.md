**English** | [简体中文](README.md)

# MoonUpgradeGuard

[![CI](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/ci.yml)
[![Native release](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/release.yml/badge.svg)](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/snorfyang/moon-upgrade-guard)](https://github.com/snorfyang/moon-upgrade-guard/releases/latest)
[![License](https://img.shields.io/github/license/snorfyang/moon-upgrade-guard)](LICENSE)

MoonUpgradeGuard is an offline, MoonBit-native preflight checker for EVM contract upgrades. It compares the storage layout and ABI of two existing Solidity compiler artifacts and emits deterministic diagnostics with CI-friendly exit codes. It does not compile source, connect to a chain, or prove an upgrade safe in every respect.

## Try it

After installing MoonBit, run a bundled fixture pair from the repository:

```bash
git clone https://github.com/snorfyang/moon-upgrade-guard.git
cd moon-upgrade-guard
moon run src/cmd/moonupgradeguard -- check fixtures/storage-moved/old.json fixtures/storage-moved/new.json
```

This pair reports moved variables and exits `1`; `0` means no blocking incompatibility was found, and `2` means the command or input is invalid. [GitHub Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) also provides native Linux x86_64 and macOS arm64 executables.

## Documentation

- [Getting started](docs/getting-started.en.md): download, prepare artifacts, and read results.
- [User guide](docs/guide.en.md): how it works, supported inputs, a full walkthrough, CI integration, compatibility rules, and limitations.
- [Diagnostics reference](docs/diagnostics.en.md) and [artifact fixtures](fixtures/README.en.md): look up findings and reproducible cases.
- [Documentation site](https://snorfyang.github.io/moon-upgrade-guard/en/) and [roadmap](ROADMAP.md).

Licensed under [Apache-2.0](LICENSE). This is a preflight check, not a replacement for a professional audit.
