**简体中文** | [English](README.en.md)

# 升级 fixture

每个目录存放一对编译产物 `old.json` 与 `new.json`，端到端地演示一条兼容性规则。多数手写样例刻意做成 Foundry 写出的那种小型平铺 artifact：一个 `abi` 数组加一个 `storageLayout` 对象。
`scripts/e2e.sh` 中的 CLI 端到端检查会跑遍每一对，顶层 README 的示例使用其中的前两对。

每个目录都是自包含的：当某一侧未变时，它是复制而不是共享文件，因此单独看一个目录也能读懂并运行。

来源说明：这里的源码和手写样例均属于本仓库；`real-*` 是由该源码生成的真实工具输出。手写样例的字段形态遵循 Solidity 编译器的 `storageLayout` 文档与 ABI 规范；没有复制任何第三方产物或 fixture。

| 目录 | 变化 | `check` 退出码 |
| --- | --- | --- |
| `compatible/` | 同一个合约重新编译：只有编译器生成的 `astId` 与类型表顺序不同 | 0 |
| `append/` | 追加一个存储变量、一个函数和一个事件 | 0 |
| `storage-removed/` | `owner` 变量被删除 | 1 |
| `storage-renamed/` | `owner` 在同一位置、类型不变的前提下重命名为 `admin` | 0 |
| `storage-moved/` | `totalSupply` 与 `owner` 交换 slot | 1 |
| `struct-change/` | `Config` struct 增加一个成员 | 1 |
| `storage-gap-shrink/` | 基础合约把 `__gap` 的一个 slot 用于新变量，gap 缩小但结束位置不变 | 0 |
| `transient-moved/` | transient 变量在 slot 之间移动 | 1 |
| `transient-append/` | 新版本新增一个 transient 变量 | 0 |
| `transient-removed/` | 新产物没有报告 transient 布局，因此旧的 transient 变量消失 | 1 |
| `storage-gap-finished/` | `__gap` 被一个结束位置相同的 struct 整体替换 | 0 |
| `storage-gap-unsafe/` | 加入同一个变量但 gap 保持原大小，导致 gap 与其后的变量移动 | 1 |
| `storage-gap-dynamic/` | `__gap` 是动态数组，slot 里是长度而非保留字节，被新变量替换时不当作 gap | 1 |
| `abi-function-removed/` | `transfer(address,uint256)` 被删除，而存储未变 | 1 |
| `abi-fallback-kind/` | `fallback` 处理器被同签名的具名 `function fallback()` 取代 | 1 |
| `abi-event-indexed/` | `Transfer` 的 `value` 参数变为 indexed | 1 |
| `invalid-json/` | `old.json` 被截断 | 2 |
| `unsupported-artifact/` | `old.json` 是 Hardhat 单合约产物，不含存储布局 | 2 |
| `contract-selector/` | 一份包含两个合约的 build info：`Alpha` 兼容，而 `Beta` 移动了变量，因此由 `--contract` 决定结论 | 不传选择器为 2，`Alpha` 为 0，`Beta` 为 1 |
| `namespaced-storage/` | `old.json` 带有 ERC-7201 `@custom:storage-location` 注释，其命名空间成员不在编译器布局中 | 2 |
| `schema-solc-0.5-to-0.8/` | 同一份合约分别由 solc 0.5.17 与 solc 0.8.28 编译，包含 0.5 写出的旧式 ABI 字段 | 0 |
| `schema-solc-0.6-to-0.8/` | 同一份合约分别由 solc 0.6.12 与 solc 0.8.28 编译 | 0 |
| `real-solc-compatible/` | solc Standard JSON：追加变量 | 0 |
| `real-solc-incompatible/` | solc Standard JSON：变量宽度从 256 位缩为 128 位 | 1 |
| `real-solc-no-layout/` | solc Standard JSON：编译时未请求存储布局 | 2 |
| `real-foundry-compatible/` | Foundry 平铺 artifact：追加变量 | 0 |
| `real-foundry-incompatible/` | Foundry 平铺 artifact：变量宽度缩小 | 1 |
| `real-foundry-no-layout/` | Foundry 平铺 artifact：编译时未请求存储布局 | 2 |
| `real-hardhat-compatible/` | Hardhat build info：追加变量 | 0 |
| `real-hardhat-incompatible/` | Hardhat build info：变量宽度缩小 | 1 |
| `real-hardhat-per-contract/` | Hardhat 单合约 artifact：不含存储布局 | 2 |
| `schema-unsupported/` | 类型表使用了本版本不认识的 `encoding` | 2 |
| `fractional-offset/` | 两边的 `offset` 都是四舍五入后为整数的小数，被当作不可用 schema 数据拒绝 | 2 |
| `ambiguous-build-info/` | `old.json` 是包含两个带存储布局合约的 Hardhat build info | 2 |
| `missing-file/` | 故意没有 `new.json`，用于覆盖不可读路径 | 2 |

## 真实产物矩阵

`real-*` 使用本仓库自行编写的 [`Counter` 源码](real-artifacts/sources/old.sol) 及其[兼容](real-artifacts/sources/compatible.sol)、[不兼容](real-artifacts/sources/incompatible.sol)版本（Apache-2.0）。三份源码分别复制成工具项目中的同一个源文件名，再编译成 `old.json` 或 `new.json`。没有改写编译器输出中的字段；`solcjs` 输出开头的非 JSON 提示行在保存前被移除。

| 工具 | 固定版本 | 生成命令及保存位置 |
| --- | --- | --- |
| solcjs | 0.8.28 | `solcjs --standard-json < fixtures/real-artifacts/inputs/old.json > output.txt`；其余三份[输入文件](real-artifacts/inputs/compatible.json)同法编译。输入的源文件键为 `src/Counter.sol`，`outputSelection` 为 `abi` 与 `storageLayout`（`without-layout.json` 只请求 `abi`）。检查 `errors` 中没有 `severity: "error"`，移除 stdout 的提示行后保存完整 JSON。 |
| Forge | 1.7.1，solc 0.8.28 | 将源码复制到临时项目的 `src/Counter.sol`，执行 `forge build --force --use /path/to/solc --extra-output storageLayout`，复制 `out/Counter.sol/Counter.json`；无布局用例省略 `--extra-output storageLayout`。 |
| Hardhat | 2.27.2，solc 0.8.28 | 将源码复制到临时项目的 `contracts/Counter.sol`，使用[配置](real-artifacts/hardhat.config.cjs)执行 `hardhat compile --force --config hardhat.config.cjs`；复制 `artifacts/build-info/*.json`，以及无布局用例的 `artifacts/contracts/Counter.sol/Counter.json`。 |

`real-solc-*`、`real-foundry-*` 和 `real-hardhat-*` 的旧端均由 `old.sol` 编译。兼容和不兼容用例的新端分别由对应源码编译；无布局用例的新端使用正常的旧版编译输出。上述命令只用于生成已提交的样例；运行检查器和测试无需安装这些工具或访问网络。

## 编译器 schema 矩阵

`schema-*` 各对用于检查不同编译器写出的字段形态：

- solc 0.5.17 会在 ABI 条目中把 `constant` 与 `payable` 写在 `stateMutability` 旁边。这些多余字段会被忽略，因此 0.5 的产物与其它版本一样可以解码。
- solc 0.6.12 与 0.8.28 只写 `stateMutability`。
- 在 `stateMutability` 出现之前的 ABI（0.4 时代）无法精确解码，因为 `constant` 区分不了
  `pure` 与 `view`。这类条目会被显式报错拒绝，而不是被猜测。
- 类型表中不认识的 `encoding` 会被拒绝，因为它可能改变字节的读取方式。

生成的 fixture 来自下面这份合约，由上述三个版本以 `abi` 与 `storageLayout` 作为
`outputSelection` 编译得到：

```solidity
pragma solidity ^VERSION;

contract Token {
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    uint8 private flags;
    uint8 private nextFlags;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function transfer(address to, uint256 value) public returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
}
```

三个版本为它生成的布局完全相同，因此这两对跨版本样例被期望是兼容的。源码属于本仓库；fixture 是它的编译产物。

transient storage 遵循与常规存储相同的规则，位于它自己的命名空间：诊断项使用
`transientStorage[...]` 作为位置，因此报告能区分这两个地址空间。没有报告 transient 布局的产物会被视为没有 transient 变量——Foundry 写出空布局时就是这个样子；把它与带有该布局的产物相比，
就会读成"删除"，因此用未开启 `transientStorageLayout` 输出选择的版本编译时会阻断，而不是悄悄通过。

重命名变量是本工具唯一一处刻意比 OpenZeppelin Upgrades Core 更宽松的地方：参考实现把重命名视为不安全（除非设置 `unsafeAllowRenames`），而这里字节留在原处，所以 `storage-renamed/` 报告警告并以 `0` 退出。详见[差分对比记录](../docs/oz-differential.md)。

包含多个合约的外层结构需要 `--contract NAME` 或 `--contract SOURCE:NAME`；不提供时会被报告为歧义，而不是被猜测。

ERC-7201 命名空间存储会被拒绝，而不是被假定兼容。命名空间通过其注释推导出的 slot 访问，而编译器在 `storageLayout` 中只列出状态变量，因此命名空间的成员不在输入里，其兼容性未知。

存储 gap 使用 `__gap` 定长数组约定：它覆盖的字节是未使用的，因此后续版本可以取用，前提是 gap 仍然结束在它原先结束的位置——这正是让声明在它之后的变量保持在原位的原因。三对 `storage-gap-*` 分别是该变化的安全版本、不安全版本，以及动态数组命名 `__gap` 时不适用的版本：动态数组的 slot 存放的是长度，不是保留字节。

三个子命令彼此独立，其中两对样例直接演示了这一点：

```bash
moon run cmd/moonupgradeguard -- abi fixtures/storage-removed/old.json fixtures/storage-removed/new.json
moon run cmd/moonupgradeguard -- storage fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json
```

两者都以 `0` 退出，尽管对这两对执行 `check` 都会以 `1` 退出。

## 手动运行一对样例

```bash
# 兼容：不输出任何内容并以 0 退出
moon run cmd/moonupgradeguard -- check fixtures/compatible/old.json fixtures/compatible/new.json

# 不兼容：输出移动并以 1 退出
moon run cmd/moonupgradeguard -- check fixtures/storage-moved/old.json fixtures/storage-moved/new.json

# 机器可读：诊断数组写在 stdout
moon run cmd/moonupgradeguard -- check fixtures/abi-function-removed/old.json fixtures/abi-function-removed/new.json --format json
```

`scripts/e2e.sh` 会把每一对样例交给构建出的 native 可执行文件运行，并核对退出码、应出现的诊断码、
JSON 合法性，以及同一输入两次运行是否产生完全一致的字节。
