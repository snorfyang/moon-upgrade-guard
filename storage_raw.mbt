///| Raw input shapes for storage-layout normalization.
///
/// These structures mirror the JSON shape that the Solidity compiler
/// documents for the `storageLayout` output object. Decoding an artifact into
/// them is a separate layer, so every field is optional: a raw value may be
/// incomplete, and normalization reports what is missing instead of silently
/// defaulting it.

///|
/// A raw `storageLayout.storage` element.
pub(all) struct RawStorageEntry {
  /// The `label` field.
  label : String?
  /// The `contract` field.
  contract : String?
  /// The `slot` field, a decimal string.
  slot : String?
  /// The `offset` field, bytes inside the slot.
  offset : Int?
  /// The `type` field, a key into the layout's type table.
  type_id : String?
} derive(Eq, @debug.Debug)

///|
/// A raw `storageLayout.types` value.
pub(all) struct RawStorageType {
  /// Key of the type in the type table.
  id : String?
  /// The `encoding` field: `inplace`, `mapping`, `dynamic_array`, or `bytes`.
  encoding : String?
  /// The `label` field, the canonical type name.
  label : String?
  /// The `numberOfBytes` field, a decimal string.
  number_of_bytes : String?
  /// The `base` field of an array type.
  base : String?
  /// The `key` field of a mapping type.
  key : String?
  /// The `value` field of a mapping type.
  value : String?
  /// The `members` field of a struct type.
  members : Array[RawStorageEntry]?
} derive(Eq, @debug.Debug)

///|
/// A raw `storageLayout` object: the two documented keys, before validation.
pub(all) struct RawStorageLayout {
  /// The `storage` array.
  storage : Array[RawStorageEntry]
  /// The `types` object, as one entry per type so that order never depends on
  /// hash iteration.
  types : Array[RawStorageType]
} derive(Eq, @debug.Debug)
