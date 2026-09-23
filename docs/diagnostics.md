**简体中文** | [English](diagnostics.en.md)

# 诊断码手册

每个诊断项都带有下面某个诊断码。诊断码及其严重度在版本之间保持稳定，同一个字符串会出现在 JSON 报告的 `code` 字段里，因此流水线可以直接用它做过滤。

严重度决定**一次跑到底的比较**的结论：

- `Error` 阻断升级：比较完整执行并发现不兼容，CLI 以 `1` 退出，报告写在 stdout 上。
- `Warning` 与 `Info` 会被报告但不改变结论，因此只产生它们的升级仍然以 `0` 退出。

退出码 `2` 表示**分析未能完成**，它与严重度无关：`artifact.*` 诊断码描述无法读取、
或缺少某项操作所需数据的产物；`cli.*` 诊断码描述 CLI 无法使用的命令行或文件。这两类都是 `Error` 级，因为未完成的分析绝不能看起来兼容。未完成的报告里仍可能包含比较结论：
`check` 运行时若一边没有 ABI，存储会先被比较，随后 ABI 比较报告自己无法运行；反方向的情形是规范化失败——例如某个变量的 slot 不是十进制整数，会报告
`storage.entry.slot.invalid`，并在任何比较发生之前就以 `2` 退出。

位置相对于产生它的那一层所分析的值：提取层报告产物内部的路径，存储引擎报告它所比较的布局内部的路径（transient 命名空间为 `transientStorage[...]`），CLI 在无法读取文件时报告该文件路径。

CLI 对单侧输入产生的诊断添加 `input: "old"` 或 `input: "new"`；比较产生的诊断及命令行参数错误不带 `input`。两边都缺 ABI 时分别报告两条带来源的诊断。

本页共 41 个诊断码，由 `scripts/gen_diagnostics_doc.py` 从 `src/diagnostic.mbt` 生成。CI 会重新生成，并在提交内容与源码不一致时失败，因此新诊断码不可能没有文档。

| 诊断码 | 严重度 | 是否阻断 | 含义 |
| --- | --- | --- | --- |
| `abi.error.added` | Info | 否 | 自定义错误签名只出现在新 ABI 中。 |
| `abi.error.removed` | Error | 是 | 旧 ABI 中的自定义错误签名在新 ABI 中缺失。 |
| `abi.event.added` | Info | 否 | 事件签名只出现在新 ABI 中。 |
| `abi.event.anonymous.changed` | Error | 是 | 事件签名不变，但匿名性发生变化。 |
| `abi.event.indexed.changed` | Error | 是 | 事件签名不变，但 indexed 参数发生变化。 |
| `abi.event.removed` | Error | 是 | 旧 ABI 中的事件签名在新 ABI 中缺失。 |
| `abi.function.added` | Info | 否 | 函数签名只出现在新 ABI 中。 |
| `abi.function.mutability.changed` | Warning | 否 | 函数签名不变，但状态可变性发生变化。 |
| `abi.function.mutability.incompatible` | Error | 是 | 函数失去了现有调用方所依赖的状态可变性行为。 |
| `abi.function.outputs.changed` | Error | 是 | 函数签名不变，但返回类型列表发生变化。 |
| `abi.function.removed` | Error | 是 | 旧 ABI 中的函数签名在新 ABI 中缺失。 |
| `abi.signature.collision` | Error | 是 | 同一个 selector 或 event topic 在两个版本中属于不同的签名。 |
| `artifact.abi.missing` | Error | 是 | 需要比较 ABI 的操作拿到了一个不含 ABI 的产物。 |
| `artifact.contract.ambiguous` | Error | 是 | 产物中有多个合约带有存储布局。 |
| `artifact.contract.missing` | Error | 是 | 产物中没有合约匹配所请求的选择器。 |
| `artifact.field.invalid` | Error | 是 | 已识别的产物字段类型或取值不正确。 |
| `artifact.json.invalid` | Error | 是 | 产物文本不是合法 JSON。 |
| `artifact.layout.missing` | Error | 是 | 产物中没有存储布局。 |
| `artifact.namespaced-storage.unsupported` | Error | 是 | 产物提到 ERC-7201 命名空间存储，而该内容无法从编译产物中定位。 |
| `artifact.shape.ambiguous` | Error | 是 | 产物同时匹配多种已识别的外层形态。 |
| `artifact.shape.unsupported` | Error | 是 | 产物根节点不属于任何已识别的外层形态。 |
| `cli.argument.invalid` | Error | 是 | 命令行包含 CLI 不支持的内容。 |
| `cli.input.unreadable` | Error | 是 | CLI 无法读取输入文件。 |
| `storage.entry.added` | Info | 否 | 存储变量只出现在新布局中。 |
| `storage.entry.field.missing` | Error | 是 | 存储变量缺少必需字段。 |
| `storage.entry.label.changed` | Warning | 否 | 存储变量在同一位置、类型不变的情况下被重命名。 |
| `storage.entry.offset.changed` | Error | 是 | 存储变量在同一个 slot 内移动。 |
| `storage.entry.offset.invalid` | Error | 是 | 字节 offset 超出 slot 范围 `0..=31`。 |
| `storage.entry.removed` | Error | 是 | 旧布局中的存储变量在新布局中缺失。 |
| `storage.entry.slot.changed` | Error | 是 | 存储变量移动到了另一个 slot。 |
| `storage.entry.slot.invalid` | Error | 是 | slot 不是非负十进制整数。 |
| `storage.entry.type.changed` | Error | 是 | 存储变量位置不变，但语义类型发生变化。 |
| `storage.entry.type.missing` | Error | 是 | 存储变量引用的类型 id 在布局中不存在。 |
| `storage.gap.changed` | Info | 否 | 存储 gap 在结束位置不变的前提下被缩减、移动或占用。 |
| `storage.type.array-length.invalid` | Error | 是 | 定长数组的 label 未给出可用的十进制元素个数。 |
| `storage.type.encoding.unsupported` | Error | 是 | 存储类型使用了本版本不支持的编码。 |
| `storage.type.field.missing` | Error | 是 | 存储类型缺少必需字段。 |
| `storage.type.id.duplicate` | Error | 是 | 同一个存储类型 id 被定义多次。 |
| `storage.type.id.missing` | Error | 是 | 存储类型缺少编译器 id。 |
| `storage.type.reference.missing` | Error | 是 | 存储类型引用的另一个类型 id 在布局中不存在。 |
| `storage.type.size.invalid` | Error | 是 | `numberOfBytes` 不是十进制整数。 |
