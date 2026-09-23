[English](README.en.md) | **简体中文**

# MoonUpgradeGuard

[![CI](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/ci.yml)
[![Native release](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/release.yml/badge.svg)](https://github.com/snorfyang/moon-upgrade-guard/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/snorfyang/moon-upgrade-guard)](https://github.com/snorfyang/moon-upgrade-guard/releases/latest)
[![License](https://img.shields.io/github/license/snorfyang/moon-upgrade-guard)](LICENSE)

MoonUpgradeGuard 是一个用 MoonBit 编写的离线 EVM 合约升级兼容性预检工具。它比较两个已有 Solidity 编译产物的存储布局与 ABI，输出确定性的诊断和 CI 友好的退出码。它不编译源码、不连接链，也不证明升级在所有方面都安全。

## 快速试用

安装 MoonBit 后，在仓库中运行一对自带样例：

```bash
git clone https://github.com/snorfyang/moon-upgrade-guard.git
cd moon-upgrade-guard
moon run src/cmd/moonupgradeguard -- check fixtures/storage-moved/old.json fixtures/storage-moved/new.json
```

这对样例会报告变量移动并以 `1` 退出；`0` 表示未发现阻断性不兼容，`2` 表示命令或输入无效。[GitHub Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) 还提供 Linux x86_64 与 macOS arm64 原生可执行文件。

## 文档

- [快速开始](docs/getting-started.md)：下载、准备产物与解读结果。
- [用户指南](docs/guide.md)：工作原理、支持的输入、完整走查、CI 集成、兼容性规则与限制。
- [诊断码手册](docs/diagnostics.md)与[产物样例](fixtures/README.md)：查找报告含义和可复现的案例。
- [在线文档](https://snorfyang.github.io/moon-upgrade-guard/)与[路线图](ROADMAP.md)。

项目采用 [Apache-2.0 许可证](LICENSE)。这是一项升级前检查，不能替代专业审计。
