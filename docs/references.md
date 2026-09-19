**简体中文** | [English](references.en.md)

# 参考与许可

本页记录规则所依据的一手规范、依赖的许可证，以及每个 fixture 的来源。目标很简单：读者应当能把
每条比较规则追溯到公开文档，并能判断本仓库中的文件来自哪里、以什么许可使用。

## 规则依据的规范

- **存储布局**：变量所处 slot、byte offset、`encoding`、`numberOfBytes`，以及 `types` 表的
  mapping key/value、数组 base、struct members，都遵循 [Solidity 存储布局文档](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)。
  该文档同时说明这份输出仍是实验性的、可能在不破坏兼容的版本中变化，因此本工具遇到无法识别的形态
  会显式失败，而不是假定兼容。
- **ABI**：规范化签名、selector（签名的 Keccak-256 前四字节）、event topic（签名哈希）与 indexed
  参数遵循 [Solidity ABI 规范](https://docs.soliditylang.org/en/latest/abi-spec.html)。
- **产物形态**：solc Standard JSON 输出的 `contracts.<source>.<contract>` 结构遵循
  [编译器输入输出文档](https://docs.soliditylang.org/en/latest/using-the-compiler.html)；Foundry
  平铺 artifact 与 Hardhat artifact、build info 的字段名分别来自各自的公开文档。
- **transient storage**：瞬态存储位于独立地址空间，其语义依据
  [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153)，布局来自编译器输出的
  `transientStorageLayout`。
- **命名空间与非结构化 slot**：[ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) 的命名空间与
  [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) 这类由汇编写入的 slot 都不在编译器
  `storageLayout` 的可见范围内，但两者在本工具中的可检测性不同。ERC-7201 要求源码携带
  `erc7201` 标注，该标注会留在带 AST 的产物文本里；本工具扫描这一标记，对携带它的产物报
  `artifact.namespaced-storage.unsupported`（Error，会阻断升级），而不是判定兼容。该检查只看得见产物
  文本：裸 `storageLayout` 对象或不带 AST 的平铺产物不携带标记，因此连这一检查也不会触发。
  EIP-1967 与一切由汇编写入的 slot 不会在编译产物中留下可检测标记，因此**不可检测、不参与
  验证**——省略了这类 slot 的产物可能被判定为兼容，确认它们是使用者的责任。两者的共同前提是：
  产物文本里看不见的存储，本工具无法验证。
- **Keccak-256**：实现遵循 Keccak 规范（Keccak-f[1600]，Ethereum 使用的 `0x01` 填充，而非 SHA-3
  的 `0x06`）。测试固定公开已知答案，包括空输入、`abc`、填充边界长度，以及公开的四字节 selector
  碰撞对。

## 依赖与许可证

构建与运行时只依赖 MoonBit 生态：

- **MoonBit 标准库**（随工具链提供）：Apache-2.0。
- **moonbitlang/async 0.21.3**：Apache-2.0；CLI 的异步运行时与文件读取使用它。

仅用于开发、不进入产品的工具：

- **OpenZeppelin Upgrades Core**：MIT；仅由 `scripts/oz-differential.mjs` 调用，用于行为对比。
- **solc**：GPL-3.0；本仓库只使用它的输出来生成 `schema-solc-*` fixture，不重新分发 solc 本身。
- **pycryptodome**：BSD-2-Clause / Apache-2.0 双许可；用于生成 Keccak 测试中的参考摘要，
  不重新分发。

## fixture 的来源与许可

- 每个 fixture 都是为本仓库编写或生成的，没有复制任何第三方 artifact 或测试数据。
- `schema-solc-*` 来自本仓库自带的一份合约源码，由 solc 0.5.17、0.6.12 与 0.8.28 编译得到；源码与
  生成方式记录在 [fixture 说明](../fixtures/README.md)。
- fixture 与本仓库其余部分一样以 Apache-2.0 授权。

## 与 OpenZeppelin Upgrades Core 的关系

OpenZeppelin Upgrades Core 用于理解成熟工具的公开行为，并作为差分对比的参照；为对齐 gap 规则，
阅读了它公开的源码。没有复制其源代码、测试或 fixture：差分脚本只对比行为，结果记录在
[差分对比记录](oz-differential.md)，其中列明唯一一处刻意差异。

## 项目许可证

本仓库以 [Apache License 2.0](../LICENSE) 授权，发布到 MoonBit 包注册表的包同样是 Apache-2.0；
`moon package --list` 可以查看实际会发布的文件。
