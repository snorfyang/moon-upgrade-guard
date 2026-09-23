[English](index.en.md) | **简体中文**

# MoonUpgradeGuard 文档

MoonUpgradeGuard 是离线的 EVM 合约升级兼容性预检工具。给它两个已有的 Solidity 编译产物，它会比较存储布局与 ABI，输出稳定的诊断和适合 CI 使用的退出码。

它不编译合约、不连接链，也不证明升级在所有方面都安全。

## 从这里开始

- [快速开始](getting-started.md)：取得可执行文件，运行第一组检查，理解退出码。
- [用户指南](guide.md)：工作原理、输入格式、可复现走查与兼容性规则。
- [诊断码手册](diagnostics.md)：查找报告中的错误、警告及其含义。
- [产物样例](../fixtures/README.md)：查看兼容与不兼容的输入，以及真实编译产物。

## 深入了解

- [差分对比](oz-differential.md)：与 OpenZeppelin Upgrades Core 的行为对照及差异。
- [参考与许可](references.md)：规则依据、依赖许可证与样例来源。
- [路线图](../ROADMAP.md)：已交付能力与后续方向。

仓库 [README](../README.md) 只保留项目概览与最短上手入口；详细使用说明以本站为准。
