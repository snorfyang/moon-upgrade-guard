///| Backend-independent storage layout model.
///
/// The model is built from the Solidity compiler's `storageLayout` output,
/// documented at
/// <https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html>.
/// It deliberately keeps compiler-generated type ids only as references:
/// semantic equality is decided by the type descriptions they resolve to, not
/// by the ids, which change between compilations.

///|
/// A storage slot number.
///
/// Solidity slots are unbounded decimal integers, emitted as JSON strings
/// because they can exceed every fixed-width integer type. The value is
/// therefore kept as canonical decimal digits and is never routed through a
/// floating-point number.
pub struct Slot {
  priv digits : String
} derive(Eq, @debug.Debug)

///|
/// Parses a storage slot from its decimal representation.
///
/// Returns `None` if `text` is empty or contains anything other than ASCII
/// digits. Leading zeros are removed, so `Slot::parse("007")` equals
/// `Slot::parse("7")`.
pub fn Slot::parse(text : String) -> Slot? {
  if text.is_empty() {
    return None
  }
  let digits = StringBuilder()
  let mut significant = false
  for c in text {
    if !c.is_ascii_digit() {
      return None
    }
    if c != '0' {
      significant = true
    }
    if significant {
      digits.write_char(c)
    }
  }
  if significant {
    Some({ digits: digits.to_string(), })
  } else {
    Some({ digits: "0", })
  }
}

///|
/// Canonical decimal representation of a slot.
pub fn Slot::to_string(self : Slot) -> String {
  self.digits
}

///|
/// Numeric order of two slots.
///
/// Both values are canonical decimal digits without leading zeros, so the
/// shorter value is the smaller one and equal-length values compare digit by
/// digit. This is deliberately not a lexicographic string order: slot `10` is
/// greater than slot `9`.
pub impl Compare for Slot with fn compare(self : Slot, other : Slot) -> Int {
  let a = self.digits.char_length()
  let b = other.digits.char_length()
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    self.digits.compare(other.digits)
  }
}

///|
/// Structural description of a storage type.
///
/// The shape carries the compiler type ids that a type references, not the
/// referenced types themselves. Storage types can refer to each other
/// (a struct may hold a mapping whose value is that same struct), so resolving
/// references is the job of a later comparison step, which can then guard
/// recursion with visited pairs.
pub(all) enum TypeShape {
  /// A value laid out directly in its slot bytes: scalars, enums, and
  /// user-defined value types. The type `label` is what distinguishes types
  /// with the same size, such as `uint128` and `int128`.
  Value
  /// A fixed-size array. The fields are the base element type id and the
  /// lossless decimal element count.
  StaticArray(String, String)
  /// A dynamic array. The field is the base element type id.
  DynamicArray(String)
  /// A mapping. The fields are the key and value type ids.
  Mapping(String, String)
  /// `bytes` and `string`, whose stored size varies at run time.
  Bytes
  /// A struct. Members carry slots and offsets relative to the start of the
  /// struct, in declaration order.
  Struct(Array[StorageEntry])
} derive(Eq, @debug.Debug)

///|
/// A storage variable declaration.
pub(all) struct StorageEntry {
  /// Declared name of the variable.
  label : String
  /// Emitting contract as the artifact reports it, such as `fileA:A`. Base
  /// contract variables come first in the layout, so this is what separates
  /// an inherited variable from a new one.
  contract : String?
  /// Slot where the variable starts.
  slot : Slot
  /// Byte offset inside `slot`.
  offset : Int
  /// Compiler type id, a key into `StorageLayout.types`.
  type_id : String
} derive(Eq, @debug.Debug)

///|
/// A storage type normalized from the compiler type table.
pub(all) struct TypeEntry {
  /// Compiler-generated type id. Used only to resolve references.
  id : String
  /// Canonical type name printed by the compiler, such as `uint128` or
  /// `struct A.S`.
  label : String
  /// Bytes the type occupies, from `numberOfBytes`.
  byte_size : Int
  /// Structural description of the type.
  shape : TypeShape
} derive(Eq, @debug.Debug)

///|
/// A normalized storage layout.
pub(all) struct StorageLayout {
  /// Declared storage variables, in artifact order.
  entries : Array[StorageEntry]
  /// Referenced types, sorted by id with MoonBit's `String::compare` order so
  /// that output is deterministic.
  types : Array[TypeEntry]
} derive(Eq, @debug.Debug)

///|
/// A layout with no variables and no types, as a contract that declares no
/// transient storage has.
pub fn StorageLayout::empty() -> StorageLayout {
  { entries: [], types: [], }
}

///|
/// Finds the normalized type with compiler id `id`.
pub fn StorageLayout::find_type(
  self : StorageLayout,
  id : String,
) -> TypeEntry? {
  for entry in self.types {
    if entry.id == id {
      return Some(entry)
    }
  }
  None
}
