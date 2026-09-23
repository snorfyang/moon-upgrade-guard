[English](getting-started.en.md) | **简体中文**

# 快速开始

## 准备两个产物

准备升级前后的 Solidity 编译产物，分别作为 `OLD` 和 `NEW`。支持 solc Standard JSON、Foundry 平铺 artifact、包含 `storageLayout` 的 Hardhat build info，以及独立的 `storageLayout` 对象。Hardhat 的单合约 artifact 本身通常没有布局，不足以进行存储检查。

如果一份文件包含多个合约，运行时用 `--contract NAME` 或 `--contract SOURCE:NAME` 选定合约。想看可直接运行的输入，可从[产物样例](../fixtures/README.md)开始。

## 运行检查

从 [GitHub Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) 下载适合 Linux x86_64 或 macOS arm64 的原生可执行文件，重命名为 `moonupgradeguard`；如需自行构建，参见[用户指南](guide.md#构建与测试)。下载后若没有执行权限，先运行 `chmod +x moonupgradeguard`。

```bash
./moonupgradeguard check OLD NEW --format text
./moonupgradeguard check OLD NEW --format json
```

`check` 比较存储布局；两边都带 ABI 时也比较 ABI。只想检查其中一层，可把 `check` 换成 `storage` 或 `abi`。完整选项见[用户指南的命令行章节](guide.md#命令行)。

## 处理结果

- `0`：没有发现阻断性不兼容；这只是预检，不是安全证明。
- `1`：发现阻断性不兼容；查看诊断位置、旧值和新值。
- `2`：命令或输入无效；应修正输入，而不是将其视为兼容。

JSON 输出始终是诊断数组。由单侧输入产生的错误带有 `input: "old"` 或 `input: "new"`；比较诊断不带该字段。逐个诊断码的含义见[诊断码手册](diagnostics.md)。
