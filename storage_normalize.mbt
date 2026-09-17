///| Normalization of raw `storageLayout` data into the storage model.
///
/// Normalization validates the raw shape and turns it into the
/// backend-independent model. It never guesses: a type or entry with a
/// missing, unsupported, or dangling field is left out, and the reason is
/// reported as a diagnostic.
///
/// One invariant makes the result safe to compare: a layout whose diagnostic
/// list is empty is complete and closed under type references. A non-empty
/// list means the layout is incomplete, and a caller must not draw a
/// compatibility verdict from it.

///|
/// The largest byte offset that can start inside a storage slot.
let max_slot_offset = 31

///|
/// Normalizes a raw `storageLayout` object.
///
/// Returns the normalized layout together with the diagnostics raised while
/// validating it. Diagnostics are sorted, so identical input always produces
/// identical output. Types and entries that failed validation are absent from
/// the returned layout.
pub fn normalize_layout(
  raw : RawStorageLayout,
) -> (StorageLayout, Array[Diagnostic]) {
  let diagnostics : Array[Diagnostic] = []
  let declared = collect_type_ids(raw.types, diagnostics)
  let types = normalize_types(raw.types, declared, diagnostics)
  let retained = prune_unresolved_types(types)
  let entries = normalize_entries(
    raw.storage,
    retained.map(fn(entry) { entry.id }),
    diagnostics,
  )
  diagnostics.sort()
  let layout : StorageLayout = { entries, types: retained, }
  (layout, diagnostics)
}

///|
/// Path of the type with compiler id `id` inside the `storageLayout` object.
fn type_path(id : String) -> String {
  "types[\"\{id}\"]"
}

///|
/// Collects the type ids that the layout declares, reporting declarations
/// without an id and repeated ids. The first definition of a repeated id wins.
fn collect_type_ids(
  raw_types : Array[RawStorageType],
  diagnostics : Array[Diagnostic],
) -> Array[String] {
  let declared : Array[String] = []
  for i in 0..<raw_types.length() {
    match raw_types[i].id {
      None =>
        diagnostics.push(
          Diagnostic::new(
            StorageTypeIdMissing,
            { contract: None, path: "types[\{i}].id", },
            "storage type is missing its id",
          ),
        )
      Some(id) =>
        if declared.contains(id) {
          diagnostics.push(
            Diagnostic::new(
              StorageTypeIdDuplicate,
              { contract: None, path: type_path(id), },
              "storage type id \"\{id}\" is defined more than once; the first definition is used",
            ),
          )
        } else {
          declared.push(id)
        }
    }
  }
  declared
}

///|
/// Normalizes every raw type that has an id, sorted by id.
fn normalize_types(
  raw_types : Array[RawStorageType],
  declared : Array[String],
  diagnostics : Array[Diagnostic],
) -> Array[TypeEntry] {
  let types : Array[TypeEntry] = []
  let normalized : Array[String] = []
  for i in 0..<raw_types.length() {
    let raw_type = raw_types[i]
    if raw_type.id is Some(id) && !normalized.contains(id) {
      match normalize_type(raw_type, id, declared, type_path(id), diagnostics) {
        Some(entry) => {
          normalized.push(id)
          types.push(entry)
        }
        None => ()
      }
    }
  }
  types.sort_by_key(fn(entry) { entry.id })
  types
}

///|
/// Drops types whose references no longer resolve inside the retained set.
///
/// Every type removed here was already reported by the diagnostic that made
/// its target unavailable, so pruning raises no new diagnostic. It keeps the
/// model closed under type references: when the diagnostic list is empty,
/// every reference in the layout resolves.
fn prune_unresolved_types(types : Array[TypeEntry]) -> Array[TypeEntry] {
  let mut retained = types
  let mut changed = true
  while changed {
    changed = false
    let ids : Array[String] = retained.map(fn(entry) { entry.id })
    let kept : Array[TypeEntry] = []
    for entry in retained {
      if references_resolve(entry.shape, ids) {
        kept.push(entry)
      } else {
        changed = true
      }
    }
    retained = kept
  }
  retained
}

///|
/// Whether every type id that `shape` references is in `ids`.
fn references_resolve(shape : TypeShape, ids : Array[String]) -> Bool {
  match shape {
    Value => true
    Bytes => true
    StaticArray(base, _) => ids.contains(base)
    DynamicArray(base) => ids.contains(base)
    Mapping(key, value) => ids.contains(key) && ids.contains(value)
    Struct(members) => {
      for member_entry in members {
        if !ids.contains(member_entry.type_id) {
          return false
        }
      }
      true
    }
  }
}

///|
/// Normalizes the top-level storage variables.
fn normalize_entries(
  raw_storage : Array[RawStorageEntry],
  known_ids : Array[String],
  diagnostics : Array[Diagnostic],
) -> Array[StorageEntry] {
  let entries : Array[StorageEntry] = []
  for i in 0..<raw_storage.length() {
    match
      normalize_entry(raw_storage[i], known_ids, "storage[\{i}]", diagnostics) {
      Some(entry) => entries.push(entry)
      None => ()
    }
  }
  entries
}

///|
/// Normalizes one raw type. Returns `None` as soon as a required field is
/// missing or unsupported, or a referenced type id is not declared, so that a
/// type is never partially normalized.
fn normalize_type(
  raw : RawStorageType,
  id : String,
  declared : Array[String],
  path : String,
  diagnostics : Array[Diagnostic],
) -> TypeEntry? {
  let location : Location = { contract: None, path, }
  guard required_field(
      raw.label,
      "label",
      StorageTypeFieldMissing,
      location,
      diagnostics,
    )
    is Some(label) else {
    return None
  }
  guard required_field(
      raw.encoding,
      "encoding",
      StorageTypeFieldMissing,
      location,
      diagnostics,
    )
    is Some(encoding) else {
    return None
  }
  guard required_field(
      raw.number_of_bytes,
      "numberOfBytes",
      StorageTypeFieldMissing,
      location,
      diagnostics,
    )
    is Some(text) else {
    return None
  }
  guard parse_decimal_int(text) is Some(byte_size) else {
    diagnostics.push(
      Diagnostic::new(
        StorageTypeSizeInvalid,
        { contract: None, path: path + ".numberOfBytes", },
        "numberOfBytes \"\{text}\" is not a decimal integer",
      ),
    )
    return None
  }
  let shape = match encoding {
    "inplace" =>
      match raw.members {
        Some(members) =>
          match
            normalize_members(members, declared, path + ".members", diagnostics) {
            Some(normalized) => Struct(normalized)
            None => return None
          }
        None =>
          match raw.base {
            Some(base) => {
              guard check_reference(
                base,
                declared,
                { contract: None, path: path + ".base", },
                diagnostics,
              ) else {
                return None
              }
              guard static_array_length(label) is Some(length) else {
                diagnostics.push(
                  Diagnostic::new(
                    StorageTypeArrayLengthInvalid,
                    { contract: None, path: path + ".label", },
                    "fixed array label \"\{label}\" does not end in a decimal length",
                  ),
                )
                return None
              }
              StaticArray(base, length)
            }
            None => Value
          }
      }
    "mapping" => {
      guard required_field(
          raw.key,
          "key",
          StorageTypeFieldMissing,
          location,
          diagnostics,
        )
        is Some(key) else {
        return None
      }
      guard required_field(
          raw.value,
          "value",
          StorageTypeFieldMissing,
          location,
          diagnostics,
        )
        is Some(value) else {
        return None
      }
      guard check_reference(
        key,
        declared,
        { contract: None, path: path + ".key", },
        diagnostics,
      ) else {
        return None
      }
      guard check_reference(
        value,
        declared,
        { contract: None, path: path + ".value", },
        diagnostics,
      ) else {
        return None
      }
      Mapping(key, value)
    }
    "dynamic_array" => {
      guard required_field(
          raw.base,
          "base",
          StorageTypeFieldMissing,
          location,
          diagnostics,
        )
        is Some(base) else {
        return None
      }
      guard check_reference(
        base,
        declared,
        { contract: None, path: path + ".base", },
        diagnostics,
      ) else {
        return None
      }
      DynamicArray(base)
    }
    "bytes" => Bytes
    other => {
      diagnostics.push(
        Diagnostic::new(
          StorageTypeEncodingUnsupported,
          { contract: None, path: path + ".encoding", },
          "unsupported storage encoding \"\{other}\"",
        ),
      )
      return None
    }
  }
  Some({ id, label, byte_size, shape, })
}

///|
/// Extracts and canonicalizes the final `[length]` suffix of a fixed-array
/// label. The compiler's `numberOfBytes` is slot-rounded, so it cannot recover
/// the element count for packed element types.
fn static_array_length(label : String) -> String? {
  guard label.rev_split_once("[") is Some((_, suffix)) else { return None }
  guard suffix.has_suffix("]") else { return None }
  let digits = suffix[:suffix.length() - 1].to_owned()
  match Slot::parse(digits) {
    Some(length) => Some(length.to_string())
    None => None
  }
}

///|
/// Normalizes the members of a struct type.
///
/// Returns `None` if any member fails, so a struct is never left with a
/// partial member list that could compare equal to a different struct.
fn normalize_members(
  members : Array[RawStorageEntry],
  declared : Array[String],
  path : String,
  diagnostics : Array[Diagnostic],
) -> Array[StorageEntry]? {
  let normalized : Array[StorageEntry] = []
  for i in 0..<members.length() {
    match normalize_entry(members[i], declared, path + "[\{i}]", diagnostics) {
      Some(member_entry) => normalized.push(member_entry)
      None => return None
    }
  }
  Some(normalized)
}

///|
/// Normalizes one raw storage variable, whether it is a top-level variable or
/// a struct member.
///
/// `known_ids` is the set of type ids the variable may reference: the declared
/// ids while types are being normalized, and the retained ids once entries
/// are normalized.
fn normalize_entry(
  raw : RawStorageEntry,
  known_ids : Array[String],
  path : String,
  diagnostics : Array[Diagnostic],
) -> StorageEntry? {
  let location : Location = { contract: raw.contract, path, }
  guard required_field(
      raw.label,
      "label",
      StorageEntryFieldMissing,
      location,
      diagnostics,
    )
    is Some(label) else {
    return None
  }
  guard required_field(
      raw.slot,
      "slot",
      StorageEntryFieldMissing,
      location,
      diagnostics,
    )
    is Some(slot_text) else {
    return None
  }
  guard Slot::parse(slot_text) is Some(slot) else {
    diagnostics.push(
      Diagnostic::new(
        StorageEntrySlotInvalid,
        { contract: raw.contract, path: path + ".slot", },
        "slot \"\{slot_text}\" is not a non-negative decimal integer",
      ),
    )
    return None
  }
  guard raw.offset is Some(offset) else {
    missing_field("offset", StorageEntryFieldMissing, location, diagnostics)
    return None
  }
  guard offset >= 0 && offset <= max_slot_offset else {
    diagnostics.push(
      Diagnostic::new(
        StorageEntryOffsetInvalid,
        { contract: raw.contract, path: path + ".offset", },
        "offset \{offset} is outside the slot range 0..=\{max_slot_offset}",
      ),
    )
    return None
  }
  guard required_field(
      raw.type_id,
      "type",
      StorageEntryFieldMissing,
      location,
      diagnostics,
    )
    is Some(type_id) else {
    return None
  }
  guard known_ids.contains(type_id) else {
    diagnostics.push(
      Diagnostic::new(
        StorageEntryTypeMissing,
        { contract: raw.contract, path: path + ".type", },
        "storage type \"\{type_id}\" is not defined by the layout",
      ),
    )
    return None
  }
  Some({ label, contract: raw.contract, slot, offset, type_id, })
}

///|
/// Reads a required string field, or records why it cannot be used.
fn required_field(
  value : String?,
  field : String,
  code : DiagnosticCode,
  location : Location,
  diagnostics : Array[Diagnostic],
) -> String? {
  match value {
    Some(value) => Some(value)
    None => {
      missing_field(field, code, location, diagnostics)
      None
    }
  }
}

///|
/// Records that a required field is missing.
fn missing_field(
  field : String,
  code : DiagnosticCode,
  location : Location,
  diagnostics : Array[Diagnostic],
) -> Unit {
  diagnostics.push(
    Diagnostic::new(
      code,
      { contract: location.contract, path: location.path + "." + field, },
      "required field \"\{field}\" is missing",
    ),
  )
}

///|
/// Records a diagnostic when the referenced type id is not declared.
fn check_reference(
  id : String,
  declared : Array[String],
  location : Location,
  diagnostics : Array[Diagnostic],
) -> Bool {
  if declared.contains(id) {
    true
  } else {
    diagnostics.push(
      Diagnostic::new(
        StorageTypeReferenceMissing,
        location,
        "storage type reference \"\{id}\" is not defined",
      ),
    )
    false
  }
}

///|
/// Parses a decimal integer field, such as `numberOfBytes` or the size in an
/// ABI type name.
///
/// Returns `None` for empty input, non-digits, or a value too large for a
/// machine integer. The values this reads are bounded in practice, so `Int` is
/// exact here even though slot numbers are not. The bound is `2^31 - 1` so that
/// the result is the same on every supported target.
fn parse_decimal_int(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let max_value = 2147483647
  let zero = '0'.to_int()
  let mut value = 0
  for c in text {
    if !c.is_ascii_digit() {
      return None
    }
    let digit = c.to_int() - zero
    if value > (max_value - digit) / 10 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}
