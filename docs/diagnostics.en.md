[简体中文](diagnostics.md) | **English**

# Diagnostics reference

Every finding carries one of the codes below. A code and its severity are
stable across releases, and the same string appears in the `code` field of
the JSON report, so a pipeline can filter on it.

Severity decides the verdict of a comparison that ran to the end:

- `Error` blocks the upgrade: the comparison completed and found an
  incompatibility, and the CLI exits `1` with the report on stdout.
- `Warning` and `Info` are reported without changing the verdict, so an
  upgrade that only produces them still exits `0`.

Exit code `2` means the analysis could not be completed, and it does not
follow from severity: an `artifact.*` code describes an artifact that could
not be read or that carries no data an operation needs, and a `cli.*` code
describes a command line or a file the CLI could not use. Both families
carry `Error` severity, because a run that could not be completed must not
look compatible. An incomplete report can still contain comparison
findings: when `check` runs and one artifact has no ABI, storage is
compared first and the ABI comparison then reports that it could not run.
Normalization failures work the other way round: a variable whose slot is
not a decimal integer is reported with `storage.entry.slot.invalid`, and
the run exits `2` before any comparison happens.

Locations are relative to the value the reporting layer analysed:
extraction reports paths inside the artifact, the storage engine reports
paths inside the layout it compared — including `transientStorage[...]` for
the transient namespace — and the CLI reports the file path when it cannot
read one.

The CLI adds `input: "old"` or `input: "new"` to findings produced by one
artifact. Comparison findings and command-line argument errors omit `input`.
When both artifacts lack an ABI, each gets its own attributed finding.

This page lists 41 codes and is generated from `src/diagnostic.mbt` by `scripts/gen_diagnostics_doc.py`. CI regenerates it and fails when the committed copy differs, so a new code cannot ship undocumented.

| code | severity | blocks | meaning |
| --- | --- | --- | --- |
| `abi.error.added` | Info | no | A custom error signature appears only in the new ABI. |
| `abi.error.removed` | Error | yes | A custom error signature of the old ABI is absent from the new ABI. |
| `abi.event.added` | Info | no | An event signature appears only in the new ABI. |
| `abi.event.anonymous.changed` | Error | yes | An event kept its signature but changed its anonymity. |
| `abi.event.indexed.changed` | Error | yes | An event kept its signature but changed which parameters are indexed. |
| `abi.event.removed` | Error | yes | An event signature of the old ABI is absent from the new ABI. |
| `abi.function.added` | Info | no | A function signature appears only in the new ABI. |
| `abi.function.mutability.changed` | Warning | no | A function kept its signature but changed state mutability. |
| `abi.function.mutability.incompatible` | Error | yes | A function lost mutability behavior that existing callers rely on. |
| `abi.function.outputs.changed` | Error | yes | A function kept its signature but changed its output types. |
| `abi.function.removed` | Error | yes | A function signature of the old ABI is absent from the new ABI. |
| `abi.signature.collision` | Error | yes | A selector or event topic is used by different signatures in the two versions. |
| `artifact.abi.missing` | Error | yes | An operation that compares ABI data received an artifact without an ABI. |
| `artifact.contract.ambiguous` | Error | yes | More than one contract in the artifact carries a storage layout. |
| `artifact.contract.missing` | Error | yes | No contract in the artifact matches the requested selector. |
| `artifact.field.invalid` | Error | yes | A recognized artifact field has the wrong JSON type or value. |
| `artifact.json.invalid` | Error | yes | The artifact text is not valid JSON. |
| `artifact.layout.missing` | Error | yes | The artifact carries no storage layout. |
| `artifact.namespaced-storage.unsupported` | Error | yes | The artifact mentions ERC-7201 namespaced storage, which cannot be located from compiler output. |
| `artifact.shape.ambiguous` | Error | yes | The artifact matches more than one recognized wrapper shape. |
| `artifact.shape.unsupported` | Error | yes | The artifact root is not one of the recognized wrapper shapes. |
| `cli.argument.invalid` | Error | yes | The command line names something the CLI does not support. |
| `cli.input.unreadable` | Error | yes | The CLI could not read an input file. |
| `storage.entry.added` | Info | no | A storage variable appears only in the new layout. |
| `storage.entry.field.missing` | Error | yes | A storage variable is missing a required field. |
| `storage.entry.label.changed` | Warning | no | A storage variable was renamed without moving or changing type. |
| `storage.entry.offset.changed` | Error | yes | A storage variable moved within its slot. |
| `storage.entry.offset.invalid` | Error | yes | A storage byte offset is outside the slot range `0..=31`. |
| `storage.entry.removed` | Error | yes | A storage variable of the old layout is absent from the new layout. |
| `storage.entry.slot.changed` | Error | yes | A storage variable moved to a different slot. |
| `storage.entry.slot.invalid` | Error | yes | A storage slot is not a non-negative decimal integer. |
| `storage.entry.type.changed` | Error | yes | A storage variable kept its position but changed semantic type. |
| `storage.entry.type.missing` | Error | yes | A storage variable references a type id that the layout does not define. |
| `storage.gap.changed` | Info | no | A storage gap was resized, moved, or consumed while keeping its end position. |
| `storage.type.array-length.invalid` | Error | yes | A fixed-array label does not carry a usable decimal element count. |
| `storage.type.encoding.unsupported` | Error | yes | A storage type uses an encoding this version does not support. |
| `storage.type.field.missing` | Error | yes | A storage type is missing a required field. |
| `storage.type.id.duplicate` | Error | yes | A storage type id is defined more than once. |
| `storage.type.id.missing` | Error | yes | A storage type is missing its compiler id. |
| `storage.type.reference.missing` | Error | yes | A storage type references another type id that the layout does not define. |
| `storage.type.size.invalid` | Error | yes | A `numberOfBytes` value is not a decimal integer. |
