[English](guide.en.md) | **简体中文**

# 从编译产物到升级报告

这篇教程用仓库自带的真实 solc 编译产物完成一次升级预检，并说明如何把自己的产物接进来。MoonUpgradeGuard 只比较产物中的存储布局和 ABI：它不编译源码、不连接链，也不能证明业务逻辑或整个升级安全。命令与输出示例可在本仓库复现。

## 1. 取得可比较的产物

升级前后的文件都必须包含目标合约的 `storageLayout`；若要比较 ABI，也要保留 `abi`。保存完整编译产物，不要只截取某个字段。下表给出本仓库已验证的获取途径：

| 来源 | 保留什么 |
| --- | --- |
| solc Standard JSON | 在 `settings.outputSelection` 中请求 `abi` 与 `storageLayout`，保存完整编译器输出；需要 transient storage 时也请求 `transientStorageLayout`。参见 [Solidity 编译器文档](https://docs.soliditylang.org/en/v0.8.28/using-the-compiler.html)。 |
| Foundry | 使用 `forge build --extra-output storageLayout` 生成带布局的平铺 artifact，取 `out/<source>/<contract>.json`；仓库的[真实产物样例](../fixtures/README.md#真实产物矩阵)记录了固定版本的命令。 |
| Hardhat | 在 Solidity `outputSelection` 中请求布局，取 `artifacts/build-info/*.json`；单合约 artifact 通常不含布局。本仓库提供[已验证的配置](../fixtures/real-artifacts/hardhat.config.cjs)。 |

例如，将以下完整的 solc 0.8.28 Standard JSON 输入保存为 `input.json`，然后用 `solc --standard-json < input.json > old.json` 保存完整输出；新版替换 `sources` 中的源码后同样编译并保存为 `new.json`。若编译器报告错误，先修正源码或配置，不能把有错误的输出当作可比较产物。

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

从两个版本中选同一个合约。Standard JSON 和 build info 可能含多个合约，此时使用 `--contract NAME` 或 `--contract SOURCE:NAME`；省略选择器造成的歧义会以退出码 `2` 报告。更多输入形态与限制见 [README 的输入章节](../README.md#输入)。

## 2. 跑一次兼容检查

安装 [MoonBit](https://www.moonbitlang.com/) 后克隆仓库，从仓库根目录运行以下命令。首次构建可能需要填充 MoonBit 模块缓存。也可以从 [Releases](https://github.com/snorfyang/moon-upgrade-guard/releases/latest) 下载原生可执行文件，把下方的 `moon run src/cmd/moonupgradeguard --` 换成其路径。

```bash
git clone https://github.com/snorfyang/moon-upgrade-guard.git
cd moon-upgrade-guard
moon update
moon build --target native
```

`real-solc-compatible` 中，新版 `Counter` 只添加变量和函数，因此产生信息级诊断，退出码仍为 `0`：

```console
$ moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-compatible/old.json fixtures/real-solc-compatible/new.json --contract Counter
info[abi.function.added] abi.functions: function "extra()" was added to the new ABI (new: extra())
info[storage.entry.added] src/Counter.sol:Counter storage[1]: variable "extra" was added at slot 1, offset 0 (new: extra)
$ echo $?
0
```

`check` 同时比较存储与两侧均存在的 ABI；`storage` 和 `abi` 可分别检查单层。这里的 `0` 只表示没有发现阻断性不兼容，不等于升级已通过审计。

## 3. 读懂不兼容报告

`real-solc-incompatible` 将 `value` 从 `uint256` 缩为 `uint128`。既有存储值的解释会变，`value()` 的返回类型也会变，因此两层都报错：

```console
$ moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-incompatible/old.json fixtures/real-solc-incompatible/new.json --contract Counter
error[abi.function.outputs.changed] abi.functions["value()"].outputs: function "value()" changed its output types from "uint256" to "uint128" (old: uint256, new: uint128)
error[storage.entry.type.changed] src/Counter.sol:Counter storage[0]: storage type of "value" changed from "uint256" to "uint128" (old: uint256, new: uint128)
$ echo $?
1
```

每行从左到右给出严重度、稳定诊断码、位置、说明和可用的旧值/新值。`Error` 会阻断；`Warning` 要人工复核；`Info` 表示新增等非阻断变化。各代码的精确定义见[诊断码手册](diagnostics.md)，更多覆盖打包、mapping、struct、gap 与 transient storage 的真实案例见[产物样例](../fixtures/README.md)。

这里的 `storage[0]` 指规范化布局的第一个变量，不是 Solidity 源码行号；`old: uint256, new: uint128` 指向需要复核的具体类型变化。

## 4. 机器可读报告与 CI

加上 `--format json` 后，stdout 始终是一个 JSON 诊断数组；`code` 适合自动化判断，`message` 适合人读，`location` 和 `oldValue`/`newValue` 帮助定位。由单侧输入引起的错误另有 `input: "old"` 或 `input: "new"`；跨版本比较诊断不带这个字段。

```bash
moon run src/cmd/moonupgradeguard -- check fixtures/real-solc-incompatible/old.json fixtures/real-solc-incompatible/new.json --contract Counter --format json
```

例如，报告中的存储诊断包含稳定代码、位置及两侧类型；完整数组还会有上面看到的 ABI 诊断：

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

在 CI 中让退出码直接决定步骤是否通过；不要把 `1` 或 `2` 转成成功，也不要只搜索输出文字：

```yaml
- name: upgrade compatibility
  run: |
    moon build --target native
    _build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe \
      check build/old.json build/new.json --contract Counter --format json
```

把 `build/old.json`、`build/new.json` 和 `Counter` 换成流水线实际生成的产物与合约选择器。不要把私钥或无法公开的部署资料放进诊断样例。

## 5. 区分不兼容与无法分析

`1` 表示完成比较后发现阻断问题；`2` 表示文件、选择器或 schema 无法分析，不应被当成“兼容”。下面旧产物的 JSON 被截断，因此报告会标出 `input: "old"`：

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

如果看到缺少布局，先确认保存的是包含 `storageLayout` 的编译输出，尤其不要把 Hardhat 单合约 artifact 当作 build info。如果提示合约选择歧义，加上 `--contract`；若是未知编码或不支持的命名空间，不要绕过错误继续部署。预检之外仍需审查授权、初始化、业务逻辑与部署流程。
