///| Black-box tests for the storage compatibility engine.
///
/// Each rule has a fixture that exercises it, and the fixtures reuse the raw
/// layout helpers from `storage_normalize_test.mbt`, which is part of the same
/// test package.

///|
/// Normalizes two raw layouts and compares them.
fn storage_diff(
  old : @moonupgradeguard.RawStorageLayout,
  new : @moonupgradeguard.RawStorageLayout,
) -> Array[@moonupgradeguard.Diagnostic] raise {
  let (old_layout, old_diagnostics) = normalize(old)
  let (new_layout, new_diagnostics) = normalize(new)
  assert_eq(old_diagnostics.length(), 0, msg="old layout is not valid")
  assert_eq(new_diagnostics.length(), 0, msg="new layout is not valid")
  @moonupgradeguard.compare_storage(old_layout, new_layout)
}

///|
/// Renders the comparison of two raw layouts.
fn storage_report(
  old : @moonupgradeguard.RawStorageLayout,
  new : @moonupgradeguard.RawStorageLayout,
) -> String raise {
  @moonupgradeguard.render_text(storage_diff(old, new))
}

///|
/// The scalar type used by most fixtures.
fn uint256_type() -> @moonupgradeguard.RawStorageType {
  raw_type("t_uint256", "inplace", "uint256", "32")
}

///|
test "an unchanged layout is compatible" {
  let layout = raw_layout([raw_entry("x", "0", 0, "t_uint256")], [
    uint256_type(),
  ])
  inspect(storage_report(layout, layout), content="")
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(layout, layout)))
}

///|
test "appending a variable is compatible" {
  let old = raw_layout([raw_entry("x", "0", 0, "t_uint256")], [uint256_type()])
  let new = raw_layout(
    [raw_entry("x", "0", 0, "t_uint256"), raw_entry("y", "1", 0, "t_uint256")],
    [uint256_type()],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|info[storage.entry.added] fileA:A storage[1]: variable "y" was added at slot 1, offset 0 (new: y)
      #|
    ),
  )
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "an insertion that shifts existing data is incompatible" {
  let old = raw_layout([raw_entry("x", "0", 0, "t_uint256")], [uint256_type()])
  let new = raw_layout(
    [raw_entry("y", "0", 0, "t_uint256"), raw_entry("x", "1", 0, "t_uint256")],
    [uint256_type()],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|info[storage.entry.added] fileA:A storage[0]: variable "y" was added at slot 0, offset 0 (new: y)
      #|error[storage.entry.slot.changed] fileA:A storage[0]: variable "x" moved from slot 0 to slot 1 (old: 0, new: 1)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "an insertion into unused bytes is compatible" {
  let old = raw_layout(
    [raw_entry("a", "0", 0, "t_uint128"), raw_entry("b", "1", 0, "t_uint256")],
    [raw_type("t_uint128", "inplace", "uint128", "16"), uint256_type()],
  )
  let new = raw_layout(
    [
      raw_entry("a", "0", 0, "t_uint128"),
      raw_entry("c", "0", 16, "t_uint128"),
      raw_entry("b", "1", 0, "t_uint256"),
    ],
    [raw_type("t_uint128", "inplace", "uint128", "16"), uint256_type()],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|info[storage.entry.added] fileA:A storage[1]: variable "c" was added at slot 0, offset 16 (new: c)
      #|
    ),
  )
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a rename at the same position is a warning, not an error" {
  let old = raw_layout([raw_entry("owner", "0", 0, "t_uint256")], [
    uint256_type(),
  ])
  let new = raw_layout([raw_entry("admin", "0", 0, "t_uint256")], [
    uint256_type(),
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|warning[storage.entry.label.changed] fileA:A storage[0]: variable "owner" was renamed to "admin" without moving or changing type (old: owner, new: admin)
      #|
    ),
  )
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a rename that also changes type is a removal and an addition" {
  let old = raw_layout([raw_entry("owner", "0", 0, "t_uint256")], [
    uint256_type(),
  ])
  let new = raw_layout([raw_entry("admin", "0", 0, "t_uint128")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|info[storage.entry.added] fileA:A storage[0]: variable "admin" was added at slot 0, offset 0 (new: admin)
      #|error[storage.entry.removed] fileA:A storage[0]: variable "owner" at slot 0 is missing from the new layout (old: owner)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "deleting a variable is incompatible" {
  let old = raw_layout(
    [raw_entry("x", "0", 0, "t_uint256"), raw_entry("y", "1", 0, "t_uint256")],
    [uint256_type()],
  )
  let new = raw_layout([raw_entry("x", "0", 0, "t_uint256")], [uint256_type()])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.removed] fileA:A storage[1]: variable "y" at slot 1 is missing from the new layout (old: y)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "moving a variable to another slot is incompatible" {
  let old = raw_layout(
    [raw_entry("x", "0", 0, "t_uint256"), raw_entry("y", "1", 0, "t_uint256")],
    [uint256_type()],
  )
  let new = raw_layout(
    [raw_entry("x", "0", 0, "t_uint256"), raw_entry("y", "2", 0, "t_uint256")],
    [uint256_type()],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.slot.changed] fileA:A storage[1]: variable "y" moved from slot 1 to slot 2 (old: 1, new: 2)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "moving within a slot is incompatible" {
  let old = raw_layout([raw_entry("a", "0", 0, "t_uint128")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
  ])
  let new = raw_layout([raw_entry("a", "0", 8, "t_uint128")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.offset.changed] fileA:A storage[0]: variable "a" moved from offset 0 to offset 8 in slot 0 (old: 0, new: 8)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a width change is incompatible" {
  let old = raw_layout([raw_entry("x", "0", 0, "t_uint128")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
  ])
  let new = raw_layout([raw_entry("x", "0", 0, "t_uint256")], [uint256_type()])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "x" changed from "uint128" to "uint256" (old: uint128, new: uint256)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "an encoding change is incompatible" {
  let old = raw_layout([raw_entry("s", "0", 0, "t_string_storage")], [
    raw_type("t_string_storage", "bytes", "string", "32"),
  ])
  let new = raw_layout([raw_entry("s", "0", 0, "t_bytes_storage")], [
    raw_type("t_bytes_storage", "bytes", "bytes", "32"),
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "s" changed from "string" to "bytes" (old: string, new: bytes)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a recursive type change is incompatible even without moving" {
  let old = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "16"),
      members: Some([raw_entry("a", "0", 0, "t_uint128")]),
    },
  ])
  let new = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    uint256_type(),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "32"),
      members: Some([raw_entry("a", "0", 0, "t_uint256")]),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "s" changed: member "a": uint128 -> uint256 (old: struct { a: uint128 }, new: struct { a: uint256 })
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "adding a struct member is incompatible even when the bytes were unused" {
  let old = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "16"),
      members: Some([raw_entry("a", "0", 0, "t_uint128")]),
    },
  ])
  let new = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "32"),
      members: Some([
        raw_entry("a", "0", 0, "t_uint128"),
        raw_entry("b", "0", 16, "t_uint128"),
      ]),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "s" changed: member "b" was added (old: struct { a: uint128 }, new: struct { a: uint128, b: uint128 })
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a mapping value change is incompatible" {
  let old = raw_layout([raw_entry("m", "0", 0, "t_mapping")], [
    raw_type("t_uint256", "inplace", "uint256", "32"),
    raw_type("t_address", "inplace", "address", "20"),
    {
      ..raw_type("t_mapping", "mapping", "mapping(uint256 => address)", "32"),
      key: Some("t_uint256"),
      value: Some("t_address"),
    },
  ])
  let new = raw_layout([raw_entry("m", "0", 0, "t_mapping")], [
    raw_type("t_uint256", "inplace", "uint256", "32"),
    raw_type("t_bool", "inplace", "bool", "1"),
    {
      ..raw_type("t_mapping", "mapping", "mapping(uint256 => bool)", "32"),
      key: Some("t_uint256"),
      value: Some("t_bool"),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "m" changed from "mapping(uint256 => address)" to "mapping(uint256 => bool)" (old: mapping(uint256 => address), new: mapping(uint256 => bool))
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "an array length change is incompatible" {
  // Solidity slot-rounds both of these arrays to 32 bytes, so the element
  // count must be compared explicitly rather than inferred from byte size.
  let old = raw_layout(
    [raw_entry("a", "0", 0, "t_array(t_uint128)1_storage")],
    [
      raw_type("t_uint128", "inplace", "uint128", "16"),
      {
        ..raw_type("t_array(t_uint128)1_storage", "inplace", "uint128[1]", "32"),
        base: Some("t_uint128"),
      },
    ],
  )
  let new = raw_layout(
    [raw_entry("a", "0", 0, "t_array(t_uint128)2_storage")],
    [
      raw_type("t_uint128", "inplace", "uint128", "16"),
      {
        ..raw_type("t_array(t_uint128)2_storage", "inplace", "uint128[2]", "32"),
        base: Some("t_uint128"),
      },
    ],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "a" changed from "uint128[1]" to "uint128[2]" (old: uint128[1], new: uint128[2])
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "address payable stores exactly like address" {
  let old = raw_layout([raw_entry("to", "0", 0, "t_address")], [
    raw_type("t_address", "inplace", "address", "20"),
  ])
  let new = raw_layout([raw_entry("to", "0", 0, "t_address_payable")], [
    raw_type("t_address_payable", "inplace", "address payable", "20"),
  ])
  inspect(storage_report(old, new), content="")
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a contract-typed variable stores exactly like address" {
  let old = raw_layout([raw_entry("token", "0", 0, "t_address")], [
    raw_type("t_address", "inplace", "address", "20"),
  ])
  let new = raw_layout([raw_entry("token", "0", 0, "t_contract(IERC20)7")], [
    raw_type("t_contract(IERC20)7", "inplace", "contract IERC20", "20"),
  ])
  inspect(storage_report(old, new), content="")
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a self-referential type that did not change is compatible" {
  let types = [
    raw_type("t_uint256", "inplace", "uint256", "32"),
    {
      ..raw_type("t_struct(Node)1_storage", "inplace", "struct A.Node", "32"),
      members: Some([
        raw_entry(
          "next", "0", 0, "t_mapping(t_uint256,t_struct(Node)1_storage)",
        ),
      ]),
    },
    {
      ..raw_type(
        "t_mapping(t_uint256,t_struct(Node)1_storage)", "mapping", "mapping(uint256 => struct A.Node)",
        "32",
      ),
      key: Some("t_uint256"),
      value: Some("t_struct(Node)1_storage"),
    },
  ]
  let old = raw_layout(
    [raw_entry("node", "0", 0, "t_struct(Node)1_storage")],
    types,
  )
  let new = raw_layout(
    [raw_entry("node", "0", 0, "t_struct(Node)1_storage")],
    types,
  )
  inspect(storage_report(old, new), content="")
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a self-referential type that changed is incompatible" {
  // Both versions keep the variable in place; only the struct behind the
  // recursive mapping changes.
  let old = raw_layout([raw_entry("node", "0", 0, "t_struct(Node)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    raw_type("t_uint256", "inplace", "uint256", "32"),
    {
      ..raw_type("t_struct(Node)1_storage", "inplace", "struct A.Node", "16"),
      members: Some([
        raw_entry(
          "next", "0", 0, "t_mapping(t_uint256,t_struct(Node)1_storage)",
        ),
      ]),
    },
    {
      ..raw_type(
        "t_mapping(t_uint256,t_struct(Node)1_storage)", "mapping", "mapping(uint256 => struct A.Node)",
        "32",
      ),
      key: Some("t_uint256"),
      value: Some("t_struct(Node)1_storage"),
    },
  ])
  let new = raw_layout([raw_entry("node", "0", 0, "t_struct(Node)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    raw_type("t_uint256", "inplace", "uint256", "32"),
    // The struct gains a member, so the recursive type differs even though the
    // variable stayed in place.
    {
      ..raw_type("t_struct(Node)1_storage", "inplace", "struct A.Node", "32"),
      members: Some([
        raw_entry(
          "next", "0", 0, "t_mapping(t_uint256,t_struct(Node)1_storage)",
        ),
        raw_entry("extra", "1", 0, "t_uint128"),
      ]),
    },
    {
      ..raw_type(
        "t_mapping(t_uint256,t_struct(Node)1_storage)", "mapping", "mapping(uint256 => struct A.Node)",
        "32",
      ),
      key: Some("t_uint256"),
      value: Some("t_struct(Node)1_storage"),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "node" changed: member "extra" was added (old: struct { next: mapping(uint256 => struct { next: ... }) }, new: struct { next: mapping(uint256 => struct { next: ..., extra: ... }), extra: uint128 })
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "moving a variable between contracts is not reported" {
  let old = raw_layout(
    [{ ..raw_entry("x", "0", 0, "t_uint256"), contract: Some("fileA:Base"), }],
    [uint256_type()],
  )
  let new = raw_layout(
    [
      {
        ..raw_entry("x", "0", 0, "t_uint256"),
        contract: Some("fileA:Derived"),
      },
    ],
    [uint256_type()],
  )
  inspect(storage_report(old, new), content="")
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a struct member rename is reported as a type change" {
  let old = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "16"),
      members: Some([raw_entry("a", "0", 0, "t_uint128")]),
    },
  ])
  let new = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "16"),
      members: Some([raw_entry("b", "0", 0, "t_uint128")]),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "s" changed: member "a" was renamed to "b" (old: struct { a: uint128 }, new: struct { b: uint128 })
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a nested member type change names the member that changed" {
  let old = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    uint256_type(),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "48"),
      members: Some([
        raw_entry("a", "0", 0, "t_uint128"),
        raw_entry("b", "0", 16, "t_uint128"),
        raw_entry("c", "1", 0, "t_uint256"),
      ]),
    },
  ])
  let new = raw_layout([raw_entry("s", "0", 0, "t_struct(S)1_storage")], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    uint256_type(),
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct A.S", "48"),
      members: Some([
        raw_entry("a", "0", 0, "t_uint128"),
        raw_entry("b", "0", 16, "t_uint256"),
        raw_entry("c", "1", 0, "t_uint256"),
      ]),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "s" changed: member "b": uint128 -> uint256 (old: struct { a: uint128, b: uint128, c: uint256 }, new: struct { a: uint128, b: uint256, c: uint256 })
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
/// A fixed-size `uint256` array type with `length` slots.
fn gap_type(id : String, length : Int) -> @moonupgradeguard.RawStorageType {
  {
    ..raw_type(id, "inplace", "uint256[\{length}]", (length * 32).to_string()),
    base: Some("t_uint256"),
  }
}

///|
test "a storage gap that shrinks and is refilled is compatible" {
  let old = raw_layout(
    [
      raw_entry("a", "0", 0, "t_uint256"),
      raw_entry("__gap", "1", 0, "t_array(t_uint256)3_storage"),
      raw_entry("tail", "4", 0, "t_uint256"),
    ],
    [uint256_type(), gap_type("t_array(t_uint256)3_storage", 3)],
  )
  let new = raw_layout(
    [
      raw_entry("a", "0", 0, "t_uint256"),
      raw_entry("b", "1", 0, "t_uint256"),
      raw_entry("__gap", "2", 0, "t_array(t_uint256)2_storage"),
      raw_entry("tail", "4", 0, "t_uint256"),
    ],
    [uint256_type(), gap_type("t_array(t_uint256)2_storage", 2)],
  )
  inspect(
    storage_report(old, new),
    content=(
      #|info[storage.entry.added] fileA:A storage[1]: variable "b" was added at slot 1, offset 0 (new: b)
      #|info[storage.gap.changed] fileA:A storage[1]: storage gap "__gap" changed from "uint256[3]" to "uint256[2]", ending at the same position (old: uint256[3], new: uint256[2])
      #|
    ),
  )
  assert_true(!@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a gap whose end moved is a type change, not a resize" {
  let old = raw_layout([raw_entry("__gap", "1", 0, "t_gap_3")], [
    uint256_type(),
    gap_type("t_gap_3", 3),
  ])
  // Same slot, two slots shorter: the freed bytes are not trailing, so the gap
  // no longer ends where it did and the safe rule does not apply.
  let new = raw_layout([raw_entry("__gap", "1", 0, "t_gap_2")], [
    uint256_type(),
    gap_type("t_gap_2", 2),
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "__gap" changed from "uint256[3]" to "uint256[2]" (old: uint256[3], new: uint256[2])
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a mapping named __gap is compared like any other variable" {
  let old = raw_layout([raw_entry("__gap", "0", 0, "t_mapping")], [
    uint256_type(),
    {
      ..raw_type("t_mapping", "mapping", "mapping(uint256 => uint256)", "32"),
      key: Some("t_uint256"),
      value: Some("t_uint256"),
    },
  ])
  let new = raw_layout([raw_entry("__gap", "1", 0, "t_mapping")], [
    uint256_type(),
    {
      ..raw_type("t_mapping", "mapping", "mapping(uint256 => uint256)", "32"),
      key: Some("t_uint256"),
      value: Some("t_uint256"),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.slot.changed] fileA:A storage[0]: variable "__gap" moved from slot 0 to slot 1 (old: 0, new: 1)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a gap with a different element type is not accepted" {
  let old = raw_layout([raw_entry("__gap", "1", 0, "t_gap_u256")], [
    uint256_type(),
    gap_type("t_gap_u256", 4),
  ])
  let new = raw_layout([raw_entry("__gap", "1", 0, "t_gap_bytes32")], [
    raw_type("t_bytes32", "inplace", "bytes32", "32"),
    {
      ..raw_type("t_gap_bytes32", "inplace", "bytes32[4]", "128"),
      base: Some("t_bytes32"),
    },
  ])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.type.changed] fileA:A storage[0]: storage type of "__gap" changed from "uint256[4]" to "bytes32[4]" (old: uint256[4], new: bytes32[4])
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a gap that disappears is a removal" {
  let old = raw_layout([raw_entry("__gap", "0", 0, "t_gap_2")], [
    uint256_type(),
    gap_type("t_gap_2", 2),
  ])
  let new = raw_layout([], [])
  inspect(
    storage_report(old, new),
    content=(
      #|error[storage.entry.removed] fileA:A storage[0]: variable "__gap" at slot 0 is missing from the new layout (old: __gap)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(storage_diff(old, new)))
}

///|
test "a transient variable that moves is reported in its own namespace" {
  let old = raw_layout([raw_entry("lock", "0", 0, "t_uint256")], [
    uint256_type(),
  ])
  let new = raw_layout([raw_entry("lock", "1", 0, "t_uint256")], [
    uint256_type(),
  ])
  let (old_layout, old_diagnostics) = normalize(old)
  let (new_layout, new_diagnostics) = normalize(new)
  assert_eq(old_diagnostics.length(), 0)
  assert_eq(new_diagnostics.length(), 0)
  let diff = @moonupgradeguard.compare_transient(old_layout, new_layout)
  inspect(
    @moonupgradeguard.render_text(diff),
    content=(
      #|error[storage.entry.slot.changed] fileA:A transientStorage[0]: variable "lock" moved from slot 0 to slot 1 (old: 0, new: 1)
      #|
    ),
  )
  assert_true(@moonupgradeguard.blocks_upgrade(diff))
}
