///| Storage compatibility engine.
///
/// The engine answers one question: does every storage variable of the old
/// version still live at the same position with the same meaning in the new
/// version? Because it works on compiler output rather than source code, it
/// compares the flattened layouts the compiler emits.
///
/// The rules, stated in terms of the old layout:
///
/// - a variable that keeps its label, slot, offset, and semantic type is
///   compatible;
/// - a variable whose label changed while its position and semantic type did
///   not is a rename. The bytes stay where they were, so the layout is still
///   compatible, but the new name may carry a new meaning, so this is reported
///   as a warning rather than an error;
/// - a variable that moved slot or offset is incompatible;
/// - a variable that disappeared from the new layout is incompatible;
/// - a variable that kept its position but changed semantic type is
///   incompatible, including nested changes such as a struct member gaining a
///   field, because the bytes at that position now mean something else. This
///   holds even when the newly used bytes were unused before: the engine
///   reports the change and leaves the decision to a reviewer. A struct member
///   rename counts as a type change too, since only top level variables have a
///   position that makes a rename unambiguous;
/// - a variable that appears only in the new layout is additive and is
///   reported as information. An insertion that shifts existing data is
///   already reported as a move, and an insertion that fills unused bytes is
///   not;
/// - `contract` attribution is provenance, not compatibility, so moving a
///   variable between base and derived contracts without moving it in storage
///   is not reported.
///
/// Storage gaps are handled explicitly. A gap is an array variable named
/// `__gap` or `__gap_<n>`, the convention OpenZeppelin-style contracts use to
/// reserve room for variables that later versions add. The bytes a gap covers
/// are unused, so a gap may lose bytes at its front, and a new variable may
/// take them, as long as one thing stays true: the gap still ends at the byte
/// it ended at before. That is what keeps every variable declared after the gap
/// in place. The name alone never skips a comparison: the type has to be an
/// array, the element type has to stay the same, and a gap whose end moved is
/// still a move.
///
/// A gap replaced wholesale by a differently typed variable is reported as a
/// removal plus an addition, which is the conservative reading; replacing it
/// with a variable of the same position and type is a rename.
///
/// Namespaced layouts, such as ERC-7201, are not modelled yet.

///|
/// How two semantic types relate.
///
/// `Different` carries where the two types part company, in a form a report can
/// quote, such as `member "b": uint128 -> uint256`.
priv enum TypeComparison {
  Same
  Different(String)
  Unresolvable(String)
} derive(Eq)

///|
/// The nesting depth at which a type description stops expanding.
///
/// Types can refer to themselves, so a description must be bounded. The
/// comparison itself is not depth bounded: it uses visited pairs.
let description_depth = 3

///|
/// Compares two normalized storage layouts.
///
/// Returns the diagnostics that describe the change, sorted. An empty result
/// means every old variable kept its position and meaning.
pub fn compare_storage(
  old : StorageLayout,
  new : StorageLayout,
) -> Array[Diagnostic] {
  compare_section(old, new, "storage")
}

///|
/// Compares two normalized transient storage layouts.
///
/// Transient storage lives in its own address space, but a contract that keeps
/// transient values across calls is affected by a reordering just as it would
/// be by a storage reordering, so the rules are the same. Only the location
/// differs: a finding names `transientStorage[...]` rather than `storage[...]`,
/// which is also how a report tells the two namespaces apart.
pub fn compare_transient(
  old : StorageLayout,
  new : StorageLayout,
) -> Array[Diagnostic] {
  compare_section(old, new, "transientStorage")
}

///|
/// Compares two entry lists that share one set of rules.
///
/// `section` is the name the locations are reported under, so the same engine
/// can compare regular storage, transient storage, or any later namespace.
fn compare_section(
  old : StorageLayout,
  new : StorageLayout,
  section : String,
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let new_matched : Array[Bool] = Array::make(new.entries.length(), false)
  let old_matched : Array[Bool] = Array::make(old.entries.length(), false)
  // First by label, so that a variable that only moved is reported as moving
  // rather than as a removal plus an addition.
  for i in 0..<old.entries.length() {
    let old_entry = old.entries[i]
    let mut found = -1
    for j in 0..<new.entries.length() {
      if !new_matched[j] && new.entries[j].label == old_entry.label {
        found = j
        break
      }
    }
    if found >= 0 {
      old_matched[i] = true
      new_matched[found] = true
      compare_matched(
        old,
        new,
        old_entry,
        new.entries[found],
        i,
        section,
        diagnostics,
      )
    }
  }
  // Then by position and type, which is what makes a rename recognizable.
  for i in 0..<old.entries.length() {
    if old_matched[i] {
      continue
    }
    let old_entry = old.entries[i]
    let mut found = -1
    for j in 0..<new.entries.length() {
      if !new_matched[j] &&
        new.entries[j].slot == old_entry.slot &&
        new.entries[j].offset == old_entry.offset &&
        compare_type(old, old_entry.type_id, new, new.entries[j].type_id, []) ==
        Same {
        found = j
        break
      }
    }
    if found >= 0 {
      old_matched[i] = true
      new_matched[found] = true
      let new_entry = new.entries[found]
      diagnostics.push(
        Diagnostic::new(
          StorageEntryLabelChanged,
          entry_location(old_entry, i, section),
          "variable \"\{old_entry.label}\" was renamed to \"\{new_entry.label}\" without moving or changing type",
        ).with_values(old_value=old_entry.label, new_value=new_entry.label),
      )
    }
  }
  for i in 0..<old.entries.length() {
    if !old_matched[i] {
      let old_entry = old.entries[i]
      diagnostics.push(
        Diagnostic::new(
          StorageEntryRemoved,
          entry_location(old_entry, i, section),
          "variable \"\{old_entry.label}\" at slot \{old_entry.slot.to_string()} is missing from the new layout",
        ).with_values(old_value=old_entry.label),
      )
    }
  }
  for j in 0..<new.entries.length() {
    if !new_matched[j] {
      let new_entry = new.entries[j]
      diagnostics.push(
        Diagnostic::new(
          StorageEntryAdded,
          entry_location(new_entry, j, section),
          "variable \"\{new_entry.label}\" was added at slot \{new_entry.slot.to_string()}, offset \{new_entry.offset}",
        ).with_values(new_value=new_entry.label),
      )
    }
  }
  diagnostics.sort()
  diagnostics
}

///|
/// Location of a storage variable inside the `storageLayout` object.
fn entry_location(
  entry : StorageEntry,
  index : Int,
  section : String,
) -> Location {
  { contract: entry.contract, path: section + "[\{index}]", }
}

///|
/// Compares a pair of variables that share a label.
fn compare_matched(
  old : StorageLayout,
  new : StorageLayout,
  old_entry : StorageEntry,
  new_entry : StorageEntry,
  old_index : Int,
  section : String,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let location = entry_location(old_entry, old_index, section)
  if gap_change_accepted(old, old_entry, new, new_entry) {
    // A gap covers unused bytes, so it may be resized in place as long as it
    // still ends where it ended before. Everything after it keeps its place.
    report_gap_change(old, old_entry, new, new_entry, location, diagnostics)
    return
  }
  if old_entry.slot != new_entry.slot {
    diagnostics.push(
      Diagnostic::new(
        StorageEntrySlotChanged,
        location,
        "variable \"\{old_entry.label}\" moved from slot \{old_entry.slot.to_string()} to slot \{new_entry.slot.to_string()}",
      ).with_values(
        old_value=old_entry.slot.to_string(),
        new_value=new_entry.slot.to_string(),
      ),
    )
  } else if old_entry.offset != new_entry.offset {
    diagnostics.push(
      Diagnostic::new(
        StorageEntryOffsetChanged,
        location,
        "variable \"\{old_entry.label}\" moved from offset \{old_entry.offset} to offset \{new_entry.offset} in slot \{old_entry.slot.to_string()}",
      ).with_values(
        old_value=old_entry.offset.to_string(),
        new_value=new_entry.offset.to_string(),
      ),
    )
  }
  match compare_type(old, old_entry.type_id, new, new_entry.type_id, []) {
    Same => ()
    Unresolvable(id) =>
      diagnostics.push(
        Diagnostic::new(
          StorageEntryTypeMissing,
          location,
          "storage type \"\{id}\" is not defined by the layout",
        ),
      )
    Different(difference) => {
      let old_type = match old.find_type(old_entry.type_id) {
        Some(entry) => entry
        None => {
          diagnostics.push(
            Diagnostic::new(
              StorageEntryTypeMissing,
              location,
              "storage type \"\{old_entry.type_id}\" is not defined by the layout",
            ),
          )
          return
        }
      }
      let new_type = match new.find_type(new_entry.type_id) {
        Some(entry) => entry
        None => {
          diagnostics.push(
            Diagnostic::new(
              StorageEntryTypeMissing,
              location,
              "storage type \"\{new_entry.type_id}\" is not defined by the layout",
            ),
          )
          return
        }
      }
      let message = if old_type.label == new_type.label {
        "storage type of \"\{old_entry.label}\" changed: \{difference}"
      } else {
        "storage type of \"\{old_entry.label}\" changed from \"\{old_type.label}\" to \"\{new_type.label}\""
      }
      diagnostics.push(
        Diagnostic::new(StorageEntryTypeChanged, location, message).with_values(
          old_value=describe_type(old, old_entry.type_id, description_depth),
          new_value=describe_type(new, new_entry.type_id, description_depth),
        ),
      )
    }
  }
}

///|
/// Compares two semantic types, following references through both layouts.
///
/// `visited` holds the id pairs already being compared. When a pair comes back,
/// the comparison has already committed to those two types being compared
/// together, so it reports them as the same rather than following the cycle for
/// ever. That makes the result bisimulation equality, which is the right notion
/// for the possibly recursive type graphs a layout can contain.
fn compare_type(
  old : StorageLayout,
  old_id : String,
  new : StorageLayout,
  new_id : String,
  visited : Array[(String, String)],
) -> TypeComparison {
  if visited.contains((old_id, new_id)) {
    return Same
  }
  let old_entry = match old.find_type(old_id) {
    Some(entry) => entry
    None => return Unresolvable(old_id)
  }
  let new_entry = match new.find_type(new_id) {
    Some(entry) => entry
    None => return Unresolvable(new_id)
  }
  visited.push((old_id, new_id))
  match (old_entry.shape, new_entry.shape) {
    (Value, Value) =>
      if value_equivalent(old_entry, new_entry) {
        Same
      } else {
        Different(
          encoding_name(old_entry.label) +
          " -> " +
          encoding_name(new_entry.label),
        )
      }
    (Bytes, Bytes) =>
      if old_entry.label == new_entry.label {
        Same
      } else {
        Different(old_entry.label + " -> " + new_entry.label)
      }
    (StaticArray(old_base, old_length), StaticArray(new_base, new_length)) =>
      if old_length != new_length || old_entry.byte_size != new_entry.byte_size {
        Different(old_entry.label + " -> " + new_entry.label)
      } else {
        child_difference(
          "element",
          compare_type(old, old_base, new, new_base, visited),
        )
      }
    (DynamicArray(old_base), DynamicArray(new_base)) =>
      child_difference(
        "element",
        compare_type(old, old_base, new, new_base, visited),
      )
    (Mapping(old_key, old_value), Mapping(new_key, new_value)) => {
      let key = compare_type(old, old_key, new, new_key, visited)
      if key == Same {
        child_difference(
          "value",
          compare_type(old, old_value, new, new_value, visited),
        )
      } else {
        child_difference("key", key)
      }
    }
    (Struct(old_members), Struct(new_members)) =>
      compare_members(old, old_members, new, new_members, visited)
    (_, _) => Different(old_entry.label + " -> " + new_entry.label)
  }
}

///|
/// Compares the member lists of two struct types.
fn compare_members(
  old : StorageLayout,
  old_members : Array[StorageEntry],
  new : StorageLayout,
  new_members : Array[StorageEntry],
  visited : Array[(String, String)],
) -> TypeComparison {
  if old_members.length() < new_members.length() {
    return Different(
      "member \"" + new_members[old_members.length()].label + "\" was added",
    )
  }
  if old_members.length() > new_members.length() {
    return Different(
      "member \"" + old_members[new_members.length()].label + "\" was removed",
    )
  }
  let mut result : TypeComparison = Same
  for i in 0..<old_members.length() {
    let old_member = old_members[i]
    let new_member = new_members[i]
    if old_member.label != new_member.label {
      result = Different(
        "member \"\{old_member.label}\" was renamed to \"\{new_member.label}\"",
      )
      break
    }
    if old_member.slot != new_member.slot ||
      old_member.offset != new_member.offset {
      result = Different("member \"\{old_member.label}\" moved")
      break
    }
    let nested = compare_type(
      old,
      old_member.type_id,
      new,
      new_member.type_id,
      visited,
    )
    if nested != Same {
      result = child_difference("member \"\{old_member.label}\"", nested)
      break
    }
  }
  result
}

///|
/// Prefixes a nested difference with the position it was found at.
fn child_difference(
  prefix : String,
  comparison : TypeComparison,
) -> TypeComparison {
  match comparison {
    Same => Same
    Different(difference) => Different(prefix + ": " + difference)
    Unresolvable(id) => Unresolvable(id)
  }
}

///|
/// Whether two value types encode the same values.
///
/// The stored name decides, except where the compiler writes two names for one
/// encoding: `address payable` and contract types are stored exactly like
/// `address`, so they compare equal. Sizes are compared as well, so a name that
/// is not the one expected here still cannot pass with a different width.
fn value_equivalent(old : TypeEntry, new : TypeEntry) -> Bool {
  old.byte_size == new.byte_size &&
  encoding_name(old.label) == encoding_name(new.label)
}

///|
/// The value-encoding name of a value type.
///
/// Assumption: the compiler labels contract-typed storage as
/// `contract <Name>`. If a future compiler labels it differently, the two names
/// differ and the comparison reports a change, which is the conservative
/// outcome.
fn encoding_name(label : String) -> String {
  if label == "address payable" {
    "address"
  } else if label.has_prefix("contract ") {
    "address"
  } else {
    label
  }
}

///|
/// Describes a semantic type for a report, with `depth` left to expand.
fn describe_type(layout : StorageLayout, id : String, depth : Int) -> String {
  if depth <= 0 {
    return "..."
  }
  match layout.find_type(id) {
    None => "\"\{id}\" (not defined)"
    Some(entry) =>
      match entry.shape {
        Value => entry.label
        Bytes => entry.label
        StaticArray(base, length) =>
          describe_type(layout, base, depth - 1) + "[" + length + "]"
        DynamicArray(base) => describe_type(layout, base, depth - 1) + "[]"
        Mapping(key, value) =>
          "mapping(" +
          describe_type(layout, key, depth - 1) +
          " => " +
          describe_type(layout, value, depth - 1) +
          ")"
        Struct(members) => {
          let parts : Array[String] = []
          for member_entry in members {
            parts.push(
              member_entry.label +
              ": " +
              describe_type(layout, member_entry.type_id, depth - 1),
            )
          }
          "struct { " + parts.join(", ") + " }"
        }
      }
  }
}

///|
/// The largest byte position the engine indexes.
///
/// A position is the slot times 32 plus the offset, and slots can in principle
/// be as large as `2^256`. A layout whose position does not fit is never
/// treated as a gap, so the gap rule can only abstain, never guess.
let max_byte_position = 2147483647

///|
/// Whether a variable is a storage gap.
///
/// The convention is `__gap` or `__gap_<n>`. The name alone is not enough: the
/// type has to be an array, so a mapping that happens to be called `__gap` is
/// compared like any other variable.
fn is_storage_gap(layout : StorageLayout, entry : StorageEntry) -> Bool {
  if entry.label != "__gap" && !entry.label.has_prefix("__gap_") {
    return false
  }
  match layout.find_type(entry.type_id) {
    Some(type_entry) =>
      match type_entry.shape {
        StaticArray(_) => true
        DynamicArray(_) => true
        _ => false
      }
    None => false
  }
}

///|
/// The first byte a variable occupies, or `None` when the position is too large
/// to index.
fn entry_begin(entry : StorageEntry) -> Int? {
  match parse_decimal_int(entry.slot.to_string()) {
    Some(slot) =>
      if slot > (max_byte_position - entry.offset) / 32 {
        None
      } else {
        Some(slot * 32 + entry.offset)
      }
    None => None
  }
}

///|
/// The byte just past a variable, or `None` when it cannot be computed.
fn entry_end(layout : StorageLayout, entry : StorageEntry) -> Int? {
  match (entry_begin(entry), layout.find_type(entry.type_id)) {
    (Some(begin), Some(type_entry)) =>
      if begin > max_byte_position - type_entry.byte_size {
        None
      } else {
        Some(begin + type_entry.byte_size)
      }
    _ => None
  }
}

///|
/// Label of a variable's type, falling back to the raw type id.
fn type_label(layout : StorageLayout, entry : StorageEntry) -> String {
  match layout.find_type(entry.type_id) {
    Some(type_entry) => type_entry.label
    None => entry.type_id
  }
}

///|
/// Whether an old gap may be treated as resized in place.
///
/// True when the old variable is a gap, the new one is an array with the same
/// element type, and both end at the same byte. Anything else, including a
/// changed element type or a gap whose end moved, falls back to the ordinary
/// rules.
fn gap_change_accepted(
  old : StorageLayout,
  old_entry : StorageEntry,
  new : StorageLayout,
  new_entry : StorageEntry,
) -> Bool {
  if !is_storage_gap(old, old_entry) {
    return false
  }
  let same_element = match
    (old.find_type(old_entry.type_id), new.find_type(new_entry.type_id)) {
    (Some(old_type), Some(new_type)) =>
      match (old_type.shape, new_type.shape) {
        (StaticArray(old_base, _), StaticArray(new_base, _)) =>
          compare_type(old, old_base, new, new_base, []) == Same
        (DynamicArray(old_base), DynamicArray(new_base)) =>
          compare_type(old, old_base, new, new_base, []) == Same
        _ => false
      }
    _ => false
  }
  if !same_element {
    return false
  }
  match (entry_end(old, old_entry), entry_end(new, new_entry)) {
    (Some(old_end), Some(new_end)) => old_end == new_end
    _ => false
  }
}

///|
/// Reports how a gap changed, when it changed at all.
fn report_gap_change(
  old : StorageLayout,
  old_entry : StorageEntry,
  new : StorageLayout,
  new_entry : StorageEntry,
  location : Location,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let old_label = type_label(old, old_entry)
  let new_label = type_label(new, new_entry)
  if old_entry.slot == new_entry.slot &&
    old_entry.offset == new_entry.offset &&
    old_label == new_label {
    return
  }
  diagnostics.push(
    Diagnostic::new(
      StorageGapChanged,
      location,
      "storage gap \"\{old_entry.label}\" changed from \"\{old_label}\" to \"\{new_label}\", ending at the same position",
    ).with_values(old_value=old_label, new_value=new_label),
  )
}
