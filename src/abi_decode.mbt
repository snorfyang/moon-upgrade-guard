///| Decoding a compiler ABI array into the ABI model.
///
/// Decoding validates and canonicalizes: a signature is built from canonical
/// parameter types, and a selector or topic is derived from that signature, so
/// comparison never depends on how the compiler happened to print a type or on
/// which order the JSON keys appeared in.

///|
/// Decodes an `abi` JSON array into the ABI model.
///
/// Returns `None` when the value is `null`, which stands for an artifact that
/// carries no ABI, and also after reporting a value that is not an array.
/// Entries that cannot be decoded are reported and skipped, so an ABI that
/// comes back with a diagnostic is incomplete and must not be compared as if
/// it were whole.
fn decode_abi(
  json : Json,
  path : String,
  diagnostics : Array[Diagnostic],
) -> Abi? {
  let entries = match json {
    Array(entries) => entries
    Null => return None
    _ => {
      diagnostics.push(invalid_field(path, "expected a JSON array"))
      return None
    }
  }
  let abi : Abi = Abi::empty()
  for i in 0..<entries.length() {
    let entry_path = "\{path}[\{i}]"
    guard entries[i] is Object(fields) else {
      diagnostics.push(invalid_field(entry_path, "expected a JSON object"))
      continue
    }
    let kind = match fields.get("type") {
      Some(String(value)) => value
      None | Some(Null) => {
        diagnostics.push(
          invalid_field(entry_path + ".type", "required field is missing"),
        )
        continue
      }
      Some(_) => {
        diagnostics.push(
          invalid_field(entry_path + ".type", "expected a JSON string"),
        )
        continue
      }
    }
    match kind {
      "function" =>
        match decode_callable(fields, entry_path, Function, diagnostics) {
          Some(entry) => abi.functions.push(entry)
          None => ()
        }
      "fallback" =>
        match decode_callable(fields, entry_path, Fallback, diagnostics) {
          Some(entry) => abi.functions.push(entry)
          None => ()
        }
      "receive" =>
        match decode_callable(fields, entry_path, Receive, diagnostics) {
          Some(entry) => abi.functions.push(entry)
          None => ()
        }
      "event" =>
        match decode_event(fields, entry_path, diagnostics) {
          Some(entry) => abi.events.push(entry)
          None => ()
        }
      "error" =>
        match decode_error(fields, entry_path, diagnostics) {
          Some(entry) => abi.errors.push(entry)
          None => ()
        }
      // Constructor inputs affect deployment, not the interface an existing
      // proxy exposes, so they take no part in compatibility.
      "constructor" => ()
      other =>
        diagnostics.push(
          invalid_field(
            entry_path + ".type",
            "unsupported ABI entry type \"\{other}\"",
          ),
        )
    }
  }
  Some(abi)
}

///|
/// Decodes one callable entry: a function, fallback, or receive.
fn decode_callable(
  fields : Map[String, Json],
  path : String,
  kind : AbiEntryKind,
  diagnostics : Array[Diagnostic],
) -> AbiFunction? {
  let name = match kind {
    Function => {
      guard require_string(fields, "name", path, diagnostics) is Some(value) else {
        return None
      }
      value
    }
    Fallback | Receive => ""
  }
  guard require_mutability(fields, path, diagnostics) is Some(mutability) else {
    return None
  }
  let inputs = if kind == Function {
    match decode_params(fields, "inputs", path, false, diagnostics) {
      Some(inputs) => inputs
      None => return None
    }
  } else {
    []
  }
  let outputs = if kind == Function {
    match decode_params(fields, "outputs", path, false, diagnostics) {
      Some(outputs) => outputs
      None => return None
    }
  } else {
    []
  }
  let signature = canonical_signature(callable_name(name, kind), inputs)
  Some({
    kind,
    name,
    signature,
    selector: selector_of(signature),
    inputs,
    outputs,
    mutability,
  })
}

///|
/// The name an entry contributes to its signature.
///
/// Fallback and receive carry no name in the ABI, but their signatures are
/// still written `fallback()` and `receive()`, which is what tooling hashes and
/// prints.
fn callable_name(name : String, kind : AbiEntryKind) -> String {
  match kind {
    Function => name
    Fallback => "fallback"
    Receive => "receive"
  }
}

///|
/// Decodes one event.
fn decode_event(
  fields : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> AbiEvent? {
  guard require_string(fields, "name", path, diagnostics) is Some(name) else {
    return None
  }
  guard decode_params(fields, "inputs", path, true, diagnostics) is Some(inputs) else {
    return None
  }
  let anonymous = match fields.get("anonymous") {
    Some(True) => true
    Some(False) => false
    None | Some(Null) => {
      diagnostics.push(
        invalid_field(path + ".anonymous", "required field is missing"),
      )
      return None
    }
    Some(_) => {
      diagnostics.push(invalid_field(path + ".anonymous", "expected a boolean"))
      return None
    }
  }
  let signature = canonical_signature(name, inputs)
  Some({ name, signature, topic: topic_of(signature), inputs, anonymous, })
}

///|
/// Decodes one custom error.
fn decode_error(
  fields : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> AbiError? {
  guard require_string(fields, "name", path, diagnostics) is Some(name) else {
    return None
  }
  guard decode_params(fields, "inputs", path, false, diagnostics)
    is Some(inputs) else {
    return None
  }
  let signature = canonical_signature(name, inputs)
  Some({ name, signature, selector: selector_of(signature), inputs, })
}

///|
/// Decodes a required parameter list field.
fn decode_params(
  fields : Map[String, Json],
  name : String,
  path : String,
  indexed_required : Bool,
  diagnostics : Array[Diagnostic],
) -> Array[AbiParam]? {
  match fields.get(name) {
    None | Some(Null) => {
      diagnostics.push(
        invalid_field(path + "." + name, "required field is missing"),
      )
      None
    }
    Some(Array(items)) => {
      let params : Array[AbiParam] = []
      for i in 0..<items.length() {
        guard decode_param(
            items[i],
            "\{path}.\{name}[\{i}]",
            indexed_required,
            diagnostics,
          )
          is Some(param) else {
          return None
        }
        params.push(param)
      }
      Some(params)
    }
    Some(_) => {
      diagnostics.push(
        invalid_field(path + "." + name, "expected a JSON array"),
      )
      None
    }
  }
}

///|
/// Decodes one parameter, including its canonical type name.
fn decode_param(
  json : Json,
  path : String,
  indexed_required : Bool,
  diagnostics : Array[Diagnostic],
) -> AbiParam? {
  guard json is Object(fields) else {
    diagnostics.push(invalid_field(path, "expected a JSON object"))
    return None
  }
  guard require_string(fields, "type", path, diagnostics) is Some(type_name) else {
    return None
  }
  guard canonical_type(type_name, fields.get("components"), path, diagnostics)
    is Some(canonical) else {
    return None
  }
  let name = match fields.get("name") {
    Some(String(value)) => value
    _ => ""
  }
  let indexed = if indexed_required {
    match fields.get("indexed") {
      Some(True) => true
      Some(False) => false
      None | Some(Null) => {
        diagnostics.push(
          invalid_field(path + ".indexed", "required field is missing"),
        )
        return None
      }
      Some(_) => {
        diagnostics.push(invalid_field(path + ".indexed", "expected a boolean"))
        return None
      }
    }
  } else {
    false
  }
  Some({ name, type_name: canonical, indexed, })
}

///|
/// The canonical type name of a parameter.
///
/// Solidity's ABI specification canonicalizes tuples as `(t1,t2)`, and every
/// parameter has to be written that way for its selector to match the one
/// callers compute. `type` is therefore checked against the canonical
/// elementary names instead of being trusted, and a name that is not canonical
/// is rejected rather than silently hashed into a wrong selector.
fn canonical_type(
  type_name : String,
  components : Json?,
  path : String,
  diagnostics : Array[Diagnostic],
) -> String? {
  let (base, suffix) = split_array_suffix(type_name)
  if !valid_array_suffix(suffix) {
    diagnostics.push(
      invalid_field(path + ".type", "unsupported array type \"\{type_name}\""),
    )
    return None
  }
  if base == "tuple" {
    match components {
      Some(Array(items)) => {
        let parts : Array[String] = []
        for i in 0..<items.length() {
          guard decode_param(
              items[i],
              "\{path}.components[\{i}]",
              false,
              diagnostics,
            )
            is Some(param) else {
            return None
          }
          parts.push(param.type_name)
        }
        Some("(" + parts.join(",") + ")" + suffix)
      }
      None | Some(Null) => {
        diagnostics.push(
          invalid_field(path + ".components", "a tuple type needs components"),
        )
        None
      }
      Some(_) => {
        diagnostics.push(
          invalid_field(path + ".components", "expected a JSON array"),
        )
        None
      }
    }
  } else if is_elementary_type(base) {
    Some(base + suffix)
  } else {
    diagnostics.push(
      invalid_field(path + ".type", "unsupported ABI type \"\{type_name}\""),
    )
    None
  }
}

///|
/// Splits a type name into its base name and its array suffixes.
fn split_array_suffix(type_name : String) -> (String, String) {
  match type_name.find("[") {
    Some(index) => (type_name[:index].to_owned(), type_name[index:].to_owned())
    None => (type_name, "")
  }
}

///|
/// Whether an array suffix is a sequence of `[length]` groups, where `length`
/// may be empty for a dynamic array.
fn valid_array_suffix(suffix : String) -> Bool {
  let chars = suffix.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] != '[' {
      return false
    }
    i += 1
    while i < chars.length() && chars[i].is_ascii_digit() {
      i += 1
    }
    if i >= chars.length() || chars[i] != ']' {
      return false
    }
    i += 1
  }
  true
}

///|
/// Whether `name` is a canonical elementary ABI type.
fn is_elementary_type(name : String) -> Bool {
  match name {
    "address" | "bool" | "string" | "bytes" | "function" => true
    _ =>
      if name.has_prefix("uint") {
        sized_integer(name, 4, 8)
      } else if name.has_prefix("int") {
        sized_integer(name, 3, 8)
      } else if name.has_prefix("bytes") {
        sized_bytes(name)
      } else {
        false
      }
  }
}

///|
/// Whether the width in a `uintN` or `intN` name is a valid multiple of 8 up
/// to 256.
fn sized_integer(name : String, prefix_length : Int, step : Int) -> Bool {
  match parse_decimal_int(name[prefix_length:].to_owned()) {
    Some(size) => size >= step && size <= 256 && size % step == 0
    None => false
  }
}

///|
/// Whether the width in a `bytesN` name is between 1 and 32.
fn sized_bytes(name : String) -> Bool {
  match parse_decimal_int(name[5:].to_owned()) {
    Some(size) => size >= 1 && size <= 32
    None => false
  }
}

///|
/// Reads a required string field, reporting whether it is absent or of the
/// wrong JSON type.
fn require_string(
  fields : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[Diagnostic],
) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    None | Some(Null) => {
      diagnostics.push(
        invalid_field(path + "." + name, "required field is missing"),
      )
      None
    }
    Some(_) => {
      diagnostics.push(
        invalid_field(path + "." + name, "expected a JSON string"),
      )
      None
    }
  }
}

///|
/// Reads the required `stateMutability` field.
///
/// Pre-0.5 ABIs wrote `constant` and `payable` booleans instead. They cannot be
/// translated exactly, because `constant` does not distinguish `pure` from
/// `view`, so they are reported as unsupported rather than guessed at.
fn require_mutability(
  fields : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> Mutability? {
  match fields.get("stateMutability") {
    Some(String(value)) =>
      match value {
        "pure" => Some(Pure)
        "view" => Some(View)
        "nonpayable" => Some(NonPayable)
        "payable" => Some(Payable)
        other => {
          diagnostics.push(
            invalid_field(
              path + ".stateMutability",
              "unsupported state mutability \"\{other}\"",
            ),
          )
          None
        }
      }
    None | Some(Null) =>
      if fields.contains("constant") || fields.contains("payable") {
        diagnostics.push(
          invalid_field(
            path + ".stateMutability",
            "legacy ABI mutability fields are not supported; recompile with Solidity 0.5 or later",
          ),
        )
        None
      } else {
        diagnostics.push(
          invalid_field(path + ".stateMutability", "required field is missing"),
        )
        None
      }
    Some(_) => {
      diagnostics.push(
        invalid_field(path + ".stateMutability", "expected a JSON string"),
      )
      None
    }
  }
}

///|
/// Canonical signature of an entry: its name and canonical parameter types.
fn canonical_signature(name : String, params : Array[AbiParam]) -> String {
  let types : Array[String] = params.map(fn(param) { param.type_name })
  name + "(" + types.join(",") + ")"
}

///|
/// Four-byte selector of a signature, as `0x` plus eight lowercase hex digits.
fn selector_of(signature : String) -> String {
  "0x" + hex_encode(keccak_256(@utf8.encode(signature)))[:8].to_owned()
}

///|
/// Topic of an event signature, as `0x` plus 64 lowercase hex digits.
fn topic_of(signature : String) -> String {
  "0x" + hex_encode(keccak_256(@utf8.encode(signature)))
}
