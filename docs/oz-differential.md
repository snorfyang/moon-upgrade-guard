**简体中文** | [English](oz-differential.en.md)

# 与 OpenZeppelin Upgrades Core 的差分对比

存储引擎会针对每一对 fixture 与成熟参考实现
[`@openzeppelin/upgrades-core`](https://github.com/OpenZeppelin/openzeppelin-upgrades)
对比。两者拿到同样的产物并被要求给出结论；重点不是它们的措辞是否一致，而是**对于某个变更是否
阻断升级，两者是否一致**，以及每一处分歧是否都被理解。

对比时把参考实现作用在编译器自己的 `storageLayout` 对象上（那正是它的比较器所消费的形态），并
运行 CLI 的 `storage` 子命令。只有当引擎给出了结论（退出码 `0` 或 `1`）时，这一对才算"已比较"；
退出码 `2` 表示产物被拒绝，那不是可比较的结论。

这是开发工具，不在 CI 中运行：它需要 Node 与一份安装好的参考实现，而测试套件保持离线。

## 复现方式

```bash
npm install --prefix /tmp/ozdiff @openzeppelin/upgrades-core
moon build --target native
OZ_UPGRADES_CORE=/tmp/ozdiff/node_modules/@openzeppelin/upgrades-core \
  node scripts/oz-differential.mjs
```

针对 `@openzeppelin/upgrades-core` 1.46.0 运行，输出为：

```console
reference: @openzeppelin/upgrades-core 1.46.0
engine:    _build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe

- abi-event-indexed: engine exit 0 | reference pass | agree
- abi-function-removed: engine exit 0 | reference pass | agree
- ambiguous-build-info: engine exit 2 | reference skip (no storageLayout) | n/a
- append: engine exit 0 | reference pass | agree
- compatible: engine exit 0 | reference pass | agree
- contract-selector: engine exit 2 | reference skip (no storageLayout) | n/a
- invalid-json: engine exit 2 | reference skip (error: Expected ',' or '}' after property value in JSON at position 50 (line 4 column 1)) | n/a
- missing-file: no pair
- namespaced-storage: engine exit 2 | reference pass | n/a
- schema-solc-0.5-to-0.8: engine exit 0 | reference pass | agree
- schema-solc-0.6-to-0.8: engine exit 0 | reference pass | agree
- schema-unsupported: engine exit 2 | reference rename | n/a
- storage-gap-finished: engine exit 0 | reference pass | agree
- storage-gap-shrink: engine exit 0 | reference pass | agree
- storage-gap-unsafe: engine exit 1 | reference layoutchange | agree
- storage-moved: engine exit 1 | reference delete, insert, layoutchange | agree
- storage-removed: engine exit 1 | reference delete | agree
- storage-renamed: engine exit 0 | reference rename | DIFFER
- struct-change: engine exit 1 | reference typechange | agree
- transient-append: engine exit 0 | reference skip (transient layout) | n/a
- transient-moved: engine exit 1 | reference skip (transient layout) | n/a
- transient-removed: engine exit 1 | reference skip (transient layout) | n/a
- unsupported-artifact: engine exit 2 | reference skip (no storageLayout) | n/a

compared 13 pairs, 1 divergences
  storage-renamed: engine exit 0 vs reference rename
```

## 一致的部分

- **存储 gap。** `storage-gap-shrink` 正是催生该规则的情形：基础合约把 `__gap` 的一个 slot
  用于新变量，因此 gap 缩小，但结束位置不变。两者都通过。参考实现用 `endMatchesGap` 判定，而
  引擎用的是同一个判据，所以这里的一致并非偶然。
- **追加。** `append` 追加了一个变量、一个函数和一个事件：两者都通过，因为没有移动任何东西的
  新增是安全的。
- **移动、删除与类型变化。** `storage-moved`、`storage-removed`、`struct-change` 在两者中都
  阻断。特别是"struct 增加成员"对两者都是类型变化，说明引擎对递归类型变化的保守解读与参考实现
  一致，而不是更严格。
- **编译器版本。** 由真实 solc 0.5.17、0.6.12、0.8.28 产出的 `schema-solc-*` 各对，在两者中
  都通过。

## 唯一一处刻意差异

| 样例对 | 引擎 | 参考实现 |
| --- | --- | --- |
| `storage-renamed` | 警告，退出码 `0` | `rename`，阻断 |

在不移动位置的前提下重命名变量，会让每个字节都留在原处，因此存储布局仍然兼容。参考实现把重命名
视为不安全（除非传入 `unsafeAllowRenames`），因为新名字可能承载新的含义。引擎则报告警告，并把
这一点写进公开文档：布局兼容，含义需要人工确认。

改为更严格的策略是一次严重度变更加上快照更新，而不是重写实现；但它会改变现有用户的兼容性契约，
因此留作显式决策，而不是悄悄改变。

## 对比覆盖不到的情况

- `ambiguous-build-info` 与 `contract-selector` 包含多个合约，需要 `--contract`；脚本不传
  选择器，引擎会报告歧义。
- `invalid-json` 与 `missing-file` 在任何布局出现之前就被拒绝。
- `unsupported-artifact` 是 Hardhat 的单合约产物，本身不含存储布局。
- `schema-unsupported` 使用了引擎不认识的 `encoding`。引擎拒绝该产物（退出码 `2`），因为编码
  决定了字节如何被读取；参考实现不校验该字段，并报告了一个无关的重命名。拒绝是刻意的选择：可能
  影响兼容性的未知形态，绝不能被报告为兼容。
- 带有 transient storage 布局的样例对会被跳过：脚本把常规布局交给参考实现，所以它的结论与
  transient 命名空间无关，而引擎会单独比较后者。
- `namespaced-storage` 被引擎拒绝（退出码 `2`）。参考实现在这里通过，只是因为该 fixture 携带的
  是一行文档字符串而不是真实的编译 AST；它的命名空间支持读取 AST，而本工具不分析 AST。这两点都
  已记录为已知限制。

## 来源说明

参考实现用于理解公开行为；为对齐 gap 规则，阅读了它公开的源码（`storage/gap.ts`、
`storage/compare.ts`）。没有复制任何源代码、测试或 fixture：本仓库中的每个 fixture 都是自行
编写或生成的，脚本只对比行为。
