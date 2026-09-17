///| Diagnostic model.
///
/// Every analysis layer reports through the same `Diagnostic` value, so text
/// and JSON output can be rendered from one place. Codes and severities are
/// part of the public contract: new codes may be added, but the spelling and
/// meaning of an existing code must not change.

///|
/// How serious a finding is.
pub(all) enum Severity {
  /// Context that does not change the compatible/incompatible verdict.
  Info
  /// A change that is compatible but should be reviewed by a human.
  Warning
  /// A structural incompatibility or an unsupported input.
  Error
} derive(Eq, @debug.Debug)

///|
/// Lowercase name of the severity, shared by both renderers.
pub fn Severity::name(self : Severity) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
/// Rank used to order findings that share a location.
fn Severity::rank(self : Severity) -> Int {
  match self {
    Info => 0
    Warning => 1
    Error => 2
  }
}

///|
/// Stable code identifying one diagnostic rule.
///
/// Codes are namespaced by layer: `storage.entry.*` describes a storage
/// variable, and `storage.type.*` describes an entry of the compiler type
/// table that a storage type reference resolves to.
pub(all) enum DiagnosticCode {
  /// A storage variable is missing a required field.
  StorageEntryFieldMissing
  /// A storage slot is not a non-negative decimal integer.
  StorageEntrySlotInvalid
  /// A storage byte offset is outside the slot range `0..=31`.
  StorageEntryOffsetInvalid
  /// A storage variable references a type id that the layout does not define.
  StorageEntryTypeMissing
  /// A storage type is missing its compiler id.
  StorageTypeIdMissing
  /// A storage type id is defined more than once.
  StorageTypeIdDuplicate
  /// A storage type is missing a required field.
  StorageTypeFieldMissing
  /// A storage type uses an encoding this version does not support.
  StorageTypeEncodingUnsupported
  /// A `numberOfBytes` value is not a decimal integer.
  StorageTypeSizeInvalid
  /// A storage type references another type id that the layout does not
  /// define.
  StorageTypeReferenceMissing
  /// A fixed-array label does not carry a usable decimal element count.
  StorageTypeArrayLengthInvalid
  /// The artifact text is not valid JSON.
  ArtifactJsonInvalid
  /// The artifact root is not one of the recognized wrapper shapes.
  ArtifactShapeUnsupported
  /// The artifact matches more than one recognized wrapper shape.
  ArtifactShapeAmbiguous
  /// A recognized artifact field has the wrong JSON type or value.
  ArtifactFieldInvalid
  /// The artifact carries no storage layout.
  ArtifactLayoutMissing
  /// More than one contract in the artifact carries a storage layout.
  ArtifactContractAmbiguous
  /// No contract in the artifact matches the requested selector.
  ArtifactContractMissing
  /// An operation that compares ABI data received an artifact without an ABI.
  ArtifactAbiMissing
  /// A storage variable of the old layout is absent from the new layout.
  StorageEntryRemoved
  /// A storage variable appears only in the new layout.
  StorageEntryAdded
  /// A storage variable moved to a different slot.
  StorageEntrySlotChanged
  /// A storage variable moved within its slot.
  StorageEntryOffsetChanged
  /// A storage variable was renamed without moving or changing type.
  StorageEntryLabelChanged
  /// A storage variable kept its position but changed semantic type.
  StorageEntryTypeChanged
  /// A storage gap was resized, moved, or consumed while keeping its end
  /// position.
  StorageGapChanged
  /// The artifact mentions ERC-7201 namespaced storage, which cannot be
  /// located from compiler output.
  ArtifactNamespacedStorageUnsupported
  /// The command line names something the CLI does not support.
  CliArgumentInvalid
  /// The CLI could not read an input file.
  CliInputUnreadable
  /// A function signature of the old ABI is absent from the new ABI.
  AbiFunctionRemoved
  /// A function signature appears only in the new ABI.
  AbiFunctionAdded
  /// A function kept its signature but changed state mutability.
  AbiFunctionMutabilityChanged
  /// A function lost mutability behavior that existing callers rely on.
  AbiFunctionMutabilityIncompatible
  /// A function kept its signature but changed its output types.
  AbiFunctionOutputsChanged
  /// An event signature of the old ABI is absent from the new ABI.
  AbiEventRemoved
  /// An event signature appears only in the new ABI.
  AbiEventAdded
  /// An event kept its signature but changed which parameters are indexed.
  AbiEventIndexedChanged
  /// An event kept its signature but changed its anonymity.
  AbiEventAnonymousChanged
  /// A custom error signature of the old ABI is absent from the new ABI.
  AbiErrorRemoved
  /// A custom error signature appears only in the new ABI.
  AbiErrorAdded
  /// A selector or event topic is used by different signatures in the two
  /// versions.
  AbiSignatureCollision
} derive(Eq, @debug.Debug)

///|
/// Stable string code emitted in text and JSON output.
pub fn DiagnosticCode::name(self : DiagnosticCode) -> String {
  match self {
    StorageEntryFieldMissing => "storage.entry.field.missing"
    StorageEntrySlotInvalid => "storage.entry.slot.invalid"
    StorageEntryOffsetInvalid => "storage.entry.offset.invalid"
    StorageEntryTypeMissing => "storage.entry.type.missing"
    StorageTypeIdMissing => "storage.type.id.missing"
    StorageTypeIdDuplicate => "storage.type.id.duplicate"
    StorageTypeFieldMissing => "storage.type.field.missing"
    StorageTypeEncodingUnsupported => "storage.type.encoding.unsupported"
    StorageTypeSizeInvalid => "storage.type.size.invalid"
    StorageTypeReferenceMissing => "storage.type.reference.missing"
    StorageTypeArrayLengthInvalid => "storage.type.array-length.invalid"
    ArtifactJsonInvalid => "artifact.json.invalid"
    ArtifactShapeUnsupported => "artifact.shape.unsupported"
    ArtifactShapeAmbiguous => "artifact.shape.ambiguous"
    ArtifactFieldInvalid => "artifact.field.invalid"
    ArtifactLayoutMissing => "artifact.layout.missing"
    ArtifactContractAmbiguous => "artifact.contract.ambiguous"
    ArtifactContractMissing => "artifact.contract.missing"
    ArtifactAbiMissing => "artifact.abi.missing"
    StorageEntryRemoved => "storage.entry.removed"
    StorageEntryAdded => "storage.entry.added"
    StorageEntrySlotChanged => "storage.entry.slot.changed"
    StorageEntryOffsetChanged => "storage.entry.offset.changed"
    StorageEntryLabelChanged => "storage.entry.label.changed"
    StorageEntryTypeChanged => "storage.entry.type.changed"
    StorageGapChanged => "storage.gap.changed"
    ArtifactNamespacedStorageUnsupported =>
      "artifact.namespaced-storage.unsupported"
    CliArgumentInvalid => "cli.argument.invalid"
    CliInputUnreadable => "cli.input.unreadable"
    AbiFunctionRemoved => "abi.function.removed"
    AbiFunctionAdded => "abi.function.added"
    AbiFunctionMutabilityChanged => "abi.function.mutability.changed"
    AbiFunctionMutabilityIncompatible => "abi.function.mutability.incompatible"
    AbiFunctionOutputsChanged => "abi.function.outputs.changed"
    AbiEventRemoved => "abi.event.removed"
    AbiEventAdded => "abi.event.added"
    AbiEventIndexedChanged => "abi.event.indexed.changed"
    AbiEventAnonymousChanged => "abi.event.anonymous.changed"
    AbiErrorRemoved => "abi.error.removed"
    AbiErrorAdded => "abi.error.added"
    AbiSignatureCollision => "abi.signature.collision"
  }
}

///|
/// Canonical severity of a code.
///
/// The severity is fixed per code so that consumers can filter on it across
/// releases. `Diagnostic::new` uses this table; a future policy that wants a
/// different severity for the same code must document that choice.
pub fn DiagnosticCode::severity(self : DiagnosticCode) -> Severity {
  match self {
    StorageEntryFieldMissing => Error
    StorageEntrySlotInvalid => Error
    StorageEntryOffsetInvalid => Error
    StorageEntryTypeMissing => Error
    StorageTypeIdMissing => Error
    StorageTypeIdDuplicate => Error
    StorageTypeFieldMissing => Error
    StorageTypeEncodingUnsupported => Error
    StorageTypeSizeInvalid => Error
    StorageTypeReferenceMissing => Error
    StorageTypeArrayLengthInvalid => Error
    ArtifactJsonInvalid => Error
    ArtifactShapeUnsupported => Error
    ArtifactShapeAmbiguous => Error
    ArtifactFieldInvalid => Error
    ArtifactLayoutMissing => Error
    ArtifactContractAmbiguous => Error
    ArtifactContractMissing => Error
    ArtifactAbiMissing => Error
    StorageEntryRemoved => Error
    StorageEntryAdded => Info
    StorageEntrySlotChanged => Error
    StorageEntryOffsetChanged => Error
    StorageEntryLabelChanged => Warning
    StorageEntryTypeChanged => Error
    StorageGapChanged => Info
    ArtifactNamespacedStorageUnsupported => Error
    CliArgumentInvalid => Error
    CliInputUnreadable => Error
    AbiFunctionRemoved => Error
    AbiFunctionAdded => Info
    AbiFunctionMutabilityChanged => Warning
    AbiFunctionMutabilityIncompatible => Error
    AbiFunctionOutputsChanged => Error
    AbiEventRemoved => Error
    AbiEventAdded => Info
    AbiEventIndexedChanged => Error
    AbiEventAnonymousChanged => Error
    AbiErrorRemoved => Error
    AbiErrorAdded => Info
    AbiSignatureCollision => Error
  }
}

///|
/// Where a finding was located.
///
/// `path` is relative to the `storageLayout` object that was analyzed: for
/// example `storage[2].slot` or `types["t_uint8"].encoding`. Which artifact the
/// layout came from is a wrapper concern, so the file name is not part of the
/// path; `contract` carries the emitting contract as the artifact reports it.
pub(all) struct Location {
  /// Emitting contract, such as `fileA:A`, when the artifact provides one.
  contract : String?
  /// Path inside the `storageLayout` object.
  path : String
} derive(Eq, @debug.Debug)

///|
/// One finding.
pub(all) struct Diagnostic {
  /// Stable rule code.
  code : DiagnosticCode
  /// Severity of this finding.
  severity : Severity
  /// Where the finding was located.
  location : Location
  /// Human-readable description. Messages are single-line.
  message : String
  /// Value in the old artifact, for findings that relate two artifacts.
  old_value : String?
  /// Value in the new artifact, for findings that relate two artifacts.
  new_value : String?
} derive(Eq, @debug.Debug)

///|
/// Builds a diagnostic with the canonical severity of `code`.
pub fn Diagnostic::new(
  code : DiagnosticCode,
  location : Location,
  message : String,
) -> Diagnostic {
  {
    code,
    severity: code.severity(),
    location,
    message,
    old_value: None,
    new_value: None,
  }
}

///|
/// Total order over diagnostics: contract, path, code, severity, message, and
/// finally the compared values. Text fields compare with MoonBit's
/// `String::compare`, which orders shorter strings first and then by code
/// unit.
///
/// Both renderers sort with this order, so output never depends on the order
/// in which a caller collected findings.
pub impl Compare for Diagnostic with fn compare(
  self : Diagnostic,
  other : Diagnostic,
) -> Int {
  let c = compare_optional(self.location.contract, other.location.contract)
  if c != 0 {
    return c
  }
  let c = self.location.path.compare(other.location.path)
  if c != 0 {
    return c
  }
  let c = self.code.name().compare(other.code.name())
  if c != 0 {
    return c
  }
  let c = self.severity.rank() - other.severity.rank()
  if c != 0 {
    return c
  }
  let c = self.message.compare(other.message)
  if c != 0 {
    return c
  }
  let c = compare_optional(self.old_value, other.old_value)
  if c != 0 {
    return c
  }
  compare_optional(self.new_value, other.new_value)
}

///|
/// Compares two optional strings. An absent value sorts before a present one.
fn compare_optional(a : String?, b : String?) -> Int {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(a), Some(b)) => a.compare(b)
  }
}

///|
/// Whether a diagnostic set blocks an upgrade.
///
/// Only `Error` findings block. They mark a storage or ABI change that breaks
/// existing storage or existing callers. `Warning` and `Info` findings are
/// reported without changing the verdict, so they never make a checker fail.
pub fn blocks_upgrade(diagnostics : Array[Diagnostic]) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.severity == Error {
      return true
    }
  }
  false
}

///|
/// Returns a copy of the diagnostic with the compared values set.
///
/// A value that is not passed keeps the value already on the diagnostic, so a
/// finding that only has an old value can be built with one argument.
pub fn Diagnostic::with_values(
  self : Diagnostic,
  old_value? : String,
  new_value? : String,
) -> Diagnostic {
  {
    ..self,
    old_value: match old_value {
      Some(value) => Some(value)
      None => self.old_value
    },
    new_value: match new_value {
      Some(value) => Some(value)
      None => self.new_value
    },
  }
}
