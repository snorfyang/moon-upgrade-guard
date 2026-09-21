///| Artifact extraction.
///
/// Extraction turns compiler output text into a raw `storageLayout` plus the
/// provenance its wrapper records. It locates and type-checks the layout; it
/// does not decide compatibility, and it performs no file or network access,
/// so any caller that already holds the text gets the same behavior.
///
/// Recognized shapes, each documented by the tool that writes it:
///
/// - the `storageLayout` object itself, `{ "storage": [...], "types": {...} }`;
/// - a flat artifact with `storageLayout` at the top level, as Foundry writes
///   (<https://github.com/foundry-rs/compilers>);
/// - a solc Standard JSON output document, `contracts.<source>.<contract>`
///   (<https://docs.soliditylang.org/en/latest/using-the-compiler.html>);
/// - a build info document, `output.contracts.<source>.<contract>`, as
///   Hardhat writes it.
///
/// A Hardhat per-contract artifact has `contractName`, `abi`, and bytecode
/// but no storage layout at all, so it reports that instead of a layout.

///|
/// Which wrapper shape a storage layout was found in.
pub(all) enum ArtifactKind {
  /// The `storageLayout` object itself.
  Layout
  /// A flat artifact with `storageLayout` at the top level, in the shape
  /// Foundry writes.
  FlatArtifact
  /// A solc Standard JSON output document with `contracts`.
  StandardJson
  /// A build info document with `output.contracts`, in the shape Hardhat
  /// writes.
  BuildInfo
} derive(Eq, @debug.Debug)

///|
/// A located storage layout and the provenance its wrapper records.
pub(all) struct Artifact {
  /// Which wrapper shape the layout was found in.
  kind : ArtifactKind
  /// Source file the wrapper records, when it records one.
  source : String?
  /// Contract name the wrapper records, when it records one.
  contract : String?
  /// The raw `storageLayout` object, ready for `normalize_layout`.
  layout : RawStorageLayout
  /// The normalized ABI, when the artifact carries one. `None` means the
  /// artifact has no ABI to compare, which is the normal case for a layout
  /// extracted on its own.
  abi : Abi?
  /// The raw `transientStorageLayout` object, when the artifact carries one.
  /// `None` means the artifact reports no transient layout, which Foundry does
  /// by omitting an empty one.
  transient : RawStorageLayout?
} derive(Eq, @debug.Debug)

///|
/// Reads a storage layout from artifact `text`.
///
/// `select` chooses a contract in a wrapper that can hold several layouts,
/// either by contract name or as `source:contract`. A wrapper with several
/// layouts and no selector produces an ambiguity diagnostic instead of a
/// guess; a wrapper with a single layout ignores `select`.
///
/// Returns the artifact and the diagnostics raised while locating it.
/// Diagnostics are sorted. A `None` artifact always comes with at least one
/// diagnostic.
pub fn extract_artifact(
  text : String,
  select? : String,
) -> (Artifact?, Array[Diagnostic]) {
  let diagnostics : Array[Diagnostic] = []
  // ERC-7201 namespaced storage is invisible in `storageLayout`: the compiler
  // lists state variables, and a namespace is reached through a slot that its
  // own annotation derives. Since namespace members are not in the layout, a
  // verdict for such an artifact would not have been checked, so the artifact
  // is refused instead. The marker is the annotation id itself, which appears
  // in the AST that artifacts carry.
  if text.contains("erc7201") {
    diagnostics.push(
      Diagnostic::new(
        ArtifactNamespacedStorageUnsupported,
        artifact_root(),
        "artifact mentions ERC-7201 namespaced storage, which this version cannot locate; the compiler storageLayout does not list namespace members, so their compatibility is unknown",
      ),
    )
  }
  let parsed = @json.parse(text) catch {
    err => {
      diagnostics.push(
        Diagnostic::new(
          ArtifactJsonInvalid,
          artifact_root(),
          "artifact is not valid JSON: \{err}",
        ),
      )
      diagnostics.sort()
      return (None, diagnostics)
    }
  }
  // Numbers must be validated on their lexical form. The parser keeps only a
  // correctly rounded Double, so a fraction such as 3.0000000000000000000001
  // is indistinguishable from 3 by the time a field is read, and a comparison
  // built on rounded values could pass silently. Every producer this tool
  // supports writes integer numbers only, so a number token that is not an
  // integer literal is unusable schema data and refuses the artifact.
  let non_integer = scan_non_integer_numbers(text)
  if non_integer.length() > 0 {
    for violation in non_integer {
      let (offset, lexeme) = violation
      diagnostics.push(
        Diagnostic::new(
          ArtifactFieldInvalid,
          artifact_root(),
          "number literal \"\{lexeme}\" at offset \{offset} is not an integer; artifact numbers must be integer literals",
        ),
      )
    }
    diagnostics.sort()
    return (None, diagnostics)
  }
  let artifact = extract_from_root(parsed, select, diagnostics)
  diagnostics.sort()
  (artifact, diagnostics)
}

///|
/// Collects every JSON number token that is not an integer literal.
///
/// Runs on text that has already parsed as JSON, so every number token starts
/// at a `-` or a digit outside a string, and its characters are exactly
/// digits, sign, fraction point, and exponent markers. Tokens inside strings
/// are skipped, including escaped quotes. The result holds the offset of each
/// violation in the text and its literal, in document order.
fn scan_non_integer_numbers(text : String) -> Array[(Int, String)] {
  let violations : Array[(Int, String)] = []
  let length = text.length()
  let mut in_string = false
  let mut escaped = false
  let mut i = 0
  while i < length {
    let c = text[i]
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
      i += 1
      continue
    }
    if c == '"' {
      in_string = true
      i += 1
      continue
    }
    if c == '-' || (c >= '0' && c <= '9') {
      let start = i
      while i < length {
        let d = text[i]
        if d == '.' ||
          d == 'e' ||
          d == 'E' ||
          d == '+' ||
          d == '-' ||
          (d >= '0' && d <= '9') {
          i += 1
        } else {
          break
        }
      }
      if !is_integer_literal(text[start:i]) {
        violations.push((start, text[start:i].to_owned()))
      }
      continue
    }
    i += 1
  }
  violations
}

///|
/// Whether a scanned number token is a plain integer literal: an optional
/// sign followed by digits only, with no fraction point or exponent. JSON
/// forbids leading zeros, and the text has already parsed, so shape is the
/// only thing left to check.
fn is_integer_literal(token : StringView) -> Bool {
  let body = if token.length() > 0 && token[0] == '-' {
    token[1:]
  } else {
    token
  }
  body.length() > 0 && body.iter().all(fn(c) { c >= '0' && c <= '9' })
}

///|
/// Location of the artifact document itself.
fn artifact_root() -> Location {
  { contract: None, path: "$", }
}

///|
/// Renders one key of an artifact path, such as `["src/Vault.sol"]`.
fn quoted(key : String) -> String {
  "[\"\{key}\"]"
}

///|
/// Builds a diagnostic for a malformed artifact field.
fn invalid_field(path : String, message : String) -> Diagnostic {
  Diagnostic::new(ArtifactFieldInvalid, { contract: None, path, }, message)
}

///|
/// Dispatches on the wrapper shape of the artifact root.
fn extract_from_root(
  json : Json,
  select : String?,
  diagnostics : Array[Diagnostic],
) -> Artifact? {
  guard json is Object(fields) else {
    diagnostics.push(
      Diagnostic::new(
        ArtifactShapeUnsupported,
        artifact_root(),
        "artifact root must be a JSON object",
      ),
    )
    return None
  }
  let has_layout = fields.contains("storage") || fields.contains("types")
  let has_flat = match fields.get("storageLayout") {
    None | Some(Null) => false
    Some(_) => true
  }
  let has_contracts = fields.contains("contracts")
  let has_build_info = match fields.get("output") {
    Some(Object(output)) => output.contains("contracts")
    _ => false
  }
  let shapes : Array[String] = []
  if has_layout {
    shapes.push("a storage layout object")
  }
  if has_flat {
    shapes.push("a flat artifact")
  }
  if has_contracts {
    shapes.push("Standard JSON output")
  }
  if has_build_info {
    shapes.push("a build info document")
  }
  if shapes.length() > 1 {
    diagnostics.push(
      Diagnostic::new(
        ArtifactShapeAmbiguous,
        artifact_root(),
        "artifact matches more than one known shape (\{shapes.join(", ")}); extract one artifact shape at a time",
      ),
    )
    return None
  }
  if has_layout {
    guard decode_layout(json, "$", diagnostics) is Some(layout) else {
      return None
    }
    return Some({
      kind: Layout,
      source: None,
      contract: None,
      layout,
      abi: None,
      transient: None,
    })
  }
  if has_flat {
    guard fields.get("storageLayout") is Some(layout_json) else { return None }
    return extract_flat(fields, layout_json, diagnostics)
  }
  if has_contracts {
    guard fields.get("contracts") is Some(contracts) else { return None }
    return extract_contracts(
      contracts,
      "$.contracts",
      select,
      StandardJson,
      diagnostics,
    )
  }
  if has_build_info {
    guard fields.get("output") is Some(Object(output)) else { return None }
    guard output.get("contracts") is Some(contracts) else { return None }
    return extract_contracts(
      contracts,
      "$.output.contracts",
      select,
      BuildInfo,
      diagnostics,
    )
  }
  if looks_like_contract_artifact(fields) {
    diagnostics.push(layout_missing_diagnostic(fields))
    return None
  }
  if fields.contains("language") && fields.contains("sources") {
    diagnostics.push(
      Diagnostic::new(
        ArtifactShapeUnsupported,
        artifact_root(),
        "artifact is compiler input, which carries no storage layout; pass compiler output or a compile artifact",
      ),
    )
    return None
  }
  diagnostics.push(
    Diagnostic::new(
      ArtifactShapeUnsupported,
      artifact_root(),
      "artifact is not a recognized shape; expected a storage layout object, a flat artifact with storageLayout, or compiler output with contracts",
    ),
  )
  None
}

///|
/// Whether an unrecognized object still looks like a compiled contract, which
/// makes "no storage layout" a more useful report than "unknown shape".
fn looks_like_contract_artifact(fields : Map[String, Json]) -> Bool {
  fields.contains("_format") ||
  fields.contains("contractName") ||
  fields.contains("sourceName") ||
  fields.contains("abi") ||
  fields.contains("bytecode") ||
  fields.contains("deployedBytecode")
}

///|
/// Reports that a contract artifact carries no storage layout.
fn layout_missing_diagnostic(fields : Map[String, Json]) -> Diagnostic {
  let format = match fields.get("_format") {
    Some(String(value)) => " of format \"\{value}\""
    _ => ""
  }
  Diagnostic::new(
    ArtifactLayoutMissing,
    artifact_root(),
    "artifact\{format} does not contain a storage layout; compile with the storageLayout output selected",
  )
}

///|
/// Extracts the layout of a flat artifact, the shape Foundry writes.
fn extract_flat(
  fields : Map[String, Json],
  layout_json : Json,
  diagnostics : Array[Diagnostic],
) -> Artifact? {
  guard layout_json is Object(_) else {
    diagnostics.push(invalid_field("$.storageLayout", "expected a JSON object"))
    return None
  }
  guard decode_layout(layout_json, "$.storageLayout", diagnostics)
    is Some(layout) else {
    return None
  }
  Some({
    kind: FlatArtifact,
    source: get_string(fields, "sourceName"),
    contract: get_string(fields, "contractName"),
    layout,
    abi: decode_abi_field(fields, "$.abi", diagnostics),
    transient: decode_transient_field(
      fields, "$.transientStorageLayout", diagnostics,
    ),
  })
}

///|
/// A contract object inside a wrapper that carries a storage layout.
priv struct LayoutCandidate {
  source : String
  contract : String
  layout : Json
  fields : Map[String, Json]
}

///|
/// Extracts a layout from a `contracts` object, which both Standard JSON
/// output and build info documents use.
fn extract_contracts(
  contracts : Json,
  path : String,
  select : String?,
  kind : ArtifactKind,
  diagnostics : Array[Diagnostic],
) -> Artifact? {
  guard contracts is Object(sources) else {
    diagnostics.push(invalid_field(path, "expected a JSON object"))
    return None
  }
  let candidates = collect_candidates(sources, path, diagnostics)
  if candidates.is_empty() {
    diagnostics.push(
      Diagnostic::new(
        ArtifactLayoutMissing,
        { contract: None, path, },
        "compiler output contains no storage layout; compile with the storageLayout output selected",
      ),
    )
    return None
  }
  guard select_candidate(candidates, select, path, diagnostics)
    is Some(candidate) else {
    return None
  }
  let layout_path = path +
    quoted(candidate.source) +
    quoted(candidate.contract) +
    ".storageLayout"
  guard decode_layout(candidate.layout, layout_path, diagnostics)
    is Some(layout) else {
    return None
  }
  let contract_path = path +
    quoted(candidate.source) +
    quoted(candidate.contract)
  Some({
    kind,
    source: Some(candidate.source),
    contract: Some(candidate.contract),
    layout,
    abi: decode_abi_field(candidate.fields, contract_path + ".abi", diagnostics),
    transient: decode_transient_field(
      candidate.fields,
      contract_path + ".transientStorageLayout",
      diagnostics,
    ),
  })
}

///|
/// Decodes the `abi` field of a contract object, when it has one.
fn decode_abi_field(
  fields : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> Abi? {
  match fields.get("abi") {
    None | Some(Null) => None
    Some(value) => decode_abi(value, path, diagnostics)
  }
}

///|
/// Collects every contract in a `contracts` object that has a storage layout.
///
/// Sources and contract names are visited in sorted order, so diagnostics and
/// ambiguity reports are the same for every run.
fn collect_candidates(
  sources : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> Array[LayoutCandidate] {
  let candidates : Array[LayoutCandidate] = []
  let source_names = sources.keys().collect()
  source_names.sort()
  for source in source_names {
    let source_json = match sources.get(source) {
      Some(value) => value
      None => continue
    }
    guard source_json is Object(contracts) else {
      diagnostics.push(
        invalid_field(path + quoted(source), "expected a JSON object"),
      )
      continue
    }
    let contract_names = contracts.keys().collect()
    contract_names.sort()
    for contract in contract_names {
      let contract_json = match contracts.get(contract) {
        Some(value) => value
        None => continue
      }
      guard contract_json is Object(fields) else {
        diagnostics.push(
          invalid_field(
            path + quoted(source) + quoted(contract),
            "expected a JSON object",
          ),
        )
        continue
      }
      match fields.get("storageLayout") {
        Some(Object(_) as layout) =>
          candidates.push({ source, contract, layout, fields, })
        None | Some(Null) => ()
        Some(_) =>
          diagnostics.push(
            invalid_field(
              path + quoted(source) + quoted(contract) + ".storageLayout",
              "expected a JSON object",
            ),
          )
      }
    }
  }
  candidates
}

///|
/// Picks the one candidate a selector names, or reports why it cannot.
fn select_candidate(
  candidates : Array[LayoutCandidate],
  select : String?,
  path : String,
  diagnostics : Array[Diagnostic],
) -> LayoutCandidate? {
  match select {
    None =>
      if candidates.length() == 1 {
        Some(candidates[0])
      } else {
        diagnostics.push(
          Diagnostic::new(
            ArtifactContractAmbiguous,
            { contract: None, path, },
            "artifact holds \{candidates.length()} storage layouts; select one of \{candidate_list(candidates, path)}",
          ),
        )
        None
      }
    Some(selector) => {
      let (want_source, want_contract) = split_qualified(selector)
      let matching : Array[LayoutCandidate] = []
      for candidate in candidates {
        let source_matches = match want_source {
          Some(source) => source == candidate.source
          None => true
        }
        if source_matches && candidate.contract == want_contract {
          matching.push(candidate)
        }
      }
      if matching.length() == 1 {
        Some(matching[0])
      } else if matching.is_empty() {
        diagnostics.push(
          Diagnostic::new(
            ArtifactContractMissing,
            { contract: None, path, },
            "no storage layout matches \"\{selector}\"; available: \{candidate_list(candidates, path)}",
          ),
        )
        None
      } else {
        diagnostics.push(
          Diagnostic::new(
            ArtifactContractAmbiguous,
            { contract: None, path, },
            "\"\{selector}\" matches more than one storage layout; use source:contract, one of \{candidate_list(matching, path)}",
          ),
        )
        None
      }
    }
  }
}

///|
/// Splits `source:contract` into its two parts, at the last colon.
fn split_qualified(selector : String) -> (String?, String) {
  match selector.rev_split_once(":") {
    Some((source, contract)) => (Some(source.to_owned()), contract.to_owned())
    None => (None, selector)
  }
}

///|
/// Renders the artifact paths of `candidates` as a comma-separated list.
fn candidate_list(candidates : Array[LayoutCandidate], path : String) -> String {
  let labels : Array[String] = []
  for candidate in candidates {
    labels.push(path + quoted(candidate.source) + quoted(candidate.contract))
  }
  labels.join(", ")
}

///|
/// Decodes the `transientStorageLayout` field of a contract object, when it has
/// one.
///
/// An artifact that omits the field reports no transient layout: Foundry omits
/// an empty one, and a compiler run that was not asked for
/// `transientStorageLayout` reports nothing either.
fn decode_transient_field(
  fields : Map[String, Json],
  path : String,
  diagnostics : Array[Diagnostic],
) -> RawStorageLayout? {
  match fields.get("transientStorageLayout") {
    None | Some(Null) => None
    Some(layout_json) => decode_layout(layout_json, path, diagnostics)
  }
}

///|
/// Decodes a `storageLayout` object into the raw storage model.
///
/// Every field is type-checked and any mismatch fails the whole layout, so a
/// half-decoded layout never reaches normalization. `astId` and unknown fields
/// are ignored because they cannot affect compatibility. `types` may be absent
/// or `null`, which the compiler emits and upstream tooling accepts; a
/// variable that then references a type fails normalization explicitly.
fn decode_layout(
  json : Json,
  path : String,
  diagnostics : Array[Diagnostic],
) -> RawStorageLayout? {
  guard json is Object(fields) else {
    diagnostics.push(invalid_field(path, "expected a JSON object"))
    return None
  }
  let storage_json = match fields.get("storage") {
    Some(value) => value
    None => {
      diagnostics.push(
        invalid_field(path + ".storage", "required field is missing"),
      )
      return None
    }
  }
  guard storage_json is Array(entries) else {
    diagnostics.push(invalid_field(path + ".storage", "expected a JSON array"))
    return None
  }
  let storage : Array[RawStorageEntry] = []
  for i in 0..<entries.length() {
    guard decode_entry(entries[i], "\{path}.storage[\{i}]", diagnostics)
      is Some(entry) else {
      return None
    }
    storage.push(entry)
  }
  let types : Array[RawStorageType] = []
  match fields.get("types") {
    None | Some(Null) => ()
    Some(Object(type_table)) => {
      let ids = type_table.keys().collect()
      ids.sort()
      for id in ids {
        let type_json = match type_table.get(id) {
          Some(value) => value
          None => continue
        }
        guard decode_type(
            id,
            type_json,
            "\{path}.types[\"\{id}\"]",
            diagnostics,
          )
          is Some(entry) else {
          return None
        }
        types.push(entry)
      }
    }
    Some(_) => {
      diagnostics.push(invalid_field(path + ".types", "expected a JSON object"))
      return None
    }
  }
  Some({ storage, types, })
}

///|
/// Decodes one storage variable, whether it is a top-level variable or a
/// struct member.
fn decode_entry(
  json : Json,
  path : String,
  diagnostics : Array[Diagnostic],
) -> RawStorageEntry? {
  guard json is Object(fields) else {
    diagnostics.push(invalid_field(path, "expected a JSON object"))
    return None
  }
  guard check_string(fields, "label", path, diagnostics) else { return None }
  guard check_string(fields, "contract", path, diagnostics) else { return None }
  guard check_string(fields, "slot", path, diagnostics) else { return None }
  guard check_string(fields, "type", path, diagnostics) else { return None }
  guard check_integer(fields, "offset", path, diagnostics) else { return None }
  Some({
    label: get_string(fields, "label"),
    contract: get_string(fields, "contract"),
    slot: get_string(fields, "slot"),
    offset: get_integer(fields, "offset"),
    type_id: get_string(fields, "type"),
  })
}

///|
/// Decodes one entry of the compiler type table.
fn decode_type(
  id : String,
  json : Json,
  path : String,
  diagnostics : Array[Diagnostic],
) -> RawStorageType? {
  guard json is Object(fields) else {
    diagnostics.push(invalid_field(path, "expected a JSON object"))
    return None
  }
  guard check_string(fields, "encoding", path, diagnostics) else { return None }
  guard check_string(fields, "label", path, diagnostics) else { return None }
  guard check_string(fields, "numberOfBytes", path, diagnostics) else {
    return None
  }
  guard check_string(fields, "base", path, diagnostics) else { return None }
  guard check_string(fields, "key", path, diagnostics) else { return None }
  guard check_string(fields, "value", path, diagnostics) else { return None }
  let members = match fields.get("members") {
    None | Some(Null) => None
    Some(Array(items)) => {
      let decoded : Array[RawStorageEntry] = []
      for i in 0..<items.length() {
        guard decode_entry(items[i], "\{path}.members[\{i}]", diagnostics)
          is Some(entry) else {
          return None
        }
        decoded.push(entry)
      }
      Some(decoded)
    }
    Some(_) => {
      diagnostics.push(
        invalid_field(path + ".members", "expected a JSON array"),
      )
      return None
    }
  }
  Some({
    id: Some(id),
    encoding: get_string(fields, "encoding"),
    label: get_string(fields, "label"),
    number_of_bytes: get_string(fields, "numberOfBytes"),
    base: get_string(fields, "base"),
    key: get_string(fields, "key"),
    value: get_string(fields, "value"),
    members,
  })
}

///|
/// Checks that a field is absent, `null`, or a JSON string.
fn check_string(
  fields : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match fields.get(name) {
    None | Some(Null) => true
    Some(value) => {
      guard value is String(_) else {
        diagnostics.push(
          invalid_field(path + "." + name, "expected a JSON string"),
        )
        return false
      }
      true
    }
  }
}

///|
/// Checks that a field is absent, `null`, or an integer-valued JSON number.
///
/// The artifact-level scan has already established that every number token in
/// the text is an integer literal, so the `Double` the parser hands over is
/// exact for any machine-sized value; this check only rejects literals whose
/// value exceeds the range every supported target can hold.
fn check_integer(
  fields : Map[String, Json],
  name : String,
  path : String,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match fields.get(name) {
    None | Some(Null) => true
    Some(Number(value, ..)) =>
      if json_integer(value) is Some(_) {
        true
      } else {
        diagnostics.push(
          invalid_field(
            path + "." + name,
            "expected an integer that fits in a machine integer",
          ),
        )
        false
      }
    Some(_) => {
      diagnostics.push(
        invalid_field(path + "." + name, "expected a JSON number"),
      )
      false
    }
  }
}

///|
/// Reads an optional string field, after `check_string` has accepted it.
fn get_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
/// Reads an optional integer field, after `check_integer` has accepted it.
fn get_integer(fields : Map[String, Json], name : String) -> Int? {
  match fields.get(name) {
    Some(Number(value, ..)) => json_integer(value)
    _ => None
  }
}

///|
/// Converts an integral JSON number to an `Int`, or `None` when it is outside
/// the range every supported target can hold.
///
/// Callers reach this only after the artifact-level scan has proven the token
/// was an integer literal. A literal within ±(2^53 - 1) converts through
/// `Double` without loss; anything larger rounds to a value beyond the machine
/// range and is rejected here, so a fractional literal can never slip through
/// as a rounded integer.
fn json_integer(value : Double) -> Int? {
  if value < -2147483648.0 || value > 2147483647.0 {
    None
  } else {
    let converted = value.to_int()
    if converted.to_double() == value {
      Some(converted)
    } else {
      None
    }
  }
}
