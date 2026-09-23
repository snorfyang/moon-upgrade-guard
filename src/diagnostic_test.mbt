///| Black-box tests for the diagnostic model and its renderers.

///|
fn diag(
  code : @moonupgradeguard.DiagnosticCode,
  contract : String?,
  path : String,
  message : String,
) -> @moonupgradeguard.Diagnostic {
  @moonupgradeguard.Diagnostic::new(code, { contract, path, }, message)
}

///|
test "severity names" {
  inspect(@moonupgradeguard.Severity::Info.name(), content="info")
  inspect(@moonupgradeguard.Severity::Warning.name(), content="warning")
  inspect(@moonupgradeguard.Severity::Error.name(), content="error")
}

///|
test "codes have stable names and a canonical severity" {
  inspect(
    @moonupgradeguard.DiagnosticCode::StorageEntrySlotInvalid.name(),
    content="storage.entry.slot.invalid",
  )
  inspect(
    @moonupgradeguard.DiagnosticCode::StorageTypeReferenceMissing.name(),
    content="storage.type.reference.missing",
  )
  assert_eq(
    @moonupgradeguard.DiagnosticCode::StorageEntryTypeMissing.severity(),
    @moonupgradeguard.Severity::Error,
  )
}

///|
test "new uses the canonical severity and no values" {
  let diagnostic = diag(
    @moonupgradeguard.DiagnosticCode::StorageEntrySlotInvalid,
    None,
    "storage[0].slot",
    "bad slot",
  )
  assert_eq(diagnostic.severity, @moonupgradeguard.Severity::Error)
  assert_eq(diagnostic.input, None)
  assert_eq(diagnostic.old_value, None)
  assert_eq(diagnostic.new_value, None)
}

///|
test "renderers sort findings into a canonical order" {
  let entry_type = diag(
    @moonupgradeguard.DiagnosticCode::StorageEntryTypeMissing,
    Some("fileA:A"),
    "storage[1].type",
    "storage type \"t_x\" is not defined by the layout",
  )
  let entry_slot = diag(
    @moonupgradeguard.DiagnosticCode::StorageEntrySlotInvalid,
    Some("fileA:A"),
    "storage[1].slot",
    "slot \"0x1f\" is not a non-negative decimal integer",
  )
  let type_encoding = diag(
    @moonupgradeguard.DiagnosticCode::StorageTypeEncodingUnsupported,
    None,
    "types[\"t_x\"].encoding",
    "unsupported storage encoding \"packed\"",
  )
  let forward = [entry_type, entry_slot, type_encoding]
  let backward = [type_encoding, entry_slot, entry_type]
  let text = @moonupgradeguard.render_text(forward)
  assert_eq(text, @moonupgradeguard.render_text(backward))
  inspect(
    text,
    content=(
      #|error[storage.type.encoding.unsupported] types["t_x"].encoding: unsupported storage encoding "packed"
      #|error[storage.entry.slot.invalid] fileA:A storage[1].slot: slot "0x1f" is not a non-negative decimal integer
      #|error[storage.entry.type.missing] fileA:A storage[1].type: storage type "t_x" is not defined by the layout
      #|
    ),
  )
  let json = @moonupgradeguard.render_json(forward)
  assert_eq(json, @moonupgradeguard.render_json(backward))
  inspect(
    json,
    content=(
      #|[
      #|  {
      #|    "code": "storage.type.encoding.unsupported",
      #|    "severity": "error",
      #|    "location": {"path": "types[\"t_x\"].encoding"},
      #|    "message": "unsupported storage encoding \"packed\""
      #|  },
      #|  {
      #|    "code": "storage.entry.slot.invalid",
      #|    "severity": "error",
      #|    "location": {"contract": "fileA:A", "path": "storage[1].slot"},
      #|    "message": "slot \"0x1f\" is not a non-negative decimal integer"
      #|  },
      #|  {
      #|    "code": "storage.entry.type.missing",
      #|    "severity": "error",
      #|    "location": {"contract": "fileA:A", "path": "storage[1].type"},
      #|    "message": "storage type \"t_x\" is not defined by the layout"
      #|  }
      #|]
      #|
    ),
  )
}

///|
test "input findings render old before new" {
  let diagnostic = diag(
    @moonupgradeguard.DiagnosticCode::ArtifactLayoutMissing,
    None,
    "$",
    "no layout",
  )
  let old = diagnostic.with_input(@moonupgradeguard.InputSide::Old)
  let new = diagnostic.with_input(@moonupgradeguard.InputSide::New)
  inspect(
    @moonupgradeguard.render_text([new, old]),
    content=(
      #|error[artifact.layout.missing] old $: no layout
      #|error[artifact.layout.missing] new $: no layout
      #|
    ),
  )
}

///|
test "json output escapes strings" {
  let diagnostic = diag(
    @moonupgradeguard.DiagnosticCode::StorageEntrySlotInvalid,
    Some("quote\"key\\"),
    "path\twith\u{1}control",
    "line\nbreak\rend\bback\fform é中",
  )
  inspect(
    @moonupgradeguard.render_json([diagnostic]),
    content=(
      #|[
      #|  {
      #|    "code": "storage.entry.slot.invalid",
      #|    "severity": "error",
      #|    "location": {"contract": "quote\"key\\", "path": "path\twith\u0001control"},
      #|    "message": "line\nbreak\rend\bback\fform é中"
      #|  }
      #|]
      #|
    ),
  )
}

///|
test "compared values render when both sides are known" {
  let both : @moonupgradeguard.Diagnostic = {
    code: @moonupgradeguard.DiagnosticCode::StorageEntryTypeMissing,
    severity: @moonupgradeguard.Severity::Error,
    input: None,
    location: { contract: None, path: "storage[0].type", },
    message: "type changed",
    old_value: Some("t_uint128"),
    new_value: Some("t_uint256"),
  }
  let old_only : @moonupgradeguard.Diagnostic = {
    code: @moonupgradeguard.DiagnosticCode::StorageEntryTypeMissing,
    severity: @moonupgradeguard.Severity::Error,
    input: None,
    location: { contract: None, path: "storage[1].type", },
    message: "field removed",
    old_value: Some("t_bool"),
    new_value: None,
  }
  let new_only : @moonupgradeguard.Diagnostic = {
    code: @moonupgradeguard.DiagnosticCode::StorageEntryTypeMissing,
    severity: @moonupgradeguard.Severity::Error,
    input: None,
    location: { contract: None, path: "storage[2].type", },
    message: "field added",
    old_value: None,
    new_value: Some("t_bool"),
  }
  inspect(
    @moonupgradeguard.render_text([both, old_only, new_only]),
    content=(
      #|error[storage.entry.type.missing] storage[0].type: type changed (old: t_uint128, new: t_uint256)
      #|error[storage.entry.type.missing] storage[1].type: field removed (old: t_bool)
      #|error[storage.entry.type.missing] storage[2].type: field added (new: t_bool)
      #|
    ),
  )
  inspect(
    @moonupgradeguard.render_json([both, old_only, new_only]),
    content=(
      #|[
      #|  {
      #|    "code": "storage.entry.type.missing",
      #|    "severity": "error",
      #|    "location": {"path": "storage[0].type"},
      #|    "message": "type changed",
      #|    "oldValue": "t_uint128",
      #|    "newValue": "t_uint256"
      #|  },
      #|  {
      #|    "code": "storage.entry.type.missing",
      #|    "severity": "error",
      #|    "location": {"path": "storage[1].type"},
      #|    "message": "field removed",
      #|    "oldValue": "t_bool"
      #|  },
      #|  {
      #|    "code": "storage.entry.type.missing",
      #|    "severity": "error",
      #|    "location": {"path": "storage[2].type"},
      #|    "message": "field added",
      #|    "newValue": "t_bool"
      #|  }
      #|]
      #|
    ),
  )
}

///|
test "empty findings render as an empty report" {
  inspect(@moonupgradeguard.render_text([]), content="")
  inspect(@moonupgradeguard.render_json([]), content="[]\n")
}
