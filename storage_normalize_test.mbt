///| Black-box tests for storage-layout normalization.
///
/// The fixture shapes follow the `storageLayout` format documented by the
/// Solidity compiler at
/// <https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html>.
/// The fixtures themselves were written for these tests.

///|
fn raw_entry(
  label : String,
  slot : String,
  offset : Int,
  type_id : String,
) -> @moonupgradeguard.RawStorageEntry {
  {
    label: Some(label),
    contract: Some("fileA:A"),
    slot: Some(slot),
    offset: Some(offset),
    type_id: Some(type_id),
  }
}

///|
fn raw_type(
  id : String,
  encoding : String,
  label : String,
  size : String,
) -> @moonupgradeguard.RawStorageType {
  {
    id: Some(id),
    encoding: Some(encoding),
    label: Some(label),
    number_of_bytes: Some(size),
    base: None,
    key: None,
    value: None,
    members: None,
  }
}

///|
fn raw_layout(
  storage : Array[@moonupgradeguard.RawStorageEntry],
  types : Array[@moonupgradeguard.RawStorageType],
) -> @moonupgradeguard.RawStorageLayout {
  { storage, types, }
}

///|
fn normalize(
  raw : @moonupgradeguard.RawStorageLayout,
) -> (@moonupgradeguard.StorageLayout, Array[@moonupgradeguard.Diagnostic]) {
  @moonupgradeguard.normalize_layout(raw)
}

///|
fn slot(text : String) -> @moonupgradeguard.Slot {
  match @moonupgradeguard.Slot::parse(text) {
    Some(slot) => slot
    None => abort("slot \"\{text}\" is not parseable")
  }
}

///|
fn type_entry(
  layout : @moonupgradeguard.StorageLayout,
  id : String,
) -> @moonupgradeguard.TypeEntry {
  match layout.find_type(id) {
    Some(entry) => entry
    None => abort("storage type \"\{id}\" is missing")
  }
}

///|
fn type_shape(
  layout : @moonupgradeguard.StorageLayout,
  id : String,
) -> @moonupgradeguard.TypeShape {
  type_entry(layout, id).shape
}

///|
test "slot parsing normalizes digits and rejects non-numbers" {
  assert_eq(slot("0").to_string(), "0")
  assert_eq(slot("7").to_string(), "7")
  assert_eq(slot("007").to_string(), "7")
  assert_true(@moonupgradeguard.Slot::parse("") is None)
  assert_true(@moonupgradeguard.Slot::parse("-1") is None)
  assert_true(@moonupgradeguard.Slot::parse("0x1f") is None)
  assert_true(@moonupgradeguard.Slot::parse("1 000") is None)
}

///|
test "unbounded slots survive normalization and order numerically" {
  let max = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  let raw = raw_layout(
    [
      raw_entry("huge", max, 0, "t_uint256"),
      raw_entry("ten", "10", 0, "t_uint256"),
      raw_entry("nine", "9", 0, "t_uint256"),
    ],
    [raw_type("t_uint256", "inplace", "uint256", "32")],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(layout.entries[0].slot.to_string(), max)
  assert_true(layout.entries[0].slot > layout.entries[1].slot)
  assert_true(layout.entries[1].slot > layout.entries[2].slot)
}

///|
test "packed scalars keep their slot and byte offset" {
  let raw = raw_layout(
    [
      raw_entry("x", "0", 0, "t_uint256"),
      raw_entry("a", "1", 0, "t_uint128"),
      raw_entry("b", "1", 16, "t_uint128"),
    ],
    [
      raw_type("t_uint128", "inplace", "uint128", "16"),
      raw_type("t_uint256", "inplace", "uint256", "32"),
    ],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(layout.entries.length(), 3)
  assert_eq(layout.entries[1].slot.to_string(), "1")
  assert_eq(layout.entries[1].offset, 0)
  assert_eq(layout.entries[2].offset, 16)
  assert_eq(type_entry(layout, "t_uint128").byte_size, 16)
  assert_eq(type_shape(layout, "t_uint128"), @moonupgradeguard.TypeShape::Value)
  debug_inspect(
    layout,
    content=(
      #|{
      #|  entries: [
      #|    {
      #|      label: "x",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "0" },
      #|      offset: 0,
      #|      type_id: "t_uint256",
      #|    },
      #|    {
      #|      label: "a",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "1" },
      #|      offset: 0,
      #|      type_id: "t_uint128",
      #|    },
      #|    {
      #|      label: "b",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "1" },
      #|      offset: 16,
      #|      type_id: "t_uint128",
      #|    },
      #|  ],
      #|  types: [
      #|    { id: "t_uint128", label: "uint128", byte_size: 16, shape: Value },
      #|    { id: "t_uint256", label: "uint256", byte_size: 32, shape: Value },
      #|  ],
      #|}
    ),
  )
}

///|
test "mappings, arrays, and byte strings become structural shapes" {
  let raw = raw_layout(
    [
      raw_entry("m", "0", 0, "t_mapping(t_uint256,t_address)"),
      raw_entry("dyn", "1", 0, "t_array(t_uint8)dyn_storage"),
      raw_entry("fixed", "2", 0, "t_array(t_uint8)3_storage"),
      raw_entry("s", "3", 0, "t_string_storage"),
    ],
    [
      raw_type("t_uint8", "inplace", "uint8", "1"),
      raw_type("t_address", "inplace", "address", "20"),
      raw_type("t_uint256", "inplace", "uint256", "32"),
      {
        ..raw_type(
          "t_mapping(t_uint256,t_address)", "mapping", "mapping(uint256 => address)",
          "32",
        ),
        key: Some("t_uint256"),
        value: Some("t_address"),
      },
      {
        ..raw_type(
          "t_array(t_uint8)dyn_storage", "dynamic_array", "uint8[]", "32",
        ),
        base: Some("t_uint8"),
      },
      {
        ..raw_type("t_array(t_uint8)3_storage", "inplace", "uint8[3]", "32"),
        base: Some("t_uint8"),
      },
      raw_type("t_string_storage", "bytes", "string", "32"),
    ],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(
    type_shape(layout, "t_mapping(t_uint256,t_address)"),
    @moonupgradeguard.TypeShape::Mapping("t_uint256", "t_address"),
  )
  assert_eq(
    type_shape(layout, "t_array(t_uint8)dyn_storage"),
    @moonupgradeguard.TypeShape::DynamicArray("t_uint8"),
  )
  assert_eq(
    type_shape(layout, "t_array(t_uint8)3_storage"),
    @moonupgradeguard.TypeShape::StaticArray("t_uint8", "3"),
  )
  assert_eq(
    type_shape(layout, "t_string_storage"),
    @moonupgradeguard.TypeShape::Bytes,
  )
  assert_eq(type_entry(layout, "t_array(t_uint8)3_storage").byte_size, 32)
  debug_inspect(
    layout,
    content=(
      #|{
      #|  entries: [
      #|    {
      #|      label: "m",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "0" },
      #|      offset: 0,
      #|      type_id: "t_mapping(t_uint256,t_address)",
      #|    },
      #|    {
      #|      label: "dyn",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "1" },
      #|      offset: 0,
      #|      type_id: "t_array(t_uint8)dyn_storage",
      #|    },
      #|    {
      #|      label: "fixed",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "2" },
      #|      offset: 0,
      #|      type_id: "t_array(t_uint8)3_storage",
      #|    },
      #|    {
      #|      label: "s",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "3" },
      #|      offset: 0,
      #|      type_id: "t_string_storage",
      #|    },
      #|  ],
      #|  types: [
      #|    { id: "t_uint8", label: "uint8", byte_size: 1, shape: Value },
      #|    { id: "t_address", label: "address", byte_size: 20, shape: Value },
      #|    { id: "t_uint256", label: "uint256", byte_size: 32, shape: Value },
      #|    {
      #|      id: "t_string_storage",
      #|      label: "string",
      #|      byte_size: 32,
      #|      shape: Bytes,
      #|    },
      #|    {
      #|      id: "t_array(t_uint8)3_storage",
      #|      label: "uint8[3]",
      #|      byte_size: 32,
      #|      shape: StaticArray("t_uint8", "3"),
      #|    },
      #|    {
      #|      id: "t_array(t_uint8)dyn_storage",
      #|      label: "uint8[]",
      #|      byte_size: 32,
      #|      shape: DynamicArray("t_uint8"),
      #|    },
      #|    {
      #|      id: "t_mapping(t_uint256,t_address)",
      #|      label: "mapping(uint256 => address)",
      #|      byte_size: 32,
      #|      shape: Mapping("t_uint256", "t_address"),
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "struct members keep relative slots and offsets" {
  let raw = raw_layout(
    [raw_entry("point", "0", 0, "t_struct(Point)10_storage")],
    [
      raw_type("t_uint128", "inplace", "uint128", "16"),
      {
        ..raw_type(
          "t_struct(Point)10_storage", "inplace", "struct A.Point", "48",
        ),
        members: Some([
          raw_entry("x", "0", 0, "t_uint128"),
          raw_entry("y", "0", 16, "t_uint128"),
          raw_entry("z", "1", 0, "t_uint128"),
        ]),
      },
    ],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(type_entry(layout, "t_struct(Point)10_storage").byte_size, 48)
  match type_shape(layout, "t_struct(Point)10_storage") {
    @moonupgradeguard.TypeShape::Struct(members) => {
      assert_eq(members.length(), 3)
      assert_eq(members[1].offset, 16)
      assert_eq(members[2].slot.to_string(), "1")
    }
    _ => fail("expected a struct shape")
  }
  debug_inspect(
    layout,
    content=(
      #|{
      #|  entries: [
      #|    {
      #|      label: "point",
      #|      contract: Some("fileA:A"),
      #|      slot: { digits: "0" },
      #|      offset: 0,
      #|      type_id: "t_struct(Point)10_storage",
      #|    },
      #|  ],
      #|  types: [
      #|    { id: "t_uint128", label: "uint128", byte_size: 16, shape: Value },
      #|    {
      #|      id: "t_struct(Point)10_storage",
      #|      label: "struct A.Point",
      #|      byte_size: 48,
      #|      shape: Struct(
      #|        [
      #|          {
      #|            label: "x",
      #|            contract: Some("fileA:A"),
      #|            slot: { digits: "0" },
      #|            offset: 0,
      #|            type_id: "t_uint128",
      #|          },
      #|          {
      #|            label: "y",
      #|            contract: Some("fileA:A"),
      #|            slot: { digits: "0" },
      #|            offset: 16,
      #|            type_id: "t_uint128",
      #|          },
      #|          {
      #|            label: "z",
      #|            contract: Some("fileA:A"),
      #|            slot: { digits: "1" },
      #|            offset: 0,
      #|            type_id: "t_uint128",
      #|          },
      #|        ],
      #|      ),
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "a type that refers to itself normalizes without looping" {
  let raw = raw_layout([raw_entry("node", "0", 0, "t_struct(Node)1_storage")], [
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
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(layout.types.length(), 3)
  assert_eq(layout.entries.length(), 1)
}

///|
test "inherited variables keep their emitting contract" {
  let raw = raw_layout(
    [
      {
        ..raw_entry("baseValue", "0", 0, "t_uint256"),
        contract: Some("fileA:Base"),
      },
      {
        ..raw_entry("derivedValue", "1", 0, "t_uint256"),
        contract: Some("fileA:Derived"),
      },
    ],
    [raw_type("t_uint256", "inplace", "uint256", "32")],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(diagnostics.length(), 0)
  assert_eq(layout.entries[0].contract, Some("fileA:Base"))
  assert_eq(layout.entries[1].contract, Some("fileA:Derived"))
  debug_inspect(
    layout,
    content=(
      #|{
      #|  entries: [
      #|    {
      #|      label: "baseValue",
      #|      contract: Some("fileA:Base"),
      #|      slot: { digits: "0" },
      #|      offset: 0,
      #|      type_id: "t_uint256",
      #|    },
      #|    {
      #|      label: "derivedValue",
      #|      contract: Some("fileA:Derived"),
      #|      slot: { digits: "1" },
      #|      offset: 0,
      #|      type_id: "t_uint256",
      #|    },
      #|  ],
      #|  types: [{ id: "t_uint256", label: "uint256", byte_size: 32, shape: Value }],
      #|}
    ),
  )
}

///|
test "an invalid slot is reported and the entry is dropped" {
  let raw = raw_layout([raw_entry("x", "0x1f", 0, "t_uint256")], [
    raw_type("t_uint256", "inplace", "uint256", "32"),
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.entries.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.entry.slot.invalid] fileA:A storage[0].slot: slot "0x1f" is not a non-negative decimal integer
      #|
    ),
  )
}

///|
test "a missing required field is reported" {
  let raw = raw_layout(
    [{ ..raw_entry("x", "0", 0, "t_uint256"), offset: None, }],
    [raw_type("t_uint256", "inplace", "uint256", "32")],
  )
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.entries.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.entry.field.missing] fileA:A storage[0].offset: required field "offset" is missing
      #|
    ),
  )
}

///|
test "an offset outside the slot is reported" {
  let raw = raw_layout([raw_entry("x", "0", 32, "t_uint256")], [
    raw_type("t_uint256", "inplace", "uint256", "32"),
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.entries.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.entry.offset.invalid] fileA:A storage[0].offset: offset 32 is outside the slot range 0..=31
      #|
    ),
  )
}

///|
test "an unsupported encoding is reported" {
  let raw = raw_layout([], [raw_type("t_uint256", "packed", "uint256", "32")])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.types.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.encoding.unsupported] types["t_uint256"].encoding: unsupported storage encoding "packed"
      #|
    ),
  )
}

///|
test "an unparseable numberOfBytes is reported" {
  let raw = raw_layout([], [
    raw_type("t_uint256", "inplace", "uint256", "thirty-two"),
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.types.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.size.invalid] types["t_uint256"].numberOfBytes: numberOfBytes "thirty-two" is not a decimal integer
      #|
    ),
  )
}

///|
test "an undefined type reference is reported and never guessed" {
  let raw = raw_layout(
    [raw_entry("m", "0", 0, "t_mapping(t_uint256,t_bool)")],
    [
      {
        ..raw_type(
          "t_mapping(t_uint256,t_bool)", "mapping", "mapping(uint256 => bool)", "32",
        ),
        key: Some("t_uint256"),
        value: Some("t_bool"),
      },
      raw_type("t_bool", "inplace", "bool", "1"),
    ],
  )
  let (layout, diagnostics) = normalize(raw)
  // Only the unrelated `t_bool` survives; the mapping and the variable that
  // used it are gone.
  assert_eq(layout.types.length(), 1)
  assert_eq(layout.entries.length(), 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.reference.missing] types["t_mapping(t_uint256,t_bool)"].key: storage type reference "t_uint256" is not defined
      #|error[storage.entry.type.missing] fileA:A storage[0].type: storage type "t_mapping(t_uint256,t_bool)" is not defined by the layout
      #|
    ),
  )
}

///|
test "missing and repeated type ids are reported" {
  let raw = raw_layout([], [
    { ..raw_type("t_uint256", "inplace", "uint256", "32"), id: None, },
    raw_type("t_bool", "inplace", "bool", "1"),
    raw_type("t_bool", "inplace", "bool", "1"),
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.types.length(), 1)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.id.missing] types[0].id: storage type is missing its id
      #|error[storage.type.id.duplicate] types["t_bool"]: storage type id "t_bool" is defined more than once; the first definition is used
      #|
    ),
  )
}

///|
test "types that cannot resolve are pruned from the model" {
  let raw = raw_layout([], [
    {
      ..raw_type("t_struct(S)1_storage", "inplace", "struct S", "32"),
      members: Some([raw_entry("m", "0", 0, "t_mapping(t_uint256,t_uint8)")]),
    },
    {
      ..raw_type(
        "t_mapping(t_uint256,t_uint8)", "mapping", "mapping(uint256 => uint8)", "32",
      ),
      key: Some("t_uint256"),
      value: Some("t_uint8"),
    },
    raw_type("t_uint8", "inplace", "uint8", "1"),
  ])
  let (layout, diagnostics) = normalize(raw)
  // The mapping is the root cause; the struct is pruned by reference closure
  // without adding a second, redundant diagnostic. Only `t_uint8` survives.
  assert_eq(layout.types.length(), 1)
  assert_eq(diagnostics.length(), 1)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.reference.missing] types["t_mapping(t_uint256,t_uint8)"].key: storage type reference "t_uint256" is not defined
      #|
    ),
  )
}

///|
test "a fixed array label must carry its element count" {
  let raw = raw_layout([], [
    raw_type("t_uint128", "inplace", "uint128", "16"),
    {
      ..raw_type("t_bad_array", "inplace", "uint128[]", "32"),
      base: Some("t_uint128"),
    },
  ])
  let (layout, diagnostics) = normalize(raw)
  assert_eq(layout.types.length(), 1)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.type.array-length.invalid] types["t_bad_array"].label: fixed array label "uint128[]" does not end in a decimal length
      #|
    ),
  )
}

///|
test "a path prefix names the namespace a finding belongs to" {
  let raw = raw_layout([raw_entry("x", "0x1f", 0, "t_uint256")], [
    uint256_type(),
  ])
  let (_, diagnostics) = @moonupgradeguard.normalize_layout(
    raw,
    prefix="transientStorage.",
  )
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[storage.entry.slot.invalid] fileA:A transientStorage.storage[0].slot: slot "0x1f" is not a non-negative decimal integer
      #|
    ),
  )
}
