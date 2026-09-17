///| Property tests for the storage comparator.
///
/// The generated input is one type choice per variable, so these run over
/// layout shapes rather than over a single fixture. A layout is built directly
/// in its normalized form, because that is the value the comparator takes, and
/// labels and positions are unique by construction so that a permutation means
/// "the same layout written in another order".

///|
/// The scalar types a generated layout picks from.
let property_type_table : Array[@moonupgradeguard.TypeEntry] = [
  {
    id: "t_uint8",
    label: "uint8",
    byte_size: 1,
    shape: @moonupgradeguard.TypeShape::Value,
  },
  {
    id: "t_uint128",
    label: "uint128",
    byte_size: 16,
    shape: @moonupgradeguard.TypeShape::Value,
  },
  {
    id: "t_uint256",
    label: "uint256",
    byte_size: 32,
    shape: @moonupgradeguard.TypeShape::Value,
  },
  {
    id: "t_bytes32",
    label: "bytes32",
    byte_size: 32,
    shape: @moonupgradeguard.TypeShape::Value,
  },
]

///|
/// A non-negative index for a generated integer.
fn property_index(value : Int) -> Int {
  let rest = value % property_type_table.length()
  if rest < 0 {
    rest + property_type_table.length()
  } else {
    rest
  }
}

///|
/// Builds a layout with one variable per element, each in its own slot.
fn property_layout(sizes : Array[Int]) -> @moonupgradeguard.StorageLayout raise {
  let entries : Array[@moonupgradeguard.StorageEntry] = []
  for i in 0..<sizes.length() {
    let type_id = property_type_table[property_index(sizes[i])].id
    let slot = match @moonupgradeguard.Slot::parse(i.to_string()) {
      Some(slot) => slot
      None => fail("slot \{i} does not parse")
    }
    entries.push({ label: "v\{i}", contract: None, slot, offset: 0, type_id, })
  }
  { entries, types: property_type_table, }
}

///|
/// The same layout with its entries written in the opposite order.
fn reversed_layout(
  layout : @moonupgradeguard.StorageLayout,
) -> @moonupgradeguard.StorageLayout {
  { entries: layout.entries.rev(), types: layout.types, }
}

///|
/// The same layout with every variable moved on by one slot.
fn shifted_layout(
  layout : @moonupgradeguard.StorageLayout,
) -> @moonupgradeguard.StorageLayout raise {
  let entries : Array[@moonupgradeguard.StorageEntry] = []
  for i in 0..<layout.entries.length() {
    let slot = match @moonupgradeguard.Slot::parse((i + 1).to_string()) {
      Some(slot) => slot
      None => fail("slot \{i + 1} does not parse")
    }
    entries.push({ ..layout.entries[i], slot, })
  }
  { entries, types: layout.types, }
}

///|
/// The same layout with one more variable after the last one.
fn appended_layout(
  layout : @moonupgradeguard.StorageLayout,
  next_slot : Int,
) -> @moonupgradeguard.StorageLayout raise {
  let slot = match @moonupgradeguard.Slot::parse(next_slot.to_string()) {
    Some(slot) => slot
    None => fail("slot \{next_slot} does not parse")
  }
  let entries = layout.entries.copy()
  entries.push({
    label: "appended",
    contract: None,
    slot,
    offset: 0,
    type_id: "t_uint256",
  })
  { entries, types: layout.types, }
}

///|
test "a layout compared with itself never blocks" {
  @quickcheck.check(
    fn(sizes : Array[Int]) -> Bool raise {
      let layout = property_layout(sizes)
      !@moonupgradeguard.blocks_upgrade(
        @moonupgradeguard.compare_storage(layout, layout),
      )
    },
    count=200,
    seed=20260917UL,
  )
}

///|
test "appending a variable never blocks" {
  @quickcheck.check(
    fn(sizes : Array[Int]) -> Bool raise {
      let layout = property_layout(sizes)
      let appended = appended_layout(layout, sizes.length())
      !@moonupgradeguard.blocks_upgrade(
        @moonupgradeguard.compare_storage(layout, appended),
      )
    },
    count=200,
    seed=20260918UL,
  )
}

///|
test "permuting the entry order reports nothing" {
  @quickcheck.check(
    fn(sizes : Array[Int]) -> Bool raise {
      let layout = property_layout(sizes)
      @moonupgradeguard.compare_storage(layout, reversed_layout(layout)).is_empty()
    },
    count=200,
    seed=20260919UL,
  )
}

///|
test "a shift is reported whatever the entry order" {
  @quickcheck.check(
    fn(sizes : Array[Int]) -> Bool raise {
      if sizes.is_empty() {
        return true
      }
      let layout = property_layout(sizes)
      let shifted = shifted_layout(layout)
      let forward = @moonupgradeguard.compare_storage(layout, shifted)
      let backward = @moonupgradeguard.compare_storage(
        reversed_layout(layout),
        reversed_layout(shifted),
      )
      @moonupgradeguard.blocks_upgrade(forward) &&
      @moonupgradeguard.blocks_upgrade(backward) &&
      forward.length() == backward.length()
    },
    count=200,
    seed=20260920UL,
  )
}
