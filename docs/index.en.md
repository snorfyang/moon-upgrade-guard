**English** | [简体中文](index.md)

# MoonUpgradeGuard documentation

MoonUpgradeGuard is an offline preflight compatibility checker for EVM contract upgrades. Given two existing Solidity compiler artifacts, it compares storage layout and ABI, then emits stable diagnostics and CI-friendly exit codes.

It does not compile contracts, connect to a chain, or prove an upgrade safe in every respect.

## Start here

- [Getting started](getting-started.en.md): get an executable, run a first check, and understand the exit codes.
- [Hands-on tutorial](guide.en.md): prepare real compiler artifacts, read compatible, incompatible, and invalid results, and integrate CI.
- [Diagnostics reference](diagnostics.en.md): look up errors, warnings, and their meanings.
- [Artifact fixtures](../fixtures/README.en.md): inspect compatible and incompatible inputs and real compiler artifacts.

## Go deeper

- [Differential results](oz-differential.en.md): behavior compared with OpenZeppelin Upgrades Core.
- [References and licensing](references.en.md): rule sources, dependency licenses, and fixture provenance.
- [Roadmap](../ROADMAP.md): delivered capabilities and later directions.

The repository [README](../README.en.md) retains the full project description; this site also organizes the material by task.
