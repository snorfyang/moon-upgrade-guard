///| Text and JSON rendering for diagnostics.
///
/// Rendering is deterministic by construction: both renderers copy and sort
/// their input with `Diagnostic`'s total order, emit JSON keys in a fixed
/// order, and never read a hash table. Identical findings therefore always
/// produce byte-identical output, whichever order the caller collected them
/// in.
///
/// JSON omits `contract`, `oldValue`, and `newValue` when they are absent
/// instead of emitting `null`, so a missing key always means "not applicable"
/// rather than "unknown".

///|
/// Copies and sorts `diagnostics` into canonical order.
fn sorted_diagnostics(diagnostics : Array[Diagnostic]) -> Array[Diagnostic] {
  let sorted = diagnostics.copy()
  sorted.sort()
  sorted
}

///|
/// Renders findings as one line each:
///
/// ```text
/// error[storage.entry.slot.invalid] fileA:A storage[1].slot: slot "0x1f" is not a non-negative decimal integer
/// ```
///
/// The result is empty when there are no findings; otherwise every line ends
/// with a newline.
pub fn render_text(diagnostics : Array[Diagnostic]) -> String {
  let sorted = sorted_diagnostics(diagnostics)
  let buf = StringBuilder()
  for diagnostic in sorted {
    buf.write_string(diagnostic.severity.name())
    buf.write_char('[')
    buf.write_string(diagnostic.code.name())
    buf.write_string("] ")
    if diagnostic.location.contract is Some(contract) {
      buf.write_string(contract)
      buf.write_char(' ')
    }
    buf.write_string(diagnostic.location.path)
    buf.write_string(": ")
    buf.write_string(diagnostic.message)
    write_text_values(buf, diagnostic)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Appends the old/new values of a finding, when it has any.
fn write_text_values(buf : StringBuilder, diagnostic : Diagnostic) -> Unit {
  match (diagnostic.old_value, diagnostic.new_value) {
    (None, None) => ()
    (Some(old), None) => {
      buf.write_string(" (old: ")
      buf.write_string(old)
      buf.write_char(')')
    }
    (None, Some(new)) => {
      buf.write_string(" (new: ")
      buf.write_string(new)
      buf.write_char(')')
    }
    (Some(old), Some(new)) => {
      buf.write_string(" (old: ")
      buf.write_string(old)
      buf.write_string(", new: ")
      buf.write_string(new)
      buf.write_char(')')
    }
  }
}

///|
/// Renders findings as a JSON array, pretty-printed with two-space indents.
///
/// ```json
/// [
///   {
///     "code": "storage.entry.slot.invalid",
///     "severity": "error",
///     "location": {"contract": "fileA:A", "path": "storage[1].slot"},
///     "message": "slot \"0x1f\" is not a non-negative decimal integer"
///   }
/// ]
/// ```
///
/// The result is `[]\n` when there are no findings, and otherwise ends with a
/// newline.
pub fn render_json(diagnostics : Array[Diagnostic]) -> String {
  let sorted = sorted_diagnostics(diagnostics)
  let buf = StringBuilder()
  if sorted.is_empty() {
    buf.write_string("[]\n")
    return buf.to_string()
  }
  buf.write_string("[\n")
  let mut first = true
  for diagnostic in sorted {
    if !first {
      buf.write_string(",\n")
    }
    first = false
    buf.write_string("  {\n")
    buf.write_string("    \"code\": ")
    write_json_string(buf, diagnostic.code.name())
    buf.write_string(",\n")
    buf.write_string("    \"severity\": ")
    write_json_string(buf, diagnostic.severity.name())
    buf.write_string(",\n")
    buf.write_string("    \"location\": {")
    if diagnostic.location.contract is Some(contract) {
      buf.write_string("\"contract\": ")
      write_json_string(buf, contract)
      buf.write_string(", ")
    }
    buf.write_string("\"path\": ")
    write_json_string(buf, diagnostic.location.path)
    buf.write_string("},\n")
    buf.write_string("    \"message\": ")
    write_json_string(buf, diagnostic.message)
    let has_values = diagnostic.old_value is Some(_) ||
      diagnostic.new_value is Some(_)
    if has_values {
      buf.write_string(",\n")
    } else {
      buf.write_char('\n')
    }
    if diagnostic.old_value is Some(old) {
      buf.write_string("    \"oldValue\": ")
      write_json_string(buf, old)
      if diagnostic.new_value is Some(_) {
        buf.write_string(",\n")
      } else {
        buf.write_char('\n')
      }
    }
    if diagnostic.new_value is Some(new) {
      buf.write_string("    \"newValue\": ")
      write_json_string(buf, new)
      buf.write_char('\n')
    }
    buf.write_string("  }")
  }
  buf.write_string("\n]\n")
  buf.to_string()
}

///|
/// Writes `value` as a JSON string literal, including the quotes.
///
/// Escaping follows RFC 8259: the two mandatory escapes, the short forms for
/// backspace, form feed, newline, carriage return, and tab, and `\u00xx` for
/// the remaining control characters. Every other character, including
/// non-ASCII ones, is written unchanged, so output does not depend on locale
/// or platform.
fn write_json_string(buf : StringBuilder, value : String) -> Unit {
  buf.write_char('"')
  for c in value {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      '\u{c}' => buf.write_string("\\f")
      _ =>
        if c.to_int() < 0x20 {
          buf.write_string("\\u00")
          buf.write_string(c.to_int().to_byte().to_hex())
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}
